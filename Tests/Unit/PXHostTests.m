// 宿主单元测试：只覆盖不依赖 iOS 私有框架/UIImage 的纯逻辑层。
// 在 macOS 上编译运行（见 Tests/run-host-tests.sh）。

#import <Foundation/Foundation.h>
#import "../../Sources/Common/PXGeometry.h"
#import "../../Sources/Common/PXClaimSet.h"
#import "../../Sources/Common/PXConstants.h"
#import "../../Sources/Common/PXEditorOrder.h"
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
    PXCheck(![markupActions containsObject:@"undo"], "markup preview honors visibility");
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

    // 图标点大小：默认 17，夹取 12–28。
    PXCheckInt((NSInteger)[PXEditorOrder buttonIconPointSize], 17, "icon size default");
    [PXEditorOrder saveButtonIconPointSize:99.0];
    PXCheckInt((NSInteger)[PXEditorOrder buttonIconPointSize], 28, "icon size clamped high");
    [PXEditorOrder saveButtonIconPointSize:5.0];
    PXCheckInt((NSInteger)[PXEditorOrder buttonIconPointSize], 12, "icon size clamped low");
    [PXEditorOrder saveButtonIconPointSize:17.0];
}

static void testSelectionOrder(void) {
    printf("[selection order]\n");
    NSArray<NSString *> *defaults = [PXEditorOrder defaultSelectionIdentifiers];
    PXCheckInt(defaults.count, 7, "selection catalog count");
    PXCheckInt([NSSet setWithArray:defaults].count, 7, "selection ids unique");
    for (NSString *identifier in defaults) {
        PXCheck([PXEditorOrder displayNameForSelectionIdentifier:identifier].length > 0, "selection display name");
        PXCheck([PXEditorOrder iconNameForSelectionIdentifier:identifier].length > 0, "selection icon name");
    }
    PXCheck([[PXEditorOrder resolvedSelectionOrderFromString:nil] isEqualToArray:defaults], "nil csv -> defaults");
    NSArray<NSString *> *reordered = [PXEditorOrder resolvedSelectionOrderFromString:@"float,save,bogus,cancel"];
    PXCheck([reordered[0] isEqualToString:@"float"] && [reordered[1] isEqualToString:@"save"],
            "selection reorder preserved, missing appended");

    // 区域/冻结：自定义顺序 + 出口兜底（取消/完成不可隐藏，保持配置位置）。
    NSArray<NSString *> *visible = [PXEditorOrder visibleSelectionOrderForOrder:reordered
                                                                        hidden:@[@"float", @"cancel", @"confirm"]
                                                                       instant:NO];
    PXCheck(![visible containsObject:@"float"], "float hidable");
    PXCheck([visible indexOfObject:@"cancel"] == 1, "cancel stays at configured position");
    PXCheck([visible.lastObject isEqualToString:@"confirm"], "confirm stays at configured position");

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
        testEditorOrder();
        testSelectionOrder();
        testEditorOverrides();
        testIndependentButtonPreferences();
        printf("\n%d checks, %d failures\n", (int)PXTestCount, (int)PXTestFailures);
        return PXTestFailures > 0 ? 1 : 0;
    }
}
