#import <UIKit/UIKit.h>
@implementation UIScreen
+ (instancetype)mainScreen {
    static UIScreen *screen;
    if (!screen) { screen = [self new]; screen.bounds = CGRectMake(0, 0, 64, 256); screen.scale = 1; }
    return screen;
}
// 有签名但不返回图像：复现排除窗口 API 空返回后首帧无法开始的回归。
- (id)_snapshotExcludingWindows:(NSArray *)windows withRect:(CGRect)rect { return nil; }
@end
@implementation UIWindow
- (void)setHidden:(BOOL)hidden { _hidden = hidden; _hiddenChanges++; }
- (BOOL)drawViewHierarchyInRect:(CGRect)rect afterScreenUpdates:(BOOL)updates { return NO; }
@end
@implementation UIScene
@end
@implementation UIWindowScene
@end
@implementation UIApplication
+ (instancetype)sharedApplication { static UIApplication *app; if (!app) app = [self new]; return app; }
@end
@implementation UIGraphicsImageRendererFormat
@end
@implementation UIGraphicsImageRendererContext
- (CGContextRef)CGContext { return NULL; }
- (void)fillRect:(CGRect)rect {}
@end
@implementation UIGraphicsImageRenderer
- (instancetype)initWithSize:(CGSize)size format:(UIGraphicsImageRendererFormat *)format { return [super init]; }
- (UIImage *)imageWithActions:(void (^)(UIGraphicsImageRendererContext *))actions { return nil; }
@end
@implementation UIImage (PXCaptureStub)
+ (instancetype)imageWithCGImage:(CGImageRef)image {
    return [self imageWithCGImage:image scale:1 orientation:UIImageOrientationUp];
}
@end
