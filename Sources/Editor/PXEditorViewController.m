#import "PXEditorViewController.h"
#import "PXEditorCanvas.h"
#import "PXEditorDocument.h"
#import "PXEditorRenderer.h"
#import "../Common/PXLog.h"
#import "../Common/PXPreferences.h"
#import "../Common/PXConstants.h"

static const CGFloat PXEditorTopBarHeight = 44.0;
static const CGFloat PXEditorBottomPanelHeight = 96.0;
static const CGFloat PXEditorMaxZoomFactor = 8.0;

#pragma mark - 工具定义

typedef struct {
    PXAnnotationType type;
    PXAnnotationFillStyle fillStyle;
    NSString *title;
} PXEditorToolItem;

static const PXEditorToolItem PXEditorTools[] = {
    { PXAnnotationTypePan,       PXAnnotationFillStyleHollow, @"平移" },
    { PXAnnotationTypeBrush,     PXAnnotationFillStyleHollow, @"画笔" },
    { PXAnnotationTypeHighlight, PXAnnotationFillStyleHollow, @"荧光" },
    { PXAnnotationTypeLine,      PXAnnotationFillStyleHollow, @"直线" },
    { PXAnnotationTypeArrow,     PXAnnotationFillStyleHollow, @"箭头" },
    { PXAnnotationTypeRectangle, PXAnnotationFillStyleHollow, @"方框" },
    { PXAnnotationTypeRectangle, PXAnnotationFillStyleSolid,  @"实心方" },
    { PXAnnotationTypeOval,      PXAnnotationFillStyleHollow, @"椭圆" },
    { PXAnnotationTypeOval,      PXAnnotationFillStyleSolid,  @"实心圆" },
    { PXAnnotationTypeMosaic,    PXAnnotationFillStyleHollow, @"马赛克" },
    { PXAnnotationTypeSpotlight, PXAnnotationFillStyleHollow, @"聚光" },
    { PXAnnotationTypeText,      PXAnnotationFillStyleHollow, @"文字" },
    { PXAnnotationTypeMagnifier, PXAnnotationFillStyleHollow, @"放大镜" },
    { PXAnnotationTypeSticker,   PXAnnotationFillStyleHollow, @"贴纸" },
    { PXAnnotationTypeStamp,     PXAnnotationFillStyleHollow, @"图章" },
};
static const NSUInteger PXEditorToolCount = sizeof(PXEditorTools) / sizeof(PXEditorTools[0]);

@interface PXEditorViewController () <
    PXEditorCanvasDelegate,
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

@property (nonatomic, strong) UIView *bottomPanel;
@property (nonatomic, strong) UIScrollView *toolRow;
@property (nonatomic, strong) NSMutableArray<UIButton *> *toolButtons;
@property (nonatomic, strong) UIView *colorRow;
@property (nonatomic, strong) NSMutableArray<UIButton *> *colorButtons;
@property (nonatomic, strong) UISlider *widthSlider;
@property (nonatomic, strong) UIScrollView *stickerRow;
@property (nonatomic, strong) NSMutableArray<UIButton *> *stickerButtons;
@property (nonatomic, strong) UIView *cropRow;
@property (nonatomic, strong) UIButton *cropCancelButton;
@property (nonatomic, strong) UIButton *cropApplyButton;

@property (nonatomic, assign) NSUInteger selectedToolIndex;
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

    [self pxSelectToolIndex:0];
    [self pxSelectColorIndex:0];
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
}

- (UIButton *)pxTopIconNamed:(NSString *)iconName a11y:(NSString *)a11y action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.tintColor = [UIColor whiteColor];
    UIImage *icon = [UIImage systemImageNamed:iconName];
    if (icon) {
        [button setImage:icon forState:UIControlStateNormal];
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
    _bottomPanel.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.88];
    [self.view addSubview:_bottomPanel];

    // 工具行（横向滚动）
    _toolRow = [[UIScrollView alloc] init];
    _toolRow.showsHorizontalScrollIndicator = NO;
    [_bottomPanel addSubview:_toolRow];
    for (NSUInteger i = 0; i < PXEditorToolCount; i++) {
        UIButton *tool = [UIButton buttonWithType:UIButtonTypeSystem];
        tool.tintColor = [UIColor whiteColor];
        tool.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        [tool setTitle:PXEditorTools[i].title forState:UIControlStateNormal];
        tool.layer.cornerRadius = 8.0;
        tool.layer.borderWidth = 1.0;
        tool.layer.borderColor = [UIColor colorWithWhite:0.4 alpha:1.0].CGColor;
        [tool addTarget:self action:@selector(pxToolTapped:) forControlEvents:UIControlEventTouchUpInside];
        tool.tag = (NSInteger)i;
        [_toolRow addSubview:tool];
        [self.toolButtons addObject:tool];
    }

    // 颜色 + 线宽行
    _colorRow = [[UIView alloc] init];
    [_bottomPanel addSubview:_colorRow];
    NSArray<UIColor *> *colors = @[
        [UIColor redColor],
        [UIColor colorWithRed:1.0 green:0.55 blue:0.1 alpha:1.0],
        [UIColor yellowColor],
        [UIColor colorWithRed:0.15 green:0.75 blue:0.3 alpha:1.0],
        [UIColor colorWithRed:0.1 green:0.5 blue:1.0 alpha:1.0],
        [UIColor colorWithRed:0.65 green:0.3 blue:0.95 alpha:1.0],
        [UIColor blackColor],
        [UIColor whiteColor],
    ];
    for (NSUInteger i = 0; i < colors.count; i++) {
        UIButton *colorButton = [UIButton buttonWithType:UIButtonTypeCustom];
        colorButton.backgroundColor = colors[i];
        colorButton.layer.cornerRadius = 13.0;
        colorButton.layer.borderWidth = 2.0;
        colorButton.layer.borderColor = [UIColor clearColor].CGColor;
        [colorButton addTarget:self action:@selector(pxColorTapped:) forControlEvents:UIControlEventTouchUpInside];
        colorButton.tag = (NSInteger)i;
        [_colorRow addSubview:colorButton];
        [self.colorButtons addObject:colorButton];
    }

    _widthSlider = [[UISlider alloc] init];
    _widthSlider.minimumTrackTintColor = [UIColor colorWithWhite:0.5 alpha:1.0];
    [_widthSlider addTarget:self action:@selector(pxWidthChanged:) forControlEvents:UIControlEventValueChanged];
    [_colorRow addSubview:_widthSlider];

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
        sticker.titleLabel.font = [UIFont systemFontOfSize:24];
        [sticker setTitle:stickers[i] forState:UIControlStateNormal];
        [sticker addTarget:self action:@selector(pxStickerTapped:) forControlEvents:UIControlEventTouchUpInside];
        sticker.tag = (NSInteger)i;
        [_stickerRow addSubview:sticker];
        [self.stickerButtons addObject:sticker];
    }
    self.canvas.currentStickerText = stickers.firstObject;

    // 裁剪操作行（裁剪模式替换工具行）
    _cropRow = [[UIView alloc] init];
    _cropRow.hidden = YES;
    [_bottomPanel addSubview:_cropRow];
    _cropCancelButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _cropCancelButton.tintColor = [UIColor whiteColor];
    _cropCancelButton.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    [_cropCancelButton setTitle:@"取消裁剪" forState:UIControlStateNormal];
    _cropCancelButton.layer.cornerRadius = 8.0;
    _cropCancelButton.layer.borderWidth = 1.0;
    _cropCancelButton.layer.borderColor = [UIColor colorWithWhite:0.4 alpha:1.0].CGColor;
    [_cropCancelButton addTarget:self action:@selector(pxCropCancelTapped:) forControlEvents:UIControlEventTouchUpInside];
    [_cropRow addSubview:_cropCancelButton];

    _cropApplyButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _cropApplyButton.tintColor = [UIColor whiteColor];
    _cropApplyButton.backgroundColor = [UIColor colorWithRed:0.15 green:0.55 blue:0.25 alpha:1.0];
    _cropApplyButton.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    [_cropApplyButton setTitle:@"应用裁剪" forState:UIControlStateNormal];
    _cropApplyButton.layer.cornerRadius = 8.0;
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
    CGFloat bottom = self.view.safeAreaInsets.bottom;

    _topBar.frame = CGRectMake(0, 0, viewWidth, top + PXEditorTopBarHeight);
    [self pxLayoutTopBarWithTop:top];

    _bottomPanel.frame = CGRectMake(0, viewHeight - bottom - PXEditorBottomPanelHeight,
                                    viewWidth, PXEditorBottomPanelHeight + bottom);
    [self pxLayoutBottomPanel];

    CGRect scrollFrame = CGRectMake(0, top + PXEditorTopBarHeight,
                                    viewWidth,
                                    viewHeight - top - PXEditorTopBarHeight - PXEditorBottomPanelHeight);
    if (!CGRectEqualToRect(_scrollView.frame, scrollFrame)) {
        BOOL needsReset = !CGSizeEqualToSize(_scrollView.frame.size, scrollFrame.size);
        _scrollView.frame = scrollFrame;
        if (needsReset) {
            [self pxRelayoutZoomContainer];
        }
    }
}

- (void)pxLayoutTopBarWithTop:(CGFloat)top {
    CGFloat width = self.topBar.bounds.size.width;
    CGFloat y = top;
    CGFloat height = PXEditorTopBarHeight;
    self.closeButton.frame = CGRectMake(8, y, 36, height);
    self.cropButton.frame = CGRectMake(46, y, 40, height);
    self.rotateButton.frame = CGRectMake(88, y, 40, height);
    self.undoButton.frame = CGRectMake(width - 220, y, 40, height);
    self.redoButton.frame = CGRectMake(width - 180, y, 40, height);
    self.deleteButton.frame = CGRectMake(width - 136, y, 40, height);
    self.frontButton.frame = CGRectMake(width - 96, y, 40, height);
    self.doneButton.frame = CGRectMake(width - 52, y, 48, height);
}

- (void)pxLayoutBottomPanel {
    CGFloat width = _bottomPanel.bounds.size.width;
    _toolRow.frame = CGRectMake(0, 6, width, 32);
    _cropRow.frame = CGRectMake(0, 6, width, 32);

    CGFloat rowY = 46.0;
    CGFloat colorRowHeight = PXEditorBottomPanelHeight - rowY - 6.0;
    _colorRow.frame = CGRectMake(0, rowY, width, MAX(colorRowHeight, 36.0));
    _stickerRow.frame = CGRectMake(0, rowY, width, MAX(colorRowHeight, 36.0));

    [self pxLayoutToolButtons];
    [self pxLayoutColorRow];
    [self pxLayoutStickerRow];
    [self pxLayoutCropRow];
}

- (void)pxLayoutToolButtons {
    CGFloat x = 10;
    for (UIButton *button in self.toolButtons) {
        CGSize fit = [button sizeThatFits:CGSizeMake(160, 28)];
        // contentEdgeInsets 在 iOS 15+ 被弃用，改用布局期加宽实现内边距。
        button.frame = CGRectMake(x, 2, ceil(fit.width) + 20, 28);
        x += ceil(fit.width) + 20 + 8;
    }
    self.toolRow.contentSize = CGSizeMake(x + 10, 32);
}

- (void)pxLayoutColorRow {
    CGFloat colorSize = 26.0;
    CGFloat x = 14;
    for (UIButton *button in self.colorButtons) {
        button.frame = CGRectMake(x, 4, colorSize, colorSize);
        x += colorSize + 9;
    }
    CGFloat sliderX = x + 6;
    CGFloat rowWidth = _colorRow.bounds.size.width;
    self.widthSlider.frame = CGRectMake(sliderX, 6,
                                        MAX(40.0, rowWidth - sliderX - 14), 20);
}

- (void)pxLayoutStickerRow {
    CGFloat x = 10;
    for (UIButton *button in self.stickerButtons) {
        button.frame = CGRectMake(x, 2, 40, 34);
        x += 44;
    }
    self.stickerRow.contentSize = CGSizeMake(x + 10, 36);
}

- (void)pxLayoutCropRow {
    CGFloat width = _cropRow.bounds.size.width;
    self.cropCancelButton.frame = CGRectMake(14, 2, (width - 34) / 2.0, 28);
    self.cropApplyButton.frame = CGRectMake(20 + (width - 34) / 2.0, 2, (width - 34) / 2.0, 28);
}

#pragma mark - 缩放容器

/// 画布/容器尺寸随文档底图变化（进入、裁剪、旋转后调用）。
- (void)pxRelayoutZoomContainer {
    CGSize imageSize = self.document.sourceImage.size;
    if (imageSize.width <= 0 || imageSize.height <= 0) return;

    CGRect fitted = [self pxFittedRectForImageSize:imageSize inBounds:_scrollView.bounds];
    _zoomContainer.frame = CGRectMake(0, 0, imageSize.width, imageSize.height);
    _imageView.frame = _zoomContainer.bounds;
    _imageView.image = self.document.sourceImage;
    self.canvas.frame = _zoomContainer.bounds;

    CGFloat fitScale = (imageSize.width > 0) ? fitted.size.width / imageSize.width : 1.0;
    _scrollView.minimumZoomScale = fitScale;
    _scrollView.maximumZoomScale = fitScale * PXEditorMaxZoomFactor;
    _scrollView.zoomScale = fitScale;
    [self pxCenterContent];
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

#pragma mark - 顶栏动作

- (void)pxSelectToolIndex:(NSUInteger)index {
    if (index >= PXEditorToolCount) return;
    self.selectedToolIndex = index;
    for (NSUInteger i = 0; i < self.toolButtons.count; i++) {
        UIButton *button = self.toolButtons[i];
        BOOL selected = (i == index);
        button.backgroundColor = selected ? [UIColor colorWithWhite:0.35 alpha:1.0] : [UIColor clearColor];
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
}

- (void)pxSelectColorIndex:(NSUInteger)index {
    for (NSUInteger i = 0; i < self.colorButtons.count; i++) {
        UIButton *button = self.colorButtons[i];
        button.layer.borderColor = (i == index) ? [UIColor whiteColor].CGColor : [UIColor clearColor].CGColor;
    }
    if (self.canvas && self.colorButtons.count > index) {
        self.canvas.currentColor = self.colorButtons[index].backgroundColor;
    }
}

- (void)pxToolTapped:(UIButton *)sender {
    [self pxSelectToolIndex:(NSUInteger)sender.tag];
}

- (void)pxColorTapped:(UIButton *)sender {
    [self pxSelectColorIndex:(NSUInteger)sender.tag];
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
    self.toolRow.hidden = YES;
    self.colorRow.hidden = YES;
    self.stickerRow.hidden = YES;
    self.cropRow.hidden = NO;
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
    BOOL stickerTool = (PXEditorTools[self.selectedToolIndex].type == PXAnnotationTypeSticker);
    self.toolRow.hidden = NO;
    self.colorRow.hidden = stickerTool;
    self.stickerRow.hidden = !stickerTool;
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
