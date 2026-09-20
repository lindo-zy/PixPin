// 宿主单元测试：只覆盖不依赖 iOS 私有框架/UIImage 的纯逻辑层。
// 在 macOS 上编译运行（见 Tests/run-host-tests.sh）。

#import <Foundation/Foundation.h>
#import "../../Sources/Common/PXGeometry.h"
#import "../../Sources/Common/PXClaimSet.h"
#import "../../Sources/History/PXHistoryItem.h"

static NSInteger PXTestFailures = 0;
static NSInteger PXTestCount = 0;

#define PXCheck(condition, name) do { \
    PXTestCount++; \
    if (!(condition)) { \
        PXTestFailures++; \
        printf("  FAIL: %s (line %d)\n", name, __LINE__); \
    } else { \
        printf("  ok: %s\n", name); \
    } \
} while (0)

#define PXCheckInt(actual, expected, name) do { \
    PXTestCount++; \
    if ((NSInteger)(actual) != (NSInteger)(expected)) { \
        PXTestFailures++; \
        printf("  FAIL: %s (line %d): %ld != %ld\n", name, __LINE__, (long)(actual), (long)(expected)); \
    } else { \
        printf("  ok: %s\n", name); \
    } \
} while (0)

#pragma mark - 状态机

static void testStateMachine(void) {
    printf("[state machine]\n");
    PXCheck(PXCaptureStateCanTransition(PXCaptureStateIdle, PXCaptureStatePreparing), "idle->preparing");
    PXCheck(PXCaptureStateCanTransition(PXCaptureStatePreparing, PXCaptureStateCapturing), "preparing->capturing");
    PXCheck(PXCaptureStateCanTransition(PXCaptureStateCapturing, PXCaptureStateCaptured), "capturing->captured");
    PXCheck(PXCaptureStateCanTransition(PXCaptureStateCaptured, PXCaptureStatePresenting), "captured->presenting");
    PXCheck(PXCaptureStateCanTransition(PXCaptureStateCaptured, PXCaptureStateExporting), "captured->exporting");
    PXCheck(PXCaptureStateCanTransition(PXCaptureStatePresenting, PXCaptureStateEditing), "presenting->editing");
    PXCheck(PXCaptureStateCanTransition(PXCaptureStateEditing, PXCaptureStateExporting), "editing->exporting");
    PXCheck(PXCaptureStateCanTransition(PXCaptureStateEditing, PXCaptureStatePresenting), "editing->presenting");
    PXCheck(PXCaptureStateCanTransition(PXCaptureStateExporting, PXCaptureStateFinished), "exporting->finished");
    PXCheck(PXCaptureStateCanTransition(PXCaptureStateExporting, PXCaptureStateFailed), "exporting->failed");
    PXCheck(PXCaptureStateCanTransition(PXCaptureStatePreparing, PXCaptureStateCancelling), "preparing->cancelling");
    PXCheck(PXCaptureStateCanTransition(PXCaptureStateCancelling, PXCaptureStateCancelled), "cancelling->cancelled");
    PXCheck(PXCaptureStateCanTransition(PXCaptureStatePresenting, PXCaptureStateCancelling), "presenting->cancelling");

    PXCheck(!PXCaptureStateCanTransition(PXCaptureStateIdle, PXCaptureStateCapturing), "!idle->capturing");
    PXCheck(!PXCaptureStateCanTransition(PXCaptureStateFinished, PXCaptureStatePreparing), "!finished->preparing");
    PXCheck(!PXCaptureStateCanTransition(PXCaptureStateCancelled, PXCaptureStatePreparing), "!cancelled->preparing");
    PXCheck(!PXCaptureStateCanTransition(PXCaptureStateFailed, PXCaptureStateCapturing), "!failed->capturing");
    PXCheck(!PXCaptureStateCanTransition(PXCaptureStateCapturing, PXCaptureStateFinished), "!capturing->finished");

    PXCheck(PXCaptureStateIsBusy(PXCaptureStateCapturing), "capturing is busy");
    PXCheck(PXCaptureStateIsBusy(PXCaptureStateExporting), "exporting is busy");
    PXCheck(!PXCaptureStateIsBusy(PXCaptureStateFinished), "finished not busy");
    PXCheck(!PXCaptureStateIsBusy(PXCaptureStateFailed), "failed not busy");
}

#pragma mark - 坐标转换

static void testGeometry(void) {
    printf("[geometry]\n");
    CGSize display = CGSizeMake(390, 844);
    CGSize pixel = CGSizeMake(1170, 2532);

    CGRect full = PXConvertDisplayRectToPixel(CGRectMake(0, 0, 390, 844), display, pixel);
    PXCheckInt(full.origin.x, 0, "full origin.x");
    PXCheckInt(full.origin.y, 0, "full origin.y");
    PXCheckInt(full.size.width, 1170, "full width");
    PXCheckInt(full.size.height, 2532, "full height");

    CGRect part = PXConvertDisplayRectToPixel(CGRectMake(10, 20, 100, 50), display, pixel);
    PXCheckInt(part.origin.x, 30, "part origin.x");
    PXCheckInt(part.origin.y, 60, "part origin.y");
    PXCheckInt(part.size.width, 300, "part width");
    PXCheckInt(part.size.height, 150, "part height");

    CGRect bad = PXConvertDisplayRectToPixel(CGRectMake(0, 0, 100, 100), CGSizeZero, pixel);
    PXCheck(CGRectIsEmpty(bad), "zero display bounds rejected");

    CGRect outside = PXConvertDisplayRectToPixel(CGRectMake(-50, -50, 200, 200), display, pixel);
    PXCheckInt(outside.origin.x, 0, "outside clamped x");
    PXCheckInt(outside.size.width, 450, "outside clamped width");   // 显示 -50..150 → 像素 0..450

    // 横屏一致性：显示坐标/像素坐标同比缩放，换算只依赖比例。
    CGSize landDisplay = CGSizeMake(844, 390);
    CGSize landPixel = CGSizeMake(2532, 1170);
    CGRect landPart = PXConvertDisplayRectToPixel(CGRectMake(10, 20, 100, 50), landDisplay, landPixel);
    PXCheckInt(landPart.origin.x, 30, "landscape origin.x");
    PXCheckInt(landPart.size.height, 150, "landscape height");

    // 选区钳制
    CGRect clamped = PXClampSelectionRect(CGRectMake(350, 800, 100, 100), display, 24.0);
    PXCheck(CGRectGetMaxX(clamped) <= 390.001, "clamp right edge");
    PXCheck(CGRectGetMaxY(clamped) <= 844.001, "clamp bottom edge");

    CGRect tiny = PXClampSelectionRect(CGRectMake(100, 100, 10, 10), display, 24.0);
    PXCheck(CGRectIsEmpty(tiny), "tiny selection rejected");

    CGRect valid = PXClampSelectionRect(CGRectMake(100, 100, 120, 80), display, 24.0);
    PXCheck(CGRectEqualToRect(valid, CGRectMake(100, 100, 120, 80)), "valid selection untouched");
}

#pragma mark - 输出幂等（§9.2）

static void testClaimSet(void) {
    printf("[claim set]\n");
    PXClaimSet *set = [[PXClaimSet alloc] init];

    PXCheck([set claimAction:PXOutputActionSave] == YES, "first claim succeeds");
    PXCheck([set claimAction:PXOutputActionSave] == NO, "duplicate claim rejected");
    PXCheck([set isActionClaimed:PXOutputActionSave] == YES, "claimed state visible");

    PXCheck([set claimAction:PXOutputActionCopy] == YES, "other action claimable");
    PXCheck([set isActionClaimed:PXOutputActionCopy] == YES, "second action claimed");

    [set unclaimAction:PXOutputActionSave];
    PXCheck([set isActionClaimed:PXOutputActionSave] == NO, "unclaim clears state");
    PXCheck([set claimAction:PXOutputActionSave] == YES, "retry after failure succeeds");

    [set reset];
    PXCheck([set isActionClaimed:PXOutputActionSave] == NO && [set isActionClaimed:PXOutputActionCopy] == NO,
            "reset clears all");

    // 并发认领同一动作：只允许一个成功（幂等的线程安全前提）。
    PXClaimSet *shared = [[PXClaimSet alloc] init];
    __block NSInteger winners = 0;
    dispatch_group_t group = dispatch_group_create();
    for (NSInteger i = 0; i < 16; i++) {
        dispatch_group_enter(group);
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
            if ([shared claimAction:7]) {
                @synchronized(shared) { winners++; }
            }
            dispatch_group_leave(group);
        });
    }
    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
    PXCheckInt(winners, 1, "concurrent claim has exactly one winner");
}

#pragma mark - 历史 JSON 往返

static void testHistoryItemRoundTrip(void) {
    printf("[history item]\n");
    PXHistoryItem *item = [[PXHistoryItem alloc] init];
    item.historyID = @"ABCDEF0123456789";
    item.createdAt = [NSDate dateWithTimeIntervalSince1970:1758270000];
    item.mode = PXCaptureModeArea;
    item.originalAssetIdentifier = @"asset-1";
    item.thumbnailPath = @"/tmp/thumb_ABCDEF0123456789.jpg";
    item.originalPath = @"/tmp/original_ABCDEF0123456789.jpg";
    item.pixelWidth = 1170;
    item.pixelHeight = 800;
    item.isEdited = YES;

    NSDictionary *dict = item.dictionaryRepresentation;
    PXHistoryItem *restored = [PXHistoryItem itemWithDictionary:dict];
    PXCheck(restored != nil, "restored from dict");
    PXCheck([restored.historyID isEqualToString:item.historyID], "historyID round trip");
    PXCheck(restored.mode == PXCaptureModeArea, "mode round trip");
    PXCheck([restored.originalAssetIdentifier isEqualToString:@"asset-1"], "asset id round trip");
    PXCheck(restored.pixelWidth == 1170 && restored.pixelHeight == 800, "pixel size round trip");
    PXCheck(restored.isEdited == YES, "isEdited round trip");

    PXCheck([PXHistoryItem itemWithDictionary:nil] == nil, "nil dict rejected");
    PXCheck([PXHistoryItem itemWithDictionary:@{}] == nil, "empty dict rejected");

    NSString *display = item.displayName;
    PXCheck([display isEqualToString:@"区域截图"], "display name");
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        printf("PixPin host unit tests\n");
        testStateMachine();
        testGeometry();
        testClaimSet();
        testHistoryItemRoundTrip();
        printf("\n%d checks, %d failures\n", (int)PXTestCount, (int)PXTestFailures);
        return PXTestFailures > 0 ? 1 : 0;
    }
}
