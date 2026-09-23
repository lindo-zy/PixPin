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
    CGRect screenBounds = [UIScreen mainScreen].bounds;
    // 成功态：缩略图 + 编辑 + 关闭；失败态：错误文字 + 关闭（诊断优先）。
    BOOL failureStyle = !succeeded || (task == nil);
    CGFloat bubbleWidth = failureStyle ? 240.0 : 136.0;
    CGFloat bubbleHeight = 54.0;
    CGRect frame = CGRectMake(14.0,
                              screenBounds.size.height - bubbleHeight - 34.0,
                              bubbleWidth, bubbleHeight);

    PXResultBubble *bubble = [[PXResultBubble alloc] initWithFrame:frame];
    bubble.task = task;
    bubble.delegate = delegate;
    bubble.thumbView.image = thumbnail;
    bubble.messageLabel.text = message ?: (failureStyle ? @"截图失败" : @"截图完成");
    bubble.editButton.hidden = failureStyle;
    bubble.messageLabel.hidden = !failureStyle;

    PXCaptureWindow *window = [PXCaptureWindow pxCaptureWindow];
    window.windowLevel = 1000001.0;   // 高于选区窗口，低于系统紧急层级
    window.frame = [UIScreen mainScreen].bounds;
    window.passesTouchesOutsideHostedContent = YES;
    bubble.window = window;
    UIView *bubbleHost = [[UIView alloc] initWithFrame:window.bounds];
    bubbleHost.backgroundColor = [UIColor clearColor];
    [bubbleHost addSubview:bubble];
    [window hostContentView:bubbleHost];
    bubble.frame = frame;
    [window showAnimated:NO becomeKey:NO];

    bubble.transform = CGAffineTransformMakeTranslation(-bubbleWidth - 20, 0);
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
        self.backgroundColor = [UIColor colorWithWhite:0.05 alpha:0.92];
        self.layer.cornerRadius = 12.0;
        self.clipsToBounds = YES;

        _thumbView = [[UIImageView alloc] initWithFrame:CGRectMake(6, 5, 44, 44)];
        _thumbView.contentMode = UIViewContentModeScaleAspectFill;
        _thumbView.clipsToBounds = YES;
        _thumbView.layer.cornerRadius = 8.0;
        _thumbView.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1.0];
        [self addSubview:_thumbView];

        CGFloat width = frame.size.width;
        _messageLabel = [[UILabel alloc] initWithFrame:CGRectMake(58, 0, width - 58 - 38, frame.size.height)];
        _messageLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        _messageLabel.textColor = [UIColor whiteColor];
        _messageLabel.adjustsFontSizeToFitWidth = YES;
        _messageLabel.text = @"截图完成";
        [self addSubview:_messageLabel];

        _editButton = [self pxMakeButtonWithTitle:@"编辑" action:@selector(pxEditTapped:)];
        _closeButton = [self pxMakeButtonWithTitle:@"✕" action:@selector(pxCloseTapped:)];
        _closeButton.frame = CGRectMake(width - 34, 0, 34, frame.size.height);
        _editButton.frame = CGRectMake(width - 82, 0, 44, frame.size.height);   // 与 ✕ 留 4pt 间隙
        _editButton.hidden = YES;   // 失败气泡（无任务）没有可编辑结果

        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(pxTapGesture:)];
        [self addGestureRecognizer:tap];
    }
    return self;
}

- (UIButton *)pxMakeButtonWithTitle:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.tintColor = [UIColor whiteColor];
    button.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    button.backgroundColor = [UIColor colorWithWhite:0.25 alpha:1.0];
    button.layer.cornerRadius = 10.0;
    [button setTitle:title forState:UIControlStateNormal];
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
