#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

// 本文件只允许依赖 Foundation / CoreGraphics，保证可以在 macOS 宿主上做单元测试。
// 头文件会同时被 .m（C）与 .xm/.mm（C++）包含，C 接口统一加 extern "C"。

#ifdef __cplusplus
extern "C" {
#endif

// MARK: - 枚举定义

typedef NS_ENUM(NSInteger, PXCaptureMode) {
    PXCaptureModeFull = 0,
    PXCaptureModeArea = 1,
    PXCaptureModeFreeze = 2,
    PXCaptureModeInstant = 3,
    PXCaptureModeMarkup = 4,
};

typedef NS_ENUM(NSInteger, PXCaptureState) {
    PXCaptureStateIdle = 0,
    PXCaptureStatePreparing = 1,
    PXCaptureStateCapturing = 2,
    PXCaptureStateCaptured = 3,
    PXCaptureStatePresenting = 4,
    PXCaptureStateEditing = 5,
    PXCaptureStateExporting = 6,
    PXCaptureStateFinished = 7,
    PXCaptureStateCancelling = 8,
    PXCaptureStateCancelled = 9,
    PXCaptureStateFailed = 10,
};

typedef NS_ENUM(NSInteger, PXOutputAction) {
    PXOutputActionSave = 0,
    PXOutputActionCopy = 1,
    PXOutputActionShare = 2,
    PXOutputActionSaveAndCopy = 3,
    PXOutputActionSaveAndDeleteSource = 4,
    /// 内部哨兵值：表示"使用配置的默认动作"/"仅显示预览气泡"，不作为相册/剪贴板动作执行。
    PXOutputActionPreviewOnly = 5,
};

// MARK: - 状态机（集中管理，禁止各控制器自行修改状态）

/// 任务状态机唯一合法转换表；非法转换返回 NO，调用方必须记录日志并忽略。
BOOL PXCaptureStateCanTransition(PXCaptureState from, PXCaptureState to);

/// 是否处于允许接受新任务的状态（Finished/Cancelled/Failed/Idle 之外均视为忙碌）。
BOOL PXCaptureStateIsBusy(PXCaptureState state);

// MARK: - 几何转换

/// 显示坐标（屏幕点）矩形 → 截图像素坐标矩形。
/// displayRect 必须落在 displayBounds 内；转换后向上/向下取整，保证不越界、不丢像素。
CGRect PXConvertDisplayRectToPixel(CGRect displayRect, CGSize displayBounds, CGSize pixelSize);

/// 将选区钳制在容器内，并强制不小于 minimumSize（点单位）。无法满足时返回零矩形。
CGRect PXClampSelectionRect(CGRect rect, CGSize containerSize, CGFloat minimumSize);

/// 保持悬浮图尺寸，只限制位置。大于屏幕时允许拖动查看两端，不缩图。
CGRect PXConstrainFloatingRect(CGRect frame, CGRect bounds);

// MARK: - 展示辅助

NSString *PXStringFromCaptureMode(PXCaptureMode mode);
NSString *PXStringFromOutputAction(PXOutputAction action);
NSString *PXStringFromCaptureState(PXCaptureState state);

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
