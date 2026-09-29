#import "PXFloatingSnap.h"
#import "PXCaptureWindow.h"
#import "../Common/PXLog.h"

static const CGFloat PXFloatSnapInset = 14.0;
static const CGFloat PXFloatSnapBarHeight = 44.0;

@interface PXFloatingSnap () <UIGestureRecognizerDelegate>
@property (nonatomic, strong, readwrite) UIImage *image;
@property (nonatomic, assign, readwrite) PXCaptureMode captureMode;
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) PXCaptureWindow *overlayWindow;
@property (nonatomic, strong) UIVisualEffectView *actionBar;
@property (nonatomic, strong) NSArray<UIButton *> *actionButtons;
@property (nonatomic, assign) BOOL actionBarVisible;
@property (nonatomic, assign) BOOL alive;
@property (nonatomic, assign) CGRect dragStartFrame;
@end

@interface PXFloatingSnap (HostLayout)
- (void)constrainToHostBounds;
@end

@interface PXFloatingSnapHostView : UIView
@property (nonatomic, weak) PXFloatingSnap *snap;
@end

@implementation PXFloatingSnapHostView
- (void)layoutSubviews {
    [super layoutSubviews];
    [self.snap constrainToHostBounds];
}
@end

@implementation PXFloatingSnap

- (void)setImage:(UIImage *)image {
    _image = image;
    self.imageView.image = image;
}

+ (instancetype)presentWithImage:(UIImage *)image
                            mode:(PXCaptureMode)mode
                        delegate:(id<PXFloatingSnapDelegate>)delegate
                           index:(NSUInteger)index {
    if (![NSThread isMainThread]) {
        // 调用契约是主线程。降级路径只记日志不弹出：异步弹出会返回 nil，调用方将永远无法 dismiss，
        // 悬浮窗会沦为无人能关的孤儿窗口。
        PXLogWarn(@"floating snap present called off main thread, dropped");
        return nil;
    }
    return [self pxPresentWithImage:image mode:mode delegate:delegate index:index];
}

+ (instancetype)pxPresentWithImage:(UIImage *)image
                              mode:(PXCaptureMode)mode
                          delegate:(id<PXFloatingSnapDelegate>)delegate
                             index:(NSUInteger)index {
    if (!image || image.size.width <= 0 || image.size.height <= 0) return nil;

    PXCaptureWindow *window = [PXCaptureWindow pxCaptureWindow];
    CGRect screenBounds = window.bounds;
    CGSize size = [self pxDisplaySizeForImageSize:image.size screenBounds:screenBounds];
    // 新图错开摆放；每张图有独立窗口与生命周期。
    CGFloat offset = (index % 6) * 28.0;
    CGRect frame = CGRectMake(MAX(PXFloatSnapInset, screenBounds.size.width - size.width - PXFloatSnapInset - offset),
                              MIN(screenBounds.size.height - size.height - PXFloatSnapInset,
                                  MAX(PXFloatSnapInset, screenBounds.size.height * 0.18) + offset),
                              size.width, size.height);

    PXFloatingSnap *snap = [[PXFloatingSnap alloc] initWithFrame:frame];
    snap.image = image;
    snap.captureMode = mode;
    snap.delegate = delegate;
    snap.alive = YES;

    window.windowLevel = 999000.0;   // 低于选区/编辑器（1000000）与结果气泡（1000001）
    window.frame = screenBounds;
    window.passesTouchesOutsideHostedContent = YES;
    snap.overlayWindow = window;
    PXFloatingSnapHostView *host = [[PXFloatingSnapHostView alloc] initWithFrame:window.bounds];
    host.snap = snap;
    host.backgroundColor = [UIColor clearColor];
    [host addSubview:snap];
    snap.frame = frame;
    [window hostContentView:host];
    [window showAnimated:NO becomeKey:NO];

    snap.transform = CGAffineTransformMakeScale(0.6, 0.6);
    snap.alpha = 0.0;
    [UIView animateWithDuration:0.22 animations:^{
        snap.transform = CGAffineTransformIdentity;
        snap.alpha = 1.0;
    }];
    PXLogInfo(@"floating snap presented (mode %ld, image %.0fx%.0f px)",
              (long)mode, image.size.width * image.scale, image.size.height * image.scale);
    return snap;
}

/// 极窄/极长选区使用留白展示，容器始终受屏幕约束，四个按钮均保留触控宽度。
+ (CGSize)pxDisplaySizeForImageSize:(CGSize)imageSize screenBounds:(CGRect)screenBounds {
    CGFloat maxWidth = MIN(MAX(176.0, screenBounds.size.width * 0.46), screenBounds.size.width - 28.0);
    CGFloat maxHeight = MIN(MAX(88.0, screenBounds.size.height * 0.38), screenBounds.size.height - 28.0);
    CGFloat scale = MIN(maxWidth / imageSize.width, maxHeight / imageSize.height);
    return CGSizeMake(MIN(maxWidth, MAX(176.0, floor(imageSize.width * scale))),
                      MIN(maxHeight, MAX(88.0, floor(imageSize.height * scale))));
}

- (void)constrainToHostBounds {
    if (!self.alive || !self.superview || !CGAffineTransformIsIdentity(self.transform)) return;
    CGRect bounds = UIEdgeInsetsInsetRect(self.superview.bounds, self.superview.safeAreaInsets);
    CGRect frame = self.frame;
    frame.size = [PXFloatingSnap pxDisplaySizeForImageSize:self.image.size screenBounds:bounds];
    frame.origin.x = MAX(CGRectGetMinX(bounds), MIN(frame.origin.x, CGRectGetMaxX(bounds) - frame.size.width));
    frame.origin.y = MAX(CGRectGetMinY(bounds), MIN(frame.origin.y, CGRectGetMaxY(bounds) - frame.size.height));
    self.frame = frame;
}

- (void)updateImage:(UIImage *)image {
    if (!self.alive || !image || image.size.width <= 0 || image.size.height <= 0) return;
    self.image = image;
    [self constrainToHostBounds];
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.backgroundColor = [UIColor colorWithWhite:0.05 alpha:1.0];
        self.layer.cornerRadius = 12.0;
        self.layer.borderWidth = 0.5;
        self.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.25].CGColor;
        self.clipsToBounds = YES;

        UIImageView *imageView = [[UIImageView alloc] initWithFrame:self.bounds];
        imageView.contentMode = UIViewContentModeScaleAspectFit;
        imageView.backgroundColor = [UIColor colorWithWhite:0.05 alpha:1.0];
        imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        imageView.userInteractionEnabled = YES;
        [self addSubview:imageView];
        self.imageView = imageView;

        // 动作条悬浮在图片底部：默认收起（alpha<0.01 时不参与命中测试）。
        _actionBar = [[UIVisualEffectView alloc] initWithEffect:
                      [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterialDark]];
        _actionBar.frame = CGRectMake(0, frame.size.height - PXFloatSnapBarHeight,
                                      frame.size.width, PXFloatSnapBarHeight);
        _actionBar.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
        [self addSubview:_actionBar];
        // 长按展开动作；取消只关闭当前图片。
        NSArray<NSArray *> *items = @[
            @[@"保存", @1, NSStringFromSelector(@selector(pxOutputTapped:))],
            @[@"复制", @2, NSStringFromSelector(@selector(pxOutputTapped:))],
            @[@"取消", @3, NSStringFromSelector(@selector(pxCloseTapped:))],
            @[@"编辑", @0, NSStringFromSelector(@selector(pxEditTapped:))],
        ];
        NSMutableArray<UIButton *> *buttons = [[NSMutableArray alloc] init];
        for (NSArray *item in items) {
            UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
            button.tintColor = [UIColor whiteColor];
            button.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
            [button setTitle:item[0] forState:UIControlStateNormal];
            [button addTarget:self action:NSSelectorFromString(item[2])
             forControlEvents:UIControlEventTouchUpInside];
            button.tag = [item[1] integerValue];
            [_actionBar.contentView addSubview:button];
            [buttons addObject:button];
        }
        _actionButtons = buttons;
        _actionBar.alpha = 0.0;

        UITapGestureRecognizer *tap =
            [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(pxTapGesture:)];
        tap.numberOfTapsRequired = 2;
        tap.delegate = self;
        [self addGestureRecognizer:tap];
        UILongPressGestureRecognizer *press = [[UILongPressGestureRecognizer alloc]
            initWithTarget:self action:@selector(pxLongPressGesture:)];
        press.minimumPressDuration = 0.45;
        press.delegate = self;
        [self addGestureRecognizer:press];
        UIPanGestureRecognizer *pan =
            [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pxPanGesture:)];
        pan.delegate = self;
        [self addGestureRecognizer:pan];
        self.accessibilityLabel = @"悬浮截图";
        self.accessibilityHint = @"双击关闭，长按显示保存、复制、取消和编辑";
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width;
    CGFloat height = self.bounds.size.height;
    CGFloat barTop = height - PXFloatSnapBarHeight;
    _actionBar.frame = CGRectMake(0, barTop, width, PXFloatSnapBarHeight);
    CGFloat buttonWidth = width / _actionButtons.count;
    for (NSUInteger i = 0; i < _actionButtons.count; i++) {
        _actionButtons[i].frame = CGRectMake(i * buttonWidth, 0, buttonWidth, PXFloatSnapBarHeight);
    }
}

#pragma mark - 手势

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldReceiveTouch:(UITouch *)touch {
    for (UIView *view = touch.view; view && view != self; view = view.superview) {
        if ([view isKindOfClass:UIControl.class]) return NO;
    }
    return self.alive;
}

- (void)pxTapGesture:(UITapGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateRecognized) [self dismissWithCompletion:nil];
}

- (void)pxLongPressGesture:(UILongPressGestureRecognizer *)gesture {
    if (!self.alive || gesture.state != UIGestureRecognizerStateBegan) return;
    self.actionBarVisible = !self.actionBarVisible;
    [UIView animateWithDuration:0.18 animations:^{
        self.actionBar.alpha = self.actionBarVisible ? 1.0 : 0.0;
    }];
}

- (void)pxPanGesture:(UIPanGestureRecognizer *)gesture {
    if (!self.alive) return;
    switch (gesture.state) {
        case UIGestureRecognizerStateBegan:
            self.dragStartFrame = self.frame;
            break;
        case UIGestureRecognizerStateChanged: {
            CGPoint translation = [gesture translationInView:self.superview];
            CGRect frame = self.dragStartFrame;
            frame.origin.x += translation.x;
            frame.origin.y += translation.y;
            self.frame = frame;
            [self constrainToHostBounds];
            break;
        }
        default:
            break;
    }
}

#pragma mark - 动作

- (void)pxNotifyEdit {
    if (self.alive && self.delegate && [self.delegate respondsToSelector:@selector(floatingSnapDidRequestEdit:)]) {
        [self.delegate floatingSnapDidRequestEdit:self];
    }
}

- (void)pxNotifyOutput:(PXOutputAction)action {
    if (self.alive && self.delegate && [self.delegate respondsToSelector:@selector(floatingSnapDidRequestOutput:action:)]) {
        [self.delegate floatingSnapDidRequestOutput:self action:action];
    }
}

- (void)pxEditTapped:(UIButton *)sender {
    [self pxNotifyEdit];
}

- (void)pxOutputTapped:(UIButton *)sender {
    PXOutputAction action = (sender.tag == 1) ? PXOutputActionSave : PXOutputActionCopy;
    self.actionBarVisible = NO;
    self.actionBar.alpha = 0;
    [self pxNotifyOutput:action];
}

- (void)pxCloseTapped:(UIButton *)sender {
    [self dismissWithCompletion:nil];
}

#pragma mark - 生命周期

- (void)hideForCapture {
    if (!self.alive || !self.overlayWindow) return;
    self.overlayWindow.hidden = YES;
}

- (void)restoreAfterCapture {
    if (!self.alive || !self.overlayWindow) return;
    self.overlayWindow.hidden = NO;
    [self constrainToHostBounds];
}

- (void)dismissWithCompletion:(void (^)(void))completion {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self dismissWithCompletion:completion]; });
        return;
    }
    if (!self.alive) {
        if (completion) completion();
        return;
    }
    self.alive = NO;
    self.userInteractionEnabled = NO;
    [self.layer removeAllAnimations];
    // 关闭后停止接收手势；即使窗口已因抓屏隐藏，也必须拆掉窗口与内容的持有关系。
    for (UIGestureRecognizer *gesture in self.gestureRecognizers) {
        [self removeGestureRecognizer:gesture];
    }
    PXCaptureWindow *window = self.overlayWindow;
    id<PXFloatingSnapDelegate> delegate = self.delegate;
    self.overlayWindow = nil;
    self.delegate = nil;
    [self removeFromSuperview];

    PXLogInfo(@"floating snap dismissed");
    void (^finish)(void) = ^{
        if (completion) completion();
        if (delegate && [delegate respondsToSelector:@selector(floatingSnapDidClose:)]) {
            [delegate floatingSnapDidClose:self];
        }
    };
    if (window) {
        [window hideAndDestroyWithCompletion:finish];
    } else {
        finish();
    }
}

@end
