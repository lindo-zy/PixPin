#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 系统分享面板。宿主控制器必须是 PixPin 自有窗口内的 VC（SpringBoard 内不能随意找 keyWindow）。
@interface PXSharePresenter : NSObject

+ (void)shareImage:(UIImage *)image
            fromViewController:(nullable UIViewController *)hostViewController
                    completion:(void (^)(BOOL completed))completion;

@end

NS_ASSUME_NONNULL_END
