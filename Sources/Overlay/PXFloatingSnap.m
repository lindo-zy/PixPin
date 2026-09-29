#import "PXFloatingSnap.h"
#import "PXCaptureWindow.h"
#import "../Common/PXLog.h"

static const CGFloat PXFloatSnapInset = 14.0;
static const CGFloat PXFloatSnapBarHeight = 40.0;

@interface PXFloatingSnap ()
@property (nonatomic, strong, readwrite) UIImage *image;
@property (nonatomic, assign, readwrite) PXCaptureMode captureMode;
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) PXCaptureWindow *window;
@property (nonatomic, strong) UIVisualEffectView *actionBar;
@property (nonatomic, strong) NSArray<UIButton *> *actionButtons;
@property (nonatomic, assign) BOOL actionBarVisible;
@property (nonatomic, assign) BOOL alive;
@property (nonatomic, assign) CGRect dragStartFrame;
@end

@implementation PXFloatingSnap

- (void)setImage:(UIImage *)image {
    _image = image;
    self.imageView.image = image;
}

+ (instancetype)presentWithImage:(UIImage *)image
                            mode:(PXCaptureMode)mode
                        delegate:(id<PXFloatingSnapDelegate>)delegate {
    if (![NSThread isMainThread]) {
        // 调用契约是主线程。降级路径只记日志不弹出：异步弹出会返回 nil，调用方将永远无法 dismiss，
        // 悬浮窗会沦为无人能关的孤儿窗口。
        PXLogWarn(@"floating snap present called off main thread, dropped");
        return nil;
    }
    return [self pxPresentWithImage:image mode:mode delegate:delegate];
}

+ (instancetype)pxPresentWithImage:(UIImage *)image
                              mode:(PXCaptureMode)mode
                          delegate:(id<PXFloatingSnapDelegate>)delegate {
    if (!image || image.size.width <= 0 || image.size.height <= 0) return nil;

    CGRect screenBounds = [UIScreen mainScreen].bounds;
    CGSize size = [self pxDisplaySizeForImageSize:image.size screenBounds:screenBounds];
    // 默认停靠右上（避开左下角结果气泡），后续位置完全跟随用户拖动。
    CGRect frame = CGRectMake(screenBounds.size.width - size.width - PXFloatSnapInset,
                              MAX(PXFloatSnapInset, screenBounds.size.height * 0.18),
                              size.width, size.height);

    PXFloatingSnap *snap = [[PXFloatingSnap alloc] initWithFrame:frame];
    snap.image = image;
    snap.captureMode = mode;
    snap.delegate = delegate;
    snap.alive = YES;

    PXCaptureWindow *window = [PXCaptureWindow pxCaptureWindow];
    window.windowLevel = 999000.0;   // 低于选区/编辑器（1000000）与结果气泡（1000001）
    window.frame = screenBounds;
    window.passesTouchesOutsideHostedContent = YES;
    snap.window = window;
    UIView *host = [[UIView alloc] initWithFrame:window.bounds];
    host.backgroundColor = [UIColor clearColor];
    [host addSubview:snap];
    snap.frame = frame;
    [window hostContentView:host];
    [window showAnimated:NO becomeKey:NO];

    snap.transform = CGAffineTransformMakeScale(0.6, 0.6);
    snap.alpha = 0.0;
    [UIView animateWithDuration:0.22 animations:^{ snap.transform = CGAffineTransformIdentity; }];
    PXLogInfo(@"floating snap presented (mode %ld, image %.0fx%.0f px)",
              (long)mode, image.size.width * image.scale, image.size.height * image.scale);
    return snap;
}

/// 悬浮展示尺寸：等比放进 46% 宽 × 38% 高的屏幕区域内，下限 88pt 保证可点可拖。
+ (CGSize)pxDisplaySizeForImageSize:(CGSize)imageSize screenBounds:(CGRect)screenBounds {
    CGFloat maxWidth = screenBounds.size.width * 0.46;
    CGFloat maxHeight = screenBounds.size.height * 0.38;
    CGFloat scale = MIN(maxWidth / imageSize.width, maxHeight / imageSize.height);
    CGSize size = CGSizeMake(floor(imageSize.width * scale), floor(imageSize.height * scale));
    CGFloat aspect = imageSize.width / imageSize.height;
    if (size.width < 88.0) {
        size.width = 88.0;
        size.height = floor(size.width / aspect);
    }
    if (size.height < 88.0) {
        size.height = 88.0;
        size.width = floor(size.height * aspect);
    }
    return size;
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
        // 顺序固定 编辑/保存/复制/关闭；语义走 tag 分支，文案可改不破逻辑。
        NSArray<NSArray *> *items = @[
            @[@"编辑", @0, NSStringFromSelector(@selector(pxEditTapped:))],
            @[@"保存", @1, NSStringFromSelector(@selector(pxOutputTapped:))],
            @[@"复制", @2, NSStringFromSelector(@selector(pxOutputTapped:))],
            @[@"关闭", @3, NSStringFromSelector(@selector(pxCloseTapped:))],
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
        [self addGestureRecognizer:tap];
        UIPanGestureRecognizer *pan =
            [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pxPanGesture:)];
        [self addGestureRecognizer:pan];
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

- (void)pxTapGesture:(UITapGestureRecognizer *)gesture {
    self.actionBarVisible = !self.actionBarVisible;
    [UIView animateWithDuration:0.18 animations:^{
        self.actionBar.alpha = self.actionBarVisible ? 1.0 : 0.0;
    }];
}

- (void)pxPanGesture:(UIPanGestureRecognizer *)gesture {
    switch (gesture.state) {
        case UIGestureRecognizerStateBegan:
            self.dragStartFrame = self.frame;
            break;
        case UIGestureRecognizerStateChanged: {
            CGPoint translation = [gesture translationInView:self.superview];
            CGRect frame = self.dragStartFrame;
            frame.origin.x += translation.x;
            frame.origin.y += translation.y;
            CGRect bounds = self.window.bounds;
            frame.origin.x = MAX(-frame.size.width * 0.4, MIN(frame.origin.x, bounds.size.width - frame.size.width * 0.6));
            frame.origin.y = MAX(0, MIN(frame.origin.y, bounds.size.height - PXFloatSnapBarHeight));
            self.frame = frame;
            break;
        }
        default:
            break;
    }
}

#pragma mark - 动作

- (void)pxNotifyEdit {
    if (self.delegate && [self.delegate respondsToSelector:@selector(floatingSnapDidRequestEdit:)]) {
        [self.delegate floatingSnapDidRequestEdit:self];
    }
}

- (void)pxNotifyOutput:(PXOutputAction)action {
    if (self.delegate && [self.delegate respondsToSelector:@selector(floatingSnapDidRequestOutput:action:)]) {
        [self.delegate floatingSnapDidRequestOutput:self action:action];
    }
}

- (void)pxEditTapped:(UIButton *)sender {
    [self pxNotifyEdit];
}

- (void)pxOutputTapped:(UIButton *)sender {
    PXOutputAction action = (sender.tag == 1) ? PXOutputActionSave : PXOutputActionCopy;
    [self pxNotifyOutput:action];
}

- (void)pxCloseTapped:(UIButton *)sender {
    [self dismissWithCompletion:nil];
}

#pragma mark - 生命周期

- (void)hideForCapture {
    if (!self.alive || !self.window) return;
    self.window.hidden = YES;
}

- (void)restoreAfterCapture {
    if (!self.alive || !self.window) return;
    self.window.hidden = NO;
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
    // tap/pan 手势的 target 是 self：不移除会形成 self→手势→self 强引用环，
    // 窗口销毁后 snap（含全分辨率裁剪图）永不释放（同 PXSelectionView.prepareForDismissal 的处理）。
    for (UIGestureRecognizer *gesture in self.gestureRecognizers) {
        [self removeGestureRecognizer:gesture];
    }
    PXCaptureWindow *window = self.window;
    id<PXFloatingSnapDelegate> delegate = self.delegate;
    self.window = nil;
    self.delegate = nil;

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
