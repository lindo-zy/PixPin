#import "PXEditorViewController.h"
#import "PXEditorCanvas.h"
#import "PXEditorDocument.h"
#import "PXEditorRenderer.h"
#import "PXEditorLayout.h"
#import "../Common/PXLog.h"
#import "../Common/PXConstants.h"
#import "../Common/PXEditorOrder.h"
#import "../Common/PXPanelAppearance.h"
#import "../Output/PXClipboardWriter.h"
#import "../Output/PXSharePresenter.h"

static const CGFloat PXEditorMaxZoomFactor = 8.0;
static const CGFloat PXEditorRowSliderHeight = 44.0;
static const CGFloat PXEditorPanelPadTop = 10.0;
static const CGFloat PXEditorPanelPadBottom = 12.0;
static const CGFloat PXEditorPanelRowGap = 8.0;
static const CGFloat PXEditorCropRowHeight = 48.0;
static const CGFloat PXEditorPanelGripHeight = 24.0;
static const CGFloat PXEditorCollapsedHandleWidth = 48.0;
static const CGFloat PXEditorCollapsedHandleHeight = 48.0;

static UIColor *PXEditorAccentColor(void) {
    return [UIColor colorWithRed:1.0 green:0.78 blue:0.08 alpha:1.0];
}

#pragma mark - 工具定义

@interface PXEditorTool : NSObject
@property (nonatomic, assign) PXAnnotationType type;
@property (nonatomic, assign) PXAnnotationFillStyle fillStyle;
@property (nonatomic, copy) NSString *identifier;   // 对齐 PXEditorOrder 目录 id
@property (nonatomic, copy) NSString *title;        // 显示名统一取自 PXEditorOrder
@property (nonatomic, copy) NSString *iconName;     // SF Symbol；缺失时回退显示文字
@end
@implementation PXEditorTool
@end

static PXEditorTool *PXEditorToolMake(PXAnnotationType type, PXAnnotationFillStyle fillStyle,
                                      NSString *identifier) {
    PXEditorTool *tool = [[PXEditorTool alloc] init];
    tool.type = type;
    tool.fillStyle = fillStyle;
    tool.identifier = identifier;
    tool.title = [PXEditorOrder displayNameForToolIdentifier:identifier];
    tool.iconName = [PXEditorOrder iconNameForToolIdentifier:identifier];
    return tool;
}

// 全量工具目录：id 是唯一命名来源，显示顺序与显隐由设置页（PXEditorOrder）决定。
static NSDictionary<NSString *, PXEditorTool *> *PXEditorToolCatalog(void) {
    // 每次打开重新读取名称和图标，避免 SpringBoard 常驻缓存旧偏好。
    NSArray<PXEditorTool *> *tools = @[
        PXEditorToolMake(PXAnnotationTypeBrush,     PXAnnotationFillStyleHollow, @"brush"),
        PXEditorToolMake(PXAnnotationTypePan,       PXAnnotationFillStyleHollow, @"pan"),
        PXEditorToolMake(PXAnnotationTypeRectangle, PXAnnotationFillStyleHollow, @"rect"),
        PXEditorToolMake(PXAnnotationTypeOval,      PXAnnotationFillStyleHollow, @"oval"),
        PXEditorToolMake(PXAnnotationTypeArrow,     PXAnnotationFillStyleHollow, @"arrow"),
        PXEditorToolMake(PXAnnotationTypeMagnifier, PXAnnotationFillStyleHollow, @"magnifier"),
        PXEditorToolMake(PXAnnotationTypeLine,      PXAnnotationFillStyleHollow, @"line"),
        PXEditorToolMake(PXAnnotationTypeMosaic,    PXAnnotationFillStyleHollow, @"mosaic"),
        PXEditorToolMake(PXAnnotationTypeText,      PXAnnotationFillStyleHollow, @"text"),
        PXEditorToolMake(PXAnnotationTypeRectangle, PXAnnotationFillStyleSolid,  @"rectSolid"),
        PXEditorToolMake(PXAnnotationTypeOval,      PXAnnotationFillStyleSolid,  @"ovalSolid"),
        PXEditorToolMake(PXAnnotationTypeSpotlight, PXAnnotationFillStyleHollow, @"spotlight"),
        PXEditorToolMake(PXAnnotationTypeHighlight, PXAnnotationFillStyleHollow, @"highlight"),
        PXEditorToolMake(PXAnnotationTypeSticker,   PXAnnotationFillStyleHollow, @"sticker"),
        PXEditorToolMake(PXAnnotationTypeStamp,     PXAnnotationFillStyleHollow, @"stamp"),
    ];
    NSMutableDictionary<NSString *, PXEditorTool *> *mapping =
        [NSMutableDictionary dictionaryWithCapacity:tools.count];
    for (PXEditorTool *tool in tools) mapping[tool.identifier] = tool;
    NSDictionary<NSString *, PXEditorTool *> *catalog = mapping;
    return catalog;
}

/// 按设置页排序组装编辑器工具列表；被隐藏的工具不出现，全部隐藏时回退为完整列表。
static NSArray<PXEditorTool *> *PXEditorToolsInPreferredOrder(BOOL fullscreen) {
    NSDictionary<NSString *, PXEditorTool *> *catalog = PXEditorToolCatalog();
    NSArray<NSString *> *order = [PXEditorOrder visibleOrderForOrder:[PXEditorOrder currentToolOrderForFullscreenMarkup:fullscreen]
                                                              hidden:[PXEditorOrder currentToolHiddenForFullscreenMarkup:fullscreen]];
    NSMutableArray<PXEditorTool *> *tools = [NSMutableArray arrayWithCapacity:order.count];
    for (NSString *identifier in order) {
        PXEditorTool *tool = catalog[identifier];
        if (tool) [tools addObject:tool];
    }
    return tools;
}

@interface PXEditorViewController () <
    PXEditorCanvasDelegate,
    UIColorPickerViewControllerDelegate,
    UIAdaptivePresentationControllerDelegate,
    UIGestureRecognizerDelegate,
    UIScrollViewDelegate>
@property (nonatomic, strong) UIImage *sourceImage;
@property (nonatomic, weak) id<PXEditorViewControllerDelegate> delegate;
@property (nonatomic, strong) PXEditorDocument *document;
@property (nonatomic, strong) PXEditorCanvas *canvas;

@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *zoomContainer;
@property (nonatomic, strong) UIImageView *imageView;

@property (nonatomic, strong) UIView *editorCard;
@property (nonatomic, strong) UIImageView *backdropView;
@property (nonatomic, strong) UIScrollView *panelScrollView;
@property (nonatomic, copy) NSArray<PXEditorTool *> *tools;   // 按设置页排序后的展示顺序
@property (nonatomic, strong) NSArray<UIButton *> *actionButtons;
@property (nonatomic, strong) UIButton *saveButton;
@property (nonatomic, strong) UIButton *fitButton;
@property (nonatomic, strong) UIButton *dockButton;
@property (nonatomic, strong) UIButton *collapseButton;
@property (nonatomic, assign) BOOL panelAtTop;
@property (nonatomic, assign) BOOL fitAbovePanel;
@property (nonatomic, assign) BOOL panelCollapsed;
@property (nonatomic, assign) BOOL hasPanelPosition;
@property (nonatomic, assign) CGPoint panelOrigin;
@property (nonatomic, assign) CGPoint panStartOrigin;
@property (nonatomic, assign) CGPoint collapsedHandleOrigin;
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
@property (nonatomic, strong) UIView *panelDragGrip;
@property (nonatomic, strong) UIButton *collapsedHandle;
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
    self.backdropView = [[UIImageView alloc] initWithImage:self.backdropImage ?: self.sourceImage];
    self.backdropView.contentMode = UIViewContentModeScaleAspectFill;
    self.backdropView.alpha = 0.45;
    self.backdropView.clipsToBounds = YES;
    [self.view addSubview:self.backdropView];
    self.editorCard = [[UIView alloc] init];
    self.editorCard.backgroundColor = [UIColor colorWithWhite:0.10 alpha:1.0];
    self.editorCard.layer.cornerRadius = self.fullscreenMarkup ? 0.0 : 28.0;
    self.editorCard.clipsToBounds = YES;
    [self.view addSubview:self.editorCard];
    // 全屏标记默认使用全屏画布，工具面板悬浮其上；可按需切换避开面板的视口。
    self.fitAbovePanel = NO;

    self.document = [[PXEditorDocument alloc] initWithSourceImage:self.sourceImage];
    self.document.backgroundColor = [UIColor whiteColor];

    [self pxBuildScrollContainer];
    [self pxBuildCanvas];
    // 工具按钮在 pxBuildBottomPanel 内按 self.tools 顺序创建，必须先解析排序偏好。
    self.tools = PXEditorToolsInPreferredOrder(self.fullscreenMarkup);
    [self pxBuildTopBar];
    [self pxBuildBottomPanel];
    [self pxConfigureWidthSlider];
    [self pxAssembleActionButtons];
    self.dockButton.hidden = !self.fullscreenMarkup;
    self.fitButton.accessibilityLabel = @"整图适屏";

    // 默认选中排序后的第一个工具按钮（平移等其余工具仍在网格中可点选）。
    [self pxSelectToolIndex:0];
    [self pxApplyCurrentColor];
    [self pxRefreshButtons];
    // 马赛克底图不在此预热：布局前画布尺寸为零会导致块尺寸取错，drawRect 首帧会按正确尺寸懒加载。
}

- (void)dealloc {
    [self.canvas prepareForDismissal];
}

/// 编辑器销毁前由协调器调用：断开 view→手势→self 的强引用环
/// （UIGestureRecognizer 对 target 持强引用，不移除则整棵视图树+文档成孤岛永不释放）。
- (void)prepareForDismissal {
    // arrayWithObjects 以 nil 终止：非全屏标记没有拖条/把手，nil 项自动跳过（字面量数组遇 nil 会崩）。
    NSMutableArray<UIView *> *containers = [NSMutableArray arrayWithObjects:
        self.bottomPanel, self.widthRow, self.panelDragGrip, self.collapsedHandle, nil];
    for (UIView *container in containers) {
        for (UIGestureRecognizer *gesture in container.gestureRecognizers) {
            [container removeGestureRecognizer:gesture];
        }
    }
    [self.canvas prepareForDismissal];
}

#pragma mark - UI 构建

- (void)pxBuildScrollContainer {
    _scrollView = [[UIScrollView alloc] init];
    _scrollView.backgroundColor = [UIColor colorWithWhite:0.05 alpha:1.0];
    _scrollView.showsVerticalScrollIndicator = YES;
    _scrollView.showsHorizontalScrollIndicator = YES;
    _scrollView.bouncesZoom = YES;
    _scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    _scrollView.delegate = self;
    _scrollView.minimumZoomScale = 1.0;
    _scrollView.maximumZoomScale = PXEditorMaxZoomFactor;
    [self.editorCard addSubview:_scrollView];

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
    [self.editorCard addSubview:_topBar];

    // 所有操作保留独立按钮；小屏自动换行。a11y 文案与设置页排序条目同源（PXEditorOrder）。
    _closeButton = [self pxTopIconForIdentifier:@"close" action:@selector(pxCloseTapped:)];
    _undoButton = [self pxTopIconForIdentifier:@"undo" action:@selector(pxUndoTapped:)];
    _redoButton = [self pxTopIconForIdentifier:@"redo" action:@selector(pxRedoTapped:)];
    _cropButton = [self pxTopIconForIdentifier:@"crop" action:@selector(pxCropTapped:)];
    _rotateButton = [self pxTopIconForIdentifier:@"rotate" action:@selector(pxRotateTapped:)];
    _clipboardButton = [self pxTopIconForIdentifier:@"copy" action:@selector(pxCopyTapped:)];
    _shareButton = [self pxTopIconForIdentifier:@"share" action:@selector(pxShareTapped:)];
    _saveButton = [self pxTopIconForIdentifier:@"save" action:@selector(pxSaveTapped:)];
    _fitButton = [self pxTopIconForIdentifier:@"fit" action:@selector(pxFitTapped:)];
    _dockButton = [self pxTopIconForIdentifier:@"dock" action:@selector(pxDockTapped:)];
    _collapseButton = [self pxTopIconForIdentifier:@"collapse" action:@selector(pxCollapsePanelTapped:)];
    _deleteButton = [self pxTopIconForIdentifier:@"delete" action:@selector(pxDeleteTapped:)];
    _frontButton = [self pxTopIconForIdentifier:@"front" action:@selector(pxFrontTapped:)];
    _doneButton = [self pxTopIconForIdentifier:@"done" action:@selector(pxDoneTapped:)];
    _doneButton.tintColor = [UIColor systemGreenColor];
    _closeButton.tintColor = [UIColor systemRedColor];
}

/// 按设置页排序与显隐组装操作按钮；面板停靠/收起仅全屏标记显示。
/// 关闭/完成是编辑器唯一出口，设置页开关禁用，这里再兜底强制补回。
- (void)pxAssembleActionButtons {
    NSArray<NSString *> *order = [PXEditorOrder visibleActionOrderForOrder:[PXEditorOrder currentActionOrderForFullscreenMarkup:self.fullscreenMarkup]
                                                                  hidden:[PXEditorOrder currentActionHiddenForFullscreenMarkup:self.fullscreenMarkup]
                                                        fullscreenMarkup:self.fullscreenMarkup];
    NSDictionary<NSString *, UIButton *> *table = [self pxActionButtonTable];
    NSMutableArray<UIButton *> *buttons = [NSMutableArray arrayWithCapacity:order.count];
    for (NSString *identifier in order) {
        UIButton *button = table[identifier];
        if (button) [buttons addObject:button];
    }
    self.actionButtons = buttons;
    if (self.fullscreenMarkup) {
        for (UIButton *button in self.actionButtons) [self.toolGrid addSubview:button];
    }
}

- (NSDictionary<NSString *, UIButton *> *)pxActionButtonTable {
    return @{
        @"close": self.closeButton,
        @"undo": self.undoButton,
        @"redo": self.redoButton,
        @"crop": self.cropButton,
        @"rotate": self.rotateButton,
        @"copy": self.clipboardButton,
        @"share": self.shareButton,
        @"save": self.saveButton,
        @"fit": self.fitButton,
        @"delete": self.deleteButton,
        @"front": self.frontButton,
        @"dock": self.dockButton,
        @"collapse": self.collapseButton,
        @"done": self.doneButton,
    };
}

- (UIButton *)pxTopIconForIdentifier:(NSString *)identifier
                              action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.tintColor = [UIColor whiteColor];
    CGFloat iconSize = [PXEditorOrder buttonIconPointSize];
    UIImage *icon = [UIImage systemImageNamed:[PXEditorOrder iconNameForActionIdentifier:identifier]];
    if (icon) {
        UIImageSymbolConfiguration *configuration =
            [UIImageSymbolConfiguration configurationWithPointSize:iconSize weight:UIFontWeightMedium];
        [button setImage:[icon imageWithConfiguration:configuration] forState:UIControlStateNormal];
    } else {
        NSString *a11y = [PXEditorOrder displayNameForActionIdentifier:identifier];
        [button setTitle:a11y forState:UIControlStateNormal];
        button.titleLabel.font = [UIFont systemFontOfSize:10];
        button.titleLabel.adjustsFontSizeToFitWidth = YES;
    }
    button.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.08];
    button.layer.cornerRadius = 9.0;
    button.accessibilityLabel = [PXEditorOrder displayNameForActionIdentifier:identifier];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [self.topBar addSubview:button];
    return button;
}

- (void)pxBuildBottomPanel {
    _bottomPanel = [[UIView alloc] init];
    // 全屏标记使用可配置的磨砂调色层；普通图片编辑器保留原样。
    _bottomPanel.backgroundColor = self.fullscreenMarkup
        ? [UIColor clearColor]
        : [UIColor colorWithWhite:0.13 alpha:1.0];
    _bottomPanel.layer.cornerRadius = self.fullscreenMarkup ? 24.0 : 0.0;
    _bottomPanel.clipsToBounds = YES;
    [self.editorCard addSubview:_bottomPanel];
    _panelScrollView = [[UIScrollView alloc] init];
    _panelScrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    _panelScrollView.alwaysBounceVertical = NO;
    [_bottomPanel addSubview:_panelScrollView];
    if (self.fullscreenMarkup) {
        _panelDragGrip = [[UIView alloc] init];
        [_bottomPanel addSubview:_panelDragGrip];
        UIView *gripLine = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 38, 4)];
        gripLine.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.65];
        gripLine.layer.cornerRadius = 2.0;
        gripLine.tag = 1;
        gripLine.userInteractionEnabled = NO;
        [_panelDragGrip addSubview:gripLine];
        UIPanGestureRecognizer *drag = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pxPanelPan:)];
        [_panelDragGrip addGestureRecognizer:drag];

        // 双击面板空白处收起面板；当前工具与画布状态保留（画笔仍可直接涂抹），
        // 收起把手点按或双击恢复。手势 delegate 排除控件，按钮/滑杆节奏不受影响。
        UITapGestureRecognizer *panelDoubleTap =
            [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(pxPanelDoubleTapped:)];
        panelDoubleTap.numberOfTapsRequired = 2;
        panelDoubleTap.delegate = self;
        [_bottomPanel addGestureRecognizer:panelDoubleTap];

        _collapsedHandle = [UIButton buttonWithType:UIButtonTypeSystem];
        _collapsedHandle.backgroundColor = _bottomPanel.backgroundColor;
        _collapsedHandle.tintColor = [UIColor whiteColor];
        _collapsedHandle.layer.cornerRadius = PXEditorCollapsedHandleHeight / 2.0;
        _collapsedHandle.accessibilityLabel = @"展开工具面板";
        _collapsedHandle.layer.borderWidth = 0.5;
        _collapsedHandle.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.35].CGColor;
        UIImage *handleIcon = [UIImage systemImageNamed:@"pencil.tip.crop.circle"];
        if (handleIcon) {
            [_collapsedHandle setImage:handleIcon forState:UIControlStateNormal];
        } else {
            [_collapsedHandle setTitle:@"≡" forState:UIControlStateNormal];
            _collapsedHandle.titleLabel.font = [UIFont systemFontOfSize:22 weight:UIFontWeightMedium];
        }
        [_collapsedHandle addTarget:self action:@selector(pxExpandPanelTapped:) forControlEvents:UIControlEventTouchUpInside];
        UIPanGestureRecognizer *handleDrag = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pxPanelPan:)];
        [_collapsedHandle addGestureRecognizer:handleDrag];
        _collapsedHandle.hidden = YES;
        [self.editorCard addSubview:_collapsedHandle];
    }

    // 线宽行：两端“最细/最粗”示意图标 + 白色大圆滑块，置于工具网格上方。
    _widthRow = [[UIView alloc] init];
    if (self.fullscreenMarkup) {
        _widthRow.backgroundColor = _bottomPanel.backgroundColor;
        _widthRow.layer.cornerRadius = 20.0;
        [self.editorCard addSubview:_widthRow];
    } else {
        [_bottomPanel addSubview:_widthRow];
    }
    _minWidthIcon = [[UIImageView alloc] initWithImage:[self pxWidthHintIconNamed:@"circle.inset.filled"]];
    _minWidthIcon.tintColor = UIColor.whiteColor;
    [_widthRow addSubview:_minWidthIcon];
    _maxWidthIcon = [[UIImageView alloc] initWithImage:[self pxWidthHintIconNamed:@"circle.fill"]];
    _maxWidthIcon.tintColor = UIColor.whiteColor;
    [_widthRow addSubview:_maxWidthIcon];
    _widthSlider = [[UISlider alloc] init];
    _widthSlider.tintColor = UIColor.whiteColor;
    _widthSlider.minimumTrackTintColor = UIColor.whiteColor;
    _widthSlider.thumbTintColor = UIColor.whiteColor;
    _widthSlider.maximumTrackTintColor = [UIColor colorWithWhite:0.35 alpha:1.0];
    [_widthSlider setThumbImage:PXEditorSliderThumbImage() forState:UIControlStateNormal];
    _widthSlider.accessibilityLabel = @"画笔粗细";
    [_widthSlider addTarget:self action:@selector(pxWidthChanged:) forControlEvents:UIControlEventValueChanged];
    [_widthRow addSubview:_widthSlider];
    if (self.fullscreenMarkup) {
        // 线宽行在此处才创建（全屏标记下悬浮于面板上方），补挂双击收起。
        UITapGestureRecognizer *widthDoubleTap =
            [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(pxPanelDoubleTapped:)];
        widthDoubleTap.numberOfTapsRequired = 2;
        widthDoubleTap.delegate = self;
        [_widthRow addGestureRecognizer:widthDoubleTap];
    }

    // 多排工具网格，列数按最小触控宽度自动计算；顺序来自设置页排序。
    _toolGrid = [[UIView alloc] init];
    [_panelScrollView addSubview:_toolGrid];
    for (NSUInteger i = 0; i < self.tools.count; i++) {
        UIButton *tool = [UIButton buttonWithType:UIButtonTypeSystem];
        tool.tintColor = [UIColor whiteColor];
        tool.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.10];
        tool.layer.cornerRadius = 9.0;
        tool.accessibilityLabel = self.tools[i].title;
        NSString *iconName = self.tools[i].iconName;
        UIImage *icon = iconName.length ? [UIImage systemImageNamed:iconName] : nil;
        if (icon) {
            UIImageSymbolConfiguration *configuration =
                [UIImageSymbolConfiguration configurationWithPointSize:[PXEditorOrder buttonIconPointSize]
                                                                weight:UIFontWeightMedium];
            [tool setImage:[icon imageWithConfiguration:configuration] forState:UIControlStateNormal];
        } else {
            // 符号缺失兜底：显示中文名
            [tool setTitle:self.tools[i].title forState:UIControlStateNormal];
            tool.titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
        }
        [tool addTarget:self action:@selector(pxToolTapped:) forControlEvents:UIControlEventTouchUpInside];
        tool.tag = (NSInteger)i;
        [_toolGrid addSubview:tool];
        [self.toolButtons addObject:tool];
    }

    // 彩虹环作为独立网格项，点击唤起系统取色器。
    _customColorButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _customColorButton.accessibilityLabel = @"自定义颜色";
    [_customColorButton addTarget:self action:@selector(pxCustomColorTapped:)
                 forControlEvents:UIControlEventTouchUpInside];
    [_toolGrid addSubview:_customColorButton];
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
    _customColorSwatch.layer.cornerRadius = 12.0;
    _customColorSwatch.userInteractionEnabled = NO;
    [_customColorButton addSubview:_customColorSwatch];

    // 贴纸同样使用多排网格，与工具一起纵向滚动。
    _stickerRow = [[UIScrollView alloc] init];
    _stickerRow.showsHorizontalScrollIndicator = NO;
    _stickerRow.scrollEnabled = NO;
    _stickerRow.hidden = YES;
    [_panelScrollView addSubview:_stickerRow];
    NSArray<NSString *> *stickers = @[
        @"✅", @"❌", @"⚠️", @"🔥", @"⭐️", @"💡", @"📌", @"🎯",
        @"👍", @"👌", @"🙌", @"🤩", @"😂", @"🥰", @"😎", @"🤔",
        @"😭", @"😡", @"🎉", @"❤️", @"💚", @"💙", @"🚀", @"💩",
    ];
    for (NSUInteger i = 0; i < stickers.count; i++) {
        UIButton *sticker = [UIButton buttonWithType:UIButtonTypeSystem];
        sticker.titleLabel.font = [UIFont systemFontOfSize:22];
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

    [self pxApplyFrostedBackgrounds];
}

/// 背景单独使用透明磨砂，按钮、图标和滑杆保持不透明。
- (void)pxApplyFrostedBackgrounds {
    if (!self.fullscreenMarkup) return;
    [PXPanelAppearance installBackgroundInView:_bottomPanel];
    [PXPanelAppearance installBackgroundInView:_widthRow];
    [PXPanelAppearance installBackgroundInView:_collapsedHandle];
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

- (NSUInteger)pxGridItemCount {
    return self.toolButtons.count + 1 + (self.fullscreenMarkup ? self.actionButtons.count : 0);
}

- (PXEditorGridLayout)pxToolLayoutForWidth:(CGFloat)width {
    return PXEditorGridMake(width, [self pxGridItemCount], 8);
}

- (CGFloat)pxPanelContentHeightForWidth:(CGFloat)width {
    CGFloat height = [self pxToolLayoutForWidth:width].height;
    if (self.tools[self.selectedToolIndex].type == PXAnnotationTypeSticker) {
        height += PXEditorPanelRowGap + PXEditorGridMake(width, self.stickerButtons.count, 8).height;
    }
    return height;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect bounds = self.view.bounds;
    UIEdgeInsets safe = self.view.safeAreaInsets;
    self.backdropView.frame = bounds;
    self.backdropView.hidden = self.fullscreenMarkup;
    CGRect card = self.fullscreenMarkup ? bounds : UIEdgeInsetsInsetRect(bounds,
        UIEdgeInsetsMake(safe.top + 12, safe.left + 12, safe.bottom + 12, safe.right + 12));
    self.editorCard.frame = card;
    CGFloat width = card.size.width;
    CGFloat height = card.size.height;
    CGFloat panelWidth = self.fullscreenMarkup ? MIN(600.0, width - safe.left - safe.right - 24.0) : width;
    CGFloat topHeight = self.fullscreenMarkup ? 0.0 : PXEditorGridMake(width, self.actionButtons.count, 8).height + 14.0;
    self.topBar.hidden = self.fullscreenMarkup;
    self.topBar.frame = CGRectMake(0, 0, width, topHeight);
    PXEditorGridLayout actions = PXEditorGridMake(width, self.actionButtons.count, 8);
    if (!self.fullscreenMarkup) {
        for (NSUInteger i = 0; i < self.actionButtons.count; i++) {
            self.actionButtons[i].frame = CGRectOffset(PXEditorGridFrame(actions, i), 0, 7);
        }
    }

    CGFloat sliderSpace = PXEditorRowSliderHeight + PXEditorPanelRowGap;
    CGFloat wanted = PXEditorPanelPadTop + (self.fullscreenMarkup ? PXEditorPanelGripHeight : sliderSpace) +
        [self pxPanelContentHeightForWidth:panelWidth] + PXEditorPanelPadBottom;
    // 矮屏和贴纸列表允许面板纵向滚动，始终保留画布；不缩小触控区域。
    CGFloat availableHeight = self.fullscreenMarkup ? height - safe.top - safe.bottom - 24.0 - sliderSpace : height - topHeight;
    CGFloat maximum = MAX(112.0, MIN(availableHeight * 0.55, availableHeight - 100.0));
    CGFloat panelHeight = self.isCropMode ? 76.0 : MIN(wanted, maximum);
    CGFloat panelY = height - panelHeight;
    if (self.fullscreenMarkup) {
        panelY = self.panelAtTop ? safe.top + 12.0 + (self.isCropMode ? 0 : sliderSpace) : height - safe.bottom - 12.0 - panelHeight;
    }
    CGRect panelAllowed = CGRectMake(safe.left + 12.0,
        safe.top + 12.0 + (self.isCropMode ? 0.0 : sliderSpace),
        MAX(1.0, width - safe.left - safe.right - 24.0),
        MAX(1.0, height - safe.top - safe.bottom - 24.0 - (self.isCropMode ? 0.0 : sliderSpace)));
    CGPoint origin = CGPointMake((width - panelWidth) / 2.0, panelY);
    if (self.fullscreenMarkup && self.hasPanelPosition && !self.isCropMode) origin = self.panelOrigin;
    if (self.fullscreenMarkup) {
        origin = PXEditorClampFloatingOrigin(origin, CGSizeMake(panelWidth, panelHeight), panelAllowed);
        if (self.hasPanelPosition && !self.isCropMode) self.panelOrigin = origin;
    }
    self.bottomPanel.frame = CGRectMake(origin.x, origin.y, panelWidth, panelHeight);
    if (self.fullscreenMarkup) {
        CGRect handleAllowed = CGRectMake(safe.left + 12.0, safe.top + 12.0,
            MAX(1.0, width - safe.left - safe.right - 24.0),
            MAX(1.0, height - safe.top - safe.bottom - 24.0));
        CGPoint handleOrigin = self.panelCollapsed
            ? self.collapsedHandleOrigin
            : CGPointMake(origin.x + (panelWidth - PXEditorCollapsedHandleWidth) / 2.0, origin.y);
        handleOrigin = PXEditorClampFloatingOrigin(handleOrigin,
            CGSizeMake(PXEditorCollapsedHandleWidth, PXEditorCollapsedHandleHeight), handleAllowed);
        self.collapsedHandle.frame = CGRectMake(handleOrigin.x, handleOrigin.y,
            PXEditorCollapsedHandleWidth, PXEditorCollapsedHandleHeight);
        self.collapsedHandleOrigin = handleOrigin;
        self.bottomPanel.hidden = self.panelCollapsed;
        self.widthRow.hidden = self.panelCollapsed || self.isCropMode;
        self.collapsedHandle.hidden = !self.panelCollapsed || self.isCropMode;
    }
    [self pxLayoutBottomPanel];

    CGRect scrollFrame = CGRectMake(0, topHeight, width, MAX(1.0, panelY - topHeight));
    if (self.fullscreenMarkup) {
        scrollFrame = self.editorCard.bounds;
        if ((self.fitAbovePanel && !self.panelCollapsed) || self.isCropMode) {
            scrollFrame = PXEditorMarkupImageViewport(self.editorCard.bounds.size, self.bottomPanel.frame,
                safe.top, safe.left, safe.bottom, safe.right,
                self.isCropMode ? 0.0 : sliderSpace, self.panelAtTop);
        }
    }
    if (!CGRectEqualToRect(self.scrollView.frame, scrollFrame)) {
        self.scrollView.frame = scrollFrame;
        [self pxRelayoutZoomContainer];
    }
}

- (void)pxLayoutBottomPanel {
    CGFloat width = self.bottomPanel.bounds.size.width;
    CGFloat height = self.bottomPanel.bounds.size.height;
    self.widthRow.frame = self.fullscreenMarkup
        ? CGRectMake(self.bottomPanel.frame.origin.x, self.bottomPanel.frame.origin.y - PXEditorPanelRowGap - PXEditorRowSliderHeight,
                     width, PXEditorRowSliderHeight)
        : CGRectMake(0, PXEditorPanelPadTop, width, PXEditorRowSliderHeight);
    CGFloat gridY = PXEditorPanelPadTop + (self.fullscreenMarkup ? PXEditorPanelGripHeight : PXEditorRowSliderHeight + PXEditorPanelRowGap);
    if (self.fullscreenMarkup) {
        self.panelDragGrip.hidden = self.isCropMode;
        self.panelDragGrip.frame = CGRectMake(0, 0, width, PXEditorPanelGripHeight + 2.0);
        UIView *gripLine = [self.panelDragGrip viewWithTag:1];
        gripLine.center = CGPointMake(width / 2.0, PXEditorPanelGripHeight / 2.0);
    }
    self.panelScrollView.frame = CGRectMake(0, gridY, width, MAX(0.0, height - gridY - PXEditorPanelPadBottom));
    PXEditorGridLayout layout = [self pxToolLayoutForWidth:width];
    self.toolGrid.frame = CGRectMake(0, 0, width, layout.height);
    NSMutableArray<UIView *> *items = [NSMutableArray array];
    [items addObjectsFromArray:self.toolButtons];
    [items addObject:self.customColorButton];
    if (self.fullscreenMarkup) [items addObjectsFromArray:self.actionButtons];
    for (NSUInteger i = 0; i < items.count; i++) {
        CGRect frame = PXEditorGridFrame(layout, i);
        items[i].frame = frame;
    }
    BOOL sticker = self.tools[self.selectedToolIndex].type == PXAnnotationTypeSticker;
    self.stickerRow.hidden = !sticker || self.isCropMode;
    PXEditorGridLayout stickers = PXEditorGridMake(width, self.stickerButtons.count, 8);
    self.stickerRow.frame = CGRectMake(0, layout.height + PXEditorPanelRowGap, width, stickers.height);
    for (NSUInteger i = 0; i < self.stickerButtons.count; i++) {
        self.stickerButtons[i].frame = PXEditorGridFrame(stickers, i);
    }
    self.stickerRow.contentSize = self.stickerRow.bounds.size;
    self.panelScrollView.contentSize = CGSizeMake(width, [self pxPanelContentHeightForWidth:width]);
    self.panelScrollView.hidden = self.isCropMode;
    self.cropRow.frame = CGRectMake(0, (height - PXEditorCropRowHeight) / 2.0, width, PXEditorCropRowHeight);
    [self pxLayoutWidthRow];
    [self pxLayoutCropRow];
    [self pxLayoutCustomColorGradient];
}

- (void)pxLayoutWidthRow {
    CGFloat width = self.widthRow.bounds.size.width;
    self.minWidthIcon.frame = CGRectMake(16, 11, 22, 22);
    self.maxWidthIcon.frame = CGRectMake(width - 38, 11, 22, 22);
    self.widthSlider.frame = CGRectMake(48, 0, MAX(40.0, width - 92.0), PXEditorRowSliderHeight);
}

- (void)pxLayoutCustomColorGradient {
    self.customColorGradient.frame = CGRectInset(self.customColorButton.bounds, 2, 2);
    self.customColorGradient.cornerRadius = self.customColorGradient.bounds.size.width / 2.0;
    self.customColorSwatch.frame = CGRectInset(self.customColorButton.bounds, 7, 7);
    self.customColorSwatch.layer.cornerRadius = self.customColorSwatch.bounds.size.width / 2.0;
}

- (BOOL)prefersStatusBarHidden { return YES; }
- (BOOL)prefersHomeIndicatorAutoHidden { return YES; }

- (void)pxLayoutCropRow {
    CGFloat width = _cropRow.bounds.size.width;
    CGFloat y = (_cropRow.bounds.size.height - 40.0) / 2.0;
    self.cropCancelButton.frame = CGRectMake(14, y, (width - 34) / 2.0, 40);
    self.cropApplyButton.frame = CGRectMake(20 + (width - 34) / 2.0, y, (width - 34) / 2.0, 40);
}

#pragma mark - 缩放容器

/// 画布重排的初始缩放模式：适宽 = 打开/重排默认（竖长图铺满视口宽度，方便画笔编辑）；
/// 适屏 = 「适屏」按钮（整图完整可见，1.3.5 保底语义）。
typedef NS_ENUM(NSInteger, PXZoomInitialMode) {
    PXZoomInitialFitWidth = 0,
    PXZoomInitialFitWhole = 1,
};

/// 画布/容器尺寸随文档底图变化（进入、裁剪、旋转后调用）。
/// 编辑基准为适屏：缩放下限恒为适屏（整图完整可见，不放得比整图更小）；
/// 初始缩放默认适宽（见 PXZoomInitialMode）。
/// 每次视口或图片几何变化后重新适配居中；旧滚动偏移会把缩小后的图片移出视口。
- (void)pxRelayoutZoomContainer {
    [self pxRelayoutZoomContainerInMode:PXZoomInitialFitWidth];
}

- (void)pxRelayoutZoomContainerInMode:(PXZoomInitialMode)mode {
    CGSize imageSize = self.document.sourceImage.size;
    if (imageSize.width <= 0 || imageSize.height <= 0) return;

    CGFloat baseScale = [self pxBaseScaleForImageSize:imageSize inBounds:_scrollView.bounds];
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
    CGFloat maximumScale = baseScale * PXEditorMaxZoomFactor;
    _scrollView.maximumZoomScale = maximumScale;
    // 初始缩放：适宽模式取视口宽度比（竖长图按适屏显示时宽度只有视口一半、两侧大片黑边，
    // 打开即铺满宽度；下限仍是适屏，捏合缩小即可回到整图——1.3.0 被推翻的是“铺满当下限”）。
    CGFloat widthScale = _scrollView.bounds.size.width / imageSize.width;
    CGFloat initialScale = (mode == PXZoomInitialFitWidth)
        ? MIN(MAX(widthScale, baseScale), maximumScale)
        : baseScale;
    _scrollView.zoomScale = initialScale;
    [self pxCenterContent];
    _scrollView.contentOffset = CGPointMake(-_scrollView.contentInset.left,
                                            -_scrollView.contentInset.top);
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

- (void)scrollViewDidZoom:(UIScrollView *)scrollView {
    [self pxCenterContent];
}

#pragma mark - 工具与颜色选择

- (void)pxSelectToolIndex:(NSUInteger)index {
    if (index >= self.tools.count || self.isExporting) return;
    self.selectedToolIndex = index;
    self.panelScrollView.contentOffset = CGPointZero;
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
        self.canvas.currentTool = self.tools[index].type;
        self.canvas.currentFillStyle = self.tools[index].fillStyle;
    }
    BOOL stickerTool = (self.tools[index].type == PXAnnotationTypeSticker);
    // 表情行显隐改变面板高度，交由 viewDidLayoutSubviews 重算（画布随之重适配一次）。
    self.stickerRow.hidden = !stickerTool;
    [self.view setNeedsLayout];

    // 线宽行对绘制类工具有效，其余工具置灰提示（保持行高不变，避免切工具时画布重排）。
    PXAnnotationType type = self.tools[index].type;
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
    if (self.isExporting || !self.view.window || self.presentedViewController) return;
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

/// 复制/分享/保存/完成共用：提交进行中输入、放弃未确认裁剪后渲染当前文档（与完成同路径），
/// 渲染期间 isExporting 锁全 UI（含画布，防止最后一笔不入图）；失败弹窗提示。then 固定主线程回调。
- (void)pxRenderCurrentImageThen:(void (^)(UIImage *result))then {
    if (self.isExporting || !self.view.window || self.presentedViewController) return;
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
        if (!strongSelf || !strongSelf.view.window) return;
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
    // viewDidLayoutSubviews 会按裁剪视口重排一次，保证裁剪框完整可见。
}

- (void)pxExitCropModeApply:(BOOL)apply {
    if (!self.isCropMode) return;
    if (apply) {
        if (![self.canvas applyCrop]) {
            PXLogWarn(@"editor crop: apply failed, keeping crop mode");
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"裁剪失败"
                                                                           message:@"未能生成裁剪后的图片，请重新调整裁剪区域"
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
            return;
        }
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
    // viewDidLayoutSubviews 仅按退出裁剪模式后的最终视口适配新底图。
    [self pxRefreshButtons];
}

- (void)pxCloseTapped:(UIButton *)sender {
    if (self.isExporting) return;
    [self.canvas commitActiveText];
    if (self.delegate && [self.delegate respondsToSelector:@selector(editorControllerDidCancel:)]) {
        [self.delegate editorControllerDidCancel:self];
    }
}

- (void)pxFitTapped:(UIButton *)sender {
    if (self.isExporting) return;
    if (self.fullscreenMarkup) {
        self.fitAbovePanel = !self.fitAbovePanel;
        self.fitButton.accessibilityLabel = self.fitAbovePanel ? @"全屏查看" : @"整图适屏";
        [self.view setNeedsLayout];
        [self.view layoutIfNeeded];
    }
    // 「适屏」按钮的承诺是整图完整可见：固定走适屏重置，不跟随适宽默认（否则按钮名不副实）。
    [self pxRelayoutZoomContainerInMode:PXZoomInitialFitWhole];
}

- (void)pxDockTapped:(UIButton *)sender {
    if (self.isExporting) return;
    self.panelAtTop = !self.panelAtTop;
    self.hasPanelPosition = NO;
    [self.view setNeedsLayout];
}

- (void)pxCollapsePanelTapped:(UIButton *)sender {
    if (self.isExporting || self.isCropMode || !self.fullscreenMarkup) return;
    self.collapsedHandleOrigin = CGPointMake(
        CGRectGetMidX(self.bottomPanel.frame) - PXEditorCollapsedHandleWidth / 2.0,
        CGRectGetMinY(self.bottomPanel.frame));
    self.panelCollapsed = YES;
    [self.view setNeedsLayout];
}

/// 双击面板/线宽行空白处 = 收起；仅隐藏面板，画布工具态不变（画笔等可直接继续涂抹）。
- (void)pxPanelDoubleTapped:(UITapGestureRecognizer *)gesture {
    [self pxCollapsePanelTapped:nil];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    // 面板上的按钮/滑杆保持自己的点击节奏，双击只吃背景区域。
    for (UIView *view = touch.view; view && view != gestureRecognizer.view; view = view.superview) {
        if ([view isKindOfClass:UIControl.class]) return NO;
    }
    return YES;
}

- (void)pxExpandPanelTapped:(UIButton *)sender {
    if (self.isExporting || !self.fullscreenMarkup) return;
    self.panelOrigin = CGPointMake(
        CGRectGetMidX(self.collapsedHandle.frame) - self.bottomPanel.bounds.size.width / 2.0,
        CGRectGetMinY(self.collapsedHandle.frame));
    self.hasPanelPosition = YES;
    self.panelCollapsed = NO;
    self.panelAtTop = self.panelOrigin.y < CGRectGetMidY(self.editorCard.bounds);
    [self.view setNeedsLayout];
}

- (void)pxPanelPan:(UIPanGestureRecognizer *)gesture {
    if (self.isExporting || self.isCropMode || !self.fullscreenMarkup) return;
    if (gesture.state == UIGestureRecognizerStateBegan) {
        self.panStartOrigin = self.panelCollapsed ? self.collapsedHandle.frame.origin : self.bottomPanel.frame.origin;
    } else if (gesture.state == UIGestureRecognizerStateChanged) {
        CGPoint offset = [gesture translationInView:self.editorCard];
        CGPoint requested = CGPointMake(self.panStartOrigin.x + offset.x,
                                        self.panStartOrigin.y + offset.y);
        if (self.panelCollapsed) {
            self.collapsedHandleOrigin = requested;
        } else {
            self.panelOrigin = requested;
            self.hasPanelPosition = YES;
            self.panelAtTop = requested.y < CGRectGetMidY(self.editorCard.bounds);
        }
        [self.view setNeedsLayout];
        [self.view layoutIfNeeded];
    }
}

- (void)pxSaveTapped:(UIButton *)sender {
    [self pxFinishWithAction:PXOutputActionSave];
}

- (void)pxDoneTapped:(UIButton *)sender {
    [self pxFinishWithAction:PXOutputActionPreviewOnly];
}

- (void)pxFinishWithAction:(PXOutputAction)action {
    __weak typeof(self) weakSelf = self;
    [self pxRenderCurrentImageThen:^(UIImage *result) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || !strongSelf.view.window) return;
        [strongSelf.delegate editorController:strongSelf didFinishWithImage:result action:action];
    }];
}

- (void)pxRefreshButtons {
    BOOL exporting = self.isExporting;
    self.undoButton.enabled = self.canvas.canUndo && !exporting;
    self.redoButton.enabled = self.canvas.canRedo && !exporting;
    self.undoButton.alpha = self.canvas.canUndo ? 1.0 : 0.4;
    self.redoButton.alpha = self.canvas.canRedo ? 1.0 : 0.4;
    BOOL hasSelection = (self.canvas.selectedAnnotation != nil);
    self.deleteButton.hidden = NO;
    self.frontButton.hidden = NO;
    self.clipboardButton.hidden = NO;
    self.shareButton.hidden = NO;
    self.deleteButton.alpha = hasSelection ? 1.0 : 0.35;
    self.frontButton.alpha = hasSelection ? 1.0 : 0.35;
    self.deleteButton.enabled = hasSelection && !exporting;
    self.frontButton.enabled = hasSelection && !exporting;
    self.clipboardButton.enabled = !exporting;
    self.shareButton.enabled = !exporting;
    self.cropButton.enabled = !exporting;
    self.rotateButton.enabled = !exporting;
    self.doneButton.enabled = !exporting;
    self.doneButton.alpha = exporting ? 0.4 : 1.0;
    self.saveButton.enabled = !exporting;
    self.fitButton.enabled = !exporting;
    self.dockButton.enabled = !exporting;
    self.collapseButton.enabled = !exporting;
    self.collapsedHandle.enabled = !exporting;
    self.closeButton.enabled = !exporting;
    self.bottomPanel.userInteractionEnabled = !exporting;
    self.widthRow.userInteractionEnabled = !exporting;
    self.scrollView.userInteractionEnabled = !exporting;
}

#pragma mark - PXEditorCanvasDelegate

- (void)canvasDidChangeContent:(PXEditorCanvas *)canvas {
    [self pxRefreshButtons];
}

- (void)canvasDidChangeSelection:(PXEditorCanvas *)canvas {
    [self pxRefreshButtons];
}

- (void)canvasDidChangeGeometry:(PXEditorCanvas *)canvas {
    if (self.isCropMode) return;   // applyCrop 正在收尾；退出裁剪模式后再适配新底图。
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
