#import "PXCaptureProvider.h"
#import "../Common/PXLog.h"
#import "../Common/PXRuntimeStatus.h"
#import <dlfcn.h>
#import <QuartzCore/QuartzCore.h>

NSString * const PXCaptureErrorDomain = @"com.pixpin.screenshot.capture";

// 私有接口运行期解析，不做链接期依赖；全部不可用时走公开回退路径并标记 partial。
static UIImage *(*_PXCreateScreenUIImage)(void) = NULL;
static CGImageRef (*_PXGetScreenImage)(void) = NULL;

static void PXResolveScreenCaptureSymbols(void) {
    void *symbol = dlsym(RTLD_DEFAULT, "_UICreateScreenUIImage");
    if (symbol) {
        _PXCreateScreenUIImage = (UIImage *(*)(void))symbol;
    } else {
        PXLogWarn(@"_UICreateScreenUIImage unavailable");
    }

    symbol = dlsym(RTLD_DEFAULT, "UIGetScreenImage");
    if (symbol) {
        _PXGetScreenImage = (CGImageRef (*)(void))symbol;
    } else {
        PXLogWarn(@"UIGetScreenImage unavailable");
    }

    if (!_PXCreateScreenUIImage && !_PXGetScreenImage) {
        PXLogWarn(@"no private capture symbol resolved, fallback snapshot path will be used");
    }
}

@interface PXCaptureProvider ()
@property (nonatomic, copy, readwrite, nullable) NSString *lastCaptureMethod;
@end

@implementation PXCaptureProvider

- (instancetype)init {
    if (self = [super init]) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            PXResolveScreenCaptureSymbols();
        });
    }
    return self;
}

+ (NSString *)resolvedCaptureMethod {
    if (_PXCreateScreenUIImage) return @"private-uicreate";
    if (_PXGetScreenImage) return @"private-uigetscreen";
    return @"fallback-snapshot";
}

- (void)captureWithCompletion:(void (^)(UIImage *, BOOL, NSString *, NSError *))completion {
    NSParameterAssert(completion);
    void (^grabBlock)(void) = ^{
        NSString *method = [[self class] resolvedCaptureMethod];
        UIImage *image = nil;
        BOOL isPartial = NO;

        if (_PXCreateScreenUIImage) {
            image = _PXCreateScreenUIImage();
            if (image) method = @"private-uicreate";
        }
        if (!image && _PXGetScreenImage) {
            CGImageRef screenCG = _PXGetScreenImage();
            if (screenCG) {
                image = [UIImage imageWithCGImage:screenCG];
                CGImageRelease(screenCG);   // UIGetScreenImage 按命名约定返回 retained CGImage
                if (image) method = @"private-uigetscreen";
            }
        }
        if (!image) {
            image = [self pxGrabBySnapshotFallback];
            isPartial = (image != nil);
            method = @"fallback-snapshot";
        }

        if (!image) {
            NSError *error = [NSError errorWithDomain:PXCaptureErrorDomain
                                                 code:PXCaptureErrorCaptureFailed
                                             userInfo:@{NSLocalizedDescriptionKey: @"所有抓取路径均未取得屏幕图像"}];
            self.lastCaptureMethod = method;
            dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, NO, method, error); });
            return;
        }

        // 归一化放到后台：大图重排不允许阻塞 SpringBoard 主线程。
        CGSize targetPixelSize = CGSizeMake(
            [UIScreen mainScreen].bounds.size.width * [UIScreen mainScreen].scale,
            [UIScreen mainScreen].bounds.size.height * [UIScreen mainScreen].scale);
        CGFloat screenScale = [UIScreen mainScreen].scale;
        self.lastCaptureMethod = method;   // 主线程（grabBlock）内记录实际使用的策略

        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSError *normalizeError = nil;
            UIImage *normalized = [self pxNormalizeImage:image
                                        targetPixelSize:targetPixelSize
                                            screenScale:screenScale
                                                  error:&normalizeError];
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(normalized, isPartial, method, normalizeError);
            });
        });
    };

    // UIKit 抓屏要求主线程。
    if ([NSThread isMainThread]) {
        grabBlock();
    } else {
        dispatch_async(dispatch_get_main_queue(), grabBlock);
    }
}

#pragma mark - 抓取路径

- (UIImage *)pxGrabBySnapshotFallback {
    // 公开 API 回退：只能捕获 SpringBoard 自身可见窗口层级，结果由调用方标记 partial。
    // UIScreen 不是 UIView，不存在 snapshotViewAfterScreenUpdates:；旧实现会抛
    // unrecognized selector 并让整条截图链直接失败。
    @try {
        CGSize size = [UIScreen mainScreen].bounds.size;
        UIGraphicsImageRendererFormat *format = [[UIGraphicsImageRendererFormat alloc] init];
        format.scale = [UIScreen mainScreen].scale;
        format.opaque = YES;
        UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size format:format];
        return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
            [[UIColor blackColor] setFill];
            [context fillRect:CGRectMake(0, 0, size.width, size.height)];

            NSMutableArray<UIWindow *> *windows = [[NSMutableArray alloc] init];
            for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
                if (![scene isKindOfClass:[UIWindowScene class]]) continue;
                UIWindowScene *windowScene = (UIWindowScene *)scene;
                if (windowScene.screen != [UIScreen mainScreen]) continue;
                [windows addObjectsFromArray:windowScene.windows];
            }
            [windows sortUsingComparator:^NSComparisonResult(UIWindow *lhs, UIWindow *rhs) {
                if (lhs.windowLevel < rhs.windowLevel) return NSOrderedAscending;
                if (lhs.windowLevel > rhs.windowLevel) return NSOrderedDescending;
                return NSOrderedSame;
            }];

            for (UIWindow *window in windows) {
                if (window.hidden || window.alpha <= 0.01) continue;
                // 不依赖 PXCaptureWindow 类，避免 Capture 层反向引用 Overlay 层。
                if ([NSStringFromClass(window.class) isEqualToString:@"PXCaptureWindow"]) continue;
                CGContextSaveGState(context.CGContext);
                CGContextConcatCTM(context.CGContext, window.transform);
                BOOL drew = [window drawViewHierarchyInRect:window.frame afterScreenUpdates:NO];
                if (!drew) {
                    [window.layer renderInContext:context.CGContext];
                }
                CGContextRestoreGState(context.CGContext);
            }
        }];
    } @catch (NSException *exception) {
        PXLogError(@"snapshot fallback exception: %@", exception);
        return nil;
    }
}

#pragma mark - 归一化

- (UIImage *)pxNormalizeImage:(UIImage *)image
              targetPixelSize:(CGSize)targetPixelSize
                  screenScale:(CGFloat)screenScale
                        error:(NSError **)error {
    CGImageRef cg = image.CGImage;
    if (!cg) {
        if (error) {
            *error = [NSError errorWithDomain:PXCaptureErrorDomain
                                         code:PXCaptureErrorCaptureFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"抓屏结果无 CGImage"}];
        }
        return nil;
    }

    CGFloat rawW = CGImageGetWidth(cg);
    CGFloat rawH = CGImageGetHeight(cg);
    CGFloat targetW = targetPixelSize.width;
    CGFloat targetH = targetPixelSize.height;

    BOOL directMatch = [self pxIsAspect:rawW height:rawH matching:targetW height:targetH];
    BOOL rotatedMatch = [self pxIsAspect:rawH height:rawW matching:targetW height:targetH];

    if (!directMatch && !rotatedMatch) {
        // 几何对不上时宁可失败，也不能产出方向/比例错误的截图（正确性优先）。
        PXLogError(@"unexpected capture geometry raw=%.0fx%.0f target=%.0fx%.0f", rawW, rawH, targetW, targetH);
        if (error) {
            *error = [NSError errorWithDomain:PXCaptureErrorDomain
                                         code:PXCaptureErrorUnexpectedGeometry
                                     userInfo:@{NSLocalizedDescriptionKey: @"抓屏结果与屏幕几何不一致"}];
        }
        return nil;
    }

    CGImageRef uprightCG = cg;
    if (rotatedMatch && !directMatch) {
        uprightCG = [self pxRotateCGImage:cg byQuarterTurns:1];
        if (!uprightCG) {
            if (error) {
                *error = [NSError errorWithDomain:PXCaptureErrorDomain
                                             code:PXCaptureErrorCaptureFailed
                                         userInfo:@{NSLocalizedDescriptionKey: @"方向校正失败"}];
            }
            return nil;
        }
    }

    UIImage *result = [UIImage imageWithCGImage:uprightCG scale:screenScale orientation:UIImageOrientationUp];
    if (uprightCG != cg) {
        CGImageRelease(uprightCG);
    }
    return result;
}

- (BOOL)pxIsAspect:(CGFloat)w1 height:(CGFloat)h1 matching:(CGFloat)w2 height:(CGFloat)h2 {
    if (w2 <= 0 || h2 <= 0) return NO;
    CGFloat ratioA = w1 / h1;
    CGFloat ratioB = w2 / h2;
    return fabs(ratioA - ratioB) <= 0.02 && fabs(w1 - w2) / w2 <= 0.05;
}

- (CGImageRef)pxRotateCGImage:(CGImageRef)image byQuarterTurns:(NSUInteger)turns {
    CGFloat width = CGImageGetWidth(image);
    CGFloat height = CGImageGetHeight(image);
    // 只处理 90° 顺时针（横屏缓冲 → 竖屏）。
    if (turns % 4 != 1) {
        return CGImageCreateCopy(image);
    }

    // 统一使用 RGBA8 上下文，由 CoreGraphics 完成源像素格式转换。
    CGBitmapInfo info = (CGBitmapInfo)kCGImageAlphaPremultipliedLast;
    CGContextRef context = CGBitmapContextCreate(NULL, height, width, 8, 0, CGImageGetColorSpace(image), info);
    if (!context) {
        return NULL;
    }
    CGContextSetFillColorWithColor(context, [UIColor blackColor].CGColor);
    CGContextFillRect(context, CGRectMake(0, 0, height, width));
    CGContextTranslateCTM(context, height, 0);
    CGContextRotateCTM(context, M_PI_2);
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);

    CGImageRef result = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    return result;
}

@end
