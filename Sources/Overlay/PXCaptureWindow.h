#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// PixPin 自有覆盖窗口的统一生命周期封装。
/// 约定（DEVELOPMENT.md 6.2）：
/// - 创建/显示/关闭必须全部在主线程；
/// - 关闭时由持有者释放引用，视图自身的手势/图层随 dealloc 释放；
/// - 抓屏前必须先隐藏全部 PixPin 窗口（由协调器统一调度）。
@interface PXCaptureWindow : UIWindow

/// 独立覆盖窗口：优先绑定 SpringBoard 当前的前台非键盘 UIWindowScene。
+ (instancetype)pxCaptureWindow;

/// 安装覆盖内容。内容始终放在 rootViewController.view 中，禁止直接加到 UIWindow，
/// 避免后续设置 rootViewController 时把覆盖层压在下面。
- (void)hostContentView:(UIView *)contentView;

/// 用于结果气泡：命中根视图空白区时穿透，不阻断整个 SpringBoard 的触摸。
@property (nonatomic, assign) BOOL passesTouchesOutsideHostedContent;

/// 设置页运行诊断使用，不包含用户数据。
@property (nonatomic, copy, readonly) NSString *hostingDescription;

- (void)showAnimated:(BOOL)animated;
/// becomeKey=YES 用于选区/编辑器；结果气泡应传 NO，避免抢键盘焦点。
- (void)showAnimated:(BOOL)animated becomeKey:(BOOL)becomeKey;
/// 关闭并自毁；completion 在主线程回调（窗口已不可见）。幂等。
- (void)hideAndDestroyWithCompletion:(nullable void (^)(void))completion;

@end

NS_ASSUME_NONNULL_END
