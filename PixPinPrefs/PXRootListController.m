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
    [items insertObject:[self pxURLSchemeSpecifier] atIndex:insertIndex];
    return items;
}

- (PSSpecifier *)pxExternalEntryGroupIn:(NSArray *)specifiers {
    for (PSSpecifier *spec in specifiers) {
        if ([spec.name isEqualToString:@"外部入口"]) return spec;
    }
    return nil;
}

- (NSString *)pxSchemeURL {
    return [NSString stringWithFormat:@"%@://activate", PXExternalURLScheme];
}

- (NSString *)pxSchemeEntryTitle {
    return [NSString stringWithFormat:@"%@（点击复制）", [self pxSchemeURL]];
}

- (PSSpecifier *)pxURLSchemeSpecifier {
    PSSpecifier *specifier = [PSSpecifier preferenceSpecifierNamed:[self pxSchemeEntryTitle]
                                                            target:self
                                                               set:NULL
                                                               get:NULL
                                                            detail:Nil
                                                              cell:PSButtonCell
                                                               edit:Nil];
    specifier.buttonAction = @selector(pxCopyURLScheme:);
    return specifier;
}

- (void)pxCopyURLScheme:(PSSpecifier *)specifier {
    UIPasteboard.generalPasteboard.string = [self pxSchemeURL];
    PXLogInfo(@"prefs url-scheme copied");

    UISelectionFeedbackGenerator *haptic = [[UISelectionFeedbackGenerator alloc] init];
    [haptic selectionChanged];

    self.copyFeedbackGeneration++;
    NSInteger generation = self.copyFeedbackGeneration;
    specifier.name = @"已复制 ✓";
    [self reloadSpecifier:specifier animated:NO];

    // 按钮标题动态刷新未经真机验证，同时用测试中心已验证的分组 footerText 刷新做兜底反馈。
    PSSpecifier *group = [self pxExternalEntryGroupIn:_specifiers];
    NSString *originalFooter = [group propertyForKey:@"footerText"];
    if (group) {
        [group setProperty:@"已复制到剪贴板 ✓" forKey:@"footerText"];
        [self reloadSpecifier:group animated:NO];
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (generation != self.copyFeedbackGeneration) return;
        specifier.name = [self pxSchemeEntryTitle];
        [self reloadSpecifier:specifier animated:NO];
        if (group) {
            [group setProperty:originalFooter forKey:@"footerText"];
            [self reloadSpecifier:group animated:NO];
        }
    });
}

@end
