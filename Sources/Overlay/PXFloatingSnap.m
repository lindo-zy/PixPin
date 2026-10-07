#import "PXFloatingSnap.h"
#import "PXCaptureWindow.h"
#import "../Common/PXLog.h"
#import "../Common/PXPreferences.h"

static const CGFloat PXFloatSnapBarHeight = 44.0;

@interface PXFloatingSnap () <UIGestureRecognizerDelegate>
@property (nonatomic, strong, readwrite) UIImage *image;
@property (nonatomic, assign, readwrite) PXCaptureMode captureMode;
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, assign) BOOL shadowEnabled;
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
                      screenRect:(CGRect)screenRect
                          shadow:(BOOL)shadowEnabled {
    if (![NSThread isMainThread]) {
        // 调用契约是主线程。降级路径只记日志不弹出：异步弹出会返回 nil，调用方将永远无法 dismiss，
        // 悬浮窗会沦为无人能关的孤儿窗口。
        PXLogWarn(@"floating snap present called off main thread, dropped");
        return nil;
    }
    return [self pxPresentWithImage:image mode:mode delegate:delegate screenRect:screenRect shadow:shadowEnabled];
}

+ (instancetype)pxPresentWithImage:(UIImage *)image
                              mode:(PXCaptureMode)mode
                          delegate:(id<PXFloatingSnapDelegate>)delegate
                        screenRect:(CGRect)screenRect
                            shadow:(BOOL)shadowEnabled {
    if (!image || image.size.width <= 0 || image.size.height <= 0) return nil;

    PXCaptureWindow *window = [PXCaptureWindow pxCaptureWindow];
    CGRect screenBounds = window.bounds;
    CGRect frame = [window convertRect:screenRect fromCoordinateSpace:window.screen.coordinateSpace];
    frame = PXConstrainFloatingRect(frame, screenBounds);
    if (CGRectIsEmpty(frame)) return nil;

    PXFloatingSnap *snap = [[PXFloatingSnap alloc] initWithFrame:frame];
    snap.image = image;
    snap.captureMode = mode;
    snap.delegate = delegate;
    snap.alive = YES;
    snap.shadowEnabled = shadowEnabled;
    [snap pxApplyShadow];

    window.windowLevel = 999000.0;   // 低于选区/编辑器（1000000）与结果气泡（1000001）
    window.frame = screenBounds;
    window.passesTouchesOutsideHostedContent = YES;
    snap.overlayWindow = window;
    PXFloatingSnapHostView *host = [[PXFloatingSnapHostView alloc] initWithFrame:window.bounds];
    host.snap = snap;
    host.backgroundColor = [UIColor clearColor];
    [host addSubview:snap];
    [host addSubview:snap.actionBar];
    snap.frame = frame;
    [window hostContentView:host];
    [window showAnimated:NO becomeKey:NO];

    snap.alpha = 0.0;
    [UIView animateWithDuration:0.22 animations:^{
        snap.alpha = 1.0;
    }];
    PXLogInfo(@"floating snap presented (mode %ld, image %.0fx%.0f px, frame %@)",
              (long)mode, image.size.width * image.scale, image.size.height * image.scale, NSStringFromCGRect(snap.frame));
    return snap;
}

- (void)constrainToHostBounds {
    if (!self.alive || !self.superview) return;
    // 使用整个屏幕，不能用安全区把靠近屏幕边缘的原选区挤走。
    CGRect frame = PXConstrainFloatingRect(self.frame, self.superview.bounds);
    if (!CGRectIsEmpty(frame)) self.frame = frame;
    [self pxLayoutActionBar];
}

- (void)updateImage:(UIImage *)image {
    if (!self.alive || !image || image.size.width <= 0 || image.size.height <= 0) return;
    // 编辑裁剪或旋转后保留每个源像素的显示比例。
    CGFloat pointsPerPixel = self.bounds.size.width / (self.image.size.width * self.image.scale);
    CGRect frame = self.frame;
    frame.size = CGSizeMake(image.size.width * image.scale * pointsPerPixel,
                            image.size.height * image.scale * pointsPerPixel);
    self.image = image;
    self.frame = frame;
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

        // 菜单由同一窗口独立托管，不扩大或裁剪小选区图片。
        _actionBar = [[UIVisualEffectView alloc] initWithEffect:
                      [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterialDark]];
        _actionBar.layer.cornerRadius = 12.0;
        _actionBar.clipsToBounds = YES;
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

#pragma mark - 外观

// 投影画在自身 layer 上，自身不能再裁剪：圆角裁剪下沉到 imageView，避免把阴影裁没。
- (void)pxApplyShadow {
    if (!self.shadowEnabled) return;
    self.clipsToBounds = NO;
    self.layer.shadowColor = UIColor.blackColor.CGColor;
    self.layer.shadowOpacity = 0.45;
    self.layer.shadowRadius = 16.0;
    self.layer.shadowOffset = CGSizeMake(0.0, 6.0);
    self.imageView.layer.cornerRadius = self.layer.cornerRadius;
    self.imageView.clipsToBounds = YES;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (self.shadowEnabled) {
        // 显式 shadowPath：拖动和 updateImage 改 frame 时随 layout 同步，避免逐帧离屏渲染。
        self.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.bounds
                                                           cornerRadius:self.layer.cornerRadius].CGPath;
    }
    [self pxLayoutActionBar];
}

- (void)pxLayoutActionBar {
    if (!self.superview || !self.actionButtons.count) return;
    CGRect allowed = UIEdgeInsetsInsetRect(self.superview.bounds, self.superview.safeAreaInsets);
    CGFloat width = MIN(allowed.size.width, MAX(176.0, MIN(self.bounds.size.width, 320.0)));
    CGFloat x = MAX(CGRectGetMinX(allowed), MIN(CGRectGetMidX(self.frame) - width / 2.0, CGRectGetMaxX(allowed) - width));
    CGFloat y = CGRectGetMaxY(self.frame) + 8.0;
    if (y + PXFloatSnapBarHeight > CGRectGetMaxY(allowed)) y = CGRectGetMinY(self.frame) - 8.0 - PXFloatSnapBarHeight;
    y = MAX(CGRectGetMinY(allowed), MIN(y, CGRectGetMaxY(allowed) - PXFloatSnapBarHeight));
    self.actionBar.frame = CGRectMake(x, y, width, PXFloatSnapBarHeight);
    CGFloat buttonWidth = width / self.actionButtons.count;
    for (NSUInteger i = 0; i < self.actionButtons.count; i++) {
        self.actionButtons[i].frame = CGRectMake(i * buttonWidth, 0, buttonWidth, PXFloatSnapBarHeight);
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
    [self pxLayoutActionBar];
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
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled:
            [self pxApplyEdgeSnap];
            break;
        default:
            break;
    }
}

#pragma mark - 边缘吸附

// 松手时按 FloatingSnapEdgeDistance 吸附（0=关闭）：x/y 两轴独立贴到「边缘+距离」，
// 取较近一侧；动画只动位置，constrainToHostBounds 的钳制口径保持不变。
- (void)pxApplyEdgeSnap {
    if (!self.superview) return;
    CGFloat distance = [PXPreferences config].floatingSnapEdgeDistance;
    if (distance <= 0.0) return;
    CGRect target = PXApplyFloatingSnapEdge(self.frame, self.superview.bounds, distance);
    if (CGRectEqualToRect(target, self.frame)) return;
    [UIView animateWithDuration:0.2 delay:0.0
        options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
        animations:^{
            self.frame = target;
        }
        completion:nil];
    [self pxLayoutActionBar];
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
    [self.actionBar removeFromSuperview];
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
