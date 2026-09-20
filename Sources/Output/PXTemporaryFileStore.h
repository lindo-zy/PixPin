#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 任务专属临时目录管理。目录结构：<tmp>/PixPinTasks/<taskID>/
/// 任务结束（成功/失败/取消）后由协调器调用 removeTaskDirectory 清理。
@interface PXTemporaryFileStore : NSObject

+ (NSString *)directoryForTaskID:(NSString *)taskID create:(BOOL)create;
+ (nullable NSString *)writeImage:(UIImage *)image
                           taskID:(NSString *)taskID
                             name:(NSString *)name
                            error:(NSError **)error;
+ (void)removeTaskDirectory:(NSString *)taskID;
/// 启动时清理全部残留任务目录（此时不可能有活动任务）。
+ (void)sweepAllTaskDirectories;

NS_ASSUME_NONNULL_END

@end
