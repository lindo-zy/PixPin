#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class PXHistoryItem;
@class PXHistoryViewController;

@protocol PXHistoryViewControllerDelegate <NSObject>
- (void)historyViewControllerDidClose:(PXHistoryViewController *)controller;
/// 重新编辑历史图片（协调器以新任务进入编辑器 → 输出为新资源）。
- (void)historyViewController:(PXHistoryViewController *)controller didRequestReeditOfItem:(PXHistoryItem *)item;
@end

/// 截图历史查看器（自持窗口 rootViewController）：缩略图列表、删除、清空、重新编辑。
@interface PXHistoryViewController : UIViewController

@property (nonatomic, weak, nullable) id<PXHistoryViewControllerDelegate> delegate;

@end

NS_ASSUME_NONNULL_END
