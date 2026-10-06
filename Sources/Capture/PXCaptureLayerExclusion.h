#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
/// 持有自有浮窗图层的捕获排除标记；主线程建立/清理，不改变可见性或触摸。
@interface PXCaptureLayerExclusion : NSObject
@property (nonatomic, readonly, getter=isActive) BOOL active;
+ (nullable instancetype)beginWithLayers:(NSArray *)layers;
- (void)invalidate;
@end
NS_ASSUME_NONNULL_END
