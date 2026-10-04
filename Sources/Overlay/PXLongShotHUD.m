#import "PXLongShotHUD.h"

const CGFloat PXLongShotHUDPreviewWidthPt = 88.0;

typedef NS_ENUM(NSInteger, PXLongShotHUDButton) {
    PXLongShotHUDButtonCancel = 0,
    PXLongShotHUDButtonFinish = 2,
};

static const CGFloat PXLongShotHUDPreviewHeight = 176.0;

@interface PXLongShotHUD () <UIScrollViewDelegate>
@property (nonatomic, strong) UIView *bar;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UILabel *counterLabel;
@property (nonatomic, strong) UIButton *cancelButton;
@property (nonatomic, strong) UIButton *finishButton;
@property (nonatomic, assign) BOOL scrolling;
// 实时预览浮窗
@property (nonatomic, strong) UIView *previewPanel;
@property (nonatomic, strong) UIScrollView *previewScroll;
@property (nonatomic, strong) UIImageView *previewImageView;
@property (nonatomic, strong) UIButton *previewToggle;
@property (nonatomic, assign) BOOL previewVisible;
@property (nonatomic, assign) BOOL previewDragging;
@property (nonatomic, assign) BOOL previewHasContent;
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
        _statusLabel.text = @"自动滚动截取中，点「完成」停止";
        [_bar addSubview:_statusLabel];

        _counterLabel = [[UILabel alloc] init];
        _counterLabel.font = [UIFont monospacedDigitSystemFontOfSize:13.0 weight:UIFontWeightMedium];
        _counterLabel.textColor = UIColor.whiteColor;
        _counterLabel.textAlignment = NSTextAlignmentLeft;
        _counterLabel.text = @"已截 0 段";
        [_bar addSubview:_counterLabel];

        _cancelButton = [self pxButton:@"取消" tag:PXLongShotHUDButtonCancel];
        _finishButton = [self pxButton:@"完成" tag:PXLongShotHUDButtonFinish];
        _finishButton.backgroundColor = UIColor.systemBlueColor;
        _finishButton.layer.cornerRadius = 10.0;
        [_bar addSubview:_cancelButton];
        [_bar addSubview:_finishButton];
        [self setSliceCount:0];

        // 实时预览浮窗：首段截取后才出现；触摸落在浮窗内不穿透（可滚动预览）。
        _previewPanel = [[UIView alloc] init];
        _previewPanel.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.92];
        _previewPanel.layer.cornerRadius = 12.0;
        _previewPanel.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.25].CGColor;
        _previewPanel.layer.borderWidth = 1.0;
        _previewPanel.clipsToBounds = YES;
        _previewPanel.hidden = YES;

        _previewScroll = [[UIScrollView alloc] init];
        _previewScroll.backgroundColor = [UIColor blackColor];
        _previewScroll.showsVerticalScrollIndicator = NO;
        _previewScroll.showsHorizontalScrollIndicator = NO;
        _previewScroll.delegate = self;
        [_previewPanel addSubview:_previewScroll];

        _previewImageView = [[UIImageView alloc] init];
        _previewImageView.contentMode = UIViewContentModeTop;   // 图高含分配余量，只显示上部有效区
        _previewImageView.clipsToBounds = YES;
        [_previewScroll addSubview:_previewImageView];
        [self addSubview:_previewPanel];

        _previewToggle = [UIButton buttonWithType:UIButtonTypeSystem];
        _previewToggle.tintColor = UIColor.whiteColor;
        [_previewToggle setImage:[UIImage systemImageNamed:@"eye"] forState:UIControlStateNormal];
        _previewToggle.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.92];
        _previewToggle.layer.cornerRadius = 15.0;
        [_previewToggle addTarget:self action:@selector(pxPreviewToggleTapped) forControlEvents:UIControlEventTouchUpInside];
        _previewToggle.hidden = YES;
        [self addSubview:_previewToggle];
        _previewVisible = YES;
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
        case PXLongShotHUDButtonFinish:
            [self.delegate longShotHUDDidTapFinish:self];
            break;
    }
}

- (void)pxPreviewToggleTapped {
    self.previewVisible = !self.previewVisible;
    [self pxApplyPreviewVisibility];
}

- (void)pxApplyPreviewVisibility {
    self.previewPanel.hidden = self.scrolling || !(self.previewHasContent && self.previewVisible);
    self.previewToggle.hidden = self.scrolling || !self.previewHasContent;
    UIImage *icon = [UIImage systemImageNamed:self.previewVisible ? @"eye.slash" : @"eye"];
    [self.previewToggle setImage:icon forState:UIControlStateNormal];
}

#pragma mark - 布局

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
    CGFloat sideWidth = 90.0;
    self.cancelButton.frame = CGRectMake(barWidth - pad - sideWidth, buttonTop, sideWidth, buttonHeight);
    self.finishButton.frame = CGRectMake(CGRectGetMinX(self.cancelButton.frame) - 8.0 - sideWidth,
                                         buttonTop, sideWidth, buttonHeight);
    self.counterLabel.frame = CGRectMake(pad, buttonTop + 10.0,
                                         CGRectGetMinX(self.finishButton.frame) - pad - 8.0, 20.0);

    CGFloat panelWidth = MIN(PXLongShotHUDPreviewWidthPt, self.bounds.size.width - 24.0);
    self.previewPanel.frame = CGRectMake(self.bounds.size.width - 12.0 - panelWidth,
                                         CGRectGetMinY(self.bar.frame) - 10.0 - PXLongShotHUDPreviewHeight,
                                         panelWidth, PXLongShotHUDPreviewHeight);
    self.previewScroll.frame = self.previewPanel.bounds;
    self.previewToggle.frame = CGRectMake(CGRectGetMinX(self.previewPanel.frame),
                                          CGRectGetMinY(self.previewPanel.frame) - 36.0, 30.0, 30.0);
    [self pxApplyPreviewVisibility];
}

#pragma mark - 状态

- (void)setFinishing:(BOOL)finishing {
    self.finishButton.enabled = !finishing;
}

- (void)setScrolling:(BOOL)scrolling {
    _scrolling = scrolling;
    [self pxApplyPreviewVisibility];
}

- (CGFloat)scrollProtectedBottomY {
    [self layoutIfNeeded];
    return CGRectGetMinY(self.bar.frame);
}

- (void)setStatusText:(NSString *)statusText {
    if (statusText) self.statusLabel.text = statusText;
}

- (void)setSliceCount:(NSInteger)count {
    self.counterLabel.text = [NSString stringWithFormat:@"已截 %ld 段", (long)count];
}

- (void)setPreviewImage:(UIImage *)image usedPixelHeight:(NSInteger)usedPixelHeight {
    if (!image || usedPixelHeight < 1) return;
    BOOL firstContent = !self.previewHasContent;
    self.previewHasContent = YES;

    CGFloat usedPt = (CGFloat)usedPixelHeight / image.scale;
    self.previewImageView.image = image;
    self.previewImageView.frame = CGRectMake(0, 0, image.size.width, usedPt);
    self.previewScroll.contentSize = CGSizeMake(image.size.width, usedPt);
    [self pxApplyPreviewVisibility];
    [self.previewPanel setNeedsLayout];
    [self.previewPanel layoutIfNeeded];

    // 自动滚到最新一段；用户正在拖动预览时不抢位置。
    if (!self.previewDragging) {
        CGFloat maxOffset = MAX(0.0, usedPt - self.previewScroll.bounds.size.height);
        [self.previewScroll setContentOffset:CGPointMake(0, maxOffset) animated:(!firstContent)];
    }
}

#pragma mark - UIScrollViewDelegate

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    self.previewDragging = YES;
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    if (!decelerate) self.previewDragging = NO;
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    self.previewDragging = NO;
}

@end
