#import <UIKit/UIKit.h>
#import "PXAnnotation.h"

NS_ASSUME_NONNULL_BEGIN

/// 非破坏式编辑文档（DEVELOPMENT.md 5.6）：
/// - sourceImage 只被整体替换（裁剪/旋转烘焙时），单笔标注永不修改底图；
/// - 标注数组的插入/删除/替换通过显式接口提供，撤销由画布层 PXUndoManager 管理。
@interface PXEditorDocument : NSObject

@property (nonatomic, strong, readonly) UIImage *sourceImage;
@property (nonatomic, strong, readonly) NSArray<PXAnnotation *> *annotations;
/// 预留的裁剪变换记录（裁剪以烘焙方式实现，此字段仅作元数据记录）。
@property (nonatomic, assign, readonly) CGRect cropTransform;
@property (nonatomic, strong) UIColor *backgroundColor;

- (instancetype)initWithSourceImage:(UIImage *)sourceImage;

- (void)addAnnotation:(PXAnnotation *)annotation;
/// 撤销/重做恢复时按原层级插回。
- (void)insertAnnotation:(PXAnnotation *)annotation atIndex:(NSUInteger)index;
- (void)removeAnnotationWithID:(NSString *)annotationID;
- (nullable PXAnnotation *)annotationWithID:(NSString *)annotationID;
- (NSUInteger)indexOfAnnotationWithID:(NSString *)annotationID;
/// 选中标注置顶。
- (void)bringAnnotationToFront:(NSString *)annotationID;
/// 最后一个标注。
- (nullable PXAnnotation *)lastAnnotation;

/// 裁剪/旋转烘焙：整体替换底图与标注集合（替换前由调用方持有旧状态用于撤销）。
- (void)replaceContentWithImage:(UIImage *)image annotations:(NSArray<PXAnnotation *> *)annotations;

/// 图章递增序号（每个文档从 1 开始；撤销不回退，保证编号唯一）。
- (NSInteger)nextStampNumber;

@end

NS_ASSUME_NONNULL_END
