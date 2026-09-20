#import "PXTestCaptureController.h"
#import "../Sources/Common/PXConstants.h"
#import "../Sources/Common/PXRuntimeStatus.h"

@interface PXTestCaptureController ()
@property (nonatomic, strong) NSTimer *statusTimer;
@property (nonatomic, strong) PSSpecifier *statusGroup;
@property (nonatomic, copy) NSString *localMessage;
@end

@implementation PXTestCaptureController

- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;

    NSMutableArray *items = [[NSMutableArray alloc] init];

    self.statusGroup = [PSSpecifier emptyGroupSpecifier];
    self.statusGroup.name = @"运行状态";
    [self.statusGroup setProperty:[self pxStatusText] forKey:@"footerText"];
    [items addObject:self.statusGroup];

    [items addObject:[self pxButton:@"刷新运行状态" action:@selector(refreshStatus:)]];

    PSSpecifier *captureGroup = [PSSpecifier emptyGroupSpecifier];
    captureGroup.name = @"截图链路测试";
    [captureGroup setProperty:@"点击后会先让 SpringBoard 重读设置，再发起截图。本页不再弹出阻塞提示框；区域、冻结和即时模式应直接出现冻结画面、选区与底部操作栏。" forKey:@"footerText"];
    [items addObject:captureGroup];

    [items addObject:[self pxButton:@"测试全屏截图" action:@selector(testFullscreen:)]];
    [items addObject:[self pxButton:@"测试区域截图" action:@selector(testArea:)]];
    [items addObject:[self pxButton:@"测试冻结截图" action:@selector(testFreeze:)]];
    [items addObject:[self pxButton:@"测试即时区域截图" action:@selector(testInstant:)]];

    PSSpecifier *lifecycleGroup = [PSSpecifier emptyGroupSpecifier];
    lifecycleGroup.name = @"窗口与任务";
    [lifecycleGroup setProperty:@"如果调试期间留下选区或出现“有任务进行中”，可以在这里显式取消，无需重启 SpringBoard。" forKey:@"footerText"];
    [items addObject:lifecycleGroup];
    [items addObject:[self pxButton:@"取消当前截图任务" action:@selector(cancelCapture:)]];
    [items addObject:[self pxButton:@"打开截图历史" action:@selector(openHistory:)]];

    _specifiers = [items copy];
    return _specifiers;
}

- (PSSpecifier *)pxButton:(NSString *)title action:(SEL)action {
    PSSpecifier *specifier = [PSSpecifier preferenceSpecifierNamed:title
                                                            target:self
                                                               set:NULL
                                                               get:NULL
                                                            detail:Nil
                                                              cell:PSButtonCell
                                                              edit:Nil];
    specifier.buttonAction = action;
    return specifier;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self pxRefreshStatusUI];
    self.statusTimer = [NSTimer scheduledTimerWithTimeInterval:0.75
                                                       target:self
                                                     selector:@selector(pxTimerFired:)
                                                     userInfo:nil
                                                      repeats:YES];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [self.statusTimer invalidate];
    self.statusTimer = nil;
}

- (void)dealloc {
    [self.statusTimer invalidate];
}

- (void)pxTimerFired:(NSTimer *)timer {
    [self pxRefreshStatusUI];
}

- (void)pxRefreshStatusUI {
    if (!self.statusGroup) return;
    [self.statusGroup setProperty:[self pxStatusText] forKey:@"footerText"];
    [self reloadSpecifier:self.statusGroup animated:NO];
}

- (NSString *)pxCaptureMethodText:(NSString *)method {
    if ([method isEqualToString:@"private-uicreate"]) return @"_UICreateScreenUIImage";
    if ([method isEqualToString:@"private-uigetscreen"]) return @"UIGetScreenImage";
    if ([method isEqualToString:@"fallback-snapshot"]) return @"部分回退快照";
    return method.length ? method : @"未知";
}

- (NSString *)pxDateText:(NSNumber *)timestamp {
    if (timestamp.doubleValue <= 0) return @"-";
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"HH:mm:ss";
    return [formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:timestamp.doubleValue]];
}

- (NSString *)pxStatusText {
    NSDictionary *status = [PXRuntimeStatus readStatus];
    if (!status) {
        NSString *prefix = self.localMessage.length ? [self.localMessage stringByAppendingString:@"\n\n"] : @"";
        return [prefix stringByAppendingFormat:@"未读到 SpringBoard 运行状态。请确认 PixPin 已安装并在注入器中启用，然后重启 SpringBoard。\n状态文件：%@", [PXRuntimeStatus statusFilePath]];
    }

    NSMutableArray<NSString *> *lines = [[NSMutableArray alloc] init];
    if (self.localMessage.length) [lines addObject:self.localMessage];
    [lines addObject:[NSString stringWithFormat:@"已注入：%@  抓取：%@",
                      [self pxDateText:status[@"loadedAt"]],
                      [self pxCaptureMethodText:status[@"captureMethod"]]]];

    if ([status[@"lastRequestAt"] doubleValue] > 0) {
        [lines addObject:[NSString stringWithFormat:@"请求：%@ / %@  %@",
                          status[@"lastRequestMode"] ?: @"-",
                          status[@"lastRequestOutcome"] ?: @"-",
                          [self pxDateText:status[@"lastRequestAt"]]]];
    }
    if ([status[@"lastPhaseAt"] doubleValue] > 0) {
        NSString *message = status[@"lastPhaseMessage"];
        [lines addObject:[NSString stringWithFormat:@"阶段：%@  %@%@",
                          status[@"lastPhase"] ?: @"-",
                          [self pxDateText:status[@"lastPhaseAt"]],
                          message.length ? [NSString stringWithFormat:@"\n%@", message] : @""]];
    }
    if ([status[@"lastResultAt"] doubleValue] > 0) {
        [lines addObject:[NSString stringWithFormat:@"结果：%@  %@\n%@",
                          status[@"lastResult"] ?: @"-",
                          [self pxDateText:status[@"lastResultAt"]],
                          status[@"lastResultMessage"] ?: @""]];
    }
    return [lines componentsJoinedByString:@"\n"];
}

- (void)pxPost:(CFStringRef)notification {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         notification, NULL, NULL, TRUE);
}

- (void)pxRunCaptureNotification:(CFStringRef)notification label:(NSString *)label {
    self.localMessage = [NSString stringWithFormat:@"已发起“%@”，正在等待 SpringBoard…", label];
    [self pxPost:PXDarwinPreferencesReload];
    [self pxRefreshStatusUI];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [self pxPost:notification];
    });
}

- (void)refreshStatus:(PSSpecifier *)specifier {
    self.localMessage = @"已手动刷新";
    [self pxRefreshStatusUI];
}

- (void)testFullscreen:(PSSpecifier *)specifier {
    [self pxRunCaptureNotification:PXDarwinCaptureFull label:@"全屏截图"];
}

- (void)testArea:(PSSpecifier *)specifier {
    [self pxRunCaptureNotification:PXDarwinCaptureArea label:@"区域截图"];
}

- (void)testFreeze:(PSSpecifier *)specifier {
    [self pxRunCaptureNotification:PXDarwinCaptureFreeze label:@"冻结截图"];
}

- (void)testInstant:(PSSpecifier *)specifier {
    [self pxRunCaptureNotification:PXDarwinCaptureInstant label:@"即时区域截图"];
}

- (void)cancelCapture:(PSSpecifier *)specifier {
    self.localMessage = @"已发送取消请求";
    [self pxPost:PXDarwinCaptureCancel];
    [self pxRefreshStatusUI];
}

- (void)openHistory:(PSSpecifier *)specifier {
    self.localMessage = @"已请求打开截图历史";
    [self pxPost:PXDarwinHistoryOpen];
    [self pxRefreshStatusUI];
}

@end
