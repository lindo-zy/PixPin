#import <UIKit/UIKit.h>
#import "PXAnnotation.h"

NS_ASSUME_NONNULL_BEGIN

/// 非破坏式编辑文档（DEVELOPMENT.md 5.6）：sourceImage 永不被修改。
/// 标注数组的修改通过 append/remove 提供，撤销由 PXUndoManager 在视图控制器层管理。
@interface PXEditorDocument : NSObject

@property (nonatomic, strong, readonly) UIImage *sourceImage;
@property (nonatomic, strong, readonly) NSArray<PXAnnotation *> *annotations;
/// 预留的裁剪变换（第一版编辑器进入前已完成裁剪，恒为 CGRectZero）。
@property (nonatomic, assign, readonly) CGRect cropTransform;
@property (nonatomic, strong) UIColor *backgroundColor;

- (instancetype)initWithSourceImage:(UIImage *)sourceImage;

- (void)addAnnotation:(PXAnnotation *)annotation;
- (void)removeAnnotationWithID:(NSString *)annotationID;
- (nullable PXAnnotation *)annotationWithID:(NSString *)annotationID;
/// 最后一个标注（撤销/重做操作目标）。
- (nullable PXAnnotation *)lastAnnotation;

@end

NS_ASSUME_NONNULL_END
