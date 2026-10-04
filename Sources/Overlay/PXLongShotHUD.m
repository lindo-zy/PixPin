#import "PXLongShotHUD.h"
const CGFloat PXLongShotHUDPreviewWidthPt = 88.0;

@interface PXLongShotHUD () <UIScrollViewDelegate>
@property (nonatomic, strong) UIVisualEffectView *panel;
@property (nonatomic, strong) UIScrollView *preview;
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UILabel *status;
@property (nonatomic, strong) UILabel *counter;
@property (nonatomic, strong) UIButton *finishButton;
@property (nonatomic, strong) UIButton *cancelButton;
@property (nonatomic, assign) BOOL previewDragging;
@end

@implementation PXLongShotHUD
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.clearColor;
        _panel = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterialDark]];
        _panel.layer.cornerRadius = 14;
        _panel.clipsToBounds = YES;
        [self addSubview:_panel];
        _preview = [[UIScrollView alloc] init];
        _preview.backgroundColor = UIColor.blackColor;
        _preview.layer.cornerRadius = 8;
        _preview.clipsToBounds = YES;
        _preview.showsHorizontalScrollIndicator = NO;
        _preview.delegate = self;
        [_panel.contentView addSubview:_preview];
        _imageView = [[UIImageView alloc] init];
        _imageView.contentMode = UIViewContentModeScaleToFill;
        [_preview addSubview:_imageView];
        _counter = [[UILabel alloc] init];
        _counter.font = [UIFont monospacedDigitSystemFontOfSize:10 weight:UIFontWeightMedium];
        _counter.textColor = UIColor.whiteColor;
        _counter.textAlignment = NSTextAlignmentCenter;
        [_panel.contentView addSubview:_counter];
        _status = [[UILabel alloc] init];
        _status.font = [UIFont systemFontOfSize:10];
        _status.textColor = [UIColor colorWithWhite:1 alpha:0.8];
        _status.numberOfLines = 2;
        _status.textAlignment = NSTextAlignmentCenter;
        _status.text = @"请缓慢向上滑动页面";
        [_panel.contentView addSubview:_status];
        _finishButton = [self pxButton:@"完成" color:UIColor.systemGreenColor selector:@selector(pxFinish)];
        _cancelButton = [self pxButton:@"取消" color:UIColor.systemRedColor selector:@selector(pxCancel)];
        [self setSliceCount:0];
    }
    return self;
}
- (UIButton *)pxButton:(NSString *)title color:(UIColor *)color selector:(SEL)selector {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:color forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    button.backgroundColor = [UIColor colorWithWhite:1 alpha:0.08];
    button.layer.cornerRadius = 7;
    [button addTarget:self action:selector forControlEvents:UIControlEventTouchUpInside];
    [self.panel.contentView addSubview:button];
    return button;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    UIEdgeInsets safe = self.safeAreaInsets;
    CGFloat width = PXLongShotHUDPreviewWidthPt + 16;
    CGFloat height = MIN(242, self.bounds.size.height - safe.top - safe.bottom - 20);
    CGFloat previewHeight = MAX(40, height - 114);
    self.panel.frame = CGRectMake(self.bounds.size.width - safe.right - 12 - width, safe.top + 10, width, height);
    self.preview.frame = CGRectMake(8, 8, width - 16, previewHeight);
    self.counter.frame = CGRectMake(4, previewHeight + 10, width - 8, 14);
    self.status.frame = CGRectMake(4, previewHeight + 25, width - 8, 28);
    self.finishButton.frame = CGRectMake(8, height - 76, width - 16, 32);
    self.cancelButton.frame = CGRectMake(8, height - 38, width - 16, 30);
}
- (void)pxFinish { [self.delegate longShotHUDDidTapFinish:self]; }
- (void)pxCancel { [self.delegate longShotHUDDidTapCancel:self]; }
- (void)setFinishing:(BOOL)finishing { self.finishButton.enabled = !finishing; }
- (void)setStatusText:(NSString *)text { if (text) self.status.text = text; }
- (void)setSliceCount:(NSInteger)count { self.counter.text = [NSString stringWithFormat:@"已采集 %ld 段", (long)count]; }
- (void)setPreviewImage:(UIImage *)image usedPixelHeight:(NSInteger)height {
    if (!image || height < 1 || image.size.width <= 0) return;
    [self layoutIfNeeded];
    CGFloat width = self.preview.bounds.size.width;
    CGFloat used = height / image.scale * width / image.size.width;
    self.imageView.image = image;
    self.imageView.frame = CGRectMake(0, 0, width, used);
    self.preview.contentSize = CGSizeMake(width, used);
    if (!self.isPreviewInteracting) {
        [self.preview setContentOffset:CGPointMake(0, MAX(0, used - self.preview.bounds.size.height)) animated:NO];
    }
}
- (BOOL)isPreviewInteracting { return self.previewDragging || self.preview.decelerating; }
- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView { self.previewDragging = YES; }
- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate { self.previewDragging = NO; }
@end
