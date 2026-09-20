#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 剪贴板写入。失败不能阻止相册保存（调用方保证顺序）。
@interface PXClipboardWriter : NSObject

/// 异步复制：PNG 编码在后台队列执行（3x 全屏图可占数百毫秒，不占 SpringBoard 主线程），
/// 最终数据写入回主线程。completion 固定主线程回调。
+ (void)copyImageAsync:(UIImage *)image completion:(void (^)(BOOL ok))completion;

@end

NS_ASSUME_NONNULL_END
