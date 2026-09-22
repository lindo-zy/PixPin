#import "PXEditorCanvas.h"
#import "PXEditorRenderer.h"
#import "PXUndoManager.h"
#import "../Common/PXLog.h"

// 马赛克预览底图密度：按屏幕密度生成（导出走源图全密度），整图一份常驻。
static const CGFloat PXPixelatedMinScale = 1.0;

static CGPoint CGPointAdd(CGPoint a, CGPoint b) {
    return CGPointMake(a.x + b.x, a.y + b.y);
}

typedef NS_ENUM(NSInteger, PXCanvasInteraction) {
    PXCanvasInteractionIdle = 0,
    PXCanvasInteractionDrawing,
    PXCanvasInteractionMovingSelection,
    PXCanvasInteractionDraggingCrop,
};

typedef NS_ENUM(NSInteger, PXCropHandle) {
    PXCropHandleNone = 0,
    PXCropHandleTopLeft,
    PXCropHandleTopRight,
    PXCropHandleBottomLeft,
    PXCropHandleBottomRight,
    PXCropHandleTopEdge,
    PXCropHandleBottomEdge,
    PXCropHandleLeftEdge,
    PXCropHandleRightEdge,
    PXCropHandleInterior,
};

@interface PXEditorCanvas () <UIGestureRecognizerDelegate, UITextViewDelegate>
@property (nonatomic, strong, readwrite) PXEditorDocument *document;
@property (nonatomic, strong) PXUndoManager *pxUndoManager;
@property (nonatomic, strong, readwrite, nullable) PXAnnotation *selectedAnnotation;
@property (nonatomic, assign, readwrite) BOOL cropActive;
@property (nonatomic, assign, readwrite) BOOL textEditing;
@property (nonatomic, strong, nullable) PXAnnotation *activeAnnotation;
@property (nonatomic, strong, nullable) UIImage *pixelatedImage;
@property (nonatomic, assign) BOOL pixelatedGenerating;
@property (nonatomic, strong) NSMutableDictionary<NSString *, id> *gestureAnchor;   // 交互临时状态
@property (nonatomic, strong, nullable) PXAnnotation *transformBaseline;                   // 变换手势起始快照
@property (nonatomic, assign) CGFloat pinchLastScale;
@property (nonatomic, assign) CGFloat rotationLastAngle;
@property (nonatomic, assign) PXCropHandle cropHandle;
@property (nonatomic, assign) CGRect cropRect;
@property (nonatomic, assign) CGRect cropRectBaseline;
@property (nonatomic, strong, nullable) UITextView *activeTextView;
// 裁剪/旋转烘焙前的文档快照（撤销用）。
@property (nonatomic, strong, nullable) UIImage *docBaselineImage;
@property (nonatomic, strong, nullable) NSArray<PXAnnotation *> *docBaselineAnnotations;
@end

@implementation PXEditorCanvas

- (instancetype)initWithFrame:(CGRect)frame document:(PXEditorDocument *)document {
    if (self = [super initWithFrame:frame]) {
        NSParameterAssert(document);
        _document = document;
        _pxUndoManager = [[PXUndoManager alloc] init];
        _gestureAnchor = [[NSMutableDictionary alloc] init];
        _currentTool = PXAnnotationTypeBrush;
        _currentColor = [UIColor redColor];
        _currentLineWidth = 8.0;
        _currentFillStyle = PXAnnotationFillStyleHollow;
        _currentTextFontSize = [self pxDefaultTextFontSize];
        self.backgroundColor = [UIColor clearColor];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self
                                                                              action:@selector(pxHandlePan:)];
        pan.maximumNumberOfTouches = 1;
        pan.delegate = self;
        [self addGestureRecognizer:pan];

        UIPinchGestureRecognizer *pinch = [[UIPinchGestureRecognizer alloc] initWithTarget:self
                                                                                    action:@selector(pxHandlePinch:)];
        pinch.delegate = self;
        [self addGestureRecognizer:pinch];

        UIRotationGestureRecognizer *rotation = [[UIRotationGestureRecognizer alloc] initWithTarget:self
                                                                                             action:@selector(pxHandleRotation:)];
        rotation.delegate = self;
        [self addGestureRecognizer:rotation];

        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                              action:@selector(pxHandleTap:)];
        tap.delegate = self;
        [self addGestureRecognizer:tap];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(pxKeyboardFrameChanged:)
                                                     name:UIKeyboardWillChangeFrameNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [self prepareForDismissal];
}

#pragma mark - 尺寸辅助

- (CGFloat)pxShortSide {
    return MIN(self.bounds.size.width, self.bounds.size.height);
}

- (CGFloat)pxHitSlop {
    return MAX(18.0, [self pxShortSide] / 40.0);
}

- (CGFloat)pxDefaultTextFontSize {
    return MAX(18.0, MIN(120.0, [self pxShortSide] / 22.0));
}

- (CGFloat)pxSelectionUnit {
    return MAX(3.0, [self pxShortSide] / 200.0);
}

- (CGFloat)pxMosaicBlockSize {
    return MAX(10.0, MIN(40.0, [self pxShortSide] / 40.0));
}

#pragma mark - 工具切换

- (void)setCurrentTool:(PXAnnotationType)currentTool {
    if (_currentTool == currentTool) return;
    if (self.cropActive) {
        [self cancelCrop];
    }
    [self commitActiveText];
    _currentTool = currentTool;
    [self pxSetSelectedAnnotation:nil];
    [self setNeedsDisplay];
}

#pragma mark - 绘制

- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return;

    if (self.cropActive) {
        [self pxDirectDrawCropOverlayInContext:ctx];
        return;
    }

    for (PXAnnotation *annotation in self.document.annotations) {
        [PXEditorRenderer drawAnnotation:annotation
                               inContext:ctx
                             sourceImage:self.document.sourceImage
                          pixelatedImage:self.pixelatedImage];
    }
    if (self.activeAnnotation) {
        [PXEditorRenderer drawAnnotation:self.activeAnnotation
                               inContext:ctx
                             sourceImage:self.document.sourceImage
                          pixelatedImage:self.pixelatedImage];
    }
    if (self.selectedAnnotation) {
        [self pxDirectDrawSelectionChromeFor:self.selectedAnnotation inContext:ctx];
    }

    if (!self.pixelatedImage && !self.pixelatedGenerating && [self pxDocumentHasMosaic]) {
        [self requestPixelatedPreview];
    }
}

- (BOOL)pxDocumentHasMosaic {
    for (PXAnnotation *annotation in self.document.annotations) {
        if (annotation.type == PXAnnotationTypeMosaic) return YES;
    }
    return NO;
}

- (void)pxDirectDrawSelectionChromeFor:(PXAnnotation *)annotation inContext:(CGContextRef)ctx {
    CGRect bounds = CGRectInset(annotation.boundsInImageSpace, -[self pxSelectionUnit] * 2.0,
                                [self pxSelectionUnit] * 2.0);
    bounds = CGRectMake(bounds.origin.x, bounds.origin.y,
                        MAX(bounds.size.width, [self pxSelectionUnit] * 8),
                        MAX(bounds.size.height, [self pxSelectionUnit] * 8));

    CGContextSetStrokeColorWithColor(ctx, [UIColor whiteColor].CGColor);
    CGContextSetLineWidth(ctx, [self pxSelectionUnit] * 0.6);
    CGFloat dash = [self pxSelectionUnit] * 2.0;
    CGContextSetLineDash(ctx, 0, (const CGFloat[]){dash, dash}, 2);
    CGContextStrokeRect(ctx, bounds);
    CGContextSetLineDash(ctx, 0, NULL, 0);

    CGFloat r = [self pxSelectionUnit] * 1.6;
    CGPoint corners[4] = {
        CGPointMake(CGRectGetMinX(bounds), CGRectGetMinY(bounds)),
        CGPointMake(CGRectGetMaxX(bounds), CGRectGetMinY(bounds)),
        CGPointMake(CGRectGetMinX(bounds), CGRectGetMaxY(bounds)),
        CGPointMake(CGRectGetMaxX(bounds), CGRectGetMaxY(bounds)),
    };
    for (NSUInteger i = 0; i < 4; i++) {
        CGRect dot = CGRectMake(corners[i].x - r, corners[i].y - r, r * 2, r * 2);
        CGContextSetFillColorWithColor(ctx, [UIColor colorWithWhite:0.1 alpha:0.9].CGColor);
        CGContextFillEllipseInRect(ctx, CGRectInset(dot, -r * 0.35, -r * 0.35));
        CGContextSetFillColorWithColor(ctx, [UIColor whiteColor].CGColor);
        CGContextFillEllipseInRect(ctx, dot);
    }
}

#pragma mark - 裁剪模式

- (void)beginCrop {
    if (self.cropActive) return;
    [self commitActiveText];
    [self pxSetSelectedAnnotation:nil];
    CGFloat inset = [self pxShortSide] * 0.04;
    self.cropRect = CGRectInset(CGRectMake(0, 0, self.bounds.size.width, self.bounds.size.height),
                                inset, inset);
    self.cropActive = YES;
    [self setNeedsDisplay];
}

- (void)cancelCrop {
    if (!self.cropActive) return;
    self.cropActive = NO;
    self.cropHandle = PXCropHandleNone;
    [self setNeedsDisplay];
}

- (BOOL)applyCrop {
    if (!self.cropActive) return NO;
    CGRect cropRect = [self pxSanitizedCropRect];
    UIImage *cropped = [PXEditorRenderer cropImage:self.document.sourceImage toRect:cropRect];
    if (!cropped) {
        PXLogWarn(@"editor crop failed: source unavailable");
        return NO;
    }
    NSArray<PXAnnotation *> *remapped = [PXEditorRenderer annotationsByApplyingCrop:cropRect
                                                                       toAnnotations:self.document.annotations];

    UIImage *oldImage = self.document.sourceImage;
    NSArray<PXAnnotation *> *oldAnnotations = self.document.annotations;
    [self.document replaceContentWithImage:cropped annotations:remapped];

    __weak typeof(self) weakSelf = self;
    [self.pxUndoManager pushUndoBlock:^{
        [weakSelf pxRestoreDocumentImage:oldImage annotations:oldAnnotations];
    } redoBlock:^{
        [weakSelf pxRestoreDocumentImage:cropped annotations:remapped];
    } pinsImage:YES];

    self.cropActive = NO;
    self.cropHandle = PXCropHandleNone;
    self.pixelatedImage = nil;
    self.pixelatedGenerating = NO;
    [self setNeedsDisplay];
    [self pxNotifyContentChanged];
    [self.delegate canvasDidChangeGeometry:self];
    [self requestPixelatedPreview];
    return YES;
}

- (void)pxRestoreDocumentImage:(UIImage *)image annotations:(NSArray<PXAnnotation *> *)annotations {
    [self.document replaceContentWithImage:image annotations:[annotations copy]];
    [self pxSetSelectedAnnotation:nil];
    self.pixelatedImage = nil;
    self.pixelatedGenerating = NO;
    [self setNeedsDisplay];
    [self pxNotifyContentChanged];
    [self.delegate canvasDidChangeGeometry:self];
    [self requestPixelatedPreview];
}

- (CGRect)pxSanitizedCropRect {
    CGRect bounds = CGRectMake(0, 0, self.bounds.size.width, self.bounds.size.height);
    CGRect rect = CGRectIntersection(self.cropRect, bounds);
    if (CGRectIsEmpty(rect)) {
        rect = bounds;
    }
    return rect;
}

- (PXCropHandle)pxCropHandleAtPoint:(CGPoint)point {
    CGFloat hit = MAX(24.0, [self pxShortSide] * 0.06);
    CGRect rect = self.cropRect;

    BOOL nearLeft = fabs(point.x - CGRectGetMinX(rect)) <= hit;
    BOOL nearRight = fabs(point.x - CGRectGetMaxX(rect)) <= hit;
    BOOL nearTop = fabs(point.y - CGRectGetMinY(rect)) <= hit;
    BOOL nearBottom = fabs(point.y - CGRectGetMaxY(rect)) <= hit;

    if (nearLeft && nearTop) return PXCropHandleTopLeft;
    if (nearRight && nearTop) return PXCropHandleTopRight;
    if (nearLeft && nearBottom) return PXCropHandleBottomLeft;
    if (nearRight && nearBottom) return PXCropHandleBottomRight;
    if (nearTop && CGRectContainsPoint(CGRectInset(rect, -hit, -hit), point)) return PXCropHandleTopEdge;
    if (nearBottom && CGRectContainsPoint(CGRectInset(rect, -hit, -hit), point)) return PXCropHandleBottomEdge;
    if (nearLeft) return PXCropHandleLeftEdge;
    if (nearRight) return PXCropHandleRightEdge;
    if (CGRectContainsPoint(rect, point)) return PXCropHandleInterior;
    return PXCropHandleNone;
}

- (void)pxDirectDrawCropOverlayInContext:(CGContextRef)ctx {
    CGRect rect = [self pxSanitizedCropRect];
    CGFloat unit = [self pxSelectionUnit];

    CGMutablePathRef path = CGPathCreateMutable();
    CGPathAddRect(path, NULL, CGRectInfinite);
    CGPathAddRect(path, NULL, rect);
    CGContextSetFillColorWithColor(ctx, [UIColor blackColor].CGColor);
    CGContextSetAlpha(ctx, 0.55);
    CGContextAddPath(ctx, path);
    CGContextEOFillPath(ctx);
    CGPathRelease(path);
    CGContextSetAlpha(ctx, 1.0);

    CGContextSetStrokeColorWithColor(ctx, [UIColor whiteColor].CGColor);
    CGContextSetLineWidth(ctx, unit * 0.6);
    CGContextStrokeRect(ctx, rect);

    // 三分线
    CGContextSetAlpha(ctx, 0.45);
    CGContextSetLineWidth(ctx, unit * 0.35);
    for (NSUInteger i = 1; i < 3; i++) {
        CGFloat fx = CGRectGetMinX(rect) + rect.size.width * i / 3.0;
        CGFloat fy = CGRectGetMinY(rect) + rect.size.height * i / 3.0;
        CGContextMoveToPoint(ctx, fx, CGRectGetMinY(rect));
        CGContextAddLineToPoint(ctx, fx, CGRectGetMaxY(rect));
        CGContextMoveToPoint(ctx, CGRectGetMinX(rect), fy);
        CGContextAddLineToPoint(ctx, CGRectGetMaxX(rect), fy);
    }
    CGContextStrokePath(ctx);
    CGContextSetAlpha(ctx, 1.0);

    // 角部 L 手柄
    CGFloat arm = MAX(20.0, [self pxShortSide] * 0.05);
    CGFloat handleWidth = unit * 1.4;
    CGContextSetLineWidth(ctx, handleWidth);
    CGPoint cornerPairs[8][2] = {
        { CGPointMake(CGRectGetMinX(rect), CGRectGetMinY(rect) + arm), CGPointMake(CGRectGetMinX(rect), CGRectGetMinY(rect)) },
        { CGPointMake(CGRectGetMinX(rect), CGRectGetMinY(rect)), CGPointMake(CGRectGetMinX(rect) + arm, CGRectGetMinY(rect)) },
        { CGPointMake(CGRectGetMaxX(rect) - arm, CGRectGetMinY(rect)), CGPointMake(CGRectGetMaxX(rect), CGRectGetMinY(rect)) },
        { CGPointMake(CGRectGetMaxX(rect), CGRectGetMinY(rect)), CGPointMake(CGRectGetMaxX(rect), CGRectGetMinY(rect) + arm) },
        { CGPointMake(CGRectGetMinX(rect), CGRectGetMaxY(rect) - arm), CGPointMake(CGRectGetMinX(rect), CGRectGetMaxY(rect)) },
        { CGPointMake(CGRectGetMinX(rect), CGRectGetMaxY(rect)), CGPointMake(CGRectGetMinX(rect) + arm, CGRectGetMaxY(rect)) },
        { CGPointMake(CGRectGetMaxX(rect) - arm, CGRectGetMaxY(rect)), CGPointMake(CGRectGetMaxX(rect), CGRectGetMaxY(rect)) },
        { CGPointMake(CGRectGetMaxX(rect), CGRectGetMaxY(rect)), CGPointMake(CGRectGetMaxX(rect), CGRectGetMaxY(rect) - arm) },
    };
    for (NSUInteger i = 0; i < 8; i++) {
        CGContextMoveToPoint(ctx, cornerPairs[i][0].x, cornerPairs[i][0].y);
        CGContextAddLineToPoint(ctx, cornerPairs[i][1].x, cornerPairs[i][1].y);
    }
    CGContextStrokePath(ctx);
}

#pragma mark - 手势路由

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if ([gestureRecognizer isKindOfClass:[UITapGestureRecognizer class]]) {
        if (self.cropActive) return NO;
        // 点击落在文字输入框内时让 UITextView 自己处理（光标定位），框外则提交文字。
        if (self.textEditing && self.activeTextView) {
            CGPoint point = [gestureRecognizer locationInView:self];
            return !CGRectContainsPoint(self.activeTextView.frame, point);
        }
        return YES;
    }
    if ([gestureRecognizer isKindOfClass:[UIPanGestureRecognizer class]]) {
        if (self.textEditing) return NO;
        if (self.cropActive) return YES;
        if (self.currentTool == PXAnnotationTypePan) return NO;
        return YES;
    }
    if ([gestureRecognizer isKindOfClass:[UIPinchGestureRecognizer class]]) {
        return !self.cropActive && !self.textEditing && self.selectedAnnotation != nil;
    }
    if ([gestureRecognizer isKindOfClass:[UIRotationGestureRecognizer class]]) {
        return !self.cropActive && !self.textEditing &&
               self.selectedAnnotation.type == PXAnnotationTypeSticker;
    }
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
    shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    // 画布内部手势（拖动选中标注 + 捏合缩放 + 贴纸旋转）允许同时进行；
    // 与滚动容器的平移/缩放互斥，避免操纵标注时画面漂移。
    if (gestureRecognizer.view == self && otherGestureRecognizer.view == self) {
        return (self.selectedAnnotation != nil && !self.cropActive);
    }
    return NO;
}

- (nullable PXAnnotation *)pxTopmostAnnotationAtPoint:(CGPoint)point {
    NSArray<PXAnnotation *> *annotations = self.document.annotations;
    CGFloat slop = [self pxHitSlop];
    for (NSUInteger i = annotations.count; i > 0; i--) {
        PXAnnotation *annotation = annotations[i - 1];
        if ([annotation containsImagePoint:point slop:slop]) {
            return annotation;
        }
    }
    return nil;
}

- (void)pxHandlePan:(UIPanGestureRecognizer *)gesture {
    CGPoint point = [gesture locationInView:self];

    switch (gesture.state) {
        case UIGestureRecognizerStateBegan: {
            [self pxPanBeganAtPoint:point gesture:gesture];
            break;
        }
        case UIGestureRecognizerStateChanged: {
            [self pxPanChangedAtPoint:point];
            break;
        }
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled: {
            [self pxPanEnded];
            break;
        }
        default:
            break;
    }
}

- (void)pxPanBeganAtPoint:(CGPoint)point gesture:(UIPanGestureRecognizer *)gesture {
    if (self.cropActive) {
        PXCropHandle handle = [self pxCropHandleAtPoint:point];
        if (handle == PXCropHandleNone) return;
        self.cropHandle = handle;
        self.cropRectBaseline = self.cropRect;
        self.gestureAnchor[@"start"] = [NSValue valueWithCGPoint:point];
        [self pxSetInteraction:PXCanvasInteractionDraggingCrop];
        return;
    }

    if (self.selectedAnnotation &&
        [self.selectedAnnotation containsImagePoint:point slop:[self pxHitSlop]]) {
        self.transformBaseline = [self.selectedAnnotation copy];
        self.gestureAnchor[@"start"] = [NSValue valueWithCGPoint:point];
        self.gestureAnchor[@"last"] = [NSValue valueWithCGPoint:point];
        [self pxSetInteraction:PXCanvasInteractionMovingSelection];
        return;
    }

    if (self.currentTool == PXAnnotationTypePan || self.currentTool == PXAnnotationTypeText) {
        return;
    }

    [self pxBeginAnnotationAtPoint:point];
}

- (void)pxPanChangedAtPoint:(CGPoint)point {
    switch ([self pxInteraction]) {
        case PXCanvasInteractionDraggingCrop: {
            NSValue *startValue = self.gestureAnchor[@"start"];
            if (!startValue) return;
            [self pxCropDragFrom:[startValue CGPointValue] to:point];
            break;
        }
        case PXCanvasInteractionMovingSelection: {
            NSValue *lastValue = self.gestureAnchor[@"last"];
            if (!self.selectedAnnotation || !lastValue) return;
            // 增量平移：避免抓取瞬间把标注中心吸附到手指造成跳变。
            CGPoint last = [lastValue CGPointValue];
            CGPoint delta = CGPointMake(point.x - last.x, point.y - last.y);
            if (fabs(delta.x) < 0.5 && fabs(delta.y) < 0.5) return;
            [self.selectedAnnotation translateToCenter:
                CGPointAdd(self.selectedAnnotation.centerInImageSpace, delta)];
            self.gestureAnchor[@"last"] = [NSValue valueWithCGPoint:point];
            [self pxClampAnnotationIntoCanvas:self.selectedAnnotation];
            [self setNeedsDisplay];
            break;
        }
        case PXCanvasInteractionDrawing: {
            [self pxUpdateAnnotationAtPoint:point];
            break;
        }
        default:
            break;
    }
}

- (void)pxPanEnded {
    switch ([self pxInteraction]) {
        case PXCanvasInteractionDraggingCrop: {
            // 裁剪框拖动不单独入撤销栈（应用时整体快照）。
            break;
        }
        case PXCanvasInteractionMovingSelection: {
            [self pxPushTransformUndoIfChanged];
            [self pxNotifyContentChanged];
            break;
        }
        case PXCanvasInteractionDrawing: {
            [self pxCommitActiveAnnotation];
            break;
        }
        default:
            break;
    }
    [self pxSetInteraction:PXCanvasInteractionIdle];
    [self.gestureAnchor removeAllObjects];
    self.transformBaseline = nil;
}

- (PXCanvasInteraction)pxInteraction {
    NSNumber *value = self.gestureAnchor[@"mode"];
    return value ? (PXCanvasInteraction)value.integerValue : PXCanvasInteractionIdle;
}

- (void)pxSetInteraction:(PXCanvasInteraction)mode {
    self.gestureAnchor[@"mode"] = @(mode);
}

#pragma mark - 绘制标注

- (void)pxBeginAnnotationAtPoint:(CGPoint)point {
    PXAnnotationType tool = self.currentTool;
    CGSize imageSize = self.document.sourceImage.size;
    if (imageSize.width <= 0 || imageSize.height <= 0) return;
    point = CGPointMake(MAX(0, MIN(point.x, imageSize.width)),
                        MAX(0, MIN(point.y, imageSize.height)));

    PXAnnotation *annotation = [[PXAnnotation alloc] initWithType:tool
                                                            color:self.currentColor
                                                        lineWidth:self.currentLineWidth
                                                            alpha:1.0];
    annotation.fillStyle = self.currentFillStyle;
    switch (tool) {
        case PXAnnotationTypeBrush:
        case PXAnnotationTypeHighlight:
        case PXAnnotationTypeLine:
        case PXAnnotationTypeArrow:
            [annotation.points addObject:[NSValue valueWithCGPoint:point]];
            break;
        default:
            annotation.rect = CGRectMake(point.x, point.y, 0, 0);
            break;
    }
    self.activeAnnotation = annotation;
    self.gestureAnchor[@"anchor"] = [NSValue valueWithCGPoint:point];
    [self pxSetInteraction:PXCanvasInteractionDrawing];
    [self setNeedsDisplay];
}

- (void)pxUpdateAnnotationAtPoint:(CGPoint)point {
    PXAnnotation *annotation = self.activeAnnotation;
    if (!annotation) return;
    CGSize imageSize = self.document.sourceImage.size;
    point = CGPointMake(MAX(0, MIN(point.x, imageSize.width)),
                        MAX(0, MIN(point.y, imageSize.height)));

    switch (annotation.type) {
        case PXAnnotationTypeBrush:
        case PXAnnotationTypeHighlight: {
            NSUInteger count = annotation.points.count;
            if (count == 0 ||
                !CGPointEqualToPoint([annotation.points[count - 1] CGPointValue], point)) {
                [annotation.points addObject:[NSValue valueWithCGPoint:point]];
            }
            break;
        }
        case PXAnnotationTypeLine:
        case PXAnnotationTypeArrow: {
            CGPoint start = [annotation.points.firstObject CGPointValue];
            annotation.points = [NSMutableArray arrayWithObjects:
                                 [NSValue valueWithCGPoint:start],
                                 [NSValue valueWithCGPoint:point], nil];
            break;
        }
        default: {
            NSValue *anchorValue = self.gestureAnchor[@"anchor"];
            if (!anchorValue) return;
            CGPoint anchor = [anchorValue CGPointValue];
            annotation.rect = CGRectMake(MIN(anchor.x, point.x), MIN(anchor.y, point.y),
                                         fabs(point.x - anchor.x), fabs(point.y - anchor.y));
            break;
        }
    }
    [self setNeedsDisplay];
}

- (void)pxCommitActiveAnnotation {
    PXAnnotation *annotation = self.activeAnnotation;
    self.activeAnnotation = nil;
    if (!annotation) return;

    BOOL hasContent = NO;
    switch (annotation.type) {
        case PXAnnotationTypeBrush:
        case PXAnnotationTypeHighlight:
        case PXAnnotationTypeLine:
        case PXAnnotationTypeArrow:
            hasContent = (annotation.points.count >= 2) || (annotation.points.count == 1 && annotation.type == PXAnnotationTypeBrush);
            break;
        default:
            hasContent = (annotation.rect.size.width >= 6 && annotation.rect.size.height >= 6);
            break;
    }
    if (!hasContent) {
        [self setNeedsDisplay];
        return;   // 过小的误触不进入文档
    }

    [self pxAddAnnotationWithUndo:annotation];
    [self setNeedsDisplay];
    [self pxNotifyContentChanged];
}

/// 统一入口：加入文档 + 入撤销栈 + 刷新。
- (void)pxAddAnnotationWithUndo:(PXAnnotation *)annotation {
    [self.document addAnnotation:annotation];
    NSString *annotationID = annotation.annotationID;
    NSUInteger addedIndex = [self.document indexOfAnnotationWithID:annotationID];
    PXAnnotation *copyForRedo = [annotation copy];
    __weak typeof(self) weakSelf = self;
    [self.pxUndoManager pushUndoBlock:^{
        [weakSelf pxRemoveAnnotationByID:annotationID];
    } redoBlock:^{
        [weakSelf pxReinsertAnnotation:copyForRedo atIndex:addedIndex];
    }];
}

- (void)pxRemoveAnnotationByID:(NSString *)annotationID {
    NSUInteger index = [self.document indexOfAnnotationWithID:annotationID];
    if (index == NSNotFound) return;
    [self.document removeAnnotationWithID:annotationID];
    if ([self.selectedAnnotation.annotationID isEqualToString:annotationID]) {
        [self pxSetSelectedAnnotation:nil];
    }
    [self setNeedsDisplay];
    [self pxNotifyContentChanged];
}

- (void)pxReinsertAnnotation:(PXAnnotation *)annotation atIndex:(NSUInteger)index {
    if (!annotation) return;
    NSUInteger existing = [self.document indexOfAnnotationWithID:annotation.annotationID];
    if (existing != NSNotFound) {
        [self.document removeAnnotationWithID:annotation.annotationID];
    }
    [self.document insertAnnotation:annotation atIndex:MIN(index, self.document.annotations.count)];
    [self setNeedsDisplay];
    [self pxNotifyContentChanged];
}

#pragma mark - 选中与变换

- (void)pxSetSelectedAnnotation:(nullable PXAnnotation *)annotation {
    if (_selectedAnnotation == annotation) return;
    _selectedAnnotation = annotation;
    [self setNeedsDisplay];
    if (self.delegate && [self.delegate respondsToSelector:@selector(canvasDidChangeSelection:)]) {
        [self.delegate canvasDidChangeSelection:self];
    }
}

- (void)pxHandleTap:(UITapGestureRecognizer *)gesture {
    if (self.cropActive) return;
    if (self.textEditing) {
        [self commitActiveText];
        return;
    }

    CGPoint point = [gesture locationInView:self];

    switch (self.currentTool) {
        case PXAnnotationTypeMagnifier:
            [self pxPlaceMagnifierAtPoint:point];
            return;
        case PXAnnotationTypeSticker:
            [self pxPlaceStickerAtPoint:point];
            return;
        case PXAnnotationTypeStamp:
            [self pxPlaceStampAtPoint:point];
            return;
        case PXAnnotationTypeText:
            [self beginTextInputAtPoint:point];
            return;
        default:
            break;
    }

    PXAnnotation *hit = [self pxTopmostAnnotationAtPoint:point];
    [self pxSetSelectedAnnotation:hit];
}

- (void)pxPlaceMagnifierAtPoint:(CGPoint)point {
    CGFloat radius = [self pxShortSide] * 0.08;
    PXAnnotation *annotation = [[PXAnnotation alloc] initWithType:PXAnnotationTypeMagnifier
                                                            color:self.currentColor
                                                        lineWidth:1.0
                                                            alpha:1.0];
    annotation.rect = CGRectMake(point.x - radius, point.y - radius, radius * 2, radius * 2);
    annotation.zoom = 2.5;
    [self pxAddAnnotationWithUndo:annotation];
    [self pxSetSelectedAnnotation:annotation];
    [self pxNotifyContentChanged];
}

- (void)pxPlaceStickerAtPoint:(CGPoint)point {
    NSString *emoji = self.currentStickerText ?: @"✅";
    CGFloat size = [self pxShortSide] * 0.12;
    PXAnnotation *annotation = [[PXAnnotation alloc] initWithType:PXAnnotationTypeSticker
                                                            color:self.currentColor
                                                        lineWidth:1.0
                                                            alpha:1.0];
    annotation.rect = CGRectMake(point.x - size / 2.0, point.y - size / 2.0, size, size);
    annotation.stickerText = emoji;
    annotation.fontSize = size;
    [self pxAddAnnotationWithUndo:annotation];
    [self pxSetSelectedAnnotation:annotation];
    [self pxNotifyContentChanged];
}

- (void)pxPlaceStampAtPoint:(CGPoint)point {
    CGFloat size = [self pxShortSide] * 0.075;
    PXAnnotation *annotation = [[PXAnnotation alloc] initWithType:PXAnnotationTypeStamp
                                                            color:self.currentColor
                                                        lineWidth:1.0
                                                            alpha:1.0];
    annotation.rect = CGRectMake(point.x - size / 2.0, point.y - size / 2.0, size, size);
    annotation.stampNumber = [self.document nextStampNumber];
    annotation.fontSize = size * 0.52;
    [self pxAddAnnotationWithUndo:annotation];
    [self pxSetSelectedAnnotation:annotation];
    [self pxNotifyContentChanged];
}

- (void)pxHandlePinch:(UIPinchGestureRecognizer *)gesture {
    PXAnnotation *selected = self.selectedAnnotation;
    if (!selected || self.cropActive || self.textEditing) return;

    switch (gesture.state) {
        case UIGestureRecognizerStateBegan:
            self.transformBaseline = [selected copy];
            self.pinchLastScale = 1.0;
            break;
        case UIGestureRecognizerStateChanged: {
            CGFloat delta = gesture.scale / MAX(self.pinchLastScale, 0.0001);
            if (delta > 0.9 && delta < 1.1) break;   // 抑制抖动
            [selected applyScale:delta];
            self.pinchLastScale = gesture.scale;
            [self setNeedsDisplay];
            break;
        }
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled: {
            [self pxPushTransformUndoIfChanged];
            [self pxNotifyContentChanged];
            self.transformBaseline = nil;
            break;
        }
        default:
            break;
    }
}

- (void)pxHandleRotation:(UIRotationGestureRecognizer *)gesture {
    PXAnnotation *selected = self.selectedAnnotation;
    if (!selected || self.cropActive || self.textEditing) return;

    switch (gesture.state) {
        case UIGestureRecognizerStateBegan:
            self.transformBaseline = [selected copy];
            self.rotationLastAngle = 0.0;
            break;
        case UIGestureRecognizerStateChanged: {
            CGFloat delta = gesture.rotation - self.rotationLastAngle;
            [selected applyRotation:delta];
            self.rotationLastAngle = gesture.rotation;
            [self setNeedsDisplay];
            break;
        }
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled: {
            [self pxPushTransformUndoIfChanged];
            [self pxNotifyContentChanged];
            self.transformBaseline = nil;
            break;
        }
        default:
            break;
    }
}

- (void)pxPushTransformUndoIfChanged {
    PXAnnotation *baseline = self.transformBaseline;
    PXAnnotation *current = self.selectedAnnotation;
    if (!baseline || !current) return;
    if ([self pxAnnotation:baseline equalToGeometryOf:current]) return;

    PXAnnotation *before = [baseline copy];
    PXAnnotation *after = [current copy];
    NSString *annotationID = current.annotationID;
    __weak typeof(self) weakSelf = self;
    [self.pxUndoManager pushUndoBlock:^{
        [weakSelf pxReplaceAnnotationWithID:annotationID with:before];
    } redoBlock:^{
        [weakSelf pxReplaceAnnotationWithID:annotationID with:after];
    }];
}

- (BOOL)pxAnnotation:(PXAnnotation *)a equalToGeometryOf:(PXAnnotation *)b {
    return CGRectEqualToRect(a.rect, b.rect) &&
           a.points.count == b.points.count &&
           CGRectEqualToRect(a.boundsInImageSpace, b.boundsInImageSpace) &&
           fabs(a.rotation - b.rotation) < 0.001 &&
           fabs(a.fontSize - b.fontSize) < 0.01;
}

- (void)pxReplaceAnnotationWithID:(NSString *)annotationID with:(PXAnnotation *)replacement {
    NSUInteger index = [self.document indexOfAnnotationWithID:annotationID];
    if (index == NSNotFound || !replacement) return;
    PXAnnotation *copy = [replacement copy];
    [self.document removeAnnotationWithID:annotationID];
    [self.document insertAnnotation:copy atIndex:index];
    if ([self.selectedAnnotation.annotationID isEqualToString:annotationID]) {
        // 同一标注的几何替换：走统一 setter 触发选中回调（copy 指针不同必然生效）。
        [self pxSetSelectedAnnotation:copy];
    } else {
        [self setNeedsDisplay];
    }
    [self pxNotifyContentChanged];
}

- (void)pxClampAnnotationIntoCanvas:(PXAnnotation *)annotation {
    CGRect bounds = annotation.boundsInImageSpace;
    CGSize canvasSize = self.bounds.size;
    if (canvasSize.width <= 0 || canvasSize.height <= 0) return;
    CGFloat dx = 0;
    CGFloat dy = 0;
    if (bounds.size.width <= canvasSize.width) {
        if (CGRectGetMinX(bounds) < 0) dx = -CGRectGetMinX(bounds);
        else if (CGRectGetMaxX(bounds) > canvasSize.width) dx = canvasSize.width - CGRectGetMaxX(bounds);
    }
    if (bounds.size.height <= canvasSize.height) {
        if (CGRectGetMinY(bounds) < 0) dy = -CGRectGetMinY(bounds);
        else if (CGRectGetMaxY(bounds) > canvasSize.height) dy = canvasSize.height - CGRectGetMaxY(bounds);
    }
    if (fabs(dx) > 0.5 || fabs(dy) > 0.5) {
        [annotation translateToCenter:CGPointAdd(annotation.centerInImageSpace,
                                                 CGPointMake(dx, dy))];
    }
}

#pragma mark - 删除 / 置顶

- (void)deleteSelectedAnnotation {
    PXAnnotation *selected = self.selectedAnnotation;
    if (!selected) return;
    NSUInteger fromIndex = [self.document indexOfAnnotationWithID:selected.annotationID];
    if (fromIndex == NSNotFound) {
        [self pxSetSelectedAnnotation:nil];
        return;
    }
    PXAnnotation *removed = [selected copy];
    NSString *annotationID = removed.annotationID;
    [self.document removeAnnotationWithID:annotationID];
    [self pxSetSelectedAnnotation:nil];

    __weak typeof(self) weakSelf = self;
    [self.pxUndoManager pushUndoBlock:^{
        [weakSelf pxReinsertAnnotation:removed atIndex:fromIndex];
    } redoBlock:^{
        [weakSelf pxRemoveAnnotationByID:annotationID];
    }];
    [self setNeedsDisplay];
    [self pxNotifyContentChanged];
}

- (void)bringSelectedAnnotationToFront {
    PXAnnotation *selected = self.selectedAnnotation;
    if (!selected) return;
    NSString *annotationID = selected.annotationID;
    NSUInteger fromIndex = [self.document indexOfAnnotationWithID:annotationID];
    if (fromIndex == NSNotFound) return;
    NSUInteger toIndex = self.document.annotations.count - 1;
    if (fromIndex == toIndex) return;

    PXAnnotation *moved = [selected copy];
    [self.document removeAnnotationWithID:annotationID];
    [self.document insertAnnotation:moved atIndex:toIndex];

    __weak typeof(self) weakSelf = self;
    [self.pxUndoManager pushUndoBlock:^{
        [weakSelf pxMoveAnnotationWithID:annotationID toIndex:fromIndex];
    } redoBlock:^{
        [weakSelf pxMoveAnnotationWithID:annotationID toIndex:toIndex];
    }];
    [self pxSetSelectedAnnotation:moved];
    [self pxNotifyContentChanged];
}

- (void)pxMoveAnnotationWithID:(NSString *)annotationID toIndex:(NSUInteger)targetIndex {
    NSUInteger index = [self.document indexOfAnnotationWithID:annotationID];
    if (index == NSNotFound) return;
    PXAnnotation *annotation = self.document.annotations[index];
    [self.document removeAnnotationWithID:annotationID];
    NSUInteger clamped = MIN(targetIndex, self.document.annotations.count);
    [self.document insertAnnotation:annotation atIndex:clamped];
    annotation.zIndex = clamped;
    [self setNeedsDisplay];
    [self pxNotifyContentChanged];
}

#pragma mark - 撤销

- (BOOL)canUndo {
    return [self.pxUndoManager canUndo];
}

- (BOOL)canRedo {
    return [self.pxUndoManager canRedo];
}

- (void)undo {
    [self commitActiveText];
    [self.pxUndoManager undo];
    // 撤销后选中对象可能已不在文档里，做一致性清理。
    if (self.selectedAnnotation &&
        [self.document indexOfAnnotationWithID:self.selectedAnnotation.annotationID] == NSNotFound) {
        [self pxSetSelectedAnnotation:nil];
    } else {
        [self setNeedsDisplay];
    }
    [self pxNotifyContentChanged];
}

- (void)redo {
    [self commitActiveText];
    [self.pxUndoManager redo];
    if (self.selectedAnnotation &&
        [self.document indexOfAnnotationWithID:self.selectedAnnotation.annotationID] == NSNotFound) {
        [self pxSetSelectedAnnotation:nil];
    } else {
        [self setNeedsDisplay];
    }
    [self pxNotifyContentChanged];
}

- (void)pxNotifyContentChanged {
    // 马赛克清零后释放整图底图（约一份全屏位图），不留到会话结束。
    if (!self.pixelatedGenerating && self.pixelatedImage && ![self pxDocumentHasMosaic]) {
        self.pixelatedImage = nil;
    }
    if (self.delegate && [self.delegate respondsToSelector:@selector(canvasDidChangeContent:)]) {
        [self.delegate canvasDidChangeContent:self];
    }
}

#pragma mark - 文字输入

- (void)beginTextInputAtPoint:(CGPoint)point {
    [self commitActiveText];

    CGFloat width = MAX(140.0, MIN(self.bounds.size.width * 0.7, 600.0));
    CGFloat initialHeight = self.currentTextFontSize * 1.6;
    CGRect frame = CGRectMake(point.x - width / 2.0, point.y - initialHeight / 2.0, width, initialHeight);
    frame = CGRectIntersection(frame, CGRectMake(0, 0, self.bounds.size.width, self.bounds.size.height));
    if (CGRectIsEmpty(frame)) return;

    UITextView *textView = [[UITextView alloc] initWithFrame:frame];
    textView.font = [UIFont fontWithName:@"PingFangSC-Semibold" size:self.currentTextFontSize]
        ?: [UIFont boldSystemFontOfSize:self.currentTextFontSize];
    textView.textColor = self.currentColor;
    textView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.35];
    textView.layer.borderColor = [UIColor whiteColor].CGColor;
    textView.layer.borderWidth = 1.0;
    textView.autocorrectionType = UITextAutocorrectionTypeNo;
    textView.autocapitalizationType = UITextAutocapitalizationTypeNone;
    textView.keyboardDismissMode = UIScrollViewKeyboardDismissModeNone;
    textView.returnKeyType = UIReturnKeyDefault;
    textView.delegate = self;
    textView.inputAccessoryView = [self pxTextInputAccessoryBar];

    UITextPosition *begin = textView.beginningOfDocument;
    textView.selectedTextRange = [textView textRangeFromPosition:begin toPosition:begin];

    self.activeTextView = textView;
    [self addSubview:textView];
    self.textEditing = YES;
    if (self.delegate) {
        [self.delegate canvasDidStartTextInput:self];
        [self.delegate canvas:self didUpdateTextInputFrame:textView.frame];
    }
    if (![textView becomeFirstResponder]) {
        [self pxRetryEditorKeyboardWithAttempt:1 textView:textView];
    }
}

/// SpringBoard 下键盘偶发首次唤起失败（ShellX ss_retryEditorKeyboard 同款处理）：
/// 延迟重试最多 2 次；仍失败则通知调用方走弹窗输入兜底。
- (void)pxRetryEditorKeyboardWithAttempt:(NSInteger)attempt textView:(UITextView *)textView {
    if (attempt > 2 || textView != self.activeTextView) return;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || textView != strongSelf.activeTextView) return;
        if (textView.isFirstResponder) return;
        if (![textView becomeFirstResponder]) {
            if (attempt >= 2) {
                CGPoint pendingPoint = CGPointMake(CGRectGetMidX(textView.frame),
                                                   CGRectGetMidY(textView.frame));
                [strongSelf pxTeardownTextInput];
                if (strongSelf.delegate) {
                    [strongSelf.delegate canvasKeyboardUnavailable:strongSelf pendingTextPoint:pendingPoint];
                }
            } else {
                [strongSelf pxRetryEditorKeyboardWithAttempt:attempt + 1 textView:textView];
            }
        }
    });
}

- (UIView *)pxTextInputAccessoryBar {
    UIView *bar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, UIScreen.mainScreen.bounds.size.width, 44)];
    bar.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.98];
    bar.autoresizingMask = UIViewAutoresizingFlexibleWidth;

    UIButton *cancel = [UIButton buttonWithType:UIButtonTypeSystem];
    cancel.frame = CGRectMake(12, 0, 64, 44);
    [cancel setTitle:@"取消" forState:UIControlStateNormal];
    cancel.tintColor = [UIColor whiteColor];
    [cancel addTarget:self action:@selector(cancelActiveText) forControlEvents:UIControlEventTouchUpInside];
    [bar addSubview:cancel];

    UIButton *commit = [UIButton buttonWithType:UIButtonTypeSystem];
    commit.frame = CGRectMake(bar.bounds.size.width - 76, 0, 64, 44);
    commit.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [commit setTitle:@"完成" forState:UIControlStateNormal];
    commit.tintColor = [UIColor whiteColor];
    commit.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    [commit addTarget:self action:@selector(commitActiveText) forControlEvents:UIControlEventTouchUpInside];
    [bar addSubview:commit];

    return bar;
}

- (void)commitActiveText {
    UITextView *textView = self.activeTextView;
    if (!textView) return;
    NSString *content = [textView.text stringByTrimmingCharactersInSet:
                         [NSCharacterSet whitespaceAndNewlineCharacterSet]];

    CGRect frame = textView.frame;
    UIColor *color = textView.textColor ?: self.currentColor;
    CGFloat fontSize = self.currentTextFontSize;
    [self pxTeardownTextInput];

    if (content.length == 0) return;

    UIFont *font = [UIFont fontWithName:@"PingFangSC-Semibold" size:fontSize]
        ?: [UIFont boldSystemFontOfSize:fontSize];
    CGFloat maxWidth = MAX(80.0, MIN(frame.size.width, 900.0));

    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.lineBreakMode = NSLineBreakByWordWrapping;
    NSDictionary *measureAttributes = @{
        NSFontAttributeName: font,
        NSParagraphStyleAttributeName: style,
    };
    CGRect textBounds = [content boundingRectWithSize:CGSizeMake(maxWidth, CGFLOAT_MAX)
                                              options:NSStringDrawingUsesLineFragmentOrigin
                                           attributes:measureAttributes
                                              context:nil];

    PXAnnotation *annotation = [[PXAnnotation alloc] initWithType:PXAnnotationTypeText
                                                            color:color
                                                        lineWidth:1.0
                                                            alpha:1.0];
    annotation.rect = CGRectMake(frame.origin.x, frame.origin.y,
                                 ceil(textBounds.size.width) + 4, ceil(textBounds.size.height) + 4);
    annotation.text = [content copy];
    annotation.fontSize = fontSize;
    [self pxClampAnnotationIntoCanvas:annotation];
    CGRect clampedRect = annotation.rect;
    clampedRect.origin.x = MAX(0, clampedRect.origin.x);
    clampedRect.origin.y = MAX(0, clampedRect.origin.y);
    annotation.rect = clampedRect;

    [self pxAddAnnotationWithUndo:annotation];
    [self setNeedsDisplay];
    [self pxNotifyContentChanged];
}

- (void)cancelActiveText {
    if (!self.activeTextView) return;
    [self pxTeardownTextInput];
}

- (void)pxTeardownTextInput {
    UITextView *textView = self.activeTextView;
    self.activeTextView = nil;
    self.textEditing = NO;
    if (textView) {
        [textView resignFirstResponder];
        [textView removeFromSuperview];
    }
    if (self.delegate) {
        [self.delegate canvasDidEndTextInput:self];
    }
}

- (void)textViewDidEndEditing:(UITextView *)textView {
    if (textView == self.activeTextView) {
        [self commitActiveText];
    }
}

- (void)pxKeyboardFrameChanged:(NSNotification *)notification {
    if (!self.activeTextView) return;
    CGRect keyboardFrame = [notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    if (CGRectIsEmpty(keyboardFrame)) return;
    if (self.delegate) {
        [self.delegate canvas:self didUpdateTextInputFrame:self.activeTextView.frame];
    }
}

#pragma mark - 旋转 / 底图

- (BOOL)rotateImage90Clockwise {
    UIImage *rotated = [PXEditorRenderer rotateImage90Clockwise:self.document.sourceImage];
    if (!rotated) return NO;
    NSArray<PXAnnotation *> *remapped = [PXEditorRenderer annotationsByRotating90Clockwise:self.document.annotations
                                                                             sourceImageSize:self.document.sourceImage.size];

    UIImage *oldImage = self.document.sourceImage;
    NSArray<PXAnnotation *> *oldAnnotations = self.document.annotations;
    [self.document replaceContentWithImage:rotated annotations:remapped];

    __weak typeof(self) weakSelf = self;
    [self.pxUndoManager pushUndoBlock:^{
        [weakSelf pxRestoreDocumentImage:oldImage annotations:oldAnnotations];
    } redoBlock:^{
        [weakSelf pxRestoreDocumentImage:rotated annotations:remapped];
    } pinsImage:YES];

    [self pxSetSelectedAnnotation:nil];
    self.pixelatedImage = nil;
    self.pixelatedGenerating = NO;
    [self setNeedsDisplay];
    [self pxNotifyContentChanged];
    [self.delegate canvasDidChangeGeometry:self];
    [self requestPixelatedPreview];
    return YES;
}

- (void)requestPixelatedPreview {
    if (self.pixelatedGenerating || self.pixelatedImage) return;
    UIImage *source = self.document.sourceImage;
    if (!source.CGImage) return;

    self.pixelatedGenerating = YES;
    CGFloat blockSize = [self pxMosaicBlockSize];
    CGFloat screenScale = MAX(UIScreen.mainScreen.scale, PXPixelatedMinScale);
    CGFloat outputScale = MIN(MAX(source.scale, PXPixelatedMinScale), MAX(screenScale, PXPixelatedMinScale));
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        UIImage *pixelated = [PXEditorRenderer pixelatedImageForSourceImage:source
                                                                  blockSize:blockSize
                                                                outputScale:outputScale];
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            strongSelf.pixelatedGenerating = NO;
            // 生成期间底图可能已被裁剪/旋转换掉，仅当源图未变才采用。
            if (strongSelf.document.sourceImage == source) {
                strongSelf.pixelatedImage = pixelated;
                [strongSelf setNeedsDisplay];
            }
        });
    });
}

#pragma mark - 外部接线

- (void)placeTextAnnotationWithText:(NSString *)text atCanvasPoint:(CGPoint)point {
    if (text.length == 0) return;
    CGSize canvasSize = self.bounds.size;
    if (canvasSize.width <= 0 || canvasSize.height <= 0) return;

    UIFont *font = [UIFont fontWithName:@"PingFangSC-Semibold" size:self.currentTextFontSize]
        ?: [UIFont boldSystemFontOfSize:self.currentTextFontSize];
    NSDictionary *attributes = @{ NSFontAttributeName: font };
    CGRect textBounds = [text boundingRectWithSize:CGSizeMake(MAX(80.0, canvasSize.width * 0.7), CGFLOAT_MAX)
                                           options:NSStringDrawingUsesLineFragmentOrigin
                                        attributes:attributes
                                           context:nil];

    PXAnnotation *annotation = [[PXAnnotation alloc] initWithType:PXAnnotationTypeText
                                                            color:self.currentColor
                                                        lineWidth:1.0
                                                            alpha:1.0];
    annotation.rect = CGRectMake(point.x, point.y,
                                 ceil(textBounds.size.width) + 4, ceil(textBounds.size.height) + 4);
    annotation.text = [text copy];
    annotation.fontSize = self.currentTextFontSize;
    [self pxClampAnnotationIntoCanvas:annotation];
    CGRect clampedRect = annotation.rect;
    clampedRect.origin.x = MAX(0, clampedRect.origin.x);
    clampedRect.origin.y = MAX(0, clampedRect.origin.y);
    annotation.rect = clampedRect;

    [self pxAddAnnotationWithUndo:annotation];
    [self setNeedsDisplay];
    [self pxNotifyContentChanged];
}

- (void)requireTapToFail:(UIGestureRecognizer *)otherGesture {
    for (UIGestureRecognizer *gesture in self.gestureRecognizers) {
        if ([gesture isKindOfClass:[UITapGestureRecognizer class]]) {
            [gesture requireGestureRecognizerToFail:otherGesture];
        }
    }
}

- (void)prepareForDismissal {
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:UIKeyboardWillChangeFrameNotification
                                                  object:nil];
    if (self.activeTextView) {
        [self pxTeardownTextInput];
    }
    self.delegate = nil;
    self.activeAnnotation = nil;
    _selectedAnnotation = nil;
    self.transformBaseline = nil;
    [self.gestureAnchor removeAllObjects];
    self.pixelatedImage = nil;
    [self.pxUndoManager removeAllActions];
}

#pragma mark - 几何工具

// 拖动裁剪手柄。
- (void)pxCropDragFrom:(CGPoint)start to:(CGPoint)current {
    CGRect rect = self.cropRectBaseline;
    CGPoint delta = CGPointMake(current.x - start.x, current.y - start.y);
    CGFloat minSize = [self pxShortSide] * 0.1;
    CGRect bounds = CGRectMake(0, 0, self.bounds.size.width, self.bounds.size.height);

    switch (self.cropHandle) {
        case PXCropHandleInterior:
            rect = CGRectOffset(rect, delta.x, delta.y);
            break;
        case PXCropHandleTopLeft:
            rect = CGRectMake(MIN(CGRectGetMaxX(rect) - minSize, CGRectGetMinX(rect) + delta.x),
                              MIN(CGRectGetMaxY(rect) - minSize, CGRectGetMinY(rect) + delta.y),
                              CGRectGetMaxX(rect) - MIN(CGRectGetMaxX(rect) - minSize, CGRectGetMinX(rect) + delta.x),
                              CGRectGetMaxY(rect) - MIN(CGRectGetMaxY(rect) - minSize, CGRectGetMinY(rect) + delta.y));
            break;
        case PXCropHandleTopRight:
            rect = CGRectMake(CGRectGetMinX(rect),
                              MIN(CGRectGetMaxY(rect) - minSize, CGRectGetMinY(rect) + delta.y),
                              MAX(minSize, CGRectGetMaxX(rect) + delta.x - CGRectGetMinX(rect)),
                              CGRectGetMaxY(rect) - MIN(CGRectGetMaxY(rect) - minSize, CGRectGetMinY(rect) + delta.y));
            break;
        case PXCropHandleBottomLeft:
            rect = CGRectMake(MIN(CGRectGetMaxX(rect) - minSize, CGRectGetMinX(rect) + delta.x),
                              CGRectGetMinY(rect),
                              CGRectGetMaxX(rect) - MIN(CGRectGetMaxX(rect) - minSize, CGRectGetMinX(rect) + delta.x),
                              MAX(minSize, CGRectGetMaxY(rect) + delta.y - CGRectGetMinY(rect)));
            break;
        case PXCropHandleBottomRight:
            rect = CGRectMake(CGRectGetMinX(rect), CGRectGetMinY(rect),
                              MAX(minSize, CGRectGetMaxX(rect) + delta.x - CGRectGetMinX(rect)),
                              MAX(minSize, CGRectGetMaxY(rect) + delta.y - CGRectGetMinY(rect)));
            break;
        case PXCropHandleTopEdge:
            rect = CGRectMake(CGRectGetMinX(rect),
                              MIN(CGRectGetMaxY(rect) - minSize, CGRectGetMinY(rect) + delta.y),
                              rect.size.width,
                              CGRectGetMaxY(rect) - MIN(CGRectGetMaxY(rect) - minSize, CGRectGetMinY(rect) + delta.y));
            break;
        case PXCropHandleBottomEdge:
            rect = CGRectMake(CGRectGetMinX(rect), CGRectGetMinY(rect),
                              rect.size.width,
                              MAX(minSize, CGRectGetMaxY(rect) + delta.y - CGRectGetMinY(rect)));
            break;
        case PXCropHandleLeftEdge:
            rect = CGRectMake(MIN(CGRectGetMaxX(rect) - minSize, CGRectGetMinX(rect) + delta.x),
                              CGRectGetMinY(rect),
                              CGRectGetMaxX(rect) - MIN(CGRectGetMaxX(rect) - minSize, CGRectGetMinX(rect) + delta.x),
                              rect.size.height);
            break;
        case PXCropHandleRightEdge:
            rect = CGRectMake(CGRectGetMinX(rect), CGRectGetMinY(rect),
                              MAX(minSize, CGRectGetMaxX(rect) + delta.x - CGRectGetMinX(rect)),
                              rect.size.height);
            break;
        default:
            return;
    }
    self.cropRect = CGRectIntersection(rect, bounds);
    [self setNeedsDisplay];
}

@end
