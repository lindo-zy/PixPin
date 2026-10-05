#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 相册写入。失败时调用方必须保留临时文件（幂等由输出管线层保证，本层不负责）。
@interface PXPhotoWriter : NSObject

+ (void)saveImage:(UIImage *)image
       completion:(void (^)(NSString *localIdentifier, NSError *error))completion;

/// 按文件直存（JPEG 以原始数据导入相册，不经整幅解码/重编码）：
/// 长图拼接产物已是落盘文件，走此路径避免保存期全图解码尖峰把 SpringBoard
/// 推过 jetsam 高水位。path 必须是已存在的可读文件。
+ (void)saveImageFileAtPath:(NSString *)path
                 completion:(void (^)(NSString *localIdentifier, NSError *error))completion;

@end

NS_ASSUME_NONNULL_END
