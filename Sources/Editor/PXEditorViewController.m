#import "PXEditorViewController.h"
#import "PXEditorCanvas.h"
#import "PXEditorDocument.h"
#import "PXEditorRenderer.h"
#import "PXColorPickerView.h"
#import "../Common/PXLog.h"
#import "../Common/PXConstants.h"

static const CGFloat PXEditorTopBarHeight = 48.0;
static const CGFloat PXEditorMaxZoomFactor = 8.0;

// 工具面板：2 行 × 8 列大图标网格（3×5 小按钮布局已废弃）。
static const NSUInteger PXEditorGridColumns = 8;
static const CGFloat PXEditorToolButtonHeight = 44.0;
static const CGFloat PXEditorGridHeight = 96.0;   // 2 行×44 + 行距 8

// 面板行：线宽行（工具栏上方）/ 工具网格 / 颜色行（或贴纸行）。
static const CGFloat PXEditorRowSliderHeight = 44.0;
static const CGFloat PXEditorRowColorHeight = 44.0;
static const CGFloat PXEditorPanelPadTop = 10.0;
static const CGFloat PXEditorPanelPadBottom = 12.0;
static const CGFloat PXEditorPanelRowGap = 8.0;
static const CGFloat PXEditorCropRowHeight = 48.0;

// 折叠把手：浮在面板上缘，收起后浮在屏幕下缘。
static const CGFloat PXEditorPillWidth = 52.0;
static const CGFloat PXEditorPillHeight = 26.0;

static const NSUInteger PXEditorRecentColorLimit = 8;

static UIColor *PXEditorAccentColor(void) {
    return [UIColor colorWithRed:1.0 green:0.78 blue:0.08 alpha:1.0];
}

#pragma mark - 工具定义

typedef struct {
    PXAnnotationType type;
    PXAnnotationFillStyle fillStyle;
    NSString *title;
    NSString *iconName;   // SF Symbol；缺失时回退显示文字
} PXEditorToolItem;

static const PXEditorToolItem PXEditorTools[] = {
    { PXAnnotationTypePan,       PXAnnotationFillStyleHollow, @"平移",   @"hand.point.up.left" },
    { PXAnnotationTypeBrush,     PXAnnotationFillStyleHollow, @"画笔",   @"paintbrush" },
    { PXAnnotationTypeHighlight, PXAnnotationFillStyleHollow, @"荧光",   @"highlighter" },
    { PXAnnotationTypeLine,      PXAnnotationFillStyleHollow, @"直线",   @"line.diagonal" },
    { PXAnnotationTypeArrow,     PXAnnotationFillStyleHollow, @"箭头",   @"arrow.up.right" },
    { PXAnnotationTypeRectangle, PXAnnotationFillStyleHollow, @"方框",   @"rectangle" },
    { PXAnnotationTypeRectangle, PXAnnotationFillStyleSolid,  @"实心方", @"rectangle.fill" },
    { PXAnnotationTypeOval,      PXAnnotationFillStyleHollow, @"椭圆",   @"ellipse" },
    { PXAnnotationTypeOval,      PXAnnotationFillStyleSolid,  @"实心圆", @"ellipse.fill" },
    { PXAnnotationTypeMosaic,    PXAnnotationFillStyleHollow, @"马赛克", @"squareshape.split.3x3" },
    { PXAnnotationTypeSpotlight, PXAnnotationFillStyleHollow, @"聚光",   @"flashlight.on.fill" },
    { PXAnnotationTypeText,      PXAnnotationFillStyleHollow, @"文字",   @"textformat" },
    { PXAnnotationTypeMagnifier, PXAnnotationFillStyleHollow, @"放大镜", @"plus.magnifyingglass" },
    { PXAnnotationTypeSticker,   PXAnnotationFillStyleHollow, @"贴纸",   @"face.smiling" },
    { PXAnnotationTypeStamp,     PXAnnotationFillStyleHollow, @"图章",   @"checkmark.seal" },
};
static const NSUInteger PXEditorToolCount = sizeof(PXEditorTools) / sizeof(PXEditorTools[0]);

@interface PXEditorViewController () <
    PXEditorCanvasDelegate,
    PXColorPickerViewDelegate,
    UIScrollViewDelegate>
@property (nonatomic, strong) UIImage *sourceImage;
@property (nonatomic, weak) id<PXEditorViewControllerDelegate> delegate;
@property (nonatomic, strong) PXEditorDocument *document;
@property (nonatomic, strong) PXEditorCanvas *canvas;

@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *zoomContainer;
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UITapGestureRecognizer *doubleTapGesture;

@property (nonatomic, strong) UIView *topBar;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, strong) UIButton *cropButton;
@property (nonatomic, strong) UIButton *rotateButton;
@property (nonatomic, strong) UIButton *undoButton;
@property (nonatomic, strong) UIButton *redoButton;
@property (nonatomic, strong) UIButton *deleteButton;
@property (nonatomic, strong) UIButton *frontButton;
@property (nonatomic, strong) UIButton *doneButton;

@property (nonatomic, strong) UIButton *pillButton;
@property (nonatomic, strong) UIView *bottomPanel;
@property (nonatomic, strong) UIView *widthRow;
@property (nonatomic, strong) UIView *widthDotBadge;
@property (nonatomic, strong) UIView *widthDot;
@property (nonatomic, strong) UISlider *widthSlider;
@property (nonatomic, strong) UIView *toolGrid;
@property (nonatomic, strong) NSMutableArray<UIButton *> *toolButtons;
@property (nonatomic, strong) UIView *colorRow;
@property (nonatomic, strong) NSArray<UIColor *> *colorPresets;
@property (nonatomic, strong) NSMutableArray<UIButton *> *colorButtons;
@property (nonatomic, strong) UIButton *customColorButton;
@property (nonatomic, strong) CAGradientLayer *customColorGradient;
@property (nonatomic, strong) UILabel *customColorPlusLabel;
@property (nonatomic, strong) UIScrollView *stickerRow;
@property (nonatomic, strong) NSMutableArray<UIButton *> *stickerButtons;
@property (nonatomic, strong) UIView *cropRow;
@property (nonatomic, strong) UIButton *cropCancelButton;
@property (nonatomic, strong) UIButton *cropApplyButton;

@property (nonatomic, strong, nullable) PXColorPickerView *colorPicker;
@property (nonatomic, strong, nullable) UIColor *colorBeforePicker;
@property (nonatomic, strong) NSMutableArray<UIColor *> *recentColors;

@property (nonatomic, assign) NSUInteger selectedToolIndex;
@property (nonatomic, strong) UIColor *currentColor;
@property (nonatomic, assign) BOOL panelCollapsed;
@property (nonatomic, assign) BOOL isExporting;
@property (nonatomic, assign) BOOL isCropMode;
@end

@implementation PXEditorViewController

- (instancetype)initWithImage:(UIImage *)sourceImage
                     delegate:(id<PXEditorViewControllerDelegate>)delegate {
    if (self = [super initWithNibName:nil bundle:nil]) {
        _sourceImage = sourceImage;
        _delegate = delegate;
        _toolButtons = [[NSMutableArray alloc] init];
        _colorButtons = [[NSMutableArray alloc] init];
        _stickerButtons = [[NSMutableArray alloc] init];
        _recentColors = [[NSMutableArray alloc] init];
        _currentColor = [UIColor redColor];
        _colorPresets = @[
            [UIColor redColor],
            [UIColor colorWithRed:1.0 green:0.55 blue:0.1 alpha:1.0],
            [UIColor yellowColor],
            [UIColor colorWithRed:0.15 green:0.75 blue:0.3 alpha:1.0],
            [UIColor colorWithRed:0.1 green:0.5 blue:1.0 alpha:1.0],
            [UIColor colorWithRed:0.65 green:0.3 blue:0.95 alpha:1.0],
            [UIColor blackColor],
            [UIColor whiteColor],
        ];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];

    self.document = [[PXEditorDocument alloc] initWithSourceImage:self.sourceImage];
    self.document.backgroundColor = [UIColor whiteColor];

    [self pxBuildScrollContainer];
    [self pxBuildCanvas];
    [self.canvas requireTapToFail:self.doubleTapGesture];
    [self pxBuildTopBar];
    [self pxBuildBottomPanel];
    [self pxConfigureWidthSlider];
    [self pxLoadRecentColors];

    [self pxSelectToolIndex:0];
    [self pxSelectColorIndex:0];
    [self pxUpdatePillIcon];
    [self pxRefreshButtons];
    // 马赛克底图不在此预热：布局前画布尺寸为零会导致块尺寸取错，drawRect 首帧会按正确尺寸懒加载。
}

- (void)dealloc {
    [self.canvas prepareForDismissal];
}

#pragma mark - UI 构建

- (void)pxBuildScrollContainer {
    _scrollView = [[UIScrollView alloc] init];
    _scrollView.backgroundColor = [UIColor colorWithWhite:0.05 alpha:1.0];
    _scrollView.showsVerticalScrollIndicator = YES;
    _scrollView.showsHorizontalScrollIndicator = YES;
    _scrollView.bouncesZoom = YES;
    _scrollView.delegate = self;
    _scrollView.minimumZoomScale = 1.0;
    _scrollView.maximumZoomScale = PXEditorMaxZoomFactor;
    [self.view addSubview:_scrollView];

    _zoomContainer = [[UIView alloc] init];
    [_scrollView addSubview:_zoomContainer];

    _imageView = [[UIImageView alloc] init];
    _imageView.contentMode = UIViewContentModeScaleToFill;   // 容器尺寸恒等于图片点尺寸，无需保持纵横比
    [_zoomContainer addSubview:_imageView];

    _doubleTapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                action:@selector(pxDoubleTapped:)];
    _doubleTapGesture.numberOfTapsRequired = 2;
    [_scrollView addGestureRecognizer:_doubleTapGesture];
}

- (void)pxBuildCanvas {
    self.canvas = [[PXEditorCanvas alloc] initWithFrame:self.zoomContainer.bounds document:self.document];
    self.canvas.delegate = self;
    self.canvas.currentLineWidth = [self pxDefaultLineWidth];
    self.canvas.currentTextFontSize = [self pxDefaultTextFontSize];
    [self.zoomContainer addSubview:self.canvas];
}

- (void)pxBuildTopBar {
    _topBar = [[UIView alloc] init];
    _topBar.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.88];
    [self.view addSubview:_topBar];

    // 顶栏按钮用 SF Symbols 图标（ShellX createIconBtn 风格），避免小屏文字溢出。
    _closeButton = [self pxTopIconNamed:@"xmark" a11y:@"关闭" action:@selector(pxCloseTapped:)];
    _cropButton = [self pxTopIconNamed:@"crop.rotate" a11y:@"裁剪" action:@selector(pxCropTapped:)];
    _rotateButton = [self pxTopIconNamed:@"rotate.right" a11y:@"顺时针旋转90度" action:@selector(pxRotateTapped:)];
    _undoButton = [self pxTopIconNamed:@"arrow.uturn.backward" a11y:@"撤销" action:@selector(pxUndoTapped:)];
    _redoButton = [self pxTopIconNamed:@"arrow.uturn.forward" a11y:@"重做" action:@selector(pxRedoTapped:)];
    _deleteButton = [self pxTopIconNamed:@"trash" a11y:@"删除选中标注" action:@selector(pxDeleteTapped:)];
    _frontButton = [self pxTopIconNamed:@"arrow.up.to.line" a11y:@"选中标注置顶" action:@selector(pxFrontTapped:)];
    _doneButton = [self pxTopIconNamed:@"checkmark" a11y:@"完成" action:@selector(pxDoneTapped:)];
    _doneButton.tintColor = PXEditorAccentColor();
}

- (UIButton *)pxTopIconNamed:(NSString *)iconName a11y:(NSString *)a11y action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.tintColor = [UIColor whiteColor];
    UIImage *icon = [UIImage systemImageNamed:iconName];
    if (icon) {
        UIImageSymbolConfiguration *configuration =
            [UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIFontWeightMedium];
        [button setImage:[icon imageWithConfiguration:configuration] forState:UIControlStateNormal];
    } else {
        [button setTitle:@"·" forState:UIControlStateNormal];   // 符号缺失兜底
    }
    button.accessibilityLabel = a11y;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [self.topBar addSubview:button];
    return button;
}

- (void)pxBuildBottomPanel {
    _bottomPanel = [[UIView alloc] init];
    _bottomPanel.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.92];
    [self.view addSubview:_bottomPanel];

    // 折叠把手：直属 self.view，必须在 bottomPanel 之后加入以保证 Z 序在上
    // （把手半嵌在面板上缘，若被面板压住会遮掉一半可点区域）。
    _pillButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _pillButton.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.16];
    _pillButton.layer.cornerRadius = PXEditorPillHeight / 2.0;
    _pillButton.accessibilityLabel = @"收起或展开工具面板";
    [_pillButton addTarget:self action:@selector(pxPillTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_pillButton];

    // 线宽行：粗细调整独立成行，置于工具网格上方（带当前粗细预览点）。
    _widthRow = [[UIView alloc] init];
    [_bottomPanel addSubview:_widthRow];
    _widthDotBadge = [[UIView alloc] init];
    _widthDotBadge.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.08];
    _widthDotBadge.layer.cornerRadius = 18.0;
    [_widthRow addSubview:_widthDotBadge];
    _widthDot = [[UIView alloc] init];
    _widthDot.backgroundColor = self.currentColor;
    [_widthDotBadge addSubview:_widthDot];
    _widthSlider = [[UISlider alloc] init];
    _widthSlider.minimumTrackTintColor = PXEditorAccentColor();
    _widthSlider.maximumTrackTintColor = [UIColor colorWithWhite:0.35 alpha:1.0];
    _widthSlider.accessibilityLabel = @"画笔粗细";
    [_widthSlider addTarget:self action:@selector(pxWidthChanged:) forControlEvents:UIControlEventValueChanged];
    [_widthRow addSubview:_widthSlider];

    // 工具网格（2 行 × 8 列，参考系统相册编辑器的多排面板）
    _toolGrid = [[UIView alloc] init];
    [_bottomPanel addSubview:_toolGrid];
    for (NSUInteger i = 0; i < PXEditorToolCount; i++) {
        UIButton *tool = [UIButton buttonWithType:UIButtonTypeSystem];
        tool.tintColor = [UIColor whiteColor];
        tool.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.10];
        tool.layer.cornerRadius = 12.0;
        tool.accessibilityLabel = PXEditorTools[i].title;
        NSString *iconName = PXEditorTools[i].iconName;
        UIImage *icon = iconName.length ? [UIImage systemImageNamed:iconName] : nil;
        if (icon) {
            UIImageSymbolConfiguration *configuration =
                [UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIFontWeightMedium];
            [tool setImage:[icon imageWithConfiguration:configuration] forState:UIControlStateNormal];
        } else {
            // 符号缺失兜底：显示中文名
            [tool setTitle:PXEditorTools[i].title forState:UIControlStateNormal];
            tool.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
        }
        [tool addTarget:self action:@selector(pxToolTapped:) forControlEvents:UIControlEventTouchUpInside];
        tool.tag = (NSInteger)i;
        [_toolGrid addSubview:tool];
        [self.toolButtons addObject:tool];
    }

    // 颜色行：预设色 + 自定义取色入口
    _colorRow = [[UIView alloc] init];
    [_bottomPanel addSubview:_colorRow];
    for (NSUInteger i = 0; i < self.colorPresets.count; i++) {
        UIButton *colorButton = [UIButton buttonWithType:UIButtonTypeCustom];
        colorButton.backgroundColor = self.colorPresets[i];
        colorButton.layer.cornerRadius = 15.0;
        colorButton.layer.borderWidth = 2.0;
        colorButton.layer.borderColor = [UIColor clearColor].CGColor;
        colorButton.accessibilityLabel = @"预设颜色";
        [colorButton addTarget:self action:@selector(pxColorTapped:) forControlEvents:UIControlEventTouchUpInside];
        colorButton.tag = (NSInteger)i;
        [_colorRow addSubview:colorButton];
        [self.colorButtons addObject:colorButton];
    }

    _customColorButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _customColorButton.layer.cornerRadius = 15.0;
    _customColorButton.layer.borderWidth = 1.0;
    _customColorButton.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.4].CGColor;
    _customColorButton.accessibilityLabel = @"自定义颜色";
    [_customColorButton addTarget:self action:@selector(pxCustomColorTapped:)
                 forControlEvents:UIControlEventTouchUpInside];
    [_colorRow addSubview:_customColorButton];
    // 渐变环 + 独立“+”标签：sublayer 会盖住 UIButton 自绘 title，必须用子视图承载。
    _customColorGradient = [CAGradientLayer layer];
    _customColorGradient.type = kCAGradientLayerConic;
    _customColorGradient.cornerRadius = 13.0;
    NSMutableArray<id> *rainbow = [NSMutableArray array];
    for (NSUInteger i = 0; i <= 6; i++) {
        [rainbow addObject:(id)[UIColor colorWithHue:(CGFloat)i / 6.0 saturation:0.75 brightness:1.0 alpha:1.0].CGColor];
    }
    _customColorGradient.colors = rainbow;
    [_customColorButton.layer addSublayer:_customColorGradient];
    _customColorPlusLabel = [[UILabel alloc] init];
    _customColorPlusLabel.text = @"+";
    _customColorPlusLabel.textColor = [UIColor whiteColor];
    _customColorPlusLabel.font = [UIFont boldSystemFontOfSize:17];
    _customColorPlusLabel.textAlignment = NSTextAlignmentCenter;
    _customColorPlusLabel.userInteractionEnabled = NO;
    _customColorPlusLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [_customColorButton addSubview:_customColorPlusLabel];

    // 贴纸行（横向滚动，选中贴纸工具时替换颜色行）
    _stickerRow = [[UIScrollView alloc] init];
    _stickerRow.showsHorizontalScrollIndicator = NO;
    _stickerRow.hidden = YES;
    [_bottomPanel addSubview:_stickerRow];
    NSArray<NSString *> *stickers = @[
        @"✅", @"❌", @"⚠️", @"🔥", @"⭐️", @"💡", @"📌", @"🎯",
        @"👍", @"👌", @"🙌", @"🤩", @"😂", @"🥰", @"😎", @"🤔",
        @"😭", @"😡", @"🎉", @"❤️", @"💚", @"💙", @"🚀", @"💩",
    ];
    for (NSUInteger i = 0; i < stickers.count; i++) {
        UIButton *sticker = [UIButton buttonWithType:UIButtonTypeSystem];
        sticker.titleLabel.font = [UIFont systemFontOfSize:26];
        [sticker setTitle:stickers[i] forState:UIControlStateNormal];
        [sticker addTarget:self action:@selector(pxStickerTapped:) forControlEvents:UIControlEventTouchUpInside];
        sticker.tag = (NSInteger)i;
        [_stickerRow addSubview:sticker];
        [self.stickerButtons addObject:sticker];
    }
    self.canvas.currentStickerText = stickers.firstObject;

    // 裁剪操作行（裁剪模式替换面板全部内容）
    _cropRow = [[UIView alloc] init];
    _cropRow.hidden = YES;
    [_bottomPanel addSubview:_cropRow];
    _cropCancelButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _cropCancelButton.tintColor = [UIColor whiteColor];
    _cropCancelButton.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    [_cropCancelButton setTitle:@"取消裁剪" forState:UIControlStateNormal];
    _cropCancelButton.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.10];
    _cropCancelButton.layer.cornerRadius = 10.0;
    _cropCancelButton.layer.borderWidth = 1.0;
    _cropCancelButton.layer.borderColor = [UIColor colorWithWhite:0.4 alpha:1.0].CGColor;
    [_cropCancelButton addTarget:self action:@selector(pxCropCancelTapped:) forControlEvents:UIControlEventTouchUpInside];
    [_cropRow addSubview:_cropCancelButton];

    _cropApplyButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _cropApplyButton.tintColor = [UIColor whiteColor];
    _cropApplyButton.backgroundColor = [UIColor colorWithRed:0.15 green:0.55 blue:0.25 alpha:1.0];
    _cropApplyButton.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    [_cropApplyButton setTitle:@"应用裁剪" forState:UIControlStateNormal];
    _cropApplyButton.layer.cornerRadius = 10.0;
    [_cropApplyButton addTarget:self action:@selector(pxCropApplyTapped:) forControlEvents:UIControlEventTouchUpInside];
    [_cropRow addSubview:_cropApplyButton];
}

- (void)pxConfigureWidthSlider {
    CGFloat shortSide = MIN(self.document.sourceImage.size.width, self.document.sourceImage.size.height);
    CGFloat maxValue = MAX(8.0, shortSide / 6.0);
    _widthSlider.minimumValue = 2.0;
    _widthSlider.maximumValue = maxValue;
    _widthSlider.value = self.canvas.currentLineWidth;
    [self pxUpdateWidthPreview];
}

/// 预览点直径 6→24pt 映射滑条区间；颜色跟随当前画笔色。
- (void)pxUpdateWidthPreview {
    CGFloat range = _widthSlider.maximumValue - _widthSlider.minimumValue;
    CGFloat fraction = range > 0 ? (_widthSlider.value - _widthSlider.minimumValue) / range : 0;
    CGFloat diameter = 6.0 + MAX(0.0, MIN(1.0, fraction)) * 18.0;
    CGFloat badgeSize = _widthDotBadge.bounds.size.width;
    if (badgeSize <= 0) badgeSize = 36.0;
    _widthDot.frame = CGRectMake((badgeSize - diameter) / 2.0, (badgeSize - diameter) / 2.0,
                                 diameter, diameter);
    _widthDot.layer.cornerRadius = diameter / 2.0;
    _widthDot.backgroundColor = self.canvas.currentColor ?: self.currentColor;
}

- (CGFloat)pxDefaultLineWidth {
    CGFloat shortSide = MIN(self.document.sourceImage.size.width, self.document.sourceImage.size.height);
    CGFloat preferred = MAX(PXDefaultEditorLineWidth, shortSide / 100.0);
    return [self pxClampLineWidth:preferred];
}

- (CGFloat)pxClampLineWidth:(CGFloat)width {
    CGFloat shortSide = MIN(self.document.sourceImage.size.width, self.document.sourceImage.size.height);
    CGFloat maxValue = MAX(8.0, shortSide / 6.0);
    return MAX(2.0, MIN(width, maxValue));
}

- (CGFloat)pxDefaultTextFontSize {
    CGFloat shortSide = MIN(self.document.sourceImage.size.width, self.document.sourceImage.size.height);
    return MAX(18.0, MIN(120.0, shortSide / 22.0));
}

#pragma mark - 最近使用色（CFPreferences 持久化，跨编辑会话）

- (void)pxLoadRecentColors {
    NSArray *hexes = CFBridgingRelease(CFPreferencesCopyAppValue(
        (__bridge CFStringRef)PXKeyEditorRecentColors,
        (__bridge CFStringRef)PXPreferencesDomain));
    if (![hexes isKindOfClass:[NSArray class]]) return;
    for (NSString *hex in hexes) {
        UIColor *color = [PXColorPickerView colorFromHexString:hex];
        if (color) [self.recentColors addObject:color];
        if (self.recentColors.count >= PXEditorRecentColorLimit) break;
    }
}

- (void)pxAddRecentColor:(UIColor *)color {
    // 用 #RRGGBB 字符串比较去重：UIColor isEqual: 跨色彩空间可能误判不等。
    NSString *hex = [PXColorPickerView hexStringForColor:color];
    NSMutableArray<UIColor *> *updated = [NSMutableArray arrayWithObject:color];
    for (UIColor *existing in self.recentColors) {
        if (![[PXColorPickerView hexStringForColor:existing] isEqualToString:hex]) {
            [updated addObject:existing];
        }
        if (updated.count >= PXEditorRecentColorLimit) break;
    }
    self.recentColors = updated;

    NSMutableArray<NSString *> *hexes = [NSMutableArray array];
    for (UIColor *existing in updated) {
        [hexes addObject:[PXColorPickerView hexStringForColor:existing]];
    }
    CFPreferencesSetAppValue((__bridge CFStringRef)PXKeyEditorRecentColors,
                             (__bridge CFArrayRef)hexes,
                             (__bridge CFStringRef)PXPreferencesDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)PXPreferencesDomain);
}

#pragma mark - 布局

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    CGFloat viewWidth = self.view.bounds.size.width;
    CGFloat viewHeight = self.view.bounds.size.height;
    CGFloat top = self.view.safeAreaInsets.top;
    CGFloat bottom = self.view.safeAreaInsets.bottom;

    CGFloat panelHeight = [self pxBottomChromeHeight];
    CGFloat panelTop = viewHeight - panelHeight;
    BOOL collapsed = self.panelCollapsed;

    _topBar.frame = CGRectMake(0, 0, viewWidth, top + PXEditorTopBarHeight);
    [self pxLayoutTopBarWithTop:top];

    _bottomPanel.hidden = collapsed;
    if (!collapsed) {
        _bottomPanel.frame = CGRectMake(0, panelTop, viewWidth, panelHeight);
        [self pxLayoutBottomPanel];
    }

    _pillButton.hidden = self.isCropMode;
    CGFloat pillY = collapsed
        ? viewHeight - bottom - PXEditorPillHeight - 8.0
        : panelTop - PXEditorPillHeight / 2.0;
    _pillButton.frame = CGRectMake((viewWidth - PXEditorPillWidth) / 2.0, pillY,
                                   PXEditorPillWidth, PXEditorPillHeight);
    [self pxLayoutCustomColorGradient];

    CGRect scrollFrame = CGRectMake(0, top + PXEditorTopBarHeight,
                                    viewWidth,
                                    panelTop - top - PXEditorTopBarHeight);
    if (!CGRectEqualToRect(_scrollView.frame, scrollFrame)) {
        BOOL needsReset = !CGSizeEqualToSize(_scrollView.frame.size, scrollFrame.size);
        _scrollView.frame = scrollFrame;
        if (needsReset) {
            [self pxRelayoutZoomContainer];
        }
    }
}

/// 底部 UI 总占高（面板或把手浮条 + 安全区），画布可视区据此避让。
/// 裁剪模式沿用展开高度：面板高度不变 → 画布滚动区不变，进出裁剪不触发
/// pxRelayoutZoomContainer 强制重适配（对齐旧版行为，用户缩放状态不被打断）。
- (CGFloat)pxBottomChromeHeight {
    CGFloat bottom = self.view.safeAreaInsets.bottom;
    if (self.panelCollapsed) {
        return bottom + PXEditorPillHeight + 18.0;
    }
    return bottom + PXEditorPanelPadTop + PXEditorRowSliderHeight + PXEditorPanelRowGap +
           PXEditorGridHeight + PXEditorPanelRowGap + PXEditorRowColorHeight + PXEditorPanelPadBottom;
}

- (void)pxLayoutTopBarWithTop:(CGFloat)top {
    CGFloat width = self.topBar.bounds.size.width;
    CGFloat y = top;
    CGFloat height = PXEditorTopBarHeight;
    self.closeButton.frame = CGRectMake(4, y, 40, height);
    self.cropButton.frame = CGRectMake(48, y, 40, height);
    self.rotateButton.frame = CGRectMake(92, y, 40, height);
    self.undoButton.frame = CGRectMake(width - 236, y, 44, height);
    self.redoButton.frame = CGRectMake(width - 190, y, 44, height);
    self.deleteButton.frame = CGRectMake(width - 144, y, 44, height);
    self.frontButton.frame = CGRectMake(width - 98, y, 44, height);
    self.doneButton.frame = CGRectMake(width - 52, y, 48, height);
}

- (void)pxLayoutBottomPanel {
    CGFloat width = _bottomPanel.bounds.size.width;
    CGFloat y = PXEditorPanelPadTop;

    _widthRow.frame = CGRectMake(0, y, width, PXEditorRowSliderHeight);
    y += PXEditorRowSliderHeight + PXEditorPanelRowGap;

    _toolGrid.frame = CGRectMake(0, y, width, PXEditorGridHeight);
    y += PXEditorGridHeight + PXEditorPanelRowGap;

    _colorRow.frame = CGRectMake(0, y, width, PXEditorRowColorHeight);
    _stickerRow.frame = _colorRow.frame;
    // 裁剪模式沿用展开面板高度（不触发画布重适配），操作行在内容区垂直居中。
    CGFloat contentHeight = PXEditorPanelPadTop + PXEditorRowSliderHeight + PXEditorPanelRowGap +
                            PXEditorGridHeight + PXEditorPanelRowGap + PXEditorRowColorHeight;
    _cropRow.frame = CGRectMake(0, PXEditorPanelPadTop + (contentHeight - PXEditorCropRowHeight) / 2.0,
                                width, PXEditorCropRowHeight);

    [self pxLayoutToolButtons];
    [self pxLayoutWidthRow];
    [self pxLayoutColorRow];
    [self pxLayoutStickerRow];
    [self pxLayoutCropRow];
}

- (void)pxLayoutToolButtons {
    CGFloat width = _toolGrid.bounds.size.width;
    NSInteger columns = (NSInteger)PXEditorGridColumns;
    CGFloat margin = 10.0;
    CGFloat gap = 6.0;
    CGFloat buttonHeight = PXEditorToolButtonHeight;
    CGFloat buttonWidth = floor((width - margin * 2.0 - gap * (columns - 1)) / columns);
    for (NSUInteger i = 0; i < self.toolButtons.count; i++) {
        NSInteger row = (NSInteger)i / columns;
        NSInteger col = (NSInteger)i % columns;
        UIButton *button = self.toolButtons[i];
        button.frame = CGRectMake(margin + col * (buttonWidth + gap),
                                  row * (buttonHeight + PXEditorPanelRowGap),
                                  buttonWidth, buttonHeight);
    }
}

- (void)pxLayoutWidthRow {
    CGFloat width = _widthRow.bounds.size.width;
    _widthDotBadge.frame = CGRectMake(8, 4, 36, 36);
    _widthSlider.frame = CGRectMake(54, 4, MAX(40.0, width - 54.0 - 12.0), 36);
    [self pxUpdateWidthPreview];
}

- (void)pxLayoutColorRow {
    CGFloat dotSize = 30.0;
    CGFloat rowWidth = _colorRow.bounds.size.width;
    NSUInteger count = self.colorButtons.count + 1;   // 预设 + 自定义
    CGFloat step = count > 1 ? (rowWidth - 24.0 - dotSize) / (CGFloat)(count - 1) : dotSize;
    step = MAX(step, dotSize + 4.0);
    CGFloat x = 12.0;
    for (UIButton *button in self.colorButtons) {
        button.frame = CGRectMake(x, 7, dotSize, dotSize);
        x += step;
    }
    _customColorButton.frame = CGRectMake(x, 7, dotSize, dotSize);
    [self pxLayoutCustomColorGradient];
}

- (void)pxLayoutCustomColorGradient {
    if (!_customColorGradient) return;
    CGRect bounds = _customColorButton.bounds;
    _customColorGradient.frame = UIEdgeInsetsInsetRect(bounds, UIEdgeInsetsMake(2, 2, 2, 2));
    _customColorPlusLabel.frame = bounds;
}

- (void)pxLayoutStickerRow {
    CGFloat x = 10;
    for (UIButton *button in self.stickerButtons) {
        button.frame = CGRectMake(x, 0, 44, 44);
        x += 50;
    }
    self.stickerRow.contentSize = CGSizeMake(x + 10, 44);
}

- (void)pxLayoutCropRow {
    CGFloat width = _cropRow.bounds.size.width;
    CGFloat y = (_cropRow.bounds.size.height - 40.0) / 2.0;
    self.cropCancelButton.frame = CGRectMake(14, y, (width - 34) / 2.0, 40);
    self.cropApplyButton.frame = CGRectMake(20 + (width - 34) / 2.0, y, (width - 34) / 2.0, 40);
}

#pragma mark - 缩放容器

/// 画布/容器尺寸随文档底图变化（进入、裁剪、旋转后调用）。
- (void)pxRelayoutZoomContainer {
    CGSize imageSize = self.document.sourceImage.size;
    if (imageSize.width <= 0 || imageSize.height <= 0) return;

    CGRect fitted = [self pxFittedRectForImageSize:imageSize inBounds:_scrollView.bounds];
    // UIScrollView 缩放会给容器挂 scale transform；带 transform 改 frame 的行为是
    // undefined（Apple 文档明确），必须先回到基准再设置尺寸，否则裁剪/旋转/撤销后的
    // 第二次重排会把画布几何算歪（表现为图片显示不全/比例错乱）。
    _scrollView.minimumZoomScale = 1.0;
    _scrollView.maximumZoomScale = PXEditorMaxZoomFactor;
    [_scrollView setZoomScale:1.0];
    _zoomContainer.transform = CGAffineTransformIdentity;
    _zoomContainer.frame = CGRectMake(0, 0, imageSize.width, imageSize.height);
    _imageView.frame = _zoomContainer.bounds;
    _imageView.image = self.document.sourceImage;
    self.canvas.frame = _zoomContainer.bounds;

    CGFloat fitScale = (imageSize.width > 0) ? fitted.size.width / imageSize.width : 1.0;
    _scrollView.minimumZoomScale = fitScale;
    _scrollView.maximumZoomScale = fitScale * PXEditorMaxZoomFactor;
    _scrollView.zoomScale = fitScale;
    [self pxCenterContent];
    // 裁剪/旋转/撤销重排后强制回到居中位：残留 offset 会造成"图片显示不全"。
    CGSize contentSize = _scrollView.contentSize;
    CGSize boundsSize = _scrollView.bounds.size;
    if (contentSize.width <= boundsSize.width && contentSize.height <= boundsSize.height) {
        _scrollView.contentOffset = CGPointMake(-_scrollView.contentInset.left,
                                                -_scrollView.contentInset.top);
    }
}

- (CGRect)pxFittedRectForImageSize:(CGSize)imageSize inBounds:(CGRect)bounds {
    if (imageSize.width <= 0 || imageSize.height <= 0 ||
        bounds.size.width <= 0 || bounds.size.height <= 0) {
        return CGRectZero;
    }
    CGFloat scale = MIN(bounds.size.width / imageSize.width, bounds.size.height / imageSize.height);
    CGSize fitted = CGSizeMake(imageSize.width * scale, imageSize.height * scale);
    return CGRectMake((bounds.size.width - fitted.width) / 2.0,
                      (bounds.size.height - fitted.height) / 2.0,
                      fitted.width, fitted.height);
}

- (void)pxCenterContent {
    CGSize contentSize = _scrollView.contentSize;
    CGSize boundsSize = _scrollView.bounds.size;
    CGFloat offsetX = MAX(0, (boundsSize.width - contentSize.width) / 2.0);
    CGFloat offsetY = MAX(0, (boundsSize.height - contentSize.height) / 2.0);
    _scrollView.contentInset = UIEdgeInsetsMake(offsetY, offsetX, offsetY, offsetX);
}

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView {
    return self.zoomContainer;
}

- (void)scrollViewDidZoom {
    [self pxCenterContent];
}

- (void)pxDoubleTapped:(UITapGestureRecognizer *)gesture {
    if (self.canvas.textEditing || self.isCropMode) return;
    CGPoint point = [gesture locationInView:_scrollView];

    if (_scrollView.zoomScale > _scrollView.minimumZoomScale * 1.05) {
        [_scrollView setZoomScale:_scrollView.minimumZoomScale animated:YES];
    } else {
        CGRect zoomRect = CGRectMake(point.x - 40, point.y - 40, 80, 80);
        [_scrollView zoomToRect:zoomRect animated:YES];
    }
}

#pragma mark - 面板折叠

- (void)pxUpdatePillIcon {
    NSString *iconName = self.panelCollapsed ? @"chevron.up" : @"chevron.down";
    UIImage *icon = [UIImage systemImageNamed:iconName];
    if (icon) {
        UIImageSymbolConfiguration *configuration =
            [UIImageSymbolConfiguration configurationWithPointSize:13 weight:UIFontWeightBold];
        [_pillButton setImage:[icon imageWithConfiguration:configuration]
                     forState:UIControlStateNormal];
    } else {
        [_pillButton setTitle:self.panelCollapsed ? @"▲" : @"▼" forState:UIControlStateNormal];
    }
}

/// 折叠/展开工具面板：收起后画布近全屏，全屏截图不再被工具面板遮挡。
- (void)pxPillTapped:(UIButton *)sender {
    if (self.isCropMode || self.isExporting || self.canvas.textEditing) return;
    if (self.colorPicker) return;   // 防御：取色器打开时把手被遮罩挡住，正常不可达
    self.panelCollapsed = !self.panelCollapsed;
    [self pxUpdatePillIcon];
    [self.view setNeedsLayout];
    [self.view layoutIfNeeded];
}

#pragma mark - 工具与颜色选择

- (void)pxSelectToolIndex:(NSUInteger)index {
    if (index >= PXEditorToolCount) return;
    self.selectedToolIndex = index;
    for (NSUInteger i = 0; i < self.toolButtons.count; i++) {
        UIButton *button = self.toolButtons[i];
        BOOL selected = (i == index);
        // 选中态：图标染当前强调色（参考系统相册编辑器）
        button.tintColor = selected ? PXEditorAccentColor() : [UIColor whiteColor];
        button.backgroundColor = selected
            ? [UIColor colorWithWhite:1.0 alpha:0.18]
            : [UIColor colorWithWhite:1.0 alpha:0.10];
    }
    if (self.canvas) {
        if (self.isCropMode) {
            [self pxExitCropModeApply:NO];
        }
        self.canvas.currentTool = PXEditorTools[index].type;
        self.canvas.currentFillStyle = PXEditorTools[index].fillStyle;
    }
    BOOL stickerTool = (PXEditorTools[index].type == PXAnnotationTypeSticker);
    self.stickerRow.hidden = !stickerTool;
    self.colorRow.hidden = stickerTool;

    // 线宽行对绘制类工具有效，其余工具置灰提示（保持行高不变，避免切工具时画布重排）。
    PXAnnotationType type = PXEditorTools[index].type;
    BOOL widthTool = (type == PXAnnotationTypeBrush || type == PXAnnotationTypeHighlight ||
                      type == PXAnnotationTypeLine || type == PXAnnotationTypeArrow ||
                      type == PXAnnotationTypeRectangle || type == PXAnnotationTypeOval ||
                      type == PXAnnotationTypeMosaic);
    self.widthRow.alpha = widthTool ? 1.0 : 0.35;
    self.widthSlider.enabled = widthTool;
}

- (void)pxSelectColorIndex:(NSInteger)index {
    for (NSUInteger i = 0; i < self.colorButtons.count; i++) {
        UIButton *button = self.colorButtons[i];
        button.layer.borderColor = ((NSInteger)i == index)
            ? [UIColor whiteColor].CGColor
            : [UIColor clearColor].CGColor;
    }
    BOOL customSelected = (index < 0);
    self.customColorButton.layer.borderWidth = customSelected ? 2.5 : 1.0;
    self.customColorButton.layer.borderColor = customSelected
        ? PXEditorAccentColor().CGColor
        : [UIColor colorWithWhite:1.0 alpha:0.4].CGColor;
    if (index >= 0 && (NSUInteger)index < self.colorPresets.count) {
        self.currentColor = self.colorPresets[(NSUInteger)index];
        // 选中预设色时自定义入口还原成“彩虹环 +”语义；所选自定义色仍保留在按钮上待回选。
        self.customColorGradient.hidden = NO;
        self.customColorPlusLabel.hidden = NO;
        self.customColorButton.backgroundColor = nil;
    }
    if (self.canvas) {
        self.canvas.currentColor = self.currentColor;
    }
    [self pxUpdateWidthPreview];
}

- (void)pxToolTapped:(UIButton *)sender {
    [self pxSelectToolIndex:(NSUInteger)sender.tag];
}

- (void)pxColorTapped:(UIButton *)sender {
    [self pxSelectColorIndex:(NSInteger)sender.tag];
}

#pragma mark - 自定义取色器

- (void)pxCustomColorTapped:(UIButton *)sender {
    if (self.colorPicker) return;
    if (self.isExporting) return;
    [self.canvas commitActiveText];

    self.colorBeforePicker = self.currentColor;
    self.colorPicker = [[PXColorPickerView alloc] initWithColor:self.currentColor
                                                   recentColors:self.recentColors];
    self.colorPicker.delegate = self;
    [self.colorPicker showInView:self.view animated:YES completion:nil];
}

- (void)colorPicker:(PXColorPickerView *)picker didPreviewColor:(UIColor *)color {
    // 实时预览：画笔色即时跟随，取消时回退 colorBeforePicker。
    self.canvas.currentColor = color;
    [self pxUpdateWidthPreview];
}

- (void)colorPicker:(PXColorPickerView *)picker didConfirmColor:(UIColor *)color {
    if (self.colorPicker != picker) return;   // 幂等守卫：dismiss 动画期间忽略二次回调
    [picker dismissAnimated:YES completion:^{
        if (self.colorPicker == picker) self.colorPicker = nil;
    }];
    self.currentColor = color;
    self.colorBeforePicker = nil;
    // 自定义按钮展示所选色（渐变环与“+”让位），便于下次直接取用。
    self.customColorGradient.hidden = YES;
    self.customColorPlusLabel.hidden = YES;
    self.customColorButton.backgroundColor = color;
    [self pxSelectColorIndex:-1];
    [self pxAddRecentColor:color];
    PXLogInfo(@"editor custom color confirmed: %@", [PXColorPickerView hexStringForColor:color]);
}

- (void)colorPickerDidCancel:(PXColorPickerView *)picker {
    if (self.colorPicker != picker) return;   // 幂等守卫：dismiss 动画期间忽略二次回调
    [picker dismissAnimated:YES completion:^{
        if (self.colorPicker == picker) self.colorPicker = nil;
    }];
    // 无条件回退拖动期间的实时预览色，避免残留。
    self.canvas.currentColor = self.colorBeforePicker ?: self.currentColor;
    self.colorBeforePicker = nil;
    [self pxUpdateWidthPreview];
}

- (void)pxStickerTapped:(UIButton *)sender {
    NSString *sticker = nil;
    if (sender.tag < self.stickerButtons.count) {
        sticker = [self.stickerButtons[sender.tag] titleForState:UIControlStateNormal];
    }
    if (sticker.length > 0) {
        self.canvas.currentStickerText = sticker;
    }
}

- (void)pxWidthChanged:(UISlider *)slider {
    self.canvas.currentLineWidth = [self pxClampLineWidth:slider.value];
    [self pxUpdateWidthPreview];
}

- (void)pxUndoTapped:(UIButton *)sender {
    [self.canvas undo];
    [self pxRefreshButtons];
}

- (void)pxRedoTapped:(UIButton *)sender {
    [self.canvas redo];
    [self pxRefreshButtons];
}

- (void)pxDeleteTapped:(UIButton *)sender {
    [self.canvas deleteSelectedAnnotation];
    [self pxRefreshButtons];
}

- (void)pxFrontTapped:(UIButton *)sender {
    [self.canvas bringSelectedAnnotationToFront];
    [self pxRefreshButtons];
}

- (void)pxRotateTapped:(UIButton *)sender {
    if (self.isExporting) return;
    if (self.isCropMode) {
        [self pxExitCropModeApply:NO];
    }
    [self.canvas rotateImage90Clockwise];
    [self pxRefreshButtons];
}

- (void)pxCropTapped:(UIButton *)sender {
    if (self.isExporting) return;
    if (self.isCropMode) {
        [self pxExitCropModeApply:NO];
        return;
    }
    [self enterCropMode];
}

- (void)pxCropCancelTapped:(UIButton *)sender {
    [self pxExitCropModeApply:NO];
}

- (void)pxCropApplyTapped:(UIButton *)sender {
    [self pxExitCropModeApply:YES];
}

- (void)enterCropMode {
    if (self.panelCollapsed) {
        self.panelCollapsed = NO;
        [self pxUpdatePillIcon];
    }
    self.isCropMode = YES;
    _scrollView.scrollEnabled = NO;
    _scrollView.pinchGestureRecognizer.enabled = NO;
    [self.canvas beginCrop];
    self.widthRow.hidden = YES;
    self.toolGrid.hidden = YES;
    self.colorRow.hidden = YES;
    self.stickerRow.hidden = YES;
    self.cropRow.hidden = NO;
    [self.view setNeedsLayout];
    [self.view layoutIfNeeded];
    [self.canvas setNeedsDisplay];
}

- (void)pxExitCropModeApply:(BOOL)apply {
    if (!self.isCropMode) return;
    if (apply) {
        [self.canvas applyCrop];
    } else {
        [self.canvas cancelCrop];
    }
    self.isCropMode = NO;
    _scrollView.scrollEnabled = YES;
    _scrollView.pinchGestureRecognizer.enabled = YES;
    self.cropRow.hidden = YES;
    self.widthRow.hidden = NO;
    BOOL stickerTool = (PXEditorTools[self.selectedToolIndex].type == PXAnnotationTypeSticker);
    self.toolGrid.hidden = NO;
    self.colorRow.hidden = stickerTool;
    self.stickerRow.hidden = !stickerTool;
    [self.view setNeedsLayout];
    [self.view layoutIfNeeded];
    [self pxRefreshButtons];
}

- (void)pxCloseTapped:(UIButton *)sender {
    if (self.isExporting) return;
    [self.canvas commitActiveText];
    if (self.delegate && [self.delegate respondsToSelector:@selector(editorControllerDidCancel:)]) {
        [self.delegate editorControllerDidCancel:self];
    }
}

- (void)pxDoneTapped:(UIButton *)sender {
    if (self.isExporting) return;
    [self.canvas commitActiveText];
    if (self.isCropMode) {
        [self pxExitCropModeApply:NO];   // 完成时不强制应用未确认的裁剪
    }
    self.isExporting = YES;
    self.doneButton.enabled = NO;
    self.doneButton.alpha = 0.4;
    self.undoButton.enabled = NO;
    self.redoButton.enabled = NO;
    self.deleteButton.enabled = NO;
    self.frontButton.enabled = NO;
    self.cropButton.enabled = NO;
    self.rotateButton.enabled = NO;
    self.canvas.userInteractionEnabled = NO;

    __weak typeof(self) weakSelf = self;
    [PXEditorRenderer renderDocument:self.document completion:^(UIImage *result) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.isExporting = NO;
        strongSelf.canvas.userInteractionEnabled = YES;
        [strongSelf pxRefreshButtons];
        if (!result) {
            PXLogError(@"editor export failed");
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"导出失败"
                                                                           message:@"请重试或取消编辑"
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
            [strongSelf presentViewController:alert animated:YES completion:nil];
            return;
        }
        if (strongSelf.delegate &&
            [strongSelf.delegate respondsToSelector:@selector(editorController:didFinishWithImage:)]) {
            [strongSelf.delegate editorController:strongSelf didFinishWithImage:result];
        }
    }];
}

- (void)pxRefreshButtons {
    BOOL exporting = self.isExporting;
    self.undoButton.enabled = self.canvas.canUndo && !exporting;
    self.redoButton.enabled = self.canvas.canRedo && !exporting;
    self.undoButton.alpha = self.canvas.canUndo ? 1.0 : 0.4;
    self.redoButton.alpha = self.canvas.canRedo ? 1.0 : 0.4;
    BOOL hasSelection = (self.canvas.selectedAnnotation != nil);
    self.deleteButton.hidden = !hasSelection;
    self.frontButton.hidden = !hasSelection;
    self.deleteButton.enabled = hasSelection && !exporting;
    self.frontButton.enabled = hasSelection && !exporting;
    self.cropButton.enabled = !exporting;
    self.rotateButton.enabled = !exporting;
    self.doneButton.enabled = !exporting;
    self.doneButton.alpha = exporting ? 0.4 : 1.0;
}

#pragma mark - PXEditorCanvasDelegate

- (void)canvasDidChangeContent:(PXEditorCanvas *)canvas {
    [self pxRefreshButtons];
}

- (void)canvasDidChangeSelection:(PXEditorCanvas *)canvas {
    [self pxRefreshButtons];
}

- (void)canvasDidChangeGeometry:(PXEditorCanvas *)canvas {
    [self pxRelayoutZoomContainer];
    [self pxRefreshButtons];
}

- (void)canvasDidStartTextInput:(PXEditorCanvas *)canvas {
    _scrollView.scrollEnabled = NO;
    _scrollView.pinchGestureRecognizer.enabled = NO;
}

- (void)canvasDidEndTextInput:(PXEditorCanvas *)canvas {
    if (!self.isCropMode) {
        _scrollView.scrollEnabled = YES;
        _scrollView.pinchGestureRecognizer.enabled = YES;
    }
}

- (void)canvas:(PXEditorCanvas *)canvas didUpdateTextInputFrame:(CGRect)canvasFrame {
    CGRect visible = [self.canvas convertRect:canvasFrame toView:_scrollView];
    visible = CGRectInset(visible, -40, -80);
    if (CGRectContainsRect(_scrollView.bounds, visible)) return;
    [_scrollView scrollRectToVisible:visible animated:YES];
}

/// SpringBoard 键盘多次重试仍唤不起：降级为系统弹窗输入。
- (void)canvasKeyboardUnavailable:(PXEditorCanvas *)canvas pendingTextPoint:(CGPoint)canvasPoint {
    PXLogWarn(@"editor keyboard unavailable, falling back to alert input");
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"添加文字"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"输入文字";
    }];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"添加" style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        UITextField *field = alert.textFields.firstObject;
        if (!strongSelf || field.text.length == 0) return;
        [strongSelf.canvas placeTextAnnotationWithText:field.text atCanvasPoint:canvasPoint];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
