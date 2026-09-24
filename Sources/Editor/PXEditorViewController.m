#import "PXEditorViewController.h"
#import "PXEditorCanvas.h"
#import "PXEditorDocument.h"
#import "PXEditorRenderer.h"
#import "../Common/PXLog.h"
#import "../Common/PXConstants.h"
#import "../Output/PXClipboardWriter.h"
#import "../Output/PXSharePresenter.h"

static const CGFloat PXEditorTopBarHeight = 48.0;
static const CGFloat PXEditorMaxZoomFactor = 8.0;

// 工具面板：2 行 × 7 列大图标网格（对齐参考图；2×8 / 3×5 布局已废弃）。
static const NSUInteger PXEditorGridColumns = 7;
static const CGFloat PXEditorToolButtonHeight = 44.0;
static const CGFloat PXEditorGridHeight = 96.0;   // 2 行×44 + 行距 8

// 面板行：线宽行（工具栏上方）/ 工具网格（右侧彩虹取色钮）/ 贴纸表情行（仅贴纸工具显示）。
static const CGFloat PXEditorRowSliderHeight = 44.0;
static const CGFloat PXEditorRowStickerHeight = 44.0;
static const CGFloat PXEditorPanelPadTop = 10.0;
static const CGFloat PXEditorPanelPadBottom = 12.0;
static const CGFloat PXEditorPanelRowGap = 8.0;
static const CGFloat PXEditorCropRowHeight = 48.0;
static const CGFloat PXEditorColorButtonSize = 56.0;   // 彩虹环取色钮直径

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

// 顺序对齐参考图：第一行 画笔/平移/方框/椭圆/箭头/放大镜/直线，
// 第二行 马赛克/文字/实心方/实心圆/聚光/荧光/贴纸。
// 图章（PXAnnotationTypeStamp）不再占用工具位：底层放置与渲染逻辑保留，仅工具栏不可达。
static const PXEditorToolItem PXEditorTools[] = {
    { PXAnnotationTypeBrush,     PXAnnotationFillStyleHollow, @"画笔",   @"paintbrush" },
    { PXAnnotationTypePan,       PXAnnotationFillStyleHollow, @"平移",   @"hand.point.up.left" },
    { PXAnnotationTypeRectangle, PXAnnotationFillStyleHollow, @"方框",   @"rectangle" },
    { PXAnnotationTypeOval,      PXAnnotationFillStyleHollow, @"椭圆",   @"ellipse" },
    { PXAnnotationTypeArrow,     PXAnnotationFillStyleHollow, @"箭头",   @"arrow.up.right" },
    { PXAnnotationTypeMagnifier, PXAnnotationFillStyleHollow, @"放大镜", @"plus.magnifyingglass" },
    { PXAnnotationTypeLine,      PXAnnotationFillStyleHollow, @"直线",   @"line.diagonal" },
    { PXAnnotationTypeMosaic,    PXAnnotationFillStyleHollow, @"马赛克", @"squareshape.split.3x3" },
    { PXAnnotationTypeText,      PXAnnotationFillStyleHollow, @"文字",   @"textformat" },
    { PXAnnotationTypeRectangle, PXAnnotationFillStyleSolid,  @"实心方", @"rectangle.fill" },
    { PXAnnotationTypeOval,      PXAnnotationFillStyleSolid,  @"实心圆", @"ellipse.fill" },
    { PXAnnotationTypeSpotlight, PXAnnotationFillStyleHollow, @"聚光",   @"circle.lefthalf.filled" },
    { PXAnnotationTypeHighlight, PXAnnotationFillStyleHollow, @"荧光",   @"pencil" },
    { PXAnnotationTypeSticker,   PXAnnotationFillStyleHollow, @"贴纸",   @"photo" },
};
static const NSUInteger PXEditorToolCount = sizeof(PXEditorTools) / sizeof(PXEditorTools[0]);

/// 打开编辑器的默认工具：平移（随表重排动态定位，避免硬编码索引漂移）。
static NSUInteger PXEditorDefaultToolIndex(void) {
    for (NSUInteger i = 0; i < PXEditorToolCount; i++) {
        if (PXEditorTools[i].type == PXAnnotationTypePan) return i;
    }
    return 0;
}

@interface PXEditorViewController () <
    PXEditorCanvasDelegate,
    UIColorPickerViewControllerDelegate,
    UIAdaptivePresentationControllerDelegate,
    UIScrollViewDelegate>
@property (nonatomic, strong) UIImage *sourceImage;
@property (nonatomic, weak) id<PXEditorViewControllerDelegate> delegate;
@property (nonatomic, strong) PXEditorDocument *document;
@property (nonatomic, strong) PXEditorCanvas *canvas;

@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *zoomContainer;
@property (nonatomic, strong) UIImageView *imageView;

@property (nonatomic, strong) UIView *topBar;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, strong) UIButton *cropButton;
@property (nonatomic, strong) UIButton *rotateButton;
@property (nonatomic, strong) UIButton *undoButton;
@property (nonatomic, strong) UIButton *redoButton;
@property (nonatomic, strong) UIButton *clipboardButton;
@property (nonatomic, strong) UIButton *shareButton;
@property (nonatomic, strong) UIButton *deleteButton;
@property (nonatomic, strong) UIButton *frontButton;
@property (nonatomic, strong) UIButton *doneButton;

@property (nonatomic, strong) UIView *bottomPanel;
@property (nonatomic, strong) UIView *widthRow;
@property (nonatomic, strong) UIImageView *minWidthIcon;   // 线宽行左端“最细”示意
@property (nonatomic, strong) UIImageView *maxWidthIcon;   // 线宽行右端“最粗”示意
@property (nonatomic, strong) UISlider *widthSlider;
@property (nonatomic, strong) UIView *toolGrid;
@property (nonatomic, strong) NSMutableArray<UIButton *> *toolButtons;
@property (nonatomic, strong) UIButton *customColorButton;      // 彩虹环取色钮（网格右侧）
@property (nonatomic, strong) CAGradientLayer *customColorGradient;
@property (nonatomic, strong) UIView *customColorSwatch;        // 环心：显示当前画笔色
@property (nonatomic, strong) UIScrollView *stickerRow;
@property (nonatomic, strong) NSMutableArray<UIButton *> *stickerButtons;
@property (nonatomic, strong) UIView *cropRow;
@property (nonatomic, strong) UIButton *cropCancelButton;
@property (nonatomic, strong) UIButton *cropApplyButton;

@property (nonatomic, strong, nullable) UIColorPickerViewController *colorPicker;

@property (nonatomic, assign) NSUInteger selectedToolIndex;
@property (nonatomic, strong) UIColor *currentColor;
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
        _stickerButtons = [[NSMutableArray alloc] init];
        _currentColor = [UIColor redColor];
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
    [self pxBuildTopBar];
    [self pxBuildBottomPanel];
    [self pxConfigureWidthSlider];

    [self pxSelectToolIndex:PXEditorDefaultToolIndex()];
    [self pxApplyCurrentColor];
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
    _undoButton = [self pxTopIconNamed:@"arrow.uturn.backward" a11y:@"撤销" action:@selector(pxUndoTapped:)];
    _redoButton = [self pxTopIconNamed:@"arrow.uturn.forward" a11y:@"重做" action:@selector(pxRedoTapped:)];
    _cropButton = [self pxTopIconNamed:@"crop.rotate" a11y:@"裁剪" action:@selector(pxCropTapped:)];
    _rotateButton = [self pxTopIconNamed:@"rotate.right" a11y:@"顺时针旋转90度" action:@selector(pxRotateTapped:)];
    _clipboardButton = [self pxTopIconNamed:@"doc.on.doc" a11y:@"复制图片" action:@selector(pxCopyTapped:)];
    _shareButton = [self pxTopIconNamed:@"square.and.arrow.up" a11y:@"分享图片" action:@selector(pxShareTapped:)];
    // 删除/置顶与复制/分享同槽位互斥显示（选中标注时替换），见 pxRefreshButtons。
    _deleteButton = [self pxTopIconNamed:@"trash" a11y:@"删除选中标注" action:@selector(pxDeleteTapped:)];
    _frontButton = [self pxTopIconNamed:@"arrow.up.to.line" a11y:@"选中标注置顶" action:@selector(pxFrontTapped:)];
    _doneButton = [self pxTopIconNamed:@"checkmark" a11y:@"完成" action:@selector(pxDoneTapped:)];
    _doneButton.tintColor = [UIColor systemGreenColor];
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

    // 线宽行：两端“最细/最粗”示意图标 + 白色大圆滑块，置于工具网格上方。
    _widthRow = [[UIView alloc] init];
    [_bottomPanel addSubview:_widthRow];
    _minWidthIcon = [[UIImageView alloc] initWithImage:[self pxWidthHintIconNamed:@"circle.inset.filled"]];
    [_widthRow addSubview:_minWidthIcon];
    _maxWidthIcon = [[UIImageView alloc] initWithImage:[self pxWidthHintIconNamed:@"circle.fill"]];
    [_widthRow addSubview:_maxWidthIcon];
    _widthSlider = [[UISlider alloc] init];
    _widthSlider.minimumTrackTintColor = PXEditorAccentColor();
    _widthSlider.maximumTrackTintColor = [UIColor colorWithWhite:0.35 alpha:1.0];
    [_widthSlider setThumbImage:PXEditorSliderThumbImage() forState:UIControlStateNormal];
    _widthSlider.accessibilityLabel = @"画笔粗细";
    [_widthSlider addTarget:self action:@selector(pxWidthChanged:) forControlEvents:UIControlEventValueChanged];
    [_widthRow addSubview:_widthSlider];

    // 工具网格（2 行 × 7 列，顺序对齐参考图）；右侧竖排彩虹取色钮跨两行居中
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

    // 彩虹环取色钮：网格右侧跨两行，外环彩虹渐变、环心显示当前画笔色，点击唤起系统取色器
    _customColorButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _customColorButton.accessibilityLabel = @"自定义颜色";
    [_customColorButton addTarget:self action:@selector(pxCustomColorTapped:)
                 forControlEvents:UIControlEventTouchUpInside];
    [_bottomPanel addSubview:_customColorButton];
    _customColorGradient = [CAGradientLayer layer];
    _customColorGradient.type = kCAGradientLayerConic;
    NSMutableArray<id> *rainbow = [NSMutableArray array];
    for (NSUInteger i = 0; i <= 6; i++) {
        [rainbow addObject:(id)[UIColor colorWithHue:(CGFloat)i / 6.0 saturation:0.75 brightness:1.0 alpha:1.0].CGColor];
    }
    _customColorGradient.colors = rainbow;
    [_customColorButton.layer addSublayer:_customColorGradient];
    _customColorSwatch = [[UIView alloc] init];
    _customColorSwatch.backgroundColor = self.currentColor;
    _customColorSwatch.layer.cornerRadius = (PXEditorColorButtonSize - 10.0) / 2.0;
    _customColorSwatch.userInteractionEnabled = NO;
    [_customColorButton addSubview:_customColorSwatch];

    // 贴纸行（横向滚动，选中贴纸工具时显示在网格下方）
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
}

/// 线宽行两端示意图标（白色，22pt）。
- (UIImage *)pxWidthHintIconNamed:(NSString *)iconName {
    UIImage *icon = [UIImage systemImageNamed:iconName];
    if (!icon) return nil;
    UIImageSymbolConfiguration *configuration =
        [UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIFontWeightRegular];
    return [icon imageWithConfiguration:configuration];
}

/// 线宽滑块：白色大圆（参考图样式）。
static UIImage *PXEditorSliderThumbImage(void) {
    CGFloat size = 28.0;
    UIGraphicsImageRenderer *renderer =
        [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(size, size)];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        CGContextSetFillColorWithColor(context.CGContext, [UIColor whiteColor].CGColor);
        CGContextFillEllipseInRect(context.CGContext, CGRectInset(CGRectMake(0, 0, size, size), 1.0, 1.0));
    }];
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

#pragma mark - 布局

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    CGFloat viewWidth = self.view.bounds.size.width;
    CGFloat viewHeight = self.view.bounds.size.height;
    CGFloat top = self.view.safeAreaInsets.top;

    CGFloat panelHeight = [self pxBottomChromeHeight];
    CGFloat panelTop = viewHeight - panelHeight;

    _topBar.frame = CGRectMake(0, 0, viewWidth, top + PXEditorTopBarHeight);
    [self pxLayoutTopBarWithTop:top];

    _bottomPanel.frame = CGRectMake(0, panelTop, viewWidth, panelHeight);
    [self pxLayoutBottomPanel];
    [self pxLayoutCustomColorGradient];

    CGRect scrollFrame = CGRectMake(0, top + PXEditorTopBarHeight,
                                    viewWidth,
                                    panelTop - top - PXEditorTopBarHeight);
    if (!CGRectEqualToRect(_scrollView.frame, scrollFrame)) {
        BOOL needsReset = !CGSizeEqualToSize(_scrollView.frame.size, scrollFrame.size);
        _scrollView.frame = scrollFrame;
        if (needsReset) {
            [self pxRelayoutZoomContainerPreservingOffset:YES];
        }
    }
}

/// 底部 UI 总占高（常驻面板 + 安全区），画布可视区据此避让。
/// 贴纸工具时网格下方追加表情行（面板增高，画布重适配一次）。
- (CGFloat)pxBottomChromeHeight {
    CGFloat bottom = self.view.safeAreaInsets.bottom;
    CGFloat height = bottom + PXEditorPanelPadTop + PXEditorRowSliderHeight + PXEditorPanelRowGap +
                     PXEditorGridHeight + PXEditorPanelPadBottom;
    BOOL stickerTool = (PXEditorTools[self.selectedToolIndex].type == PXAnnotationTypeSticker);
    if (stickerTool && !self.isCropMode) {
        height += PXEditorPanelRowGap + PXEditorRowStickerHeight;
    }
    return height;
}

- (void)pxLayoutTopBarWithTop:(CGFloat)top {
    CGFloat width = self.topBar.bounds.size.width;
    CGFloat y = top;
    CGFloat height = PXEditorTopBarHeight;
    CGFloat buttonWidth = 40.0;
    // 左区：关闭 / 撤销 / 重做
    self.closeButton.frame = CGRectMake(4, y, buttonWidth, height);
    self.undoButton.frame = CGRectMake(46, y, buttonWidth, height);
    self.redoButton.frame = CGRectMake(88, y, buttonWidth, height);
    // 右区右对齐（间隔 4）：完成 / 分享 / 复制 / 旋转 / 裁剪；删除、置顶与复制、分享同槽互斥。
    self.doneButton.frame = CGRectMake(width - 42.0, y, buttonWidth, height);
    self.shareButton.frame = CGRectMake(width - 86.0, y, buttonWidth, height);
    self.clipboardButton.frame = CGRectMake(width - 130.0, y, buttonWidth, height);
    self.deleteButton.frame = self.clipboardButton.frame;
    self.rotateButton.frame = CGRectMake(width - 174.0, y, buttonWidth, height);
    // 下限防更窄理论屏（<375）时与左区重做按钮重叠。
    self.cropButton.frame = CGRectMake(MAX(width - 218.0, 132.0), y, buttonWidth, height);
    self.frontButton.frame = self.shareButton.frame;
}

- (void)pxLayoutBottomPanel {
    CGFloat width = _bottomPanel.bounds.size.width;
    CGFloat y = PXEditorPanelPadTop;

    _widthRow.frame = CGRectMake(0, y, width, PXEditorRowSliderHeight);
    y += PXEditorRowSliderHeight + PXEditorPanelRowGap;

    // 网格与彩虹取色钮并排：钮占右侧固定宽，网格让出余量
    CGFloat colorX = width - PXEditorPanelPadBottom - PXEditorColorButtonSize;
    CGFloat gridWidth = MAX(200.0, colorX - PXEditorPanelRowGap);
    _toolGrid.frame = CGRectMake(0, y, gridWidth, PXEditorGridHeight);
    _customColorButton.frame = CGRectMake(colorX, y + (PXEditorGridHeight - PXEditorColorButtonSize) / 2.0,
                                          PXEditorColorButtonSize, PXEditorColorButtonSize);
    y += PXEditorGridHeight;

    // 表情行仅在贴纸工具（且非裁剪）时显示，占用网格下方一行；
    // gap 随表情行一起出现，保证与 pxBottomChromeHeight 逐项一致（两种模式底边距均为 PadBottom）。
    BOOL stickerTool = (PXEditorTools[self.selectedToolIndex].type == PXAnnotationTypeSticker);
    BOOL showStickerRow = (stickerTool && !self.isCropMode);
    if (showStickerRow) {
        y += PXEditorPanelRowGap;
        _stickerRow.frame = CGRectMake(0, y, width, PXEditorRowStickerHeight);
        y += PXEditorRowStickerHeight;
    }
    _stickerRow.hidden = !showStickerRow;

    // 裁剪模式沿用面板高度（不触发画布重适配），操作行在内容区垂直居中。
    CGFloat contentHeight = y - PXEditorPanelPadTop;
    _cropRow.frame = CGRectMake(0, PXEditorPanelPadTop + (contentHeight - PXEditorCropRowHeight) / 2.0,
                                width, PXEditorCropRowHeight);

    [self pxLayoutToolButtons];
    [self pxLayoutWidthRow];
    [self pxLayoutStickerRow];
    [self pxLayoutCropRow];
    [self pxLayoutCustomColorGradient];
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
    _minWidthIcon.frame = CGRectMake(16, 11, 22, 22);
    _maxWidthIcon.frame = CGRectMake(MAX(16.0, width - 38.0), 11, 22, 22);
    _widthSlider.frame = CGRectMake(48, 0, MAX(40.0, width - 48.0 - 44.0), PXEditorRowSliderHeight);
}

- (void)pxLayoutCustomColorGradient {
    if (!_customColorGradient) return;
    // 渐变铺满整钮作外环，环心 swatch 内缩 5pt 显示当前画笔色。
    _customColorGradient.frame = _customColorButton.bounds;
    _customColorGradient.cornerRadius = PXEditorColorButtonSize / 2.0;
    _customColorSwatch.frame = UIEdgeInsetsInsetRect(_customColorButton.bounds,
                                                     UIEdgeInsetsMake(5, 5, 5, 5));
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
/// 编辑基准为适屏：打开编辑器整图完整可见，细节靠捏合放大（下限即适屏基准，不放得比整图更小）。
/// preserveOffset=YES 时按内容比例保留滚动位置（贴纸行增减等视口变化），否则回到内容原点
/// （裁剪/旋转/撤销后图片几何已变，旧位置无意义）。
- (void)pxRelayoutZoomContainerPreservingOffset:(BOOL)preserve {
    CGSize imageSize = self.document.sourceImage.size;
    if (imageSize.width <= 0 || imageSize.height <= 0) return;

    CGFloat baseScale = [self pxBaseScaleForImageSize:imageSize inBounds:_scrollView.bounds];
    CGSize previousSize = _scrollView.contentSize;
    CGPoint previousOffset = _scrollView.contentOffset;
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

    _scrollView.minimumZoomScale = baseScale;
    _scrollView.maximumZoomScale = baseScale * PXEditorMaxZoomFactor;
    _scrollView.zoomScale = baseScale;
    [self pxCenterContent];
    CGSize newSize = _scrollView.contentSize;
    if (preserve && previousSize.width > 0 && previousSize.height > 0) {
        _scrollView.contentOffset = CGPointMake(
            MIN(previousOffset.x / previousSize.width, 1.0) * newSize.width,
            MIN(previousOffset.y / previousSize.height, 1.0) * newSize.height);
    } else {
        _scrollView.contentOffset = CGPointMake(-_scrollView.contentInset.left,
                                                -_scrollView.contentInset.top);
    }
}

/// 基准缩放：适屏（取两轴比例较小者，整图完整可见，不足视口的轴由 contentInset 居中）。
- (CGFloat)pxBaseScaleForImageSize:(CGSize)imageSize inBounds:(CGRect)bounds {
    if (imageSize.width <= 0 || imageSize.height <= 0 ||
        bounds.size.width <= 0 || bounds.size.height <= 0) {
        return 1.0;
    }
    CGFloat widthScale = bounds.size.width / imageSize.width;
    CGFloat heightScale = bounds.size.height / imageSize.height;
    return MIN(widthScale, heightScale);
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
    // 表情行显隐改变面板高度，交由 viewDidLayoutSubviews 重算（画布随之重适配一次）。
    self.stickerRow.hidden = !stickerTool;
    [self.view setNeedsLayout];

    // 线宽行对绘制类工具有效，其余工具置灰提示（保持行高不变，避免切工具时画布重排）。
    PXAnnotationType type = PXEditorTools[index].type;
    BOOL widthTool = (type == PXAnnotationTypeBrush || type == PXAnnotationTypeHighlight ||
                      type == PXAnnotationTypeLine || type == PXAnnotationTypeArrow ||
                      type == PXAnnotationTypeRectangle || type == PXAnnotationTypeOval ||
                      type == PXAnnotationTypeMosaic);
    self.widthRow.alpha = widthTool ? 1.0 : 0.35;
    self.widthSlider.enabled = widthTool;
}

/// 当前画笔色统一应用点：画布 + 彩虹环心 swatch。
- (void)pxApplyCurrentColor {
    if (self.canvas) {
        self.canvas.currentColor = self.currentColor;
    }
    self.customColorSwatch.backgroundColor = self.currentColor;
}

- (void)pxToolTapped:(UIButton *)sender {
    [self pxSelectToolIndex:(NSUInteger)sender.tag];
}

#pragma mark - 系统取色器

- (void)pxCustomColorTapped:(UIButton *)sender {
    // 残留引用自愈：dismiss 动画期引用未清时（presentingViewController 已空）允许重开。
    if (self.colorPicker && self.colorPicker.presentingViewController != nil) return;
    if (self.isExporting) return;
    [self.canvas commitActiveText];

    // 系统 UIColorPickerViewController（网格/光谱/滑块/吸管），样式见 iOS 系统取色面板。
    // 编辑器内已有 UIAlertController 呈现先例，present 路径与弹窗输入兜底一致。
    UIColorPickerViewController *picker = [[UIColorPickerViewController alloc] init];
    picker.supportsAlpha = YES;
    picker.selectedColor = self.currentColor;
    picker.delegate = self;
    picker.presentationController.delegate = self;
    self.colorPicker = picker;
    [self presentViewController:picker animated:YES completion:nil];
}

/// 颜色即时生效（拖动/点选均回调）；continuously=YES 时不入撤销栈语义，此处只改画笔状态无副作用。
- (void)colorPickerViewController:(UIColorPickerViewController *)viewController
                   didSelectColor:(UIColor *)color
                     continuously:(BOOL)continuously {
    if (self.colorPicker != viewController) return;
    self.currentColor = color;
    // 环心 swatch 展示所选色，便于下次直接查看当前色。
    [self pxApplyCurrentColor];
}

/// 系统 X 关闭按钮已自行 dismiss 该控制器（见 UIKit 头文件注释），这里只清理引用。
- (void)colorPickerViewControllerDidFinish:(UIColorPickerViewController *)viewController {
    if (self.colorPicker == viewController) {
        self.colorPicker = nil;
    }
}

/// 兜底：下滑手势关闭 sheet 时系统可能不回调 DidFinish:（iOS 14 起已知行为），
/// 若不清理引用，自定义取色入口会被 colorPicker 守卫卡死到编辑器关闭。
- (void)presentationControllerDidDismiss:(UIPresentationController *)presentationController {
    if (self.colorPicker &&
        presentationController.presentedViewController == self.colorPicker) {
        self.colorPicker = nil;
    }
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
}

- (void)pxUndoTapped:(UIButton *)sender {
    [self.canvas undo];
    [self pxRefreshButtons];
}

- (void)pxRedoTapped:(UIButton *)sender {
    [self.canvas redo];
    [self pxRefreshButtons];
}

/// 复制/分享共用：提交进行中输入、放弃未确认裁剪后渲染当前文档（与完成同路径），
/// 渲染期间 isExporting 锁全 UI（含画布，防止最后一笔不入图）；失败弹窗提示。then 固定主线程回调。
- (void)pxRenderCurrentImageThen:(void (^)(UIImage *result))then {
    if (self.isExporting) return;
    [self.canvas commitActiveText];
    if (self.isCropMode) {
        [self pxExitCropModeApply:NO];
    }
    self.isExporting = YES;
    self.canvas.userInteractionEnabled = NO;
    [self pxRefreshButtons];
    __weak typeof(self) weakSelf = self;
    [PXEditorRenderer renderDocument:self.document completion:^(UIImage *result) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.isExporting = NO;
        strongSelf.canvas.userInteractionEnabled = YES;
        [strongSelf pxRefreshButtons];
        if (!result) {
            PXLogError(@"editor export for copy/share failed");
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"导出失败"
                                                                           message:@"请重试或取消编辑"
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
            [strongSelf presentViewController:alert animated:YES completion:nil];
            return;
        }
        then(result);
    }];
}

- (void)pxCopyTapped:(UIButton *)sender {
    [self pxRenderCurrentImageThen:^(UIImage *result) {
        [PXClipboardWriter copyImageAsync:result completion:^(BOOL ok) {}];
    }];
}

- (void)pxShareTapped:(UIButton *)sender {
    __weak typeof(self) weakSelf = self;
    [self pxRenderCurrentImageThen:^(UIImage *result) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        [PXSharePresenter shareImage:result
                  fromViewController:strongSelf
                          completion:^(BOOL completed) {}];
    }];
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
    self.isCropMode = YES;
    _scrollView.scrollEnabled = NO;
    _scrollView.pinchGestureRecognizer.enabled = NO;
    [self.canvas beginCrop];
    self.widthRow.hidden = YES;
    self.toolGrid.hidden = YES;
    self.customColorButton.hidden = YES;
    self.stickerRow.hidden = YES;
    self.cropRow.hidden = NO;
    [self.view setNeedsLayout];
    [self.view layoutIfNeeded];
    [self.canvas setNeedsDisplay];
    // 视口已切为矮裁剪行：显式按新视口重排一次，保证裁剪框与手柄整图可见可触。
    [self pxRelayoutZoomContainerPreservingOffset:NO];
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
    self.toolGrid.hidden = NO;
    self.customColorButton.hidden = NO;
    // 表情行显隐由 pxLayoutBottomPanel 按 selectedToolIndex 统一恢复。
    [self.view setNeedsLayout];
    [self.view layoutIfNeeded];
    // 视口恢复常驻面板高度，按适屏基准重排（applyCrop 的几何回调发生在 isCropMode 复位前，
    // 已按当时视口重排过一次，此处为复位后的最终重排）。
    [self pxRelayoutZoomContainerPreservingOffset:NO];
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
    self.clipboardButton.enabled = NO;
    self.shareButton.enabled = NO;
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
    // 复制/分享与删除/置顶同槽位：选中标注时前者让位。
    self.deleteButton.hidden = !hasSelection;
    self.frontButton.hidden = !hasSelection;
    self.clipboardButton.hidden = hasSelection;
    self.shareButton.hidden = hasSelection;
    self.deleteButton.enabled = hasSelection && !exporting;
    self.frontButton.enabled = hasSelection && !exporting;
    self.clipboardButton.enabled = !exporting;
    self.shareButton.enabled = !exporting;
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
    [self pxRelayoutZoomContainerPreservingOffset:NO];
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
