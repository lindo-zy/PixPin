#import "PXResultBubble.h"
#import "PXCaptureWindow.h"
#import "../Common/PXLog.h"

@class PXCaptureTask;

@interface PXResultBubble ()
@property (nonatomic, strong) PXCaptureWindow *window;
@property (nonatomic, strong) UIImageView *thumbView;
@property (nonatomic, strong) UILabel *messageLabel;
@property (nonatomic, strong) UIButton *editButton;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, strong, nullable) PXCaptureTask *task;
@property (nonatomic, assign) NSUInteger dismissGeneration;
@end

@implementation PXResultBubble

+ (instancetype)presentWithImage:(nullable UIImage *)thumbnail
                         message:(NSString *)message
                            task:(nullable PXCaptureTask *)task
                       succeeded:(BOOL)succeeded
                        delegate:(id<PXResultBubbleDelegate>)delegate {
    if (![NSThread isMainThread]) {
        // 调用契约是主线程；误从后台调用时降级为异步弹出并返回 nil（不做等待式 sync，防死锁埋雷）。
        PXLogWarn(@"result bubble present called off main thread, deferring");
        dispatch_async(dispatch_get_main_queue(), ^{
            [self pxPresentWithImage:thumbnail message:message task:task succeeded:succeeded delegate:delegate];
        });
        return nil;
    }
    return [self pxPresentWithImage:thumbnail message:message task:task succeeded:succeeded delegate:delegate];
}

+ (instancetype)pxPresentWithImage:(UIImage *)thumbnail
                           message:(NSString *)message
                              task:(PXCaptureTask *)task
                         succeeded:(BOOL)succeeded
                          delegate:(id<PXResultBubbleDelegate>)delegate {
    // 成功态：缩略图 + 编辑 + 关闭；失败态：错误文字 + 关闭（诊断优先）。
    BOOL failureStyle = !succeeded || (task == nil);
    CGFloat bubbleWidth = failureStyle ? 240.0 : 164.0;
    CGFloat bubbleHeight = 60.0;
    CGRect frame = CGRectMake(0, 0, bubbleWidth, bubbleHeight);

    PXResultBubble *bubble = [[PXResultBubble alloc] initWithFrame:frame];
    bubble.task = task;
    bubble.delegate = delegate;
    bubble.thumbView.image = thumbnail;
    bubble.messageLabel.text = message ?: (failureStyle ? @"截图失败" : @"截图完成");
    bubble.editButton.hidden = failureStyle;
    bubble.thumbView.hidden = failureStyle;
    bubble.messageLabel.hidden = !failureStyle;

    PXCaptureWindow *window = [PXCaptureWindow pxCaptureWindow];
    window.windowLevel = 1000001.0;   // 高于选区窗口，低于系统紧急层级
    window.passesTouchesOutsideHostedContent = YES;
    bubble.window = window;
    UIView *bubbleHost = [[UIView alloc] initWithFrame:window.bounds];
    bubbleHost.backgroundColor = [UIColor clearColor];
    [bubbleHost addSubview:bubble];
    [window hostContentView:bubbleHost];
    bubble.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [bubble.trailingAnchor constraintEqualToAnchor:bubbleHost.safeAreaLayoutGuide.trailingAnchor constant:-14.0],
        [bubble.bottomAnchor constraintEqualToAnchor:bubbleHost.safeAreaLayoutGuide.bottomAnchor constant:-14.0],
        [bubble.widthAnchor constraintEqualToConstant:bubbleWidth],
        [bubble.heightAnchor constraintEqualToConstant:bubbleHeight],
    ]];
    [window showAnimated:NO becomeKey:NO];

    bubble.transform = CGAffineTransformMakeTranslation(bubbleWidth + 20, 0);
    [UIView animateWithDuration:0.25 animations:^{ bubble.transform = CGAffineTransformIdentity; }];

    // 4 秒自动消失；generation 令牌防止与手动关闭竞态。
    __weak PXResultBubble *weakBubble = bubble;
    NSUInteger generation = ++bubble.dismissGeneration;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [weakBubble pxAutoDismissIfGeneration:generation];
    });

    return bubble;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.backgroundColor = UIColor.clearColor;
        self.layer.cornerRadius = 18.0;
        self.layer.borderWidth = 0.5;
        self.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.18].CGColor;
        self.clipsToBounds = YES;

        UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:
            [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark]];
        blur.frame = self.bounds;
        blur.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        blur.contentView.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.04];
        blur.userInteractionEnabled = NO;
        [self addSubview:blur];

        _thumbView = [[UIImageView alloc] init];
        _thumbView.contentMode = UIViewContentModeScaleAspectFill;
        _thumbView.clipsToBounds = YES;
        _thumbView.layer.cornerRadius = 12.0;
        _thumbView.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.10];
        _thumbView.userInteractionEnabled = YES;
        _thumbView.isAccessibilityElement = YES;
        _thumbView.accessibilityLabel = @"编辑截图";
        _thumbView.accessibilityTraits = UIAccessibilityTraitButton;
        [self addSubview:_thumbView];

        _messageLabel = [[UILabel alloc] init];
        _messageLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        _messageLabel.textColor = [UIColor whiteColor];
        _messageLabel.adjustsFontSizeToFitWidth = YES;
        _messageLabel.text = @"截图完成";
        [self addSubview:_messageLabel];

        _editButton = [self pxMakeButtonWithTitle:@"编辑" symbol:@"pencil" action:@selector(pxEditTapped:)];
        _closeButton = [self pxMakeButtonWithTitle:@"关闭" symbol:@"xmark" action:@selector(pxCloseTapped:)];
        _editButton.hidden = YES;   // 失败气泡（无任务）没有可编辑结果

        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(pxTapGesture:)];
        [_thumbView addGestureRecognizer:tap];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat side = 44.0;
    CGFloat padding = 8.0;
    CGFloat y = (CGRectGetHeight(self.bounds) - side) / 2.0;
    _thumbView.frame = CGRectMake(padding, y, side, side);
    _editButton.frame = CGRectMake(padding + side + padding, y, side, side);
    _closeButton.frame = CGRectMake(CGRectGetWidth(self.bounds) - padding - side, y, side, side);
    _messageLabel.frame = CGRectMake(12.0, 0, CGRectGetMinX(_closeButton.frame) - 20.0,
                                    CGRectGetHeight(self.bounds));
}

- (UIButton *)pxMakeButtonWithTitle:(NSString *)title symbol:(NSString *)symbol action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.tintColor = [UIColor whiteColor];
    button.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    button.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.10];
    button.layer.cornerRadius = 12.0;
    button.clipsToBounds = YES;
    button.accessibilityLabel = title;
    UIImage *image = [UIImage systemImageNamed:symbol withConfiguration:
        [UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightMedium]];
    if (image) [button setImage:image forState:UIControlStateNormal];
    else [button setTitle:title forState:UIControlStateNormal];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:button];
    return button;
}

#pragma mark - 动作

- (void)pxNotifyTap {
    if (self.delegate && [self.delegate respondsToSelector:@selector(resultBubbleDidTap:)]) {
        [self.delegate resultBubbleDidTap:self];
    }
}

- (void)pxTapGesture:(UITapGestureRecognizer *)gesture {
    [self pxNotifyTap];
}

- (void)pxEditTapped:(UIButton *)sender {
    [self pxNotifyTap];
}

- (void)pxCloseTapped:(UIButton *)sender {
    [self dismissWithCompletion:nil];
}

#pragma mark - 关闭

- (void)updateThumbnailImage:(UIImage *)image {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self updateThumbnailImage:image]; });
        return;
    }
    if (self.window == nil) {
        return;   // 已关闭
    }
    self.thumbView.image = image;
}

- (void)pxAutoDismissIfGeneration:(NSUInteger)generation {
    if (generation != self.dismissGeneration) return;
    [self dismissWithCompletion:nil];
}

- (void)dismissWithCompletion:(void (^)(void))completion {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self dismissWithCompletion:completion]; });
        return;
    }

    self.dismissGeneration++;   // 令牌失效：取消尚未触发的自动消失
    PXCaptureWindow *window = self.window;
    id<PXResultBubbleDelegate> delegate = self.delegate;
    self.delegate = nil;

    void (^finish)(void) = ^{
        // 打断 bubble <-> window 的引用闭环，避免隐藏后泄漏。
        self.window = nil;
        if (completion) completion();
        if (delegate && [delegate respondsToSelector:@selector(resultBubbleDidDismiss:)]) {
            [delegate resultBubbleDidDismiss:self];
        }
    };

    [window hideAndDestroyWithCompletion:finish];
}

@end
