#import <UIKit/UIKit.h>
#import "../Common/PXGeometry.h"
#import "../Common/PXPreferences.h"

NS_ASSUME_NONNULL_BEGIN

/// 一次截图任务的唯一载体。字段命名与 DEVELOPMENT.md 4.1 对应。
/// 状态只允许 PXCaptureCoordinator 通过转换表修改；输出动作必须先 claim，保证幂等。
@interface PXCaptureTask : NSObject

@property (nonatomic, copy, readonly) NSString *taskID;
@property (nonatomic, assign, readonly) PXCaptureMode mode;
@property (nonatomic, assign, readonly) PXCaptureState state;
@property (nonatomic, strong, readonly) PXConfig *configSnapshot;

/// 抓屏时刻的屏幕几何快照：选区坐标转换只允许使用这组值，不使用实时 bounds。
@property (nonatomic, assign, readonly) CGRect capturedScreenBounds;
@property (nonatomic, assign, readonly) CGFloat capturedScreenScale;

/// 归一化后的原始整屏截图（upright，scale = 屏幕缩放）。
@property (nonatomic, strong, nullable) UIImage *baseImage;
/// 当前结果图（裁剪/编辑后的输出源）。
@property (nonatomic, strong, nullable) UIImage *resultImage;
@property (nonatomic, assign) BOOL isPartialCapture;   // 回退路径仅捕获到 SpringBoard 自身窗口
@property (nonatomic, copy, nullable) NSString *savedAssetIdentifier;  // 相册写入成功后的资产 ID
@property (nonatomic, assign) BOOL isReeditFromHistory;                // 历史重编辑产生的新任务
@property (nonatomic, copy, nullable) NSString *errorCode;
@property (nonatomic, copy, nullable) NSString *errorMessage;

- (instancetype)initWithMode:(PXCaptureMode)mode
                      config:(PXConfig *)config
                screenBounds:(CGRect)screenBounds
                 screenScale:(CGFloat)screenScale;

/// 状态迁移：仅当转换合法时生效（内部持锁）。返回是否成功。
- (BOOL)transitionToState:(PXCaptureState)target;

/// 当前状态（加锁读取，供后台线程做取消态复查）。
- (PXCaptureState)currentState;

/// 输出幂等：同一动作只会被认领一次，重复触发返回 NO。
- (BOOL)claimOutputAction:(PXOutputAction)action;
- (BOOL)isOutputActionClaimed:(PXOutputAction)action;
/// 输出失败后撤回认领，允许气泡/历史入口重试。
- (void)unclaimOutputAction:(PXOutputAction)action;

/// 任务数据目录（临时文件），惰性创建。
- (NSString *)ensureTemporaryDirectory;

NS_ASSUME_NONNULL_END

@end
