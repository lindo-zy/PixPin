#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 编辑器标注类型（DEVELOPMENT.md 5.6 全集）。
/// Pan 不是标注，仅作为画布“平移/浏览”工具档位使用，永远不会写入文档。
typedef NS_ENUM(NSInteger, PXAnnotationType) {
    PXAnnotationTypeBrush = 0,
    PXAnnotationTypeLine = 1,
    PXAnnotationTypeArrow = 2,
    PXAnnotationTypeRectangle = 3,
    PXAnnotationTypeOval = 4,
    PXAnnotationTypeHighlight = 5,
    PXAnnotationTypeMosaic = 6,
    PXAnnotationTypeText = 7,
    PXAnnotationTypeSpotlight = 8,
    PXAnnotationTypeMagnifier = 9,
    PXAnnotationTypeSticker = 10,
    PXAnnotationTypeStamp = 11,
    PXAnnotationTypePan = 100,
};

/// 方框/椭圆的空心、实心样式（ShellX 的 fillrect/filloval 归并为样式位）。
typedef NS_ENUM(NSInteger, PXAnnotationFillStyle) {
    PXAnnotationFillStyleHollow = 0,
    PXAnnotationFillStyleSolid = 1,
};

/// 标注对象：坐标一律使用“源图点空间”（sourceImage.size，画布与导出共用）。
/// 几何约定：
/// - brush/highlight/line/arrow：points 点序列（line/arrow 恰为起点+终点）；
/// - rectangle/oval/mosaic/spotlight：rect；
/// - text：rect.origin 为锚点，rect.size 为预测量出的文本外框；
/// - magnifier：rect 为圆形外接框，zoom 为放大倍数；
/// - sticker/stamp：rect 为外接框，rotation（sticker）为弧度。
@interface PXAnnotation : NSObject <NSCopying>

@property (nonatomic, copy, readwrite) NSString *annotationID;
@property (nonatomic, assign) PXAnnotationType type;
@property (nonatomic, strong) UIColor *color;
@property (nonatomic, assign) CGFloat lineWidth;
@property (nonatomic, assign) CGFloat alpha;
@property (nonatomic, assign) PXAnnotationFillStyle fillStyle;
/// spotlight 挖孔形状：NO=矩形（默认），YES=椭圆。
@property (nonatomic, assign) BOOL holeIsEllipse;
/// sticker 旋转角（弧度，顺时针）。文字保持水平不旋转。
@property (nonatomic, assign) CGFloat rotation;
@property (nonatomic, assign) CGFloat zoom;
/// brush/highlight：笔画点序列；line/arrow：起点+终点。
@property (nonatomic, strong) NSMutableArray<NSValue *> *points;
/// rectangle/oval/mosaic/spotlight/magnifier/sticker/stamp 区域（源图点空间）。
@property (nonatomic, assign) CGRect rect;
@property (nonatomic, copy, nullable) NSString *text;
@property (nonatomic, copy, nullable) NSString *stickerText;
@property (nonatomic, assign) NSInteger stampNumber;
@property (nonatomic, assign) CGFloat fontSize;
@property (nonatomic, assign) NSUInteger zIndex;

- (instancetype)initWithType:(PXAnnotationType)type
                       color:(UIColor *)color
                   lineWidth:(CGFloat)lineWidth
                       alpha:(CGFloat)alpha;

/// 标注在图片空间的外接框（选中框/命中/裁剪丢弃判断共用）。
- (CGRect)boundsInImageSpace;

/// 命中测试：slop 为图片空间的手指容差（约等于屏幕 10pt 折算值）。
- (BOOL)containsImagePoint:(CGPoint)point slop:(CGFloat)slop;

/// 标注中心（变换锚点）。
- (CGPoint)centerInImageSpace;

/// 以 newCenter 平移（平移手势）。
- (void)translateToCenter:(CGPoint)newCenter;

/// 绕 center 缩放 scale（捏合手势）；文字缩放 fontSize，笔画缩放点序列。
- (void)applyScale:(CGFloat)scale;

/// 绕 center 旋转 angle（弧度）。仅 sticker 支持；其他类型忽略。
- (void)applyRotation:(CGFloat)angle;

+ (UIFont *)fontForAnnotation:(PXAnnotation *)annotation;

+ (NSString *)newAnnotationID;

@end

NS_ASSUME_NONNULL_END
