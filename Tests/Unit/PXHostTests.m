// 宿主单元测试：纯逻辑与真实 CG/ImageIO 长图链路；UIKit 图像对象使用最小适配器。
// 在 macOS 上编译运行（见 Tests/run-host-tests.sh）。

#import <Foundation/Foundation.h>
#import "../../Sources/Output/PXLongImageComposer.h"
#import "../../Sources/Output/PXLongPreviewCanvas.h"
#import "../../Sources/Common/PXGeometry.h"
#import "../../Sources/Common/PXClaimSet.h"
#import "../../Sources/Common/PXConstants.h"
#import "../../Sources/Common/PXEditorOrder.h"
#import "../../Sources/Common/PXExternalRequest.h"
#import "../../Sources/Common/PXLongShotAligner.h"
#import "../../Sources/Common/PXLongShotControl.h"
#import "../../Sources/Editor/PXEditorLayout.h"

static NSInteger PXTestFailures = 0;
static NSInteger PXTestCount = 0;
NSInteger PXRunLongShotHIDTests(NSInteger *checkCount);

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
    for (NSNumber *widthValue in @[@296, @369, @600, @800]) {
        CGFloat width = widthValue.doubleValue;
        PXEditorGridLayout baseline = PXEditorGridMake(width, 30, 8);
        for (NSNumber *iconSize in @[@6, @12, @17, @24]) {
            CGFloat scale = iconSize.doubleValue / 17.0;
            PXEditorGridLayout scaled = PXEditorGridMakeScaled(width, 30, 8, scale);
            BOOL contained = YES, separated = YES;
            for (NSUInteger i = 0; i < 30; i++) {
                CGRect frame = PXEditorGridFrame(scaled, i);
                contained &= CGRectContainsRect(CGRectMake(0, 0, width, scaled.height), frame);
                for (NSUInteger j = 0; j < i; j++) {
                    separated &= !CGRectIntersectsRect(frame, PXEditorGridFrame(scaled, j));
                }
            }
            PXCheck(contained && separated, "scaled grid stays inside panel without overlapping controls");
            if (scale <= 1.0) {
                PXCheck(fabs(scaled.buttonWidth - baseline.buttonWidth * scale) < 0.001 &&
                        fabs(scaled.buttonHeight - baseline.buttonHeight * scale) < 0.001 &&
                        fabs(scaled.height - baseline.height * scale) < 0.001,
                        "small icons shrink both button dimensions and occupied height proportionally");
            }
        }
    }
    PXCheckInt(PXEditorGridMakeScaled(369, 0, 8, 6.0 / 17.0).height, 0,
               "empty scaled grid consumes no height");
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

static void testSnapper3Aliases(void) {
    printf("[snapper3 aliases]\n");
    // 字面量必须与 Snapper3 公开文档逐字一致，写错则第三方通知永远无人接收。
    NSDictionary<NSString *, NSString *> *aliases = @{
        @"com.jontelang.snapper3.force.open": (__bridge NSString *)PXDarwinSnapperForceOpen,
        @"com.jontelang.snapper3.forceinstant.open": (__bridge NSString *)PXDarwinSnapperForceInstantOpen,
        @"com.jontelang.snapper3.forcefreeze.open": (__bridge NSString *)PXDarwinSnapperForceFreezeOpen,
        @"com.jontelang.snapper3.close.all": (__bridge NSString *)PXDarwinSnapperCloseAll,
        @"com.jontelang.snapper3.closecrop": (__bridge NSString *)PXDarwinSnapperCloseCrop,
    };
    for (NSString *expected in aliases) {
        PXCheck([aliases[expected] isEqualToString:expected], expected.UTF8String);
    }
}

static void testShellXAliases(void) {
    printf("[shellx aliases]\n");
    // 字面量必须与 SHELLX 插件文档逐字一致；history/openlast/ready 无对应功能，不注册。
    NSDictionary<NSString *, NSString *> *aliases = @{
        @"com.iosdump.screenshotshell.open": (__bridge NSString *)PXDarwinShellXOpen,
        @"com.iosdump.screenshotshell.open.instant": (__bridge NSString *)PXDarwinShellXOpenInstant,
        @"com.iosdump.screenshotshell.open.freeze": (__bridge NSString *)PXDarwinShellXOpenFreeze,
        @"com.iosdump.screenshotshell.close": (__bridge NSString *)PXDarwinShellXClose,
    };
    for (NSString *expected in aliases) {
        PXCheck([aliases[expected] isEqualToString:expected], expected.UTF8String);
    }
}

static void testShellXTriggers(void) {
    printf("[shellx triggers]\n");
    // 出向触发名必须与 SHELLX 二进制内注册的观察者名逐字一致（ShellX 3.1.1 cstring 核对）；
    // 写错则 notify_post 静默无效——没有接收方，也没有任何报错。
    NSDictionary<NSString *, NSString *> *triggers = @{
        @"com.jontelang.snapper3.force.open": (__bridge NSString *)PXShellXTriggerArea,
        @"com.jontelang.snapper3.forceinstant.open": (__bridge NSString *)PXShellXTriggerInstant,
        @"com.jontelang.snapper3.forcefreeze.open": (__bridge NSString *)PXShellXTriggerFreeze,
        @"com.jontelang.snapper3.close.all": (__bridge NSString *)PXShellXTriggerClose,
        @"com.iosdump.screenshotshell/AssistiveScreenshot": (__bridge NSString *)PXShellXTriggerAssistive,
    };
    for (NSString *expected in triggers) {
        PXCheck([triggers[expected] isEqualToString:expected], expected.UTF8String);
    }
    // 区域/即时/冻结/关闭四个触发名与本方 Snapper3 兼容别名同名：自发通知会被自己的
    // 观察者收到，外调方必须做自发自收抑制（协调器按名武装一次）；这条检查钉住该前提。
    PXCheck([(__bridge NSString *)PXShellXTriggerArea isEqualToString:(__bridge NSString *)PXDarwinSnapperForceOpen],
            "area trigger shares snapper3 alias name, self-post suppression required");
}

static void testEditorOrder(void) {
    printf("[editor order]\n");
    NSArray<NSString *> *actionDefaults = [PXEditorOrder defaultActionIdentifiers];
    NSArray<NSString *> *toolDefaults = [PXEditorOrder defaultToolIdentifiers];
    PXCheckInt(actionDefaults.count, 14, "action catalog count");
    PXCheckInt(toolDefaults.count, 15, "tool catalog count");
    PXCheckInt([NSSet setWithArray:actionDefaults].count, 14, "action ids unique");
    PXCheckInt([NSSet setWithArray:toolDefaults].count, 15, "tool ids unique");
    for (NSString *identifier in actionDefaults) {
        PXCheck([PXEditorOrder displayNameForActionIdentifier:identifier].length > 0, "action display name");
    }
    for (NSString *identifier in toolDefaults) {
        PXCheck([PXEditorOrder displayNameForToolIdentifier:identifier].length > 0, "tool display name");
    }

    // 空/nil/garbage 输入一律回退完整默认顺序。
    PXCheck([[PXEditorOrder resolvedActionOrderFromString:nil] isEqualToArray:actionDefaults], "nil csv -> defaults");
    PXCheck([[PXEditorOrder resolvedToolOrderFromString:@""] isEqualToArray:toolDefaults], "empty csv -> defaults");
    PXCheck([[PXEditorOrder resolvedToolOrderFromString:@",, "] isEqualToArray:toolDefaults], "blank csv -> defaults");
    PXCheckInt([PXEditorOrder resolvedToolOrderFromString:@"bogus,brush,nope"].count, 15, "unknown dropped, missing appended");

    // 未知剔除、去重、缺失补尾。
    // "done, bogus, close, undo, close" -> [done, close, undo] + 默认序剩余项，共 14 项。
    NSArray<NSString *> *partial = [PXEditorOrder resolvedActionOrderFromString:@"done, bogus, close, undo, close"];
    PXCheckInt(partial.count, 14, "resolved covers full catalog");
    PXCheck([partial[0] isEqualToString:@"done"], "first preserved");
    PXCheck([partial[1] isEqualToString:@"close"], "second preserved");
    PXCheck([partial[2] isEqualToString:@"undo"], "third preserved");
    PXCheck([partial[3] isEqualToString:@"redo"], "missing appended in default order");
    PXCheck([partial[13] isEqualToString:@"collapse"], "missing appended tail");
    PXCheck(![partial containsObject:@"bogus"], "unknown dropped");

    // 缺失项严格按默认顺序补尾：只排 save 时，其余项依默认顺序跟在后面。
    NSArray<NSString *> *saveFirst = [PXEditorOrder resolvedActionOrderFromString:@"save"];
    PXCheck([saveFirst[0] isEqualToString:@"save"], "single reorder first");
    NSMutableArray<NSString *> *expectedTail = [actionDefaults mutableCopy];
    [expectedTail removeObject:@"save"];
    PXCheck([[saveFirst subarrayWithRange:NSMakeRange(1, expectedTail.count)] isEqualToArray:expectedTail],
            "missing appended matches default order");

    // 完整排列往返无损。
    NSArray<NSString *> *reversed = [[actionDefaults reverseObjectEnumerator] allObjects];
    NSString *csv = [PXEditorOrder stringForOrder:reversed];
    PXCheck([[PXEditorOrder resolvedActionOrderFromString:csv] isEqualToArray:reversed], "full permutation round-trip");
    PXCheck([[PXEditorOrder resolvedActionOrderFromString:[PXEditorOrder stringForOrder:actionDefaults]]
             isEqualToArray:actionDefaults], "defaults round-trip");

    // 隐藏集：未知剔除、去重，空输入为空集。
    PXCheckInt([PXEditorOrder normalizedHiddenFromString:nil defaults:toolDefaults].count, 0, "nil hidden -> empty");
    NSArray<NSString *> *normalized = [PXEditorOrder normalizedHiddenFromString:@"bogus,brush,brush"
                                                                       defaults:toolDefaults];
    PXCheckInt(normalized.count, 1, "hidden normalized");
    PXCheck([normalized containsObject:@"brush"], "hidden keeps known id");
    PXCheck([[PXEditorOrder normalizedHiddenFromString:@" brush ,stamp" defaults:toolDefaults]
             containsObject:@"brush"], "hidden trimmed");

    // 可见过滤：保留相对顺序；全隐藏回退完整顺序。
    NSArray<NSString *> *visible = [PXEditorOrder visibleOrderForOrder:actionDefaults
                                                                hidden:@[@"undo", @"redo", @"bogus"]];
    PXCheckInt(visible.count, 12, "visible count");
    PXCheck(![visible containsObject:@"undo"] && ![visible containsObject:@"redo"], "hidden removed");
    PXCheck([visible[0] isEqualToString:@"close"] && [visible[1] isEqualToString:@"crop"], "visible order preserved");
    NSArray<NSString *> *fallback = [PXEditorOrder visibleOrderForOrder:actionDefaults hidden:actionDefaults];
    PXCheck([fallback isEqualToArray:actionDefaults], "all hidden falls back to full order");

    // 设置预览与真实编辑器共用模式过滤，保留自定义顺序。
    NSArray<NSString *> *custom = [PXEditorOrder resolvedActionOrderFromString:@"save,done,dock,close,collapse"];
    NSArray<NSString *> *imageActions = [PXEditorOrder visibleActionOrderForOrder:custom
                                                                         hidden:@[@"undo"] fullscreenMarkup:NO];
    PXCheck(![imageActions containsObject:@"dock"] && ![imageActions containsObject:@"collapse"],
            "image preview excludes markup-only actions");
    PXCheck(([[imageActions subarrayWithRange:NSMakeRange(0, 3)] isEqualToArray:@[@"save", @"done", @"close"]]),
            "mode filtering preserves custom order including exits");
    NSArray<NSString *> *markupActions = [PXEditorOrder visibleActionOrderForOrder:custom
                                                                          hidden:@[@"undo"] fullscreenMarkup:YES];
    PXCheck([markupActions containsObject:@"dock"] && [markupActions containsObject:@"collapse"],
            "markup preview includes panel controls");
    PXCheck([markupActions containsObject:@"undo"], "corner key undo ignores hidden preference");

    // 四角键写死：图标/名称不吃覆盖，顺序钉在目录默认位。
    PXCheck(([[PXEditorOrder fixedActionIdentifiers] isEqualToArray:@[@"close", @"undo", @"done"]]),
            "fixed corner key ids");
    [PXEditorOrder saveActionName:@"改名" forIdentifier:@"close"];
    [PXEditorOrder saveActionIconName:@"star" forIdentifier:@"close"];
    PXCheck([[PXEditorOrder displayNameForActionIdentifier:@"close"] isEqualToString:@"关闭"],
            "fixed key ignores custom name");
    PXCheck([[PXEditorOrder iconNameForActionIdentifier:@"close"] isEqualToString:@"xmark"],
            "fixed key ignores custom icon");
    [PXEditorOrder saveActionName:nil forIdentifier:@"close"];
    [PXEditorOrder saveActionIconName:nil forIdentifier:@"close"];
    NSArray<NSString *> *pinned = [PXEditorOrder orderWithFixedActionButtonsPinned:
                                   @[@"save", @"undo", @"copy", @"close", @"done"]];
    PXCheck(([pinned isEqualToArray:@[@"close", @"undo", @"save", @"copy", @"done"]]),
            "fixed keys pinned at catalog positions");

    NSArray<NSString *> *safeActions = [PXEditorOrder visibleActionOrderForOrder:custom
                                                                        hidden:@[@"close", @"done"] fullscreenMarkup:NO];
    PXCheck(([[safeActions subarrayWithRange:NSMakeRange(0, 3)] isEqualToArray:@[@"save", @"done", @"close"]]),
            "legacy hidden exits remain visible at their configured positions");
    PXCheck([[PXEditorOrder visibleOrderForOrder:toolDefaults hidden:toolDefaults] isEqualToArray:toolDefaults],
            "empty tool preview matches editor fallback");
}

static void testEditorOverrides(void) {
    printf("[editor overrides]\n");
    NSString *identifier = @"brush";
    PXCheck([PXEditorOrder customNameForToolIdentifier:identifier] == nil, "no override by default");
    PXCheck([[PXEditorOrder displayNameForToolIdentifier:identifier] isEqualToString:@"画笔"], "default name");
    PXCheck([[PXEditorOrder iconNameForToolIdentifier:identifier] isEqualToString:@"paintbrush"], "default icon");

    // 名称覆盖：优先于目录默认；带脏字符清洗、超长截断。
    [PXEditorOrder saveToolName:@"我的画笔,=x" forIdentifier:identifier];
    NSString *saved = [PXEditorOrder customNameForToolIdentifier:identifier];
    PXCheck([saved isEqualToString:@"我的画笔 x"], "name sanitized");
    PXCheck([[PXEditorOrder displayNameForToolIdentifier:identifier] isEqualToString:@"我的画笔 x"], "custom name wins");
    [PXEditorOrder saveToolName:@"一二三四五六七八九十一二三" forIdentifier:identifier];
    PXCheckInt([PXEditorOrder customNameForToolIdentifier:identifier].length, 12, "name truncated to 12");

    // 图标覆盖：优先于目录默认；清空恢复默认。
    [PXEditorOrder saveToolIconName:@"star" forIdentifier:identifier];
    PXCheck([[PXEditorOrder iconNameForToolIdentifier:identifier] isEqualToString:@"star"], "custom icon wins");
    PXCheck([[PXEditorOrder defaultIconNameForToolIdentifier:identifier] isEqualToString:@"paintbrush"], "default icon intact");
    [PXEditorOrder saveToolIconName:nil forIdentifier:identifier];
    PXCheck([[PXEditorOrder iconNameForToolIdentifier:identifier] isEqualToString:@"paintbrush"], "icon override cleared");
    [PXEditorOrder saveToolName:nil forIdentifier:identifier];
    PXCheck([PXEditorOrder customNameForToolIdentifier:identifier] == nil, "name override cleared");
    PXCheck([[PXEditorOrder displayNameForToolIdentifier:identifier] isEqualToString:@"画笔"], "name back to default");

    // 图标点大小：默认 17，夹取 10–20。
    PXCheckInt((NSInteger)[PXEditorOrder buttonIconPointSize], 17, "icon size default");
    [PXEditorOrder saveButtonIconPointSize:99.0];
    PXCheckInt((NSInteger)[PXEditorOrder buttonIconPointSize], 20, "icon size clamped high");
    [PXEditorOrder saveButtonIconPointSize:5.0];
    PXCheckInt((NSInteger)[PXEditorOrder buttonIconPointSize], 10, "icon size clamped low");
    [PXEditorOrder saveButtonIconPointSize:17.0];
}

static void testSelectionOrder(void) {
    printf("[selection order]\n");
    NSArray<NSString *> *defaults = [PXEditorOrder defaultSelectionIdentifiers];
    PXCheckInt(defaults.count, 13, "selection catalog count");
    PXCheckInt([NSSet setWithArray:defaults].count, 13, "selection ids unique");
    // SHELLX 扩展组是目录的子集：工具栏按运行时可用性整体增删，目录解析无需特判。
    NSArray<NSString *> *shellx = [PXEditorOrder shellxSelectionIdentifiers];
    PXCheckInt(shellx.count, 5, "shellx group count");
    for (NSString *identifier in shellx) {
        PXCheck([defaults containsObject:identifier], "shellx id inside selection catalog");
        PXCheck([PXEditorOrder displayNameForSelectionIdentifier:identifier].length > 0, "selection display name");
        PXCheck([PXEditorOrder iconNameForSelectionIdentifier:identifier].length > 0, "selection icon name");
    }
    for (NSString *identifier in defaults) {
        PXCheck([PXEditorOrder displayNameForSelectionIdentifier:identifier].length > 0, "selection display name");
        PXCheck([PXEditorOrder iconNameForSelectionIdentifier:identifier].length > 0, "selection icon name");
    }
    PXCheck([[PXEditorOrder resolvedSelectionOrderFromString:nil] isEqualToArray:defaults], "nil csv -> defaults");
    NSArray<NSString *> *reordered = [PXEditorOrder resolvedSelectionOrderFromString:@"float,save,bogus,cancel"];
    PXCheck([reordered[0] isEqualToString:@"float"] && [reordered[1] isEqualToString:@"save"],
            "selection reorder preserved, missing appended");

    // 区域/冻结：自定义顺序 + 出口兜底（取消/完成不可隐藏，保持配置位置）。
    // SHELLX 扩展组按目录规则补尾在 confirm 之后，出口不再必然是末位。
    NSArray<NSString *> *visible = [PXEditorOrder visibleSelectionOrderForOrder:reordered
                                                                        hidden:@[@"float", @"cancel", @"confirm"]
                                                                       instant:NO];
    PXCheck(![visible containsObject:@"float"], "float hidable");
    PXCheck([visible indexOfObject:@"cancel"] == 1, "cancel stays at configured position");
    // confirm 的配置位次 = 完整顺序去掉被隐藏的 float 后的原位（ShellX 组只补尾不插队）。
    NSMutableArray<NSString *> *expectedOrder = [reordered mutableCopy];
    [expectedOrder removeObject:@"float"];
    PXCheck([visible indexOfObject:@"confirm"] == [expectedOrder indexOfObject:@"confirm"],
            "confirm stays at configured position");
    PXCheck([visible.lastObject isEqualToString:@"shellxclose"], "shellx group appended at tail");

    // 即时模式：固定快速三键。
    NSArray<NSString *> *instant = [PXEditorOrder visibleSelectionOrderForOrder:defaults hidden:nil instant:YES];
    PXCheck(([[instant subarrayWithRange:NSMakeRange(0, 3)] isEqualToArray:@[@"cancel", @"selectall", @"confirm"]]),
            "instant filtered to quick trio");
    // 隐藏非出口键后即时模式只剩出口两键，仍不允许空工具栏。
    NSArray<NSString *> *safe = [PXEditorOrder visibleSelectionOrderForOrder:defaults
                                                                     hidden:@[@"selectall", @"cancel", @"confirm"]
                                                                    instant:YES];
    PXCheck(safe.count == 2 && [safe.firstObject isEqualToString:@"cancel"] &&
            [safe.lastObject isEqualToString:@"confirm"], "instant exits always visible");
}

static void testSelectionOverrides(void) {
    printf("[selection overrides]\n");
    // 新键先备份再清空，测试后恢复，避免污染宿主 CFPreferences。
    NSArray *keys = @[PXKeySelectionButtonNames, PXKeySelectionButtonIcons, PXKeySelectionButtonIconStyle];
    CFStringRef domain = (__bridge CFStringRef)PXPreferencesDomain;
    NSMutableDictionary *backup = [NSMutableDictionary dictionary];
    for (NSString *key in keys) {
        backup[key] = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, domain)) ?: NSNull.null;
        CFPreferencesSetAppValue((__bridge CFStringRef)key, NULL, domain);
    }
    CFPreferencesAppSynchronize(domain);

    NSString *identifier = @"editor";
    PXCheck([PXEditorOrder customNameForSelectionIdentifier:identifier] == nil, "no selection name override by default");
    PXCheck([[PXEditorOrder displayNameForSelectionIdentifier:identifier] isEqualToString:@"编辑"], "selection default name");
    PXCheck([[PXEditorOrder iconNameForSelectionIdentifier:identifier] isEqualToString:@"pencil.and.outline"], "selection default icon");
    PXCheck([[PXEditorOrder defaultIconNameForSelectionIdentifier:identifier] isEqualToString:@"pencil.and.outline"], "selection default icon accessor");

    // 名称覆盖：清洗破坏 CSV 的字符后生效，显示名合并覆盖。
    [PXEditorOrder saveSelectionName:@"改图,=x" forIdentifier:identifier];
    PXCheck([[PXEditorOrder customNameForSelectionIdentifier:identifier] isEqualToString:@"改图 x"], "selection name sanitized");
    PXCheck([[PXEditorOrder displayNameForSelectionIdentifier:identifier] isEqualToString:@"改图 x"], "selection custom name wins");

    // 图标覆盖：优先于目录默认；清空恢复默认。
    [PXEditorOrder saveSelectionIconName:@"star" forIdentifier:identifier];
    PXCheck([[PXEditorOrder iconNameForSelectionIdentifier:identifier] isEqualToString:@"star"], "selection custom icon wins");
    [PXEditorOrder saveSelectionIconName:nil forIdentifier:identifier];
    [PXEditorOrder saveSelectionName:nil forIdentifier:identifier];
    PXCheck([[PXEditorOrder displayNameForSelectionIdentifier:identifier] isEqualToString:@"编辑"], "selection name override cleared");
    PXCheck([[PXEditorOrder iconNameForSelectionIdentifier:identifier] isEqualToString:@"pencil.and.outline"], "selection icon override cleared");

    // 旧布尔配置必须原样保留，新增值 2 不能被当作 YES 丢失图文样式。
    PXCheckInt([PXEditorOrder selectionButtonStyle], PXSelectionButtonStyleIcon, "selection style defaults to icon");
    CFPreferencesSetAppValue((__bridge CFStringRef)PXKeySelectionButtonIconStyle, kCFBooleanFalse, domain);
    PXCheckInt([PXEditorOrder selectionButtonStyle], PXSelectionButtonStyleText, "legacy false remains text");
    CFPreferencesSetAppValue((__bridge CFStringRef)PXKeySelectionButtonIconStyle, kCFBooleanTrue, domain);
    PXCheckInt([PXEditorOrder selectionButtonStyle], PXSelectionButtonStyleIcon, "legacy true remains icon");
    [PXEditorOrder saveSelectionButtonStyle:PXSelectionButtonStyleIconAndText];
    PXCheckInt([PXEditorOrder selectionButtonStyle], PXSelectionButtonStyleIconAndText, "icon and text persisted distinctly");
    [PXEditorOrder saveSelectionButtonStyle:PXSelectionButtonStyleText];
    PXCheckInt([PXEditorOrder selectionButtonStyle], PXSelectionButtonStyleText, "combined style can switch to text");
    [PXEditorOrder saveSelectionButtonStyle:PXSelectionButtonStyleIcon];
    PXCheckInt([PXEditorOrder selectionButtonStyle], PXSelectionButtonStyleIcon, "selection style reset to icon");
    for (id invalid in @[@(-1), @3, @1.5, @"2"]) {
        CFPreferencesSetAppValue((__bridge CFStringRef)PXKeySelectionButtonIconStyle,
                                 (__bridge CFTypeRef)invalid, domain);
        PXCheckInt([PXEditorOrder selectionButtonStyle], PXSelectionButtonStyleIcon, "invalid stored style defaults to icon");
    }

    for (NSString *key in keys) {
        id value = backup[key];
        CFPreferencesSetAppValue((__bridge CFStringRef)key,
                                 (value == NSNull.null || value == nil) ? NULL : (__bridge CFTypeRef)value,
                                 domain);
    }
    CFPreferencesAppSynchronize(domain);
}

static void testIndependentButtonPreferences(void) {
    printf("[independent button preferences]\n");
    NSArray *keys = @[@"MarkupActionOrder", @"MarkupToolOrder", @"MarkupActionHidden", @"MarkupToolHidden",
                      PXKeyEditorActionOrder, PXKeyEditorToolOrder, PXKeyEditorActionHidden, PXKeyEditorToolHidden,
                      PXKeySelectionButtonOrder, PXKeySelectionButtonHidden];
    CFStringRef domain = (__bridge CFStringRef)PXPreferencesDomain;
    NSMutableDictionary *backup = [NSMutableDictionary dictionary];
    for (NSString *key in keys) {
        backup[key] = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, domain)) ?: NSNull.null;
        CFPreferencesSetAppValue((__bridge CFStringRef)key, NULL, domain);
    }
    CFPreferencesAppSynchronize(domain);
    [PXEditorOrder saveActionOrderString:@"save,close,undo"];
    [PXEditorOrder saveToolOrderString:@"arrow,brush"];
    [PXEditorOrder saveActionHiddenString:@"copy"];
    [PXEditorOrder saveToolHiddenString:@"pan"];
    [PXEditorOrder saveSelectionOrderString:@"float,copy,cancel"];
    [PXEditorOrder saveSelectionHiddenString:@"save"];
    PXCheck([[[PXEditorOrder currentActionOrderForFullscreenMarkup:YES] firstObject] isEqual:@"save"], "markup inherits legacy action order once");
    PXCheck([[[PXEditorOrder currentToolOrderForFullscreenMarkup:YES] firstObject] isEqual:@"arrow"], "markup inherits legacy tool order once");
    PXCheck([[PXEditorOrder currentActionHiddenForFullscreenMarkup:YES] containsObject:@"copy"], "markup inherits action switches");
    PXCheck([[PXEditorOrder currentToolHiddenForFullscreenMarkup:YES] containsObject:@"pan"], "markup inherits tool switches");

    [PXEditorOrder saveActionOrderString:@"undo,save" fullscreenMarkup:NO];
    [PXEditorOrder saveToolHiddenString:@"arrow" fullscreenMarkup:NO];
    PXCheck([[[PXEditorOrder currentActionOrderForFullscreenMarkup:YES] firstObject] isEqual:@"save"], "later editor changes do not alter markup order");
    PXCheck([[PXEditorOrder currentToolHiddenForFullscreenMarkup:YES] containsObject:@"pan"], "later editor changes do not alter markup switches");

    [PXEditorOrder saveActionOrderString:@"copy,save" fullscreenMarkup:YES];
    [PXEditorOrder saveToolOrderString:@"mosaic,brush" fullscreenMarkup:YES];
    [PXEditorOrder saveActionHiddenString:@"save,close,done" fullscreenMarkup:YES];
    [PXEditorOrder saveToolHiddenString:@"brush" fullscreenMarkup:YES];
    PXCheck([[[PXEditorOrder currentActionOrder] firstObject] isEqual:@"undo"], "markup save leaves image editor order alone");
    PXCheck([[[PXEditorOrder currentToolOrder] firstObject] isEqual:@"arrow"], "markup tool save leaves image editor alone");
    PXCheck([[[PXEditorOrder currentSelectionOrder] firstObject] isEqual:@"float"], "markup save leaves region order alone");
    PXCheck([[PXEditorOrder currentSelectionHidden] containsObject:@"save"], "markup save leaves region switches alone");
    NSArray *visible = [PXEditorOrder visibleActionOrderForOrder:[PXEditorOrder currentActionOrderForFullscreenMarkup:YES]
        hidden:[PXEditorOrder currentActionHiddenForFullscreenMarkup:YES] fullscreenMarkup:YES];
    PXCheck([visible containsObject:@"close"] && [visible containsObject:@"done"] && ![visible containsObject:@"save"], "markup keeps exits while honoring other switches");

    [PXEditorOrder saveSelectionOrderString:nil];
    [PXEditorOrder saveSelectionHiddenString:nil];
    PXCheck([[[PXEditorOrder currentActionOrderForFullscreenMarkup:YES] firstObject] isEqual:@"copy"], "region reset leaves markup order alone");
    PXCheck([[PXEditorOrder currentToolHiddenForFullscreenMarkup:YES] containsObject:@"brush"], "region reset leaves markup tool switches alone");
    [PXEditorOrder saveActionOrderString:nil fullscreenMarkup:YES];
    [PXEditorOrder saveToolOrderString:nil fullscreenMarkup:YES];
    [PXEditorOrder saveActionHiddenString:nil fullscreenMarkup:YES];
    [PXEditorOrder saveToolHiddenString:nil fullscreenMarkup:YES];
    PXCheck([[PXEditorOrder currentActionOrderForFullscreenMarkup:YES] isEqual:[PXEditorOrder defaultActionIdentifiers]], "markup reset does not re-inherit legacy order");
    PXCheck([[PXEditorOrder currentToolOrderForFullscreenMarkup:YES] isEqual:[PXEditorOrder defaultToolIdentifiers]], "markup tools reset independently");
    PXCheck([PXEditorOrder currentActionHiddenForFullscreenMarkup:YES].count == 0 &&
            [PXEditorOrder currentToolHiddenForFullscreenMarkup:YES].count == 0, "markup reset clears switches without re-inheriting");
    PXCheck([[[PXEditorOrder currentActionOrder] firstObject] isEqual:@"undo"] &&
            [[PXEditorOrder currentToolHidden] containsObject:@"arrow"], "markup reset preserves ordinary editor preferences");
    for (NSString *key in keys) {
        id value = backup[key];
        CFPreferencesSetAppValue((__bridge CFStringRef)key, value == NSNull.null ? NULL : (__bridge CFPropertyListRef)value, domain);
    }
    CFPreferencesAppSynchronize(domain);
}

static void testFloatingOriginalRect(void) {
    printf("[floating original rect]\n");
    CGRect portrait = CGRectMake(0, 0, 390, 844);
    CGRect selection = CGRectMake(24, 190, 300, 430);
    PXCheck(CGRectEqualToRect(PXConstrainFloatingRect(selection, portrait), selection), "float keeps selected position and size");
    CGRect small = CGRectMake(0, 0, 44, 44);
    PXCheck(CGRectEqualToRect(PXConstrainFloatingRect(small, portrait), small), "small edge selection is neither expanded nor moved into safe area");
    PXCheck(CGRectEqualToRect(PXConstrainFloatingRect(portrait, portrait), portrait), "full-screen selection remains full size");
    CGRect bottom = CGRectMake(300, 750, 90, 94);
    PXCheck(CGRectEqualToRect(PXConstrainFloatingRect(bottom, portrait), bottom), "bottom-right selection stays at exact source position");
    CGRect moved = PXConstrainFloatingRect(CGRectMake(-30, 900, 300, 430), portrait);
    PXCheck(CGRectEqualToRect(moved, CGRectMake(0, 414, 300, 430)), "drag clamps origin without changing dimensions");
    CGRect landscape = CGRectMake(0, 0, 844, 390);
    CGRect rotated = PXConstrainFloatingRect(selection, landscape);
    PXCheck(CGSizeEqualToSize(rotated.size, selection.size) && rotated.origin.y == 0, "rotation keeps oversized image unscaled");
    CGRect otherEnd = PXConstrainFloatingRect(CGRectMake(24, -200, 300, 430), landscape);
    PXCheck(otherEnd.origin.y == -40 && otherEnd.size.height == 430, "oversized image can pan to its far edge");
    PXCheck(CGRectEqualToRect(PXConstrainFloatingRect(CGRectNull, portrait), CGRectZero), "invalid float geometry is rejected");
    PXCheck(CGRectEqualToRect(PXConstrainFloatingRect(selection, CGRectZero), CGRectZero), "empty host geometry is rejected");
}

#pragma mark - 长截图对齐

// 合成“页面”签名：整数哈希（雪崩）生成高熵内容，等价真实屏幕的判别力，
// 避免代数函数在模数组合下出现近似周期混染导致的多解歧义。
static uint8_t PXTestPageHash(NSUInteger x) {
    x = (x ^ 61u) ^ (x >> 16);
    x *= 9u;
    x ^= x >> 4;
    x *= 0x27d4eb2du;
    x ^= x >> 15;
    return (uint8_t)(x & 0xFF);
}

static void PXFillPageSigs(uint8_t *sigs, NSInteger rows, NSInteger pageOffset) {
    for (NSInteger r = 0; r < rows; r++) {
        for (NSInteger c = 0; c < PXLongShotSigWidth; c++) {
            sigs[r * PXLongShotSigWidth + c] = PXTestPageHash((NSUInteger)(pageOffset + r) * 131u + (NSUInteger)c);
        }
    }
}

static uint8_t *PXAllocSigs(NSInteger rows) {
    return (uint8_t *)calloc((size_t)rows * PXLongShotSigWidth, 1);
}

static void testLongShotAligner(void) {
    printf("[long shot aligner]\n");
    NSInteger rows = 2000;
    uint8_t *prev = PXAllocSigs(rows);
    uint8_t *cur = PXAllocSigs(rows);
    PXFillPageSigs(prev, rows, 0);

    PXFillPageSigs(cur, rows, 800);
    PXLongShotFrameMatch match = PXLongShotMatchFrames(prev, cur, rows, -1, -1);
    PXCheckInt(match.kind, PXLongShotMatchForward, "forward frame recognized");
    PXCheckInt(match.shiftRows, 800, "forward displacement resolved exactly");
    PXFillPageSigs(cur, rows, 1936);
    match = PXLongShotMatchFrames(prev, cur, rows, 0, 0);
    PXCheckInt(match.shiftRows, 1936, "64-row overlap remains usable");
    PXFillPageSigs(cur, rows, 10);
    match = PXLongShotMatchFrames(prev, cur, rows, 0, 0);
    PXCheckInt(match.shiftRows, 10, "small real displacement retained");
    memset(cur, 42, (size_t)rows * PXLongShotSigWidth);
    PXCheckInt(PXLongShotMatchFrames(prev, cur, rows, 0, 0).kind,
               PXLongShotMatchUncertain, "changed uniform content is never appended whole");
    for (NSInteger r = 0; r < rows; r++)
        for (NSInteger c = 0; c < PXLongShotSigWidth; c++)
            cur[r * PXLongShotSigWidth + c] = (uint8_t)((r * 31 + c * 17) % 253);
    PXCheckInt(PXLongShotMatchFrames(prev, cur, rows, 0, 0).kind,
               PXLongShotMatchUncertain, "page replacement stops stitching");
    // 周期页即使有纹理也不能选择任意一个等价位移。
    for (NSInteger r = 0; r < rows; r++)
        for (NSInteger c = 0; c < PXLongShotSigWidth; c++) {
            prev[r * PXLongShotSigWidth + c] = (uint8_t)((r % 80) * 3 + c % 8);
            cur[r * PXLongShotSigWidth + c] = (uint8_t)(((r + 20) % 80) * 3 + c % 8);
        }
    PXCheckInt(PXLongShotMatchFrames(prev, cur, rows, 0, 0).kind,
               PXLongShotMatchUncertain, "periodic displacement is rejected");
    PXCheckInt(PXLongShotMatchFrames(NULL, cur, rows, 0, 0).kind,
               PXLongShotMatchUncertain, "missing frame is rejected");
    PXFillPageSigs(prev, rows, 0);
    PXFillPageSigs(cur, rows, 600);
    const NSInteger top = 150, bottom = 120;
    memcpy(cur, prev, (size_t)top * PXLongShotSigWidth);
    memcpy(cur + (rows-bottom)*64, prev + (rows-bottom)*64, (size_t)bottom*64);
    match = PXLongShotMatchFrames(prev, cur, rows, -1, -1);
    PXCheckInt(match.kind, PXLongShotMatchForward, "fixed header/footer do not block motion");
    PXCheckInt(match.fixedTopRows, top, "fixed header identified");
    PXCheckInt(match.fixedBottomRows, bottom, "fixed footer identified");
    PXCheckInt(match.shiftRows, 600, "body displacement ignores fixed bars");
    match = PXLongShotMatchFrames(cur, prev, rows, top, bottom);
    PXCheckInt(match.kind, PXLongShotMatchReverse, "reverse scroll does not append");
    PXCheckInt(PXLongShotMatchFrames(prev, prev, rows, top, bottom).kind,
               PXLongShotMatchDuplicate, "stationary full-screen frame does not append");
    PXCheckInt(PXLongShotMatchFrames(prev, cur, rows, rows, bottom).kind,
               PXLongShotMatchUncertain, "invalid body bounds rejected");

    // 行签名：单行已知 RGBA 缓冲按列宽采样求亮度。
    NSInteger width = 256;
    uint8_t *rgba = (uint8_t *)calloc((size_t)width * 4, 1);
    for (NSInteger x = 0; x < width; x++) {
        rgba[x * 4 + 0] = 100;   // R
        rgba[x * 4 + 1] = 200;   // G
        rgba[x * 4 + 2] = 50;    // B
        rgba[x * 4 + 3] = 255;
    }
    uint8_t sig[PXLongShotSigWidth];
    PXLongShotComputeRowSignature(rgba, width, width * 4, 0, sig);
    uint8_t expected = (uint8_t)((77 * 100 + 150 * 200 + 29 * 50) >> 8);
    BOOL allMatch = YES;
    for (NSInteger c = 0; c < PXLongShotSigWidth; c++) {
        if (sig[c] != expected) { allMatch = NO; break; }
    }
    PXCheck(allMatch, "row signature samples constant-color luma");
    free(rgba);
    free(prev);
    free(cur);
}

static void PXFillTextPageSigs(uint8_t *sigs, NSInteger rows, NSInteger offset) {
    for (NSInteger r = 0; r < rows; r++) {
        NSInteger absolute = offset + r, line = absolute / 48, local = absolute % 48;
        uint8_t pattern = PXTestPageHash((NSUInteger)line + 97);
        for (NSInteger c = 0; c < PXLongShotSigWidth; c++) {
            BOOL ink = local >= 16 && local < 32 && c >= 8 && c < 24 + pattern % 30 && ((pattern >> (c % 8)) & 1);
            sigs[r * PXLongShotSigWidth + c] = ink ? 55 : 245;
        }
    }
}

static void testManualLongShot(void) {
    printf("[manual fullscreen long shot]\n");
    const NSInteger rows = 2000;
    uint8_t *prev = calloc((size_t)rows * PXLongShotSigWidth, 1);
    uint8_t *cur = calloc((size_t)rows * PXLongShotSigWidth, 1);
    PXFillTextPageSigs(prev, rows, 0);
    PXFillTextPageSigs(cur, rows, 800);
    PXCheckInt(PXLongShotMatchFrames(prev, cur, rows, 0, 0).shiftRows, 800,
               "distributed matching finds sparse-text displacement");
    PXCheck(!PXLongShotSignaturesAreDuplicate(prev, rows, cur, rows), "scrolled text is not dropped as duplicate");
    PXFillTextPageSigs(cur, rows, 0);
    PXCheck(PXLongShotSignaturesAreDuplicate(prev, rows, cur, rows), "unchanged sparse text is detected independently of overlap search");
    memset(prev, 245, (size_t)rows * PXLongShotSigWidth);
    memset(cur, 245, (size_t)rows * PXLongShotSigWidth);
    PXCheck(PXLongShotSignaturesAreDuplicate(prev, rows, cur, rows), "unchanged plain page is detected");
    memset(cur, 55, (size_t)rows * PXLongShotSigWidth);
    PXCheck(!PXLongShotSignaturesAreDuplicate(prev, rows, cur, rows), "changed plain page is not duplicate");
    PXCheck(!PXLongShotSignaturesAreDuplicate(NULL, rows, cur, rows), "missing signature is rejected");
    free(prev); free(cur);

    CGColorSpaceRef tileSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef tileContext = CGBitmapContextCreate(NULL, 8, 10, 8, 0, tileSpace, kCGImageAlphaPremultipliedLast);
    CGContextRef output = CGBitmapContextCreate(NULL, 8, 16, 8, 0, tileSpace, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(tileSpace);
    if (tileContext && output) {
        for (NSInteger row = 0; row < 10; row++) {
            CGContextSetRGBFillColor(tileContext, (row + 1) / 16.0, 0, 0, 1);
            CGContextFillRect(tileContext, CGRectMake(0, 9 - row, 8, 1));
        }
        CGImageRef fullFrame = CGBitmapContextCreateImage(tileContext);
        // 首帧去掉两行页脚；新帧只追加末尾六行；页脚只保留一次。
        PXLongShotDrawTile(output, fullFrame, 16, 0, 8, 10, 0, 2, 1);
        PXLongShotDrawTile(output, fullFrame, 16, 8, 8, 10, 4, 0, 1);
        uint8_t *data = CGBitmapContextGetData(output);
        BOOL correct = YES;
        for (NSInteger row = 0; row < 14; row++) {
            NSInteger sourceRow = row < 8 ? row : row - 4;
            NSInteger expectedRed = (NSInteger)lround((sourceRow + 1) * 255.0 / 16.0);
            if (labs(data[row * CGBitmapContextGetBytesPerRow(output)] - expectedRed) > 1) correct = NO;
        }
        PXCheck(correct, "shared crop drawing preserves exact source rows without repeated footer");
        CGImageRelease(fullFrame);
    } else PXCheck(NO, "cropped renderer contexts available");
    if (tileContext) CGContextRelease(tileContext);
    if (output) CGContextRelease(output);

    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, 958, 16384, 8, 0, space, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    PXCheck(context != NULL, "long image native bitmap created");
    if (context) {
        CGContextSetRGBFillColor(context, 0, 0, 0, 1);
        CGContextFillRect(context, CGRectMake(0, 0, 958, 16384));
        CGContextSetRGBFillColor(context, 1, 1, 1, 1);
        CGFloat p = 16384.0 / 20000.0;
        for (NSInteger i = 0; i < 10; i++) CGContextFillRect(context, PXLongShotTileRect(16384, i * 2000, 1170, 2000, p));
        uint8_t *bytes = CGBitmapContextGetData(context);
        size_t stride = CGBitmapContextGetBytesPerRow(context), black = 0;
        for (NSInteger r = 0; r < 16384; r++) if (bytes[r * stride + 400 * 4] == 0) black++;
        PXCheck(black == 0, "scaled long image has no black gaps or missing tail tile");
        CGContextRelease(context);
    }
    CGFloat p = 264.0 / 1170.0;
    CGRect tile = PXLongShotTileRect(7575, 1200, 1170, 2000, p);
    PXCheck(fabs(7575 - CGRectGetMaxY(tile) - 1200 * p) < 0.001, "preview offset uses the same scale as tile dimensions");
}

#pragma mark - 长截图模式与外部路由

static void testLongShotScrollPlan(void) {
    printf("[long shot scroll plan]\n");
    CGRect bounds = CGRectMake(0, 0, 390, 844);
    CGRect panel = CGRectMake(274, 10, 104, 242);   // 右上 HUD 小窗
    PXLongShotScrollPlan plan;
    PXCheck(PXLongShotBuildScrollPlan(bounds, bounds, panel, &plan), "portrait fullscreen has usable band");
    PXCheck(CGRectContainsPoint(bounds, plan.start) && CGRectContainsPoint(bounds, plan.end),
            "swipe stays on screen");
    PXCheck(plan.start.y >= CGRectGetMaxY(panel) + 12, "swipe starts below HUD panel");
    PXCheck(plan.end.y > CGRectGetMaxY(panel), "swipe never crosses HUD panel");
    PXCheck(plan.start.y > plan.end.y && plan.start.y - plan.end.y <= 320, "upward drag is bounded");
    PXCheck(plan.start.y - plan.end.y >= 80, "drag distance is meaningful");

    CGRect viewport = CGRectMake(24, 120, 340, 640);
    PXCheck(PXLongShotBuildScrollPlan(viewport, bounds, panel, &plan), "selection viewport plans a swipe");
    PXCheck(CGRectContainsPoint(viewport, plan.start) && plan.start.x == CGRectGetMidX(viewport),
            "swipe centered inside selection viewport");

    PXCheck(!PXLongShotBuildScrollPlan(CGRectMake(280, 20, 90, 150), bounds, panel, &plan),
            "viewport hidden behind HUD panel is rejected");
    PXCheck(PXLongShotBuildScrollPlan(bounds, bounds, CGRectZero, &plan), "no protected rect uses full band");
    PXCheck(!PXLongShotBuildScrollPlan(CGRectNull, bounds, panel, &plan), "null viewport is rejected");
    PXCheck(!PXLongShotBuildScrollPlan(viewport, bounds, panel, NULL), "null plan is rejected");
    PXCheck(PXLongShotBuildScrollPlan(CGRectMake(20, 40, 700, 700), CGRectMake(0, 0, 844, 390), panel, &plan),
            "landscape path stays below HUD panel");
}

static void testLongCaptureRouting(void) {
    printf("[long capture routing]\n");
    PXCheck([PXStringFromCaptureMode(PXCaptureModeLong) isEqualToString:@"long"], "long mode string");
    PXCheck(PXCaptureStateIsBusy(PXCaptureStatePresenting), "presenting blocks new tasks during session");
    PXCheck([[PXEditorOrder defaultSelectionIdentifiers] containsObject:@"long"],
            "area toolbar offers rolling capture button");
    PXCheck([[PXEditorOrder resolvedSelectionOrderFromString:@"long,cancel,copy"] containsObject:@"long"],
            "area-long legacy saved order resolves with rolling capture");
    NSURL *darwin = [NSURL URLWithString:@"pixpin://capture/long"];
    PXCheck([(__bridge NSString *)PXDarwinCaptureLong isEqualToString:(PXNotificationNameForExternalURL(darwin) ?: @"")],
            "pixpin://capture/long routed to darwin notification");
    PXCheck(PXNotificationNameForExternalURL([NSURL URLWithString:@"pixpin://capture/longx"]) == nil,
            "unknown long path rejected");
}

static UIImage *PXTestLongFrame(CGFloat red, CGFloat green, CGFloat blue) {
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, 400, 600, 8, 0, space, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    if (!context) return nil;
    CGContextSetRGBFillColor(context, red, green, blue, 1);
    CGContextFillRect(context, CGRectMake(0, 0, 400, 600));
    CGImageRef image = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    UIImage *result = [UIImage imageWithCGImage:image scale:1 orientation:UIImageOrientationUp];
    CGImageRelease(image);
    return result;
}

static BOOL PXTestImageColor(UIImage *image, NSInteger row, NSInteger channel) {
    if (!image || row < 0 || row >= (NSInteger)CGImageGetHeight(image.CGImage)) return NO;
    size_t width = CGImageGetWidth(image.CGImage), height = CGImageGetHeight(image.CGImage);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, width, height, 8, 0, space, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    if (!context) return NO;
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), image.CGImage);
    uint8_t *pixel = (uint8_t *)CGBitmapContextGetData(context) + row * CGBitmapContextGetBytesPerRow(context) + (width / 2) * 4;
    BOOL correct = pixel[channel] > 220 && pixel[(channel + 1) % 3] < 30 && pixel[(channel + 2) % 3] < 30;
    CGContextRelease(context);
    return correct;
}

static void testLongShotMemoryBudget(void) {
    printf("[long shot memory budget and disk pipeline]\n");
    PXCheck(PXLongShotAvailableMemoryBytes() == 0, "host headroom is unknown so policy tolerates warning bursts");
    PXCheck(PXLongShotProcessMemoryLimitBytes() == 0, "host memory limit is unknown on test host");
    PXCheck(PXLongShotMemoryFloorBytes() == 48ull * 1024 * 1024,
            "unknown limit falls back to minimum continue floor");
    PXCheckInt(PXLongShotStitchPixelCap(0, 8000000), 8000000,
               "unknown limit keeps full export budget");
    PXCheckInt(PXLongShotStitchPixelCap(419430400ull, 8000000), 6553600,
               "400MB SpringBoard limit shrinks stitch canvas to limit/64");
    PXCheckInt(PXLongShotStitchPixelCap(32ull * 1024 * 1024, 8000000), 1000000,
               "critical limit clamps to minimum usable canvas");
    PXCheckInt(PXLongShotStitchPixelCap(1024ull * 1024 * 1024, 8000000), 8000000,
               "large limit keeps full export budget");
    PXCheckInt(PXLongShotCanvasPixelBudget(0, 8000000), 8000000,
               "unknown SpringBoard headroom does not falsely reject capture");
    PXCheckInt(PXLongShotCanvasPixelBudget(40 * 1024 * 1024, 8000000), 2097152,
               "known headroom reserves capture memory and encoding peak");
    PXCheckInt(PXLongShotCanvasPixelBudget(1, 8000000), 256000, "critical headroom uses rescue budget");
    PXCheckInt(PXLongShotCanvasPixelBudget(1024ULL * 1024 * 1024, 2000000), 2000000,
               "pressure export cannot exceed requested reduced budget");
    NSInteger widths[] = {1, 400, 1170, 1320, 2732};
    NSInteger heights[] = {600, 16384, 19999, 100000, 120000000};
    for (NSUInteger i = 0; i < 5; i++) {
        for (NSUInteger j = 0; j < 5; j++) {
            CGSize size; CGFloat scale;
            BOOL ok = PXLongShotCanvasGeometry(widths[i], heights[j], 16384, 2000000, &size, &scale);
            PXCheck(ok && size.width >= 1 && size.height >= 1 && size.height <= 16384 &&
                    size.width * size.height <= 2000000, "export geometry respects height and pixel budget");
            PXCheck(ok && ceil(heights[j] * scale) <= size.height && size.height - heights[j] * scale < 1.01,
                    "export geometry includes tail with at most one partial pixel row");
        }
    }
    CGSize size; CGFloat scale;
    PXCheck(!PXLongShotCanvasGeometry(0, 600, 16384, 2000000, &size, &scale), "invalid export width rejected");

    NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    PXLongShotCancellation *cancel = [[PXLongShotCancellation alloc] init];
    NSError *error = nil;
    PXLongShotSlice *first = [PXLongImageComposer sliceFromScreenImage:PXTestLongFrame(1, 0, 0)
        pixelRect:CGRectMake(0, 0, 400, 600) filePath:[directory stringByAppendingPathComponent:@"first.jpg"]
        cancellation:cancel error:&error];
    PXLongShotSlice *last = [PXLongImageComposer sliceFromScreenImage:PXTestLongFrame(0, 1, 0)
        pixelRect:CGRectMake(0, 0, 400, 600) filePath:[directory stringByAppendingPathComponent:@"last.jpg"]
        cancellation:cancel error:&error];
    PXCheck(first && last && !error, "real JPEG frames written with alignment signatures");
    if (first && last) {
        PXLongPreviewCanvas *preview = [[PXLongPreviewCanvas alloc] initWithWidthPixels:88 maxPixels:80000 uiScale:1 cancellation:cancel];
        UIImage *retained = [preview updateWithSlices:@[first]];
        PXCheck(retained && CGImageGetHeight(retained.CGImage) == 132, "first frame produces cropped preview");
        PXCheck(preview.allocatedPixelCount < 80000 / 2, "first preview does not allocate entire memory budget");
        first.cropBottomRows = 100;
        last.cropTopRows = 300;
        UIImage *updated = [preview updateWithSlices:@[first, last]];
        PXCheck(updated && CGImageGetHeight(updated.CGImage) == 176, "preview includes cropped frames only");
        PXCheck(PXTestImageColor(updated, 20, 0) && PXTestImageColor(updated, 160, 1),
                "preview retains first frame and appended tail in source order");
        PXCheck(PXTestImageColor(retained, 120, 0), "old HUD snapshot stays independent of mutable preview");
        UIImage *composed = [PXLongImageComposer composedImageWithSlices:@[first, last] screenScale:1
            outputURL:[NSURL fileURLWithPath:[directory stringByAppendingPathComponent:@"result.jpg"]]
            maxPixels:80000 cancellation:cancel progressBlock:nil outPixelSize:&size error:&error];
        PXCheck(composed && !error && size.width * size.height <= 80000, "reduced-budget real JPEG export succeeds");
        PXCheck(PXTestImageColor(composed, 5, 0) && PXTestImageColor(composed, (NSInteger)size.height - 3, 1),
                "reduced-budget export preserves beginning and tail without blank rows");

        first.cropBottomRows = 0;
        NSMutableArray *many = [NSMutableArray array];
        for (NSInteger count = 1; count <= 40; count++) {
            [many addObject:first];
            @autoreleasepool {
                UIImage *image = [preview updateWithSlices:many];
                PXCheck(preview.allocatedPixelCount <= 80000, "growing preview stays within pixel budget");
                if (image) PXCheck(PXTestImageColor(image, (NSInteger)CGImageGetHeight(image.CGImage) - 2, 0),
                                   "preview replay preserves last rows under rescaling");
            }
        }
        PXCheck(preview.saturated && preview.allocatedPixelCount == 0, "saturated preview releases backing canvas");
        error = nil;
        composed = [PXLongImageComposer composedImageWithSlices:many screenScale:1
            outputURL:[NSURL fileURLWithPath:[directory stringByAppendingPathComponent:@"after-preview.jpg"]]
            maxPixels:80000 cancellation:cancel progressBlock:nil outPixelSize:&size error:&error];
        PXCheck(composed && !error, "export remains available after preview saturation");
        cancel.cancelled = YES;
        PXCheck([preview updateWithSlices:@[first]] == nil, "cancelled preview does not restart");
        PXCheck([PXLongImageComposer composedImageWithSlices:@[first] screenScale:1
            outputURL:[NSURL fileURLWithPath:[directory stringByAppendingPathComponent:@"cancelled.jpg"]]
            maxPixels:80000 cancellation:cancel progressBlock:nil outPixelSize:nil error:nil] == nil,
            "cancelled composition does not export");

        UIImage *thumb = [PXLongImageComposer thumbnailImageFromFile:first.filePath screenScale:1 maxPixelSize:64];
        PXCheck(thumb && MAX(CGImageGetWidth(thumb.CGImage), CGImageGetHeight(thumb.CGImage)) <= 64 &&
                PXTestImageColor(thumb, 2, 0),
                "bubble thumbnail downsamples from disk within pixel cap");
        PXCheck([PXLongImageComposer thumbnailImageFromFile:@"" screenScale:1 maxPixelSize:64] == nil &&
                [PXLongImageComposer thumbnailImageFromFile:[directory stringByAppendingPathComponent:@"missing.jpg"]
                 screenScale:1 maxPixelSize:64] == nil,
                "missing thumbnail sources yield nil without fallback full decode");
    }
    [NSFileManager.defaultManager removeItemAtPath:directory error:nil];
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        printf("PixPin host unit tests\n");
        testStateMachine();
        testGeometry();
        testClaimSet();
        testEditorLayout();
        testExternalRequests();
        testSnapper3Aliases();
        testShellXAliases();
        testShellXTriggers();
        testEditorOrder();
        testSelectionOrder();
        testSelectionOverrides();
        testEditorOverrides();
        testIndependentButtonPreferences();
        testFloatingOriginalRect();
        testLongShotAligner();
        testLongCaptureRouting();
        testLongShotScrollPlan();
        NSInteger hidChecks = 0;
        PXTestFailures += PXRunLongShotHIDTests(&hidChecks);
        PXTestCount += hidChecks;
        testManualLongShot();
        testLongShotMemoryBudget();
        printf("\n%d checks, %d failures\n", (int)PXTestCount, (int)PXTestFailures);
        return PXTestFailures > 0 ? 1 : 0;
    }
}
