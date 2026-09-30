#import <Foundation/Foundation.h>
#import "PXGeometry.h"

NS_ASSUME_NONNULL_BEGIN

/// 配置快照对象：不可变。任务创建时整体取走一份，执行中不被偏好变更打断。
@interface PXConfig : NSObject

@property (nonatomic, readonly) BOOL enabled;
@property (nonatomic, readonly) PXOutputAction defaultResultAction;
@property (nonatomic, readonly) BOOL showResultBubble;
@property (nonatomic, readonly) BOOL screenshotHaptic;
@property (nonatomic, readonly) BOOL areaRememberLastRect;
@property (nonatomic, readonly) CGFloat editorDefaultLineWidth;

@end

/// 偏好读取层：只负责把 CFPreferences 域转成不可变配置快照。
/// 写入方是设置 Bundle（直接写 CFPreferences），跨进程通过 Darwin reload 通知同步。
@interface PXPreferences : NSObject

/// 当前配置快照。线程安全：读侧永远拿到完整一致的一份。
@property (class, nonatomic, readonly, strong) PXConfig *config;

/// 重新从 CFPreferences 读取全部键，原子替换当前快照。
+ (void)reload;

@end

NS_ASSUME_NONNULL_END
