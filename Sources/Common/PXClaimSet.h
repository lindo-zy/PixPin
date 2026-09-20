#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 输出动作认领集合：输出幂等的核心逻辑（DEVELOPMENT.md 5.7——同一任务重复触发
/// 不产生重复相册资源/历史记录）。Foundation-only，可在 macOS 宿主上单元测试。
/// 内部自持锁，可跨线程调用；临界区只做集合读写，绝不跨异步边界持有。
@interface PXClaimSet : NSObject

/// 首次认领返回 YES；重复认领返回 NO 且无副作用。
- (BOOL)claimAction:(NSInteger)action;

/// 撤回认领（输出失败后允许气泡/历史入口重试）。
- (void)unclaimAction:(NSInteger)action;

- (BOOL)isActionClaimed:(NSInteger)action;

- (void)reset;

@end

NS_ASSUME_NONNULL_END
