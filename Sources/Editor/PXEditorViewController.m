#import "PXEditorViewController.h"
#import "PXEditorCanvas.h"
#import "PXEditorDocument.h"
#import "PXEditorRenderer.h"
#import "../Common/PXLog.h"
#import "../Common/PXPreferences.h"

static const CGFloat PXEditorTopBarHeight = 46.0;
static const CGFloat PXEditorBottomPanelHeight = 104.0;

typedef struct {
    PXAnnotationType type;
    NSString *title;
} PXEditorToolItem;

static const PXEditorToolItem PXEditorTools[] = {
    { PXAnnotationTypeBrush,      @"画笔" },
    { PXAnnotationTypeLine,       @"直线" },
    { PXAnnotationTypeArrow,      @"箭头" },
    { PXAnnotationTypeRectangle,  @"方框" },
    { PXAnnotationTypeOval,       @"椭圆" },
    { PXAnnotationTypeHighlight,  @"荧光" },
    { PXAnnotationTypeMosaic,     @"马赛克" },
    { PXAnnotationTypeText,       @"文字" },
};
static const NSUInteger PXEditorToolCount = sizeof(PXEditorTools) / sizeof(PXEditorTools[0]);

@interface PXEditorViewController () <PXEditorCanvasDelegate>
@property (nonatomic, strong) UIImage *sourceImage;
@property (nonatomic, weak) id<PXEditorViewControllerDelegate> delegate;
@property (nonatomic, strong) PXEditorDocument *document;
@property (nonatomic, strong) PXEditorCanvas *canvas;
@property (nonatomic, strong) UIView *topBar;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, strong) UIButton *undoButton;
@property (nonatomic, strong) UIButton *redoButton;
@property (nonatomic, strong) UIButton *doneButton;
@property (nonatomic, strong) NSMutableArray<UIButton *> *toolButtons;
@property (nonatomic, strong) NSMutableArray<UIButton *> *colorButtons;
@property (nonatomic, strong) UISlider *widthSlider;
@property (nonatomic, assign) BOOL isExporting;
@end

@implementation PXEditorViewController

- (instancetype)initWithImage:(UIImage *)sourceImage
                     delegate:(id<PXEditorViewControllerDelegate>)delegate {
    if (self = [super initWithNibName:nil bundle:nil]) {
        _sourceImage = sourceImage;
        _delegate = delegate;
        _toolButtons = [[NSMutableArray alloc] init];
        _colorButtons = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];

    self.document = [[PXEditorDocument alloc] initWithSourceImage:self.sourceImage];
    self.document.backgroundColor = [UIColor whiteColor];

    [self pxBuildUI];
}

#pragma mark - UI 构建

- (void)pxBuildUI {
    self.canvas = [[PXEditorCanvas alloc] initWithFrame:self.view.bounds document:self.document];
    self.canvas.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1.0];
    self.canvas.delegate = self;
    self.canvas.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.canvas.currentLineWidth = PXPreferences.config.editorDefaultLineWidth;
    [self.view addSubview:self.canvas];

    _topBar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, PXEditorTopBarHeight)];
    _topBar.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.85];
    _topBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:_topBar];

    _closeButton = [self pxBarButtonWithTitle:@"✕ 关闭" action:@selector(pxCloseTapped:)];
    _undoButton = [self pxBarButtonWithTitle:@"撤销" action:@selector(pxUndoTapped:)];
    _redoButton = [self pxBarButtonWithTitle:@"重做" action:@selector(pxRedoTapped:)];
    _doneButton = [self pxBarButtonWithTitle:@"完成 ✓" action:@selector(pxDoneTapped:)];

    [self pxLayoutTopBar];

    // 工具行 + 颜色/线宽行
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
        [self.view addSubview:tool];
        [self.toolButtons addObject:tool];
    }

    NSArray<UIColor *> *colors = @[
        [UIColor redColor], [UIColor colorWithRed:0.1 green:0.45 blue:1.0 alpha:1.0],
        [UIColor colorWithRed:0.1 green:0.7 blue:0.25 alpha:1.0], [UIColor yellowColor],
        [UIColor blackColor], [UIColor whiteColor],
    ];
    for (NSUInteger i = 0; i < colors.count; i++) {
        UIButton *colorButton = [UIButton buttonWithType:UIButtonTypeCustom];
        colorButton.backgroundColor = colors[i];
        colorButton.layer.cornerRadius = 12.0;
        colorButton.layer.borderWidth = 2.0;
        colorButton.layer.borderColor = [UIColor clearColor].CGColor;
        [colorButton addTarget:self action:@selector(pxColorTapped:) forControlEvents:UIControlEventTouchUpInside];
        colorButton.tag = (NSInteger)i;
        [self.view addSubview:colorButton];
        [self.colorButtons addObject:colorButton];
    }

    _widthSlider = [[UISlider alloc] init];
    _widthSlider.minimumValue = 0.5;
    _widthSlider.maximumValue = 8.0;
    _widthSlider.value = self.canvas.currentLineWidth;
    [_widthSlider addTarget:self action:@selector(pxWidthChanged:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:_widthSlider];

    [self pxSelectToolIndex:0];
    [self pxSelectColorIndex:0];
    [self pxRefreshUndoButtons];
}

- (UIButton *)pxBarButtonWithTitle:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.tintColor = [UIColor whiteColor];
    button.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    [button setTitle:title forState:UIControlStateNormal];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [self.topBar addSubview:button];
    return button;
}

- (void)pxLayoutTopBar {
    CGFloat width = self.topBar.bounds.size.width;
    self.closeButton.frame = CGRectMake(12, 0, 80, PXEditorTopBarHeight);
    self.undoButton.frame = CGRectMake(width - 190, 0, 56, PXEditorTopBarHeight);
    self.redoButton.frame = CGRectMake(width - 130, 0, 56, PXEditorTopBarHeight);
    self.doneButton.frame = CGRectMake(width - 70, 0, 60, PXEditorTopBarHeight);
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    CGFloat viewWidth = self.view.bounds.size.width;
    CGFloat viewHeight = self.view.bounds.size.height;
    CGFloat top = self.view.safeAreaInsets.top;
    CGFloat bottom = self.view.safeAreaInsets.bottom;

    CGRect canvasFrame = CGRectMake(0, top + PXEditorTopBarHeight,
                                    viewWidth,
                                    viewHeight - top - PXEditorTopBarHeight - PXEditorBottomPanelHeight - bottom);
    self.canvas.frame = canvasFrame;

    _topBar.frame = CGRectMake(0, top, viewWidth, PXEditorTopBarHeight);
    [self pxLayoutTopBar];

    CGFloat panelTop = canvasFrame.origin.y + canvasFrame.size.height + 6;
    NSUInteger toolCount = PXEditorToolCount;
    CGFloat toolWidth = MIN(52.0, (viewWidth - 20) / toolCount - 4);
    CGFloat toolHeight = 30.0;
    for (NSUInteger i = 0; i < self.toolButtons.count; i++) {
        UIButton *button = self.toolButtons[i];
        button.frame = CGRectMake(10 + i * (toolWidth + 6), panelTop, toolWidth, toolHeight);
    }

    CGFloat colorTop = panelTop + toolHeight + 10;
    CGFloat colorSize = 24.0;
    for (NSUInteger i = 0; i < self.colorButtons.count; i++) {
        UIButton *button = self.colorButtons[i];
        button.frame = CGRectMake(14 + i * (colorSize + 10), colorTop, colorSize, colorSize);
    }

    _widthSlider.frame = CGRectMake(14 + self.colorButtons.count * (colorSize + 10) + 8, colorTop + 1,
                                    viewWidth - (14 + self.colorButtons.count * (colorSize + 10) + 8) - 14, 22);
}

#pragma mark - 动作

- (void)pxSelectToolIndex:(NSUInteger)index {
    for (NSUInteger i = 0; i < self.toolButtons.count; i++) {
        UIButton *button = self.toolButtons[i];
        BOOL selected = (i == index);
        button.backgroundColor = selected ? [UIColor colorWithWhite:0.3 alpha:1.0] : [UIColor clearColor];
    }
    self.canvas.currentTool = PXEditorTools[index].type;
}

- (void)pxSelectColorIndex:(NSUInteger)index {
    for (NSUInteger i = 0; i < self.colorButtons.count; i++) {
        UIButton *button = self.colorButtons[i];
        button.layer.borderColor = (i == index) ? [UIColor whiteColor].CGColor : [UIColor clearColor].CGColor;
    }
    self.canvas.currentColor = self.colorButtons[index].backgroundColor;
}

- (void)pxToolTapped:(UIButton *)sender {
    [self pxSelectToolIndex:(NSUInteger)sender.tag];
}

- (void)pxColorTapped:(UIButton *)sender {
    [self pxSelectColorIndex:(NSUInteger)sender.tag];
}

- (void)pxWidthChanged:(UISlider *)slider {
    self.canvas.currentLineWidth = slider.value;
}

- (void)pxUndoTapped:(UIButton *)sender {
    [self.canvas undo];
    [self pxRefreshUndoButtons];
}

- (void)pxRedoTapped:(UIButton *)sender {
    [self.canvas redo];
    [self pxRefreshUndoButtons];
}

- (void)pxRefreshUndoButtons {
    self.undoButton.enabled = self.canvas.canUndo;
    self.redoButton.enabled = self.canvas.canRedo;
    self.undoButton.alpha = self.canvas.canUndo ? 1.0 : 0.4;
    self.redoButton.alpha = self.canvas.canRedo ? 1.0 : 0.4;
}

- (void)pxCloseTapped:(UIButton *)sender {
    if (self.isExporting) return;
    if (self.delegate && [self.delegate respondsToSelector:@selector(editorControllerDidCancel:)]) {
        [self.delegate editorControllerDidCancel:self];
    }
}

- (void)pxDoneTapped:(UIButton *)sender {
    if (self.isExporting) return;
    self.isExporting = YES;
    self.doneButton.enabled = NO;
    self.doneButton.alpha = 0.4;
    // 导出期间禁止继续绘制与撤销/重做：渲染快照已复制，避免画布显示与导出图背离。
    self.canvas.userInteractionEnabled = NO;
    self.undoButton.enabled = NO;
    self.redoButton.enabled = NO;

    __weak typeof(self) weakSelf = self;
    [PXEditorRenderer renderDocument:self.document completion:^(UIImage *result) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.isExporting = NO;
        strongSelf.doneButton.enabled = YES;
        strongSelf.doneButton.alpha = 1.0;
        strongSelf.canvas.userInteractionEnabled = YES;
        [strongSelf pxRefreshUndoButtons];
        if (!result) {
            PXLogError(@"editor export failed");
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"导出失败"
                                                                           message:@"请重试或取消编辑"
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
            [strongSelf presentViewController:alert animated:YES completion:nil];
            return;
        }
        if (strongSelf.delegate && [strongSelf.delegate respondsToSelector:@selector(editorController:didFinishWithImage:)]) {
            [strongSelf.delegate editorController:strongSelf didFinishWithImage:result];
        }
    }];
}

#pragma mark - PXEditorCanvasDelegate

- (void)canvasDidChangeContent:(PXEditorCanvas *)canvas {
    [self pxRefreshUndoButtons];
}

- (void)canvas:(PXEditorCanvas *)canvas didRequestTextInputAtViewPoint:(CGPoint)viewPoint {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"添加文字"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"输入文字";
    }];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"添加" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        UITextField *field = alert.textFields.firstObject;
        [strongSelf.canvas addTextAnnotationWithText:field.text atViewPoint:viewPoint];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)dealloc {
    [self.canvas prepareForDismissal];
}

@end
