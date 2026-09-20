#import <UIKit/UIKit.h>
#import "../Common/PXGeometry.h"

NS_ASSUME_NONNULL_BEGIN

@class PXCaptureTask;
@class PXResultBubble;

@protocol PXResultBubbleDelegate <NSObject>
/// 点击气泡主体（打开编辑器/重新编辑）。
- (void)resultBubbleDidTap:(PXResultBubble *)bubble;
/// 气泡完全关闭（含自动消失），持有者应释放引用。
- (void)resultBubbleDidDismiss:(PXResultBubble *)bubble;
/// 快捷动作（保存/分享），仅当气泡携带任务时可用；幂等由任务 claim 保证。
- (void)resultBubble:(PXResultBubble *)bubble didRequestAction:(PXOutputAction)action;
@end

/// 结果预览气泡：独立小窗口，自动消失；缩略图不参与任何历史/相册链路。
@interface PXResultBubble : UIView

@property (nonatomic, weak, nullable) id<PXResultBubbleDelegate> delegate;
@property (nonatomic, strong, readonly, nullable) PXCaptureTask *task;

+ (instancetype)presentWithImage:(nullable UIImage *)thumbnail
                         message:(NSString *)message
                            task:(nullable PXCaptureTask *)task
                        delegate:(id<PXResultBubbleDelegate>)delegate;

/// 动作进行中暂停 4 秒自动消失（分享面板/保存期间宿主窗口必须存活）。
/// push/pop 必须配对；归零后下一次自动消失检查会继续。
- (void)pushDismissalHold;
- (void)popDismissalHold;

/// 主线程更新缩略图（后台渲染完成后回填；气泡已关闭时静默忽略）。
- (void)updateThumbnailImage:(UIImage *)image;

/// 幂等关闭；completion 主线程回调。
- (void)dismissWithCompletion:(nullable void (^)(void))completion;

@end

NS_ASSUME_NONNULL_END
