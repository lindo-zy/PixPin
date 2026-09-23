#import "PXColorPickerView.h"

static const CGFloat PXPickerAccentRed = 1.0;
static const CGFloat PXPickerAccentGreen = 0.78;
static const CGFloat PXPickerAccentBlue = 0.08;

static UIColor *PXPickerAccentColor(void) {
    return [UIColor colorWithRed:PXPickerAccentRed green:PXPickerAccentGreen blue:PXPickerAccentBlue alpha:1.0];
}

#pragma mark - 饱和度/亮度二维区

/// 水平轴 = 饱和度 0→1，垂直轴 = 亮度 1→0；背景按当前色相实时重绘。
@interface PXSVAreaControl : UIControl
@property (nonatomic, assign) CGFloat hue;
@property (nonatomic, assign) CGFloat saturation;
@property (nonatomic, assign) CGFloat brightness;
@end

@implementation PXSVAreaControl

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        _hue = 0.0;
        _saturation = 1.0;
        _brightness = 1.0;
        self.layer.cornerRadius = 12.0;
        self.layer.masksToBounds = YES;   // 渐变随圆角裁切
    }
    return self;
}

- (void)setHue:(CGFloat)hue {
    _hue = hue;
    [self setNeedsDisplay];
}

- (void)setSaturation:(CGFloat)saturation {
    _saturation = saturation;
    [self setNeedsDisplay];
}

- (void)setBrightness:(CGFloat)brightness {
    _brightness = brightness;
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx || rect.size.width <= 0 || rect.size.height <= 0) return;
    CGFloat w = rect.size.width;
    CGFloat h = rect.size.height;

    CGContextSetFillColorWithColor(ctx,
        [UIColor colorWithHue:self.hue saturation:1.0 brightness:1.0 alpha:1.0].CGColor);
    CGContextFillRect(ctx, rect);

    // 白（左）→ 透明（右）
    CGGradientRef whiteGradient = CGGradientCreateWithColors(NULL, (__bridge CFArrayRef)@[
        (__bridge id)[UIColor whiteColor].CGColor,
        (__bridge id)[UIColor colorWithWhite:1.0 alpha:0.0].CGColor,
    ], (const CGFloat[]){0.0, 1.0});
    CGContextDrawLinearGradient(ctx, whiteGradient, CGPointMake(0, 0), CGPointMake(w, 0), 0);
    CGGradientRelease(whiteGradient);

    // 透明（上）→ 黑（下）
    CGGradientRef blackGradient = CGGradientCreateWithColors(NULL, (__bridge CFArrayRef)@[
        (__bridge id)[UIColor colorWithWhite:0.0 alpha:0.0].CGColor,
        (__bridge id)[UIColor blackColor].CGColor,
    ], (const CGFloat[]){0.0, 1.0});
    CGContextDrawLinearGradient(ctx, blackGradient, CGPointMake(0, 0), CGPointMake(0, h), 0);
    CGGradientRelease(blackGradient);

    // 光标：当前色圆点 + 白描边（钳在可视范围内）
    CGFloat r = 11.0;
    CGFloat cx = MAX(r, MIN(w - r, self.saturation * w));
    CGFloat cy = MAX(r, MIN(h - r, (1.0 - self.brightness) * h));
    CGContextSetFillColorWithColor(ctx,
        [UIColor colorWithHue:self.hue saturation:self.saturation brightness:self.brightness alpha:1.0].CGColor);
    CGContextFillEllipseInRect(ctx, CGRectMake(cx - r, cy - r, r * 2.0, r * 2.0));
    CGContextSetStrokeColorWithColor(ctx, [UIColor whiteColor].CGColor);
    CGContextSetLineWidth(ctx, 2.5);
    CGContextStrokeEllipseInRect(ctx, CGRectMake(cx - r, cy - r, r * 2.0, r * 2.0));
}

- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(nullable UIEvent *)event {
    [self pxUpdateFromTouch:touch];
    return YES;
}

- (BOOL)continueTrackingWithTouch:(UITouch *)touch withEvent:(nullable UIEvent *)event {
    [self pxUpdateFromTouch:touch];
    return YES;
}

- (void)pxUpdateFromTouch:(UITouch *)touch {
    CGPoint point = [touch locationInView:self];
    CGFloat w = MAX(1.0, self.bounds.size.width);
    CGFloat h = MAX(1.0, self.bounds.size.height);
    self.saturation = MAX(0.0, MIN(1.0, point.x / w));
    self.brightness = MAX(0.0, MIN(1.0, 1.0 - point.y / h));
    [self sendActionsForControlEvents:UIControlEventValueChanged];
}

@end

#pragma mark - 色相条

@interface PXHueBarControl : UIControl
@property (nonatomic, assign) CGFloat hue;
@end

@implementation PXHueBarControl

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        _hue = 0.0;
        self.layer.cornerRadius = 9.0;
        self.layer.masksToBounds = YES;
    }
    return self;
}

- (void)setHue:(CGFloat)hue {
    _hue = hue;
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx || rect.size.width <= 0) return;
    CGFloat w = rect.size.width;
    CGFloat h = rect.size.height;

    NSMutableArray<id> *stops = [NSMutableArray array];
    for (NSUInteger i = 0; i <= 6; i++) {
        [stops addObject:(id)[UIColor colorWithHue:(CGFloat)i / 6.0 saturation:1.0 brightness:1.0 alpha:1.0].CGColor];
    }
    CGGradientRef rainbow = CGGradientCreateWithColors(NULL, (__bridge CFArrayRef)stops, NULL);
    CGContextDrawLinearGradient(ctx, rainbow, CGPointZero, CGPointMake(w, 0), 0);
    CGGradientRelease(rainbow);

    CGFloat cursorWidth = 10.0;
    CGFloat x = MAX(0.0, MIN(w - cursorWidth, self.hue * w - cursorWidth / 2.0));
    CGContextSetStrokeColorWithColor(ctx, [UIColor whiteColor].CGColor);
    CGContextSetLineWidth(ctx, 3.0);
    CGContextStrokeRect(ctx, CGRectMake(x + 1.5, 3.0, cursorWidth - 3.0, h - 6.0));
}

- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(nullable UIEvent *)event {
    [self pxUpdateFromTouch:touch];
    return YES;
}

- (BOOL)continueTrackingWithTouch:(UITouch *)touch withEvent:(nullable UIEvent *)event {
    [self pxUpdateFromTouch:touch];
    return YES;
}

- (void)pxUpdateFromTouch:(UITouch *)touch {
    CGPoint point = [touch locationInView:self];
    CGFloat w = MAX(1.0, self.bounds.size.width);
    self.hue = MAX(0.0, MIN(1.0, point.x / w));
    [self sendActionsForControlEvents:UIControlEventValueChanged];
}

@end

#pragma mark - 取色器视图

@interface PXColorPickerView ()
@property (nonatomic, strong) UIControl *dimControl;
@property (nonatomic, strong) UIView *sheetView;
@property (nonatomic, strong) UIButton *cancelButton;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIButton *confirmButton;
@property (nonatomic, strong) PXSVAreaControl *svArea;
@property (nonatomic, strong) PXHueBarControl *hueBar;
@property (nonatomic, strong) UIView *previewSwatch;
@property (nonatomic, strong) UILabel *hexLabel;
@property (nonatomic, strong) UILabel *recentsEmptyLabel;
@property (nonatomic, strong) NSMutableArray<UIButton *> *recentButtons;
@property (nonatomic, copy) NSArray<UIColor *> *recentColors;
@end

@implementation PXColorPickerView

- (instancetype)initWithColor:(nullable UIColor *)initialColor
                 recentColors:(NSArray<UIColor *> *)recentColors {
    if (self = [super initWithFrame:CGRectZero]) {
        CGFloat hue = 0.0, saturation = 1.0, brightness = 1.0, alpha = 1.0;
        if ([initialColor getHue:&hue saturation:&saturation brightness:&brightness alpha:&alpha]) {
            // 灰色系 hue 无意义，取回 0 即可
        }
        _recentColors = [recentColors copy] ?: @[];
        _recentButtons = [[NSMutableArray alloc] init];

        [self pxBuildSubviews];
        self.svArea.hue = hue;
        self.svArea.saturation = saturation;
        self.svArea.brightness = brightness;
        self.hueBar.hue = hue;
        [self pxRefreshPreview];
    }
    return self;
}

- (void)pxBuildSubviews {
    _dimControl = [[UIControl alloc] init];
    _dimControl.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.45];
    _dimControl.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [_dimControl addTarget:self action:@selector(pxCancelTapped) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:_dimControl];

    _sheetView = [[UIView alloc] init];
    _sheetView.backgroundColor = [UIColor colorWithWhite:0.09 alpha:1.0];
    _sheetView.layer.cornerRadius = 16.0;
    if (@available(iOS 11.0, *)) {
        _sheetView.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    }
    [self addSubview:_sheetView];

    _cancelButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _cancelButton.tintColor = [UIColor whiteColor];
    _cancelButton.titleLabel.font = [UIFont systemFontOfSize:16];
    [_cancelButton setTitle:@"取消" forState:UIControlStateNormal];
    [_cancelButton addTarget:self action:@selector(pxCancelTapped) forControlEvents:UIControlEventTouchUpInside];
    [_sheetView addSubview:_cancelButton];

    _titleLabel = [[UILabel alloc] init];
    _titleLabel.text = @"颜色";
    _titleLabel.textColor = [UIColor whiteColor];
    _titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    _titleLabel.textAlignment = NSTextAlignmentCenter;
    [_sheetView addSubview:_titleLabel];

    _confirmButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _confirmButton.tintColor = PXPickerAccentColor();
    _confirmButton.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    [_confirmButton setTitle:@"完成" forState:UIControlStateNormal];
    [_confirmButton addTarget:self action:@selector(pxConfirmTapped) forControlEvents:UIControlEventTouchUpInside];
    [_sheetView addSubview:_confirmButton];

    _svArea = [[PXSVAreaControl alloc] init];
    [_svArea addTarget:self action:@selector(pxControlChanged) forControlEvents:UIControlEventValueChanged];
    [_sheetView addSubview:_svArea];

    _hueBar = [[PXHueBarControl alloc] init];
    [_hueBar addTarget:self action:@selector(pxControlChanged) forControlEvents:UIControlEventValueChanged];
    [_sheetView addSubview:_hueBar];

    _previewSwatch = [[UIView alloc] init];
    _previewSwatch.layer.cornerRadius = 8.0;
    _previewSwatch.layer.borderWidth = 1.0;
    _previewSwatch.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.35].CGColor;
    [_sheetView addSubview:_previewSwatch];

    _hexLabel = [[UILabel alloc] init];
    _hexLabel.textColor = [UIColor colorWithWhite:0.7 alpha:1.0];
    _hexLabel.font = [UIFont monospacedDigitSystemFontOfSize:14 weight:UIFontWeightRegular];
    [_sheetView addSubview:_hexLabel];

    _recentsEmptyLabel = [[UILabel alloc] init];
    _recentsEmptyLabel.text = @"暂无最近使用的颜色";
    _recentsEmptyLabel.textColor = [UIColor colorWithWhite:0.45 alpha:1.0];
    _recentsEmptyLabel.font = [UIFont systemFontOfSize:13];
    [_sheetView addSubview:_recentsEmptyLabel];

    for (NSUInteger i = 0; i < self.recentColors.count && i < 8; i++) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        button.backgroundColor = self.recentColors[i];
        button.layer.cornerRadius = 15.0;
        button.layer.borderWidth = 1.5;
        button.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.25].CGColor;
        button.tag = (NSInteger)i;
        button.accessibilityLabel = @"最近使用的颜色";
        [button addTarget:self action:@selector(pxRecentTapped:) forControlEvents:UIControlEventTouchUpInside];
        [_sheetView addSubview:button];
        [self.recentButtons addObject:button];
    }
}

// 面板自上而下：标题行 / SV 二维区 / 色相条 / 预览 / 最近使用色。
- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat width = self.bounds.size.width;
    CGFloat height = self.bounds.size.height;
    CGFloat bottom = self.safeAreaInsets.bottom;
    CGFloat pad = 16.0;

    // 矮屏/横屏兜底：SV 区按剩余高度压缩（110~170），保证标题行始终在屏内可达。
    CGFloat fixedRows = 8.0 + 40.0 + 12.0 + 14.0 + 36.0 + 16.0 + 30.0 + 14.0 + 36.0 + 12.0;
    CGFloat availableForSV = height - bottom - fixedRows;
    CGFloat svHeight = MAX(110.0, MIN(170.0, availableForSV));
    CGFloat sheetHeight = fixedRows + svHeight;
    CGFloat maxSheet = height - bottom;
    if (sheetHeight > maxSheet) sheetHeight = maxSheet;

    _dimControl.frame = self.bounds;
    _sheetView.frame = CGRectMake(0, height - sheetHeight - bottom, width, sheetHeight + bottom);

    CGFloat y = 8.0;
    self.cancelButton.frame = CGRectMake(pad, y, 60.0, 40.0);
    self.titleLabel.frame = CGRectMake(pad + 60.0, y, width - (pad + 60.0) * 2.0, 40.0);
    self.confirmButton.frame = CGRectMake(width - pad - 60.0, y, 60.0, 40.0);
    y += 40.0 + 12.0;

    self.svArea.frame = CGRectMake(pad, y, width - pad * 2.0, svHeight);
    y += svHeight + 14.0;

    self.hueBar.frame = CGRectMake(pad, y, width - pad * 2.0, 36.0);
    y += 36.0 + 16.0;

    self.previewSwatch.frame = CGRectMake(pad, y, 52.0, 30.0);
    self.hexLabel.frame = CGRectMake(pad + 64.0, y, 120.0, 30.0);
    y += 30.0 + 14.0;

    CGFloat dotSize = 30.0;
    CGFloat dotStep = 38.0;
    self.recentsEmptyLabel.frame = CGRectMake(pad, y + 4.0, width - pad * 2.0, 24.0);
    self.recentsEmptyLabel.hidden = (self.recentButtons.count > 0);
    for (NSUInteger i = 0; i < self.recentButtons.count; i++) {
        UIButton *button = self.recentButtons[i];
        button.frame = CGRectMake(pad + (CGFloat)i * dotStep, y, dotSize, dotSize);
    }
}

#pragma mark - 状态

- (UIColor *)pxCurrentColor {
    return [UIColor colorWithHue:self.hueBar.hue
                      saturation:self.svArea.saturation
                      brightness:self.svArea.brightness
                           alpha:1.0];
}

- (void)pxRefreshPreview {
    UIColor *color = [self pxCurrentColor];
    self.previewSwatch.backgroundColor = color;
    self.hexLabel.text = [PXColorPickerView hexStringForColor:color];
}

- (void)pxSelectColor:(UIColor *)color {
    CGFloat hue = 0.0, saturation = 0.0, brightness = 0.0, alpha = 0.0;
    if (![color getHue:&hue saturation:&saturation brightness:&brightness alpha:&alpha]) return;
    self.hueBar.hue = hue;
    self.svArea.hue = hue;
    self.svArea.saturation = saturation;
    self.svArea.brightness = brightness;
    [self pxControlChanged];
}

#pragma mark - 动作

- (void)pxControlChanged {
    [self pxRefreshPreview];
    if (self.delegate && [self.delegate respondsToSelector:@selector(colorPicker:didPreviewColor:)]) {
        [self.delegate colorPicker:self didPreviewColor:[self pxCurrentColor]];
    }
}

- (void)pxRecentTapped:(UIButton *)sender {
    if (sender.tag < 0 || (NSUInteger)sender.tag >= self.recentColors.count) return;
    [self pxSelectColor:self.recentColors[(NSUInteger)sender.tag]];
}

- (void)pxCancelTapped {
    if (self.delegate && [self.delegate respondsToSelector:@selector(colorPickerDidCancel:)]) {
        [self.delegate colorPickerDidCancel:self];
    }
}

- (void)pxConfirmTapped {
    if (self.delegate && [self.delegate respondsToSelector:@selector(colorPicker:didConfirmColor:)]) {
        [self.delegate colorPicker:self didConfirmColor:[self pxCurrentColor]];
    }
}

#pragma mark - 展示与移除

- (void)showInView:(UIView *)parent animated:(BOOL)animated completion:(void (^)(void))completion {
    self.frame = parent.bounds;
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [parent addSubview:self];

    if (!animated) {
        if (completion) completion();
        return;
    }
    self.alpha = 0.0;
    self.sheetView.transform = CGAffineTransformMakeTranslation(0, self.sheetView.bounds.size.height);
    [UIView animateWithDuration:0.22 delay:0.0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        self.alpha = 1.0;
        self.sheetView.transform = CGAffineTransformIdentity;
    } completion:^(BOOL finished) {
        if (completion) completion();
    }];
}

- (void)dismissAnimated:(BOOL)animated completion:(void (^)(void))completion {
    if (!animated || self.superview == nil) {
        [self removeFromSuperview];
        if (completion) completion();
        return;
    }
    [UIView animateWithDuration:0.18 delay:0.0 options:UIViewAnimationOptionCurveEaseIn animations:^{
        self.alpha = 0.0;
        self.sheetView.transform = CGAffineTransformMakeTranslation(0, self.sheetView.bounds.size.height);
    } completion:^(BOOL finished) {
        [self removeFromSuperview];
        if (completion) completion();
    }];
}

#pragma mark - 十六进制转换

+ (NSString *)hexStringForColor:(UIColor *)color {
    CGFloat red = 0.0, green = 0.0, blue = 0.0, alpha = 0.0;
    if (![color getRed:&red green:&green blue:&blue alpha:&alpha]) {
        return @"#FF0000";
    }
    return [NSString stringWithFormat:@"#%02X%02X%02X",
            (unsigned int)MAX(0, MIN(255, lround(red * 255.0))),
            (unsigned int)MAX(0, MIN(255, lround(green * 255.0))),
            (unsigned int)MAX(0, MIN(255, lround(blue * 255.0)))];
}

+ (nullable UIColor *)colorFromHexString:(NSString *)hex {
    if (![hex isKindOfClass:[NSString class]]) return nil;
    NSString *trimmed = [hex stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) return nil;
    if ([trimmed hasPrefix:@"#"]) trimmed = [trimmed substringFromIndex:1];
    if (trimmed.length != 6) return nil;

    unsigned int value = 0;
    NSScanner *scanner = [NSScanner scannerWithString:trimmed];
    if (![scanner scanHexInt:&value] || ![scanner isAtEnd]) return nil;
    return [UIColor colorWithRed:((value >> 16) & 0xFF) / 255.0
                           green:((value >> 8) & 0xFF) / 255.0
                            blue:(value & 0xFF) / 255.0
                           alpha:1.0];
}

@end
