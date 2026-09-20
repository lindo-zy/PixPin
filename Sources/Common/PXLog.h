#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef __cplusplus
extern "C" {
#endif

/// 统一日志出口。禁止输出截图内容、剪贴板图片或用户图片数据，只允许记录状态与路径级信息。
void PXLog(NSString *level, NSString *format, ...) NS_FORMAT_FUNCTION(2, 3);

#define PXLogInfo(frmt, ...)   PXLog(@"I", (frmt), ##__VA_ARGS__)
#define PXLogWarn(frmt, ...)   PXLog(@"W", (frmt), ##__VA_ARGS__)
#define PXLogError(frmt, ...)  PXLog(@"E", (frmt), ##__VA_ARGS__)

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
