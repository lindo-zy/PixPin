#import "PXRootListController.h"
#import "../Sources/Common/PXConstants.h"
#import "../Sources/Common/PXLog.h"

@interface PXRootListController ()
@property (nonatomic, assign) NSInteger copyFeedbackGeneration;
@end

@implementation PXRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
        _specifiers = [self pxSpecifiersWithURLSchemeEntry];
    }
    return _specifiers;
}

// plist 加载器不会实例化自定义 cellClass（真机上条目缺动作且显示不全），
// 复制入口改用与截图测试中心一致的 PSButtonCell + buttonAction，在代码中构建并插入分组之后。
- (NSMutableArray *)pxSpecifiersWithURLSchemeEntry {
    NSMutableArray *items = [_specifiers mutableCopy];
    NSUInteger insertIndex = items.count;
    PSSpecifier *group = [self pxExternalEntryGroupIn:items];
    if (group) insertIndex = [items indexOfObject:group] + 1;
    for (PSSpecifier *specifier in [self pxURLSchemeSpecifiers]) {
        [items insertObject:specifier atIndex:insertIndex];
        insertIndex++;
    }
    return items;
}

- (PSSpecifier *)pxExternalEntryGroupIn:(NSArray *)specifiers {
    for (PSSpecifier *spec in specifiers) {
        if ([spec.name isEqualToString:@"外部入口"]) return spec;
    }
    return nil;
}

- (NSString *)pxSchemeURLForPath:(NSString *)path {
    return [NSString stringWithFormat:@"%@://%@", PXExternalURLScheme, path];
}

// 与 Sources/Common/PXExternalRequest.m 的路由表保持一致，全部指令逐行列出。
// activate 与裸 pixpin:// 等价，capture/cancel 是 cancel 的别名，不单独占行，见分组 footer。
- (NSArray<NSArray<NSString *> *> *)pxSchemeEntries {
    return @[
        @[@"启动（全屏标记）", @"activate"],
        @[@"全屏截图", @"capture/full"],
        @[@"区域截图", @"capture/area"],
        @[@"冻结截图", @"capture/freeze"],
        @[@"即时区域截图", @"capture/instant"],
        @[@"全屏标记", @"capture/markup"],
        @[@"取消截图", @"cancel"],
    ];
}

- (NSArray<PSSpecifier *> *)pxURLSchemeSpecifiers {
    NSMutableArray *specifiers = [NSMutableArray array];
    for (NSArray<NSString *> *entry in [self pxSchemeEntries]) {
        NSString *url = [self pxSchemeURLForPath:entry[1]];
        NSString *title = [NSString stringWithFormat:@"%@：%@", entry[0], url];
        PSSpecifier *specifier = [PSSpecifier preferenceSpecifierNamed:title
                                                                target:self
                                                                   set:NULL
                                                                   get:NULL
                                                                detail:Nil
                                                                  cell:PSButtonCell
                                                                   edit:Nil];
        specifier.buttonAction = @selector(pxCopyURLScheme:);
        [specifier setProperty:url forKey:@"pxURL"];
        [specifier setProperty:title forKey:@"pxTitle"];
        [specifiers addObject:specifier];
    }
    return specifiers;
}

- (void)pxCopyURLScheme:(PSSpecifier *)specifier {
    NSString *url = [specifier propertyForKey:@"pxURL"];
    NSString *title = [specifier propertyForKey:@"pxTitle"];
    if (url.length == 0 || title.length == 0) {
        PXLogWarn(@"prefs url-scheme specifier missing url/title");
        return;
    }
    UIPasteboard.generalPasteboard.string = url;
    PXLogInfo(@"prefs url-scheme copied: %@", url);

    UISelectionFeedbackGenerator *haptic = [[UISelectionFeedbackGenerator alloc] init];
    [haptic selectionChanged];

    // 行标题各自延迟恢复，不引入全局代际守卫，避免连续复制多行时前一行停留在反馈文案。
    specifier.name = @"已复制 ✓";
    [self reloadSpecifier:specifier animated:NO];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        specifier.name = title;
        [self reloadSpecifier:specifier animated:NO];
    });

    // 按钮标题动态刷新未经真机验证，同时用测试中心已验证的分组 footerText 刷新做兜底反馈。
    // footer 只保留最新一次反馈：原文在离开反馈态时捕获，仅最新点击的定时器执行恢复。
    self.copyFeedbackGeneration++;
    NSInteger generation = self.copyFeedbackGeneration;
    PSSpecifier *group = [self pxExternalEntryGroupIn:_specifiers];
    if (!group) return;
    NSString *feedbackFooter = @"已复制到剪贴板 ✓";
    NSString *currentFooter = [group propertyForKey:@"footerText"] ?: @"";
    if (![currentFooter isEqualToString:feedbackFooter]) {
        [group setProperty:currentFooter forKey:@"pxOriginalFooter"];
    }
    [group setProperty:feedbackFooter forKey:@"footerText"];
    [self reloadSpecifier:group animated:NO];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (generation != self.copyFeedbackGeneration) return;
        NSString *original = [group propertyForKey:@"pxOriginalFooter"];
        if (original.length > 0) {
            [group setProperty:original forKey:@"footerText"];
            [self reloadSpecifier:group animated:NO];
        }
    });
}

@end
