#import "PXCaptureProvider.h"
#import "PXCaptureLayerExclusion.h"
#import "../Common/PXLog.h"
#import "../Common/PXLongShotControl.h"
#import <dlfcn.h>
#import <QuartzCore/QuartzCore.h>
#import <string.h>

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
@property (nonatomic, strong) PXCaptureLayerExclusion *layerExclusion;
@property (nonatomic, copy) NSArray<UIWindow *> *protectedWindows;
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
    [self captureExcludingWindows:@[] completion:completion];
}

- (UIImage *)pxSnapshotExcludingWindows:(NSArray<UIWindow *> *)windows {
    SEL selector = NSSelectorFromString(@"_snapshotExcludingWindows:withRect:");
    UIScreen *screen = UIScreen.mainScreen;
    if (![screen respondsToSelector:selector]) {
        PXLogWarn(@"long shot excluding-windows selector unavailable"); return nil;
    }
    @try {
        NSMethodSignature *signature = [screen methodSignatureForSelector:selector];
        if (!signature || signature.numberOfArguments != 4 ||
            signature.methodReturnType[0] != '@' || signature.methodReturnLength != sizeof(id) ||
            [signature getArgumentTypeAtIndex:2][0] != '@' ||
            strcmp([signature getArgumentTypeAtIndex:3], @encode(CGRect)) != 0) {
            PXLogWarn(@"long shot excluding-windows signature incompatible"); return nil;
        }
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
        invocation.target = screen;
        invocation.selector = selector;
        NSArray *excluded = windows;
        CGRect rect = CGRectNull; // 整屏，与本地参考实现的调用契约一致。
        [invocation setArgument:&excluded atIndex:2];
        [invocation setArgument:&rect atIndex:3];
        [invocation invoke];
        __unsafe_unretained id raw = nil;
        [invocation getReturnValue:&raw];
        id result = raw; // 在 invocation 生命周期内建立强引用。
        if (![result isKindOfClass:UIImage.class]) {
            PXLogWarn(@"long shot excluding-windows returned %@", result ? NSStringFromClass([result class]) : @"nil");
            return nil;
        }
        return result;
    } @catch (NSException *exception) {
        PXLogWarn(@"long shot excluding-windows exception (%@)", exception.name); return nil;
    }
}

- (void)endVisibleWindowExclusion {
    NSParameterAssert(NSThread.isMainThread);
    [self.layerExclusion invalidate]; self.layerExclusion = nil; self.protectedWindows = nil;
}
- (BOOL)pxPrepareVisibleWindows:(NSArray<UIWindow *> *)windows {
    if (self.layerExclusion.isActive && [self.protectedWindows isEqualToArray:windows]) return NO;
    [self endVisibleWindowExclusion];
    NSMutableArray *layers = [NSMutableArray array];
    for (UIWindow *window in windows) [layers addObject:window.layer];
    self.layerExclusion = [PXCaptureLayerExclusion beginWithLayers:layers];
    if (self.layerExclusion) self.protectedWindows = windows;
    PXLogInfo(@"long shot visible capture exclusion (layers=%lu active=%d)",
              (unsigned long)layers.count, self.layerExclusion.isActive);
    [CATransaction flush];
    return self.layerExclusion.isActive; // 新标记等两帧提交；期间窗口仍可见。
}

- (void)captureExcludingWindows:(NSArray<UIWindow *> *)windows
                    completion:(void (^)(UIImage *, BOOL, NSString *, NSError *))completion {
    NSParameterAssert(completion);
    void (^begin)(void) = ^{
        BOOL keepVisible = self.keepsExcludedWindowsVisible && windows.count > 0;
        BOOL needsExclusionCommit = keepVisible && [self pxPrepareVisibleWindows:windows];
        NSMutableArray<NSDictionary *> *hidden = [NSMutableArray array];
        if (windows.count && !keepVisible) {
            for (UIWindow *window in windows) {
                if (window.hidden || !window.rootViewController) continue;
                [hidden addObject:@{@"window": window, @"controller": window.rootViewController}];
                window.hidden = YES;
            }
            [CATransaction flush];
        }
        BOOL detach = self.detachesCapturedImage;
        void (^grabBlock)(void) = ^{
          @autoreleasepool {
            if (detach && windows.count) {
                BOOL liveWindow = NO;
                for (UIWindow *window in windows) if (window.rootViewController) { liveWindow = YES; break; }
                if (!liveWindow) {
                    dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, NO, @"cancelled", nil); });
                    return;
                }
            }
            BOOL layerExcluded = keepVisible && self.layerExclusion.isActive &&
                                 [self.protectedWindows isEqualToArray:windows];
            BOOL canCaptureScreen = !keepVisible || layerExcluded;
            NSString *method = [[self class] resolvedCaptureMethod];
            __block UIImage *image = nil;
            BOOL isPartial = NO;

            @try {
                if (windows.count && !layerExcluded && !self.fallbackOnlyCapture) {
                    image = [self pxSnapshotExcludingWindows:windows];
                    if (image) method = @"private-excluding-windows";
                }
                if (!image && canCaptureScreen && _PXCreateScreenUIImage) {
                    image = _PXCreateScreenUIImage();
                    if (image) method = @"private-uicreate";
                }
                if (!image && canCaptureScreen && _PXGetScreenImage) {
                    CGImageRef screenCG = _PXGetScreenImage();
                    if (screenCG) {
                        image = [UIImage imageWithCGImage:screenCG];
                        CGImageRelease(screenCG);   // UIGetScreenImage 按命名约定返回 retained CGImage
                        if (image) method = @"private-uigetscreen";
                    }
                }
                if (!image && layerExcluded && !self.fallbackOnlyCapture) {
                    image = [self pxSnapshotExcludingWindows:windows];
                    if (image) method = @"private-excluding-windows";
                }
                if (!image && canCaptureScreen) {
                    image = [self pxGrabBySnapshotFallback];
                    isPartial = (image != nil);
                    method = @"fallback-snapshot";
                }
            } @catch (NSException *exception) {
                PXLogWarn(@"capture exception: %@", exception.name);
                image = nil;
            } @finally {
                // 不把后台归一化的耗时计入窗口隐藏时间；取消已销毁的窗口不能复活。
                for (NSDictionary *entry in hidden) {
                    UIWindow *window = entry[@"window"];
                    if (window.rootViewController == entry[@"controller"]) window.hidden = NO;
                }
            }
            if (!image) {
                NSError *error = [NSError errorWithDomain:PXCaptureErrorDomain
                                                     code:PXCaptureErrorCaptureFailed
                                                 userInfo:@{NSLocalizedDescriptionKey: keepVisible ? @"当前系统无法在浮窗可见时排除浮窗抓屏" : @"所有抓取路径均未取得屏幕图像"}];
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
                UIImage *normalized = nil;
                @autoreleasepool {
                    normalized = [self pxNormalizeImage:image
                                            targetPixelSize:targetPixelSize
                                                screenScale:screenScale
                                                      error:&normalizeError];
                    if (detach && normalized) {
                        normalized = [self pxOwnedBitmapImage:normalized];
                        if (!normalized) normalizeError = [NSError errorWithDomain:PXCaptureErrorDomain
                            code:PXCaptureErrorCaptureFailed userInfo:@{NSLocalizedDescriptionKey:@"抓屏位图复制失败"}];
                    }
                    image = nil;
                } // 源表面与归一化临时对象先释放，再通知会话处理下一帧。
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(normalized, isPartial, method, normalizeError);
                });
            });
          }
        };
        if (hidden.count || needsExclusionCommit) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 / 60.0 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), grabBlock);
        } else {
            grabBlock();
        }
    };
    if (NSThread.isMainThread) begin();
    else dispatch_async(dispatch_get_main_queue(), begin);
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

- (UIImage *)pxOwnedBitmapImage:(UIImage *)image {
    CGImageRef source = image.CGImage;
    if (!source) return nil;
    CGImageRef owned = PXLongShotCreateOwnedBitmap(source);
    if (!owned) return nil;
    UIImage *result = [UIImage imageWithCGImage:owned scale:image.scale orientation:UIImageOrientationUp];
    CGImageRelease(owned);
    return result;
}

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
