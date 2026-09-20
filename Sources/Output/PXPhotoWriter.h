#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 相册写入。失败时调用方必须保留临时文件（幂等由输出管线层保证，本层不负责）。
@interface PXPhotoWriter : NSObject

+ (void)saveImage:(UIImage *)image
       completion:(void (^)(NSString *localIdentifier, NSError *error))completion;

@end

NS_ASSUME_NONNULL_END
