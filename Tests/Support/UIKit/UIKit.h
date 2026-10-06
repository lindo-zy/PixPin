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
- (void)setFill;
@end

// 抓屏适配器宿主测试的最小界面；真正图像操作仍使用 CoreGraphics。
@interface UIScreen : NSObject
@property (nonatomic) CGRect bounds;
@property (nonatomic) CGFloat scale;
+ (instancetype)mainScreen;
@end
@interface UIWindow : NSObject
@property (nonatomic, getter=isHidden) BOOL hidden;
@property (nonatomic) NSUInteger hiddenChanges;
@property (nonatomic, strong) NSObject *rootViewController;
@property (nonatomic, strong) id layer;
@property (nonatomic) CGFloat alpha;
@property (nonatomic) CGFloat windowLevel;
@property (nonatomic) CGAffineTransform transform;
@property (nonatomic) CGRect frame;
- (BOOL)drawViewHierarchyInRect:(CGRect)rect afterScreenUpdates:(BOOL)updates;
@end
@interface UIScene : NSObject
@end
@interface UIWindowScene : UIScene
@property (nonatomic, strong) UIScreen *screen;
@property (nonatomic, copy) NSArray<UIWindow *> *windows;
@end
@interface UIApplication : NSObject
@property (nonatomic, copy) NSSet<UIScene *> *connectedScenes;
+ (instancetype)sharedApplication;
@end
@interface UIGraphicsImageRendererFormat : NSObject
@property (nonatomic) CGFloat scale;
@property (nonatomic) BOOL opaque;
@end
@interface UIGraphicsImageRendererContext : NSObject
@property (nonatomic, readonly) CGContextRef CGContext;
- (void)fillRect:(CGRect)rect;
@end
@interface UIGraphicsImageRenderer : NSObject
- (instancetype)initWithSize:(CGSize)size format:(UIGraphicsImageRendererFormat *)format;
- (UIImage *)imageWithActions:(void (^)(UIGraphicsImageRendererContext *))actions;
@end
@interface UIImage (PXCaptureStub)
+ (instancetype)imageWithCGImage:(CGImageRef)image;
@end
