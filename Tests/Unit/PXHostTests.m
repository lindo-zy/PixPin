// 宿主单元测试：只覆盖不依赖 iOS 私有框架/UIImage 的纯逻辑层。
// 在 macOS 上编译运行（见 Tests/run-host-tests.sh）。

#import <Foundation/Foundation.h>
#import "../../Sources/Common/PXGeometry.h"
#import "../../Sources/Common/PXClaimSet.h"
#import "../../Sources/Common/PXConstants.h"
#import "../../Sources/Common/PXExternalRequest.h"
#import "../../Sources/Editor/PXEditorLayout.h"

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

// 窄屏/常见手机/iPad/横屏面板：完整图标集合必须有可点击区域且互不覆盖。
static void testEditorLayout(void) {
    printf("[editor multirow layout]\n");
    for (NSNumber *widthValue in @[@296, @351, @369, @406, @600, @800]) {
        CGFloat width = widthValue.doubleValue;
        for (NSNumber *countValue in @[@12, @16, @24, @30]) {
            NSUInteger count = countValue.unsignedIntegerValue;
            PXEditorGridLayout layout = PXEditorGridMake(width, count, 8);
            BOOL contained = YES, separated = YES, touchable = YES;
            for (NSUInteger i = 0; i < count; i++) {
                CGRect frame = PXEditorGridFrame(layout, i);
                contained &= CGRectContainsRect(CGRectMake(0, 0, width, layout.height), frame);
                touchable &= frame.size.width >= 38 && frame.size.height >= 38;
                for (NSUInteger j = 0; j < i; j++) {
                    separated &= !CGRectIntersectsRect(frame, PXEditorGridFrame(layout, j));
                }
            }
            PXCheck(contained && separated && touchable, "all compact grid items fit without overlap");
            PXCheck(layout.rows >= 2, "tools and actions remain multirow");
        }
    }
    PXCheckInt(PXEditorGridMake(351, 16, 8).rows, 2, "region tools fit in two rows on a narrow phone");
    PXCheckInt(PXEditorGridMake(369, 30, 8).rows, 4, "markup actions and tools fit in four rows");
    PXCheckInt(PXEditorGridMake(369, 0, 6).height, 0, "empty grid consumes no height");
    PXCheck(PXCaptureStateCanTransition(PXCaptureStateEditing, PXCaptureStateCancelling), "markup can cancel without export");

    // 用户选择“整图适屏”时，冻结整屏图应避开面板和独立线宽条。
    CGSize screen = CGSizeMake(393, 852);
    CGRect bottomPanel = CGRectMake(12, 650, 369, 164);
    CGRect bottomViewport = PXEditorMarkupImageViewport(screen, bottomPanel, 59, 0, 34, 0, 52, NO);
    PXCheck(CGRectGetMaxY(bottomViewport) <= CGRectGetMinY(bottomPanel) - 52,
            "bottom panel and slider do not cover image viewport");
    CGFloat fitScale = MIN(bottomViewport.size.width / screen.width, bottomViewport.size.height / screen.height);
    PXCheck(screen.width * fitScale <= bottomViewport.size.width &&
            screen.height * fitScale <= bottomViewport.size.height,
            "full-screen image fits entirely in initial viewport");
    CGRect topPanel = CGRectMake(12, 123, 369, 164);
    CGRect topViewport = PXEditorMarkupImageViewport(screen, topPanel, 59, 0, 34, 0, 52, YES);
    PXCheck(CGRectGetMinY(topViewport) >= CGRectGetMaxY(topPanel) &&
            CGRectGetMaxY(topViewport) <= screen.height - 34,
            "top panel leaves complete visible image viewport");

    CGRect safePanelBounds = CGRectMake(12, 123, 369, 683);
    CGPoint upperLeft = PXEditorClampFloatingOrigin(CGPointMake(-100, -100),
        CGSizeMake(300, 200), safePanelBounds);
    CGPoint lowerRight = PXEditorClampFloatingOrigin(CGPointMake(1000, 1000),
        CGSizeMake(300, 200), safePanelBounds);
    PXCheck(CGPointEqualToPoint(upperLeft, CGPointMake(12, 123)),
            "dragged panel stays inside top and left safe bounds");
    PXCheck(CGPointEqualToPoint(lowerRight, CGPointMake(81, 606)),
            "dragged panel stays inside bottom and right safe bounds");
    CGPoint handle = PXEditorClampFloatingOrigin(CGPointMake(220, 200),
        CGSizeMake(64, 36), safePanelBounds);
    PXCheck(CGPointEqualToPoint(handle, CGPointMake(220, 200)),
            "collapsed handle keeps an in-bounds dragged position");
}

static void testExternalRequests(void) {
    printf("[external requests]\n");
    NSDictionary *valid = @{
        @"pixpin://": (__bridge NSString *)PXDarwinActivate,
        @"pixpin://activate": (__bridge NSString *)PXDarwinActivate,
        @"PIXPIN://ACTIVATE/": (__bridge NSString *)PXDarwinActivate,
        @"pixpin://capture/full": (__bridge NSString *)PXDarwinCaptureFull,
        @"pixpin://capture/area": (__bridge NSString *)PXDarwinCaptureArea,
        @"pixpin://capture/freeze": (__bridge NSString *)PXDarwinCaptureFreeze,
        @"pixpin://capture/instant": (__bridge NSString *)PXDarwinCaptureInstant,
        @"pixpin://capture/markup": (__bridge NSString *)PXDarwinCaptureMarkup,
        @"pixpin://capture/cancel": (__bridge NSString *)PXDarwinCaptureCancel,
        @"pixpin://cancel": (__bridge NSString *)PXDarwinCaptureCancel,
    };
    for (NSString *url in valid) {
        PXCheck([PXNotificationNameForExternalURL([NSURL URLWithString:url]) isEqual:valid[url]],
                url.UTF8String);
    }
    for (NSString *url in @[@"https://capture/full", @"other://activate", @"pixpin://unknown",
                            @"pixpin://capture", @"pixpin://capture/unknown", @"pixpin://capture/full/extra",
                            @"pixpin://capture/full?mode=markup", @"pixpin://activate#full",
                            @"pixpin://user@activate", @"pixpin://activate:80",
                            @"pixpin://capture/%66ull", @"pixpin://capture/../full",
                            @"pixpin://preferences/reload", @"pixpin:///capture/full"]) {
        PXCheck(PXNotificationNameForExternalURL([NSURL URLWithString:url]) == nil, url.UTF8String);
    }
    PXCheck(!PXIsExternalURL(nil), "nil URL belongs to original handler");
    PXCheck(PXIsExternalURL([NSURL URLWithString:@"pixpin://unknown"]),
            "invalid PixPin command is consumed without system fallback");
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        printf("PixPin host unit tests\n");
        testStateMachine();
        testGeometry();
        testClaimSet();
        testEditorLayout();
        testExternalRequests();
        printf("\n%d checks, %d failures\n", (int)PXTestCount, (int)PXTestFailures);
        return PXTestFailures > 0 ? 1 : 0;
    }
}
