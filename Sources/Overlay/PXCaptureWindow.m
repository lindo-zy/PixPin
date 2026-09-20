#import "PXCaptureWindow.h"
#import "../Common/PXLog.h"

@interface PXCaptureRootViewController : UIViewController
@end

@implementation PXCaptureRootViewController

- (void)loadView {
    UIView *view = [[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    view.backgroundColor = [UIColor clearColor];
    self.view = view;
}

- (BOOL)prefersStatusBarHidden { return YES; }
- (BOOL)prefersHomeIndicatorAutoHidden { return YES; }
- (UIRectEdge)preferredScreenEdgesDeferringSystemGestures { return UIRectEdgeAll; }
- (BOOL)shouldAutorotate { return YES; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAll; }

@end

static BOOL PXStringLooksLikeKeyboard(NSString *value) {
    if (value.length == 0) return NO;
    return [value rangeOfString:@"keyboard" options:NSCaseInsensitiveSearch].location != NSNotFound;
}

static BOOL PXWindowSceneLooksLikeKeyboard(UIWindowScene *scene) {
    if (PXStringLooksLikeKeyboard(NSStringFromClass(scene.class)) ||
        PXStringLooksLikeKeyboard(scene.session.persistentIdentifier)) {
        return YES;
    }

    BOOL sawWindow = NO;
    BOOL sawNonKeyboardWindow = NO;
    for (UIWindow *window in scene.windows) {
        sawWindow = YES;
        NSString *className = NSStringFromClass(window.class);
        if (!PXStringLooksLikeKeyboard(className)) {
            sawNonKeyboardWindow = YES;
        }
    }
    return sawWindow && !sawNonKeyboardWindow;
}

static NSInteger PXScoreWindowScene(UIWindowScene *scene) {
    if (!scene || PXWindowSceneLooksLikeKeyboard(scene)) return NSIntegerMin;
    NSInteger score = 0;
    if (scene.activationState == UISceneActivationStateForegroundActive) score += 1000;
    else if (scene.activationState == UISceneActivationStateForegroundInactive) score += 500;
    if (scene.screen == [UIScreen mainScreen]) score += 200;

    for (UIWindow *window in scene.windows) {
        if (window.isKeyWindow) score += 120;
        if (!window.hidden && window.alpha > 0.01 && !PXStringLooksLikeKeyboard(NSStringFromClass(window.class))) {
            score += 10;
        }
    }
    return score;
}

static UIWindowScene *PXResolveForegroundWindowScene(void) {
    UIApplication *application = [UIApplication sharedApplication];
    UIWindowScene *bestScene = nil;
    NSInteger bestScore = NSIntegerMin;
    for (UIScene *candidate in application.connectedScenes) {
        if (![candidate isKindOfClass:[UIWindowScene class]]) continue;
        UIWindowScene *windowScene = (UIWindowScene *)candidate;
        NSInteger score = PXScoreWindowScene(windowScene);
        if (score > bestScore) {
            bestScore = score;
            bestScene = windowScene;
        }
    }
    return bestScene;
}

@interface PXCaptureWindow ()
@property (nonatomic, weak, nullable) UIWindow *previousKeyWindow;
@property (nonatomic, weak, nullable) UIView *hostedContentView;
@property (nonatomic, copy, readwrite) NSString *hostingDescription;
@property (nonatomic, assign) BOOL requestedKeyWindow;
@end

@implementation PXCaptureWindow

+ (instancetype)pxCaptureWindow {
    UIWindowScene *scene = PXResolveForegroundWindowScene();
    CGRect screenBounds = scene ? scene.coordinateSpace.bounds : [UIScreen mainScreen].bounds;
    PXCaptureWindow *window = scene
        ? [[PXCaptureWindow alloc] initWithWindowScene:scene]
        : [[PXCaptureWindow alloc] initWithFrame:screenBounds];
    window.frame = screenBounds;
    window.windowLevel = 1000000.0;
    window.backgroundColor = [UIColor clearColor];
    window.hidden = YES;
    window.clipsToBounds = YES;

    NSString *sceneIdentifier = scene.session.persistentIdentifier ?: @"legacy-no-scene";
    window.hostingDescription = [NSString stringWithFormat:@"scene=%@ state=%ld bounds=%.0fx%.0f",
                                 sceneIdentifier,
                                 (long)(scene ? scene.activationState : -1),
                                 screenBounds.size.width,
                                 screenBounds.size.height];
    if (!scene) {
        PXLogWarn(@"capture window created without UIWindowScene");
    }
    return window;
}

- (void)hostContentView:(UIView *)contentView {
    NSParameterAssert(contentView);
    PXCaptureRootViewController *controller = [[PXCaptureRootViewController alloc] init];
    self.rootViewController = controller;
    UIView *rootView = controller.view;
    contentView.frame = rootView.bounds;
    contentView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [rootView addSubview:contentView];
    self.hostedContentView = contentView;
}

- (void)showAnimated:(BOOL)animated {
    [self showAnimated:animated becomeKey:YES];
}

- (void)showAnimated:(BOOL)animated becomeKey:(BOOL)becomeKey {
    if ([NSThread isMainThread]) {
        if (becomeKey) {
            for (UIWindow *window in self.windowScene.windows) {
                if (window != self && window.isKeyWindow) {
                    self.previousKeyWindow = window;
                    break;
                }
            }
        }
        self.requestedKeyWindow = becomeKey;
        self.alpha = animated ? 0.0 : 1.0;
        if (becomeKey) {
            [self makeKeyAndVisible];
        } else {
            self.hidden = NO;
        }
        [self layoutIfNeeded];
        PXLogInfo(@"capture window shown (%@ key=%d actualKey=%d passthrough=%d)",
                  self.hostingDescription, becomeKey, self.isKeyWindow,
                  self.passesTouchesOutsideHostedContent);
        if (animated) {
            [UIView animateWithDuration:0.15 animations:^{ self.alpha = 1.0; }];
        }
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{ [self showAnimated:animated becomeKey:becomeKey]; });
    }
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hitView = [super hitTest:point withEvent:event];
    if (!self.passesTouchesOutsideHostedContent) return hitView;
    if (hitView == self || hitView == self.rootViewController.view || hitView == self.hostedContentView) return nil;
    return hitView;
}

- (void)hideAndDestroyWithCompletion:(void (^)(void))completion {
    void (^finish)(void) = ^{
        if (!self.hidden) {
            // 立即从合成器移除：任何后续抓屏（连续截图场景）都不会再带上本窗口。
            self.hidden = YES;
            if (self.requestedKeyWindow && self.previousKeyWindow && !self.previousKeyWindow.hidden) {
                [self.previousKeyWindow makeKeyWindow];
            }
            self.hostedContentView = nil;
            self.rootViewController = nil;
        }
        if (completion) completion();
        // 持有者随后释放引用，窗口随 ARC 释放。
    };

    if ([NSThread isMainThread]) {
        finish();
    } else {
        dispatch_async(dispatch_get_main_queue(), finish);
    }
}

@end
