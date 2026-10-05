// 仅宿主测试使用：图像仍通过真实 CoreGraphics / ImageIO 解码与绘制。
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

typedef NS_ENUM(NSInteger, UIImageOrientation) { UIImageOrientationUp };
@interface UIImage : NSObject
@property (nonatomic, readonly) CGImageRef CGImage;
@property (nonatomic, readonly) CGFloat scale;
@property (nonatomic, readonly) CGSize size;
+ (instancetype)imageWithCGImage:(CGImageRef)image scale:(CGFloat)scale orientation:(UIImageOrientation)orientation;
@end
@interface UIColor : NSObject
@property (nonatomic, readonly) CGColorRef CGColor;
+ (instancetype)blackColor;
@end
