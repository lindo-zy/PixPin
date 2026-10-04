#import "PXLongShotHUD.h"

typedef NS_ENUM(NSInteger, PXLongShotHUDButton) {
    PXLongShotHUDButtonCancel = 0,
    PXLongShotHUDButtonCapture = 1,
    PXLongShotHUDButtonFinish = 2,
};

@interface PXLongShotHUD ()
@property (nonatomic, strong) UIView *bar;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UILabel *counterLabel;
@property (nonatomic, strong) UIButton *cancelButton;
@property (nonatomic, strong) UIButton *captureButton;
@property (nonatomic, strong) UIButton *finishButton;
@property (nonatomic, assign) BOOL hasSlices;
@end

@implementation PXLongShotHUD

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.backgroundColor = [UIColor clearColor];

        _bar = [[UIView alloc] init];
        _bar.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.92];
        _bar.layer.cornerRadius = 16.0;
        _bar.layer.shadowColor = [UIColor blackColor].CGColor;
        _bar.layer.shadowOpacity = 0.35;
        _bar.layer.shadowRadius = 10.0;
        _bar.layer.shadowOffset = CGSizeMake(0, 3);
        [self addSubview:_bar];

        _statusLabel = [[UILabel alloc] init];
        _statusLabel.font = [UIFont systemFontOfSize:12.0];
        _statusLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.75];
        _statusLabel.textAlignment = NSTextAlignmentCenter;
        _statusLabel.text = @"滚动页面后点「截取」逐段采集";
        [_bar addSubview:_statusLabel];

        _counterLabel = [[UILabel alloc] init];
        _counterLabel.font = [UIFont monospacedDigitSystemFontOfSize:13.0 weight:UIFontWeightMedium];
        _counterLabel.textColor = UIColor.whiteColor;
        _counterLabel.textAlignment = NSTextAlignmentLeft;
        _counterLabel.text = @"已截 0 段";
        [_bar addSubview:_counterLabel];

        _cancelButton = [self pxButton:@"取消" tag:PXLongShotHUDButtonCancel];
        _captureButton = [self pxButton:@"截取" tag:PXLongShotHUDButtonCapture];
        _captureButton.backgroundColor = [UIColor systemBlueColor];
        _captureButton.layer.cornerRadius = 10.0;
        _finishButton = [self pxButton:@"完成" tag:PXLongShotHUDButtonFinish];
        [_bar addSubview:_cancelButton];
        [_bar addSubview:_captureButton];
        [_bar addSubview:_finishButton];
        [self setSliceCount:0];
    }
    return self;
}

- (UIButton *)pxButton:(NSString *)title tag:(PXLongShotHUDButton)tag {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.titleLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [button setTitleColor:[UIColor colorWithWhite:1.0 alpha:0.4] forState:UIControlStateDisabled];
    button.tag = tag;
    [button addTarget:self action:@selector(pxButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)pxButtonTapped:(UIButton *)sender {
    if (!self.delegate) return;
    switch (sender.tag) {
        case PXLongShotHUDButtonCancel:
            [self.delegate longShotHUDDidTapCancel:self];
            break;
        case PXLongShotHUDButtonCapture:
            [self.delegate longShotHUDDidTapCapture:self];
            break;
        case PXLongShotHUDButtonFinish:
            [self.delegate longShotHUDDidTapFinish:self];
            break;
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat safeBottom = self.safeAreaInsets.bottom;
    CGFloat barWidth = MIN(344.0, self.bounds.size.width - 24.0);
    CGFloat barHeight = 88.0;
    self.bar.frame = CGRectMake((self.bounds.size.width - barWidth) / 2.0,
                                self.bounds.size.height - safeBottom - 14.0 - barHeight,
                                barWidth, barHeight);

    CGFloat pad = 14.0;
    self.statusLabel.frame = CGRectMake(pad, 10.0, barWidth - pad * 2.0, 16.0);

    CGFloat buttonTop = 34.0;
    CGFloat buttonHeight = 40.0;
    CGFloat captureWidth = 84.0;
    CGFloat sideWidth = 64.0;
    self.cancelButton.frame = CGRectMake(barWidth - pad - sideWidth, buttonTop, sideWidth, buttonHeight);
    self.captureButton.frame = CGRectMake(CGRectGetMinX(self.cancelButton.frame) - 8.0 - captureWidth,
                                          buttonTop, captureWidth, buttonHeight);
    self.finishButton.frame = CGRectMake(CGRectGetMinX(self.captureButton.frame) - 8.0 - sideWidth,
                                         buttonTop, sideWidth, buttonHeight);
    self.counterLabel.frame = CGRectMake(pad, buttonTop + 10.0,
                                         CGRectGetMinX(self.finishButton.frame) - pad - 8.0, 20.0);
}

#pragma mark - 状态

- (void)setBusy:(BOOL)busy statusText:(NSString *)statusText {
    self.captureButton.enabled = !busy;
    // 取消键忙时保持可用：截取/拼接任何阶段用户都能立即退出。
    self.finishButton.enabled = !busy && self.hasSlices;
    if (statusText) self.statusLabel.text = statusText;
}

- (void)setStatusText:(NSString *)statusText {
    if (statusText) self.statusLabel.text = statusText;
}

- (void)setSliceCount:(NSInteger)count {
    self.hasSlices = count > 0;
    self.finishButton.enabled = self.hasSlices && self.captureButton.enabled;
    self.counterLabel.text = [NSString stringWithFormat:@"已截 %ld 段", (long)count];
}

@end
