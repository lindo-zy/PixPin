#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class PXCaptureTask;
@class PXResultBubble;

@protocol PXResultBubbleDelegate <NSObject>
/// 点击气泡主体或「编辑」按钮（进入编辑器重新编辑）。
- (void)resultBubbleDidTap:(PXResultBubble *)bubble;
/// 气泡完全关闭（含自动消失），持有者应释放引用。
- (void)resultBubbleDidDismiss:(PXResultBubble *)bubble;
@end

/// 结果预览气泡：独立小窗口，自动消失。成功态显示缩略图 + 编辑 + 关闭；
/// 失败态显示错误文字（诊断优先），无编辑按钮。
/// 缩略图不参与任何历史/相册链路。
@interface PXResultBubble : UIView

@property (nonatomic, weak, nullable) id<PXResultBubbleDelegate> delegate;
@property (nonatomic, strong, readonly, nullable) PXCaptureTask *task;

+ (instancetype)presentWithImage:(nullable UIImage *)thumbnail
                         message:(NSString *)message
                            task:(nullable PXCaptureTask *)task
                       succeeded:(BOOL)succeeded
                        delegate:(id<PXResultBubbleDelegate>)delegate;

/// 主线程更新缩略图（后台渲染完成后回填；气泡已关闭时静默忽略）。
- (void)updateThumbnailImage:(UIImage *)image;

/// 幂等关闭；completion 主线程回调。
- (void)dismissWithCompletion:(nullable void (^)(void))completion;

@end

NS_ASSUME_NONNULL_END
