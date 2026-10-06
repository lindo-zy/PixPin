#import <UIKit/UIKit.h>
#import "../Common/PXLongShotControl.h"

NS_ASSUME_NONNULL_BEGIN

/// SpringBoard 内的单指 HID 拖动适配器；主线程调用，结束/取消都会发送抬指并移除 displayLink。
/// 能力检查通过只证明符号存在；事件是否被 iOS 16/17 的前台 App 接收必须真机验证。
@interface PXLongShotScroller : NSObject
@property (nonatomic, copy, readonly, nullable) NSString *availabilityError;
@property (nonatomic, copy, readonly, nullable) NSString *targetApplicationIdentifier;
- (BOOL)targetApplicationIsCurrent;
- (void)scrollWithPlan:(PXLongShotScrollPlan)plan duration:(NSTimeInterval)duration
            completion:(void (^)(BOOL completed))completion;
- (void)cancel;
@end

NS_ASSUME_NONNULL_END
