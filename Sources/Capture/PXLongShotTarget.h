#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
/// 唯一的前台/锁屏检查，手动与自动路径共用；缺失接口时拒绝继续。
NSString * _Nullable PXLongShotFrontmostIdentifier(id application);
BOOL PXLongShotTargetIsCurrent(id application, id _Nullable lockManager, NSString *identifier);
id _Nullable PXLongShotLockManager(void);
NS_ASSUME_NONNULL_END
