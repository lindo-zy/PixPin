#import "PXEditorCanvas.h"
#import "PXEditorRenderer.h"
#import "PXUndoManager.h"

// 马赛克预览缓存条目：记录生成时的 rect，rect 变化即失效重生成（预览与导出一致）。
@interface PXCanvasMosaicEntry : NSObject
@property (nonatomic, strong) UIImage *image;
@property (nonatomic, assign) CGRect rect;
@end
@implementation PXCanvasMosaicEntry
@end

// 缓存按屏幕显示密度生成，单条约 1-3MB；上限 8 条防大面积多标注把 SpringBoard 顶到 jetsam。
static const NSUInteger PXMaxMosaicCacheEntries = 8;

@interface PXEditorCanvas () <UIGestureRecognizerDelegate>
@property (nonatomic, strong, readwrite) PXEditorDocument *document;
@property (nonatomic, strong) PXUndoManager *pxUndoManager;
@property (nonatomic, strong, nullable) PXAnnotation *activeAnnotation;
@property (nonatomic, strong) NSMutableDictionary<NSString *, PXCanvasMosaicEntry *> *mosaicCache;
@property (nonatomic, strong) NSMutableArray<NSString *> *mosaicCacheOrder;   // 插入序，淘汰最旧
@property (nonatomic, assign) CGRect fitRect;      // 源图在视图中的适配区域
@property (nonatomic, assign) CGFloat fitScale;    // 视图点 / 源图点
@property (nonatomic, strong) NSMutableDictionary<NSString *, id> *gestureState;
@end

@implementation PXEditorCanvas

- (instancetype)initWithFrame:(CGRect)frame document:(PXEditorDocument *)document {
    if (self = [super initWithFrame:frame]) {
        NSParameterAssert(document);
        _document = document;
        _pxUndoManager = [[PXUndoManager alloc] init];
        _mosaicCache = [[NSMutableDictionary alloc] init];
        _mosaicCacheOrder = [[NSMutableArray alloc] init];
        _gestureState = [[NSMutableDictionary alloc] init];
        _currentTool = PXAnnotationTypeBrush;
        _currentColor = [UIColor redColor];
        _currentLineWidth = 4.0;
        self.backgroundColor = [UIColor blackColor];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self
                                                                              action:@selector(pxHandlePan:)];
        pan.maximumNumberOfTouches = 1;
        [self addGestureRecognizer:pan];

        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                              action:@selector(pxHandleTap:)];
        [self addGestureRecognizer:tap];
    }
    return self;
}

- (void)dealloc {
    [self prepareForDismissal];
}

#pragma mark - 坐标变换

- (void)layoutSubviews {
    [super layoutSubviews];
    [self pxUpdateFitTransform];
    [self setNeedsDisplay];
}

- (void)pxUpdateFitTransform {
    CGSize imageSize = self.document.sourceImage.size;
    CGSize boundsSize = self.bounds.size;
    if (imageSize.width <= 0 || imageSize.height <= 0 || boundsSize.width <= 0 || boundsSize.height <= 0) {
        _fitRect = CGRectZero;
        _fitScale = 1.0;
        return;
    }
    CGFloat scale = MIN(boundsSize.width / imageSize.width, boundsSize.height / imageSize.height);
    CGSize fittedSize = CGSizeMake(imageSize.width * scale, imageSize.height * scale);
    _fitRect = CGRectMake((boundsSize.width - fittedSize.width) / 2,
                          (boundsSize.height - fittedSize.height) / 2,
                          fittedSize.width, fittedSize.height);
    _fitScale = scale;
}

- (CGPoint)pxImagePointFromViewPoint:(CGPoint)viewPoint {
    return CGPointMake((viewPoint.x - self.fitRect.origin.x) / self.fitScale,
                       (viewPoint.y - self.fitRect.origin.y) / self.fitScale);
}

- (CGRect)pxImageRectFromViewRect:(CGRect)viewRect {
    CGPoint topLeft = [self pxImagePointFromViewPoint:viewRect.origin];
    CGPoint bottomRight = [self pxImagePointFromViewPoint:CGPointMake(CGRectGetMaxX(viewRect), CGRectGetMaxY(viewRect))];
    return CGRectMake(MIN(topLeft.x, bottomRight.x), MIN(topLeft.y, bottomRight.y),
                      fabs(bottomRight.x - topLeft.x), fabs(bottomRight.y - topLeft.y));
}

#pragma mark - 绘制

- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return;
    UIImage *source = self.document.sourceImage;
    if (!source) return;

    [source drawInRect:self.fitRect];

    if (CGRectIsEmpty(self.fitRect)) return;

    CGContextSaveGState(ctx);
    CGContextTranslateCTM(ctx, self.fitRect.origin.x, self.fitRect.origin.y);
    CGContextScaleCTM(ctx, self.fitScale, self.fitScale);

    for (PXAnnotation *annotation in self.document.annotations) {
        [self pxDrawAnnotationWithCache:annotation inContext:ctx];
    }
    if (self.activeAnnotation) {
        [self pxDrawAnnotationWithCache:self.activeAnnotation inContext:ctx];
    }
    CGContextRestoreGState(ctx);
}

- (void)pxDrawAnnotationWithCache:(PXAnnotation *)annotation inContext:(CGContextRef)ctx {
    if (annotation.type == PXAnnotationTypeMosaic) {
        PXCanvasMosaicEntry *entry = self.mosaicCache[annotation.annotationID];
        if (entry && !CGRectEqualToRect(entry.rect, annotation.rect)) {
            entry = nil;   // rect 已变（拖拽中/undo 后重画），旧底图作废
        }
        if (!entry) {
            UIImage *mosaic = [PXEditorRenderer mosaicImageForSourceImage:self.document.sourceImage
                                                                     rect:annotation.rect
                                                               blockSize:24.0
                                                             outputScale:[self pxMosaicPreviewScale]];
            if (mosaic) {
                entry = [[PXCanvasMosaicEntry alloc] init];
                entry.image = mosaic;
                entry.rect = annotation.rect;
                self.mosaicCache[annotation.annotationID] = entry;
                [self pxTouchMosaicCacheOrderForID:annotation.annotationID];
            }
        }
        if (entry) {
            [PXEditorRenderer drawMosaicImage:entry.image rect:annotation.rect inContext:ctx];
        } else {
            CGContextSetFillColorWithColor(ctx, [UIColor colorWithWhite:0.7 alpha:0.6].CGColor);
            CGContextFillRect(ctx, annotation.rect);
        }
        return;
    }
    [PXEditorRenderer drawAnnotation:annotation inContext:ctx];
}

/// 预览底图密度：屏幕显示密度与源图密度取小（导出走全密度路径，预览不超采）。
- (CGFloat)pxMosaicPreviewScale {
    CGFloat screenScale = MAX([UIScreen mainScreen].scale, 1.0);
    CGFloat displayScale = MAX(screenScale * MAX(self.fitScale, 0.01), 1.0);
    return MIN(MAX(self.document.sourceImage.scale, 1.0), displayScale);
}

- (void)pxTouchMosaicCacheOrderForID:(NSString *)annotationID {
    [self.mosaicCacheOrder removeObject:annotationID];
    [self.mosaicCacheOrder addObject:annotationID];
    while (self.mosaicCacheOrder.count > PXMaxMosaicCacheEntries) {
        NSString *oldest = self.mosaicCacheOrder.firstObject;
        [self.mosaicCacheOrder removeObjectAtIndex:0];
        [self.mosaicCache removeObjectForKey:oldest];
    }
}

- (void)pxRemoveMosaicCacheForID:(NSString *)annotationID {
    [self.mosaicCache removeObjectForKey:annotationID];
    [self.mosaicCacheOrder removeObject:annotationID];
}

#pragma mark - 手势

- (void)pxHandlePan:(UIPanGestureRecognizer *)gesture {
    CGPoint viewPoint = [gesture locationInView:self];
    CGPoint imagePoint = [self pxImagePointFromViewPoint:viewPoint];

    switch (gesture.state) {
        case UIGestureRecognizerStateBegan: {
            [self pxBeginAnnotationAtImagePoint:imagePoint gestureState:self.gestureState];
            break;
        }
        case UIGestureRecognizerStateChanged: {
            [self pxUpdateAnnotationAtImagePoint:imagePoint];
            break;
        }
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled: {
            [self pxCommitActiveAnnotation];
            break;
        }
        default:
            break;
    }
}

- (void)pxHandleTap:(UITapGestureRecognizer *)gesture {
    if (self.currentTool != PXAnnotationTypeText) {
        return;
    }
    CGPoint viewPoint = [gesture locationInView:self];
    if (self.delegate && [self.delegate respondsToSelector:@selector(canvas:didRequestTextInputAtViewPoint:)]) {
        [self.delegate canvas:self didRequestTextInputAtViewPoint:viewPoint];
    }
}

- (void)pxBeginAnnotationAtImagePoint:(CGPoint)imagePoint gestureState:(NSMutableDictionary *)state {
    PXAnnotationType tool = self.currentTool;
    if (tool == PXAnnotationTypeText) {
        return;   // 文字走点击 + 输入弹窗
    }

    PXAnnotation *annotation = [[PXAnnotation alloc] initWithType:tool
                                                            color:self.currentColor
                                                        lineWidth:self.currentLineWidth
                                                            alpha:(tool == PXAnnotationTypeHighlight ? 1.0 : 1.0)];
    if (tool == PXAnnotationTypeBrush || tool == PXAnnotationTypeHighlight ||
        tool == PXAnnotationTypeLine || tool == PXAnnotationTypeArrow) {
        [annotation.points addObject:[NSValue valueWithCGPoint:imagePoint]];
    } else {
        // rectangle/oval/mosaic 以起点为锚
        annotation.rect = CGRectMake(imagePoint.x, imagePoint.y, 0, 0);
    }
    self.activeAnnotation = annotation;
    state[@"anchor"] = [NSValue valueWithCGPoint:imagePoint];
    [self setNeedsDisplay];
}

- (void)pxUpdateAnnotationAtImagePoint:(CGPoint)imagePoint {
    PXAnnotation *annotation = self.activeAnnotation;
    if (!annotation) return;

    switch (annotation.type) {
        case PXAnnotationTypeBrush:
        case PXAnnotationTypeHighlight:
            [annotation.points addObject:[NSValue valueWithCGPoint:imagePoint]];
            break;
        case PXAnnotationTypeLine:
        case PXAnnotationTypeArrow: {
            CGPoint start = [annotation.points.firstObject CGPointValue];
            annotation.points = [NSMutableArray arrayWithObjects:
                                 [NSValue valueWithCGPoint:start],
                                 [NSValue valueWithCGPoint:imagePoint], nil];
            break;
        }
        case PXAnnotationTypeRectangle:
        case PXAnnotationTypeOval:
        case PXAnnotationTypeMosaic: {
            NSValue *anchorValue = self.gestureState[@"anchor"];
            if (!anchorValue) return;
            CGPoint anchor = [anchorValue CGPointValue];
            annotation.rect = CGRectMake(MIN(anchor.x, imagePoint.x), MIN(anchor.y, imagePoint.y),
                                         fabs(imagePoint.x - anchor.x), fabs(imagePoint.y - anchor.y));
            break;
        }
        case PXAnnotationTypeText:
            break;
    }
    [self setNeedsDisplay];
}

- (void)pxCommitActiveAnnotation {
    PXAnnotation *annotation = self.activeAnnotation;
    self.activeAnnotation = nil;
    [self.gestureState removeAllObjects];
    if (!annotation) return;

    BOOL hasContent = NO;
    switch (annotation.type) {
        case PXAnnotationTypeBrush:
        case PXAnnotationTypeHighlight:
        case PXAnnotationTypeLine:
        case PXAnnotationTypeArrow:
            hasContent = (annotation.points.count >= 2) || (annotation.points.count == 1 && annotation.type == PXAnnotationTypeBrush);
            break;
        case PXAnnotationTypeRectangle:
        case PXAnnotationTypeOval:
        case PXAnnotationTypeMosaic:
            hasContent = (annotation.rect.size.width >= 6 && annotation.rect.size.height >= 6);
            break;
        case PXAnnotationTypeText:
            hasContent = NO;
            break;
    }
    if (!hasContent) {
        [self setNeedsDisplay];
        return;   // 过小的误触不进入文档
    }

    [self.document addAnnotation:annotation];
    NSString *annotationID = annotation.annotationID;
    PXAnnotation *copyForRedo = [annotation copy];
    __weak typeof(self) weakSelf = self;
    [self.pxUndoManager pushUndoBlock:^{
        [weakSelf.document removeAnnotationWithID:annotationID];
        [weakSelf pxRemoveMosaicCacheForID:annotationID];
        [weakSelf setNeedsDisplay];
    } redoBlock:^{
        [weakSelf.document addAnnotation:copyForRedo];
        [weakSelf setNeedsDisplay];
    }];
    [self setNeedsDisplay];
    [self pxNotifyContentChanged];
}

#pragma mark - 文字

- (void)addTextAnnotationWithText:(NSString *)text atViewPoint:(CGPoint)viewPoint {
    if (text.length == 0) return;
    CGPoint imagePoint = [self pxImagePointFromViewPoint:viewPoint];
    CGSize imageSize = self.document.sourceImage.size;
    if (imagePoint.x < 0 || imagePoint.y < 0 || imagePoint.x > imageSize.width || imagePoint.y > imageSize.height) {
        return;
    }

    PXAnnotation *annotation = [[PXAnnotation alloc] initWithType:PXAnnotationTypeText
                                                            color:self.currentColor
                                                        lineWidth:self.currentLineWidth
                                                            alpha:1.0];
    annotation.rect = CGRectMake(imagePoint.x, imagePoint.y, 400, 0);
    annotation.text = [text copy];
    [self.document addAnnotation:annotation];

    NSString *annotationID = annotation.annotationID;
    PXAnnotation *copyForRedo = [annotation copy];
    __weak typeof(self) weakSelf = self;
    [self.pxUndoManager pushUndoBlock:^{
        [weakSelf.document removeAnnotationWithID:annotationID];
        [weakSelf setNeedsDisplay];
    } redoBlock:^{
        [weakSelf.document addAnnotation:copyForRedo];
        [weakSelf setNeedsDisplay];
    }];
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
    [self.pxUndoManager undo];
    [self pxNotifyContentChanged];
}

- (void)redo {
    [self.pxUndoManager redo];
    [self pxNotifyContentChanged];
}

- (void)pxNotifyContentChanged {
    if (self.delegate && [self.delegate respondsToSelector:@selector(canvasDidChangeContent:)]) {
        [self.delegate canvasDidChangeContent:self];
    }
}

#pragma mark - 清理

- (void)prepareForDismissal {
    self.delegate = nil;
    [self.gestureState removeAllObjects];
    [self.mosaicCache removeAllObjects];
    [self.mosaicCacheOrder removeAllObjects];
    [self.pxUndoManager removeAllActions];
    self.activeAnnotation = nil;
}

@end
