#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 第一版标注类型（DEVELOPMENT.md 5.6 子集；magnifier/sticker/stamp 留待后续扩展）。
typedef NS_ENUM(NSInteger, PXAnnotationType) {
    PXAnnotationTypeBrush = 0,
    PXAnnotationTypeLine = 1,
    PXAnnotationTypeArrow = 2,
    PXAnnotationTypeRectangle = 3,
    PXAnnotationTypeOval = 4,
    PXAnnotationTypeHighlight = 5,
    PXAnnotationTypeMosaic = 6,
    PXAnnotationTypeText = 7,
};

/// 标注对象：坐标一律使用“源图点空间”（sourceImage.size，画布与导出共用）。
@interface PXAnnotation : NSObject <NSCopying>

@property (nonatomic, copy, readonly) NSString *annotationID;
@property (nonatomic, assign) PXAnnotationType type;
@property (nonatomic, strong) UIColor *color;
@property (nonatomic, assign) CGFloat lineWidth;
@property (nonatomic, assign) CGFloat alpha;
/// brush/highlight：笔画点序列；line/arrow：起点+终点。
@property (nonatomic, strong) NSMutableArray<NSValue *> *points;
/// rectangle/oval/mosaic 区域（源图点空间）。
@property (nonatomic, assign) CGRect rect;
@property (nonatomic, copy, nullable) NSString *text;
@property (nonatomic, assign) CGFloat fontSize;
@property (nonatomic, assign) NSUInteger zIndex;

- (instancetype)initWithType:(PXAnnotationType)type
                       color:(UIColor *)color
                   lineWidth:(CGFloat)lineWidth
                       alpha:(CGFloat)alpha;

/// 标注在图片空间的外接框（用于局部失效与导出裁剪）。
- (CGRect)boundsInImageSpace;

+ (UIFont *)fontForAnnotation:(PXAnnotation *)annotation;

+ (NSString *)newAnnotationID;

@end

NS_ASSUME_NONNULL_END
