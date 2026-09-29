#import "PXRootListController.h"
#import "../Sources/Common/PXConstants.h"
#import "../Sources/Common/PXLog.h"
#import "../Sources/Common/PXExternalRequest.h"
#import "../Sources/Common/PXPanelAppearance.h"

@interface PXRootListController () <UIColorPickerViewControllerDelegate>
@property (nonatomic, assign) NSInteger copyFeedbackGeneration;
@property (nonatomic, strong) UIView *brandingHeader;
@end

@implementation PXRootListController

- (UITableView *)pxSettingsTable {
    if ([self respondsToSelector:@selector(tableView)]) return self.tableView;
    if ([self respondsToSelector:@selector(table)]) return self.table;
    return nil;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    UITableView *table = [self pxSettingsTable];
    if (!table) {
        PXLogWarn(@"prefs branding header skipped: table unavailable");
        return;
    }
    NSBundle *bundle = [NSBundle bundleForClass:[PXRootListController class]];
    NSString *imagePath = [bundle pathForResource:@"PixPinHeader" ofType:@"png"];
    UIImage *logo = imagePath.length ? [UIImage imageWithContentsOfFile:imagePath] : nil;
    if (!logo) {
        PXLogWarn(@"prefs branding logo missing; using bundle icon");
        logo = [UIImage imageNamed:@"PixPin" inBundle:bundle compatibleWithTraitCollection:self.traitCollection];
    }
    id versionValue = [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    NSString *version = [versionValue isKindOfClass:NSString.class] ? versionValue : nil;

    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, CGRectGetWidth(table.bounds), 270)];
    header.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    header.backgroundColor = UIColor.clearColor;
    self.brandingHeader = header;

    // 独立阴影容器保留 Logo 的透明圆角，避免裁掉阴影。
    UIView *iconContainer = [[UIView alloc] init];
    iconContainer.translatesAutoresizingMaskIntoConstraints = NO;
    iconContainer.layer.shadowColor = UIColor.blackColor.CGColor;
    iconContainer.layer.shadowOpacity = 0.25;
    iconContainer.layer.shadowRadius = 12;
    iconContainer.layer.shadowOffset = CGSizeMake(0, 6);
    [header addSubview:iconContainer];
    UIImageView *imageView = [[UIImageView alloc] initWithImage:logo];
    imageView.translatesAutoresizingMaskIntoConstraints = NO;
    imageView.contentMode = UIViewContentModeScaleAspectFit;
    imageView.isAccessibilityElement = NO;
    [iconContainer addSubview:imageView];

    UILabel *nameLabel = [[UILabel alloc] init];
    nameLabel.text = @"PixPin";
    UIFontDescriptor *rounded = [[UIFont systemFontOfSize:36 weight:UIFontWeightRegular].fontDescriptor
        fontDescriptorWithDesign:UIFontDescriptorSystemDesignRounded];
    nameLabel.font = rounded ? [UIFont fontWithDescriptor:rounded size:36] : [UIFont systemFontOfSize:36];
    nameLabel.textColor = UIColor.labelColor;
    nameLabel.textAlignment = NSTextAlignmentCenter;
    nameLabel.adjustsFontSizeToFitWidth = YES;
    nameLabel.minimumScaleFactor = 0.7;
    nameLabel.accessibilityTraits |= UIAccessibilityTraitHeader;
    nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:nameLabel];

    UILabel *versionLabel = [[UILabel alloc] init];
    versionLabel.text = version.length ? [NSString stringWithFormat:@"版本 %@", version] : @"版本未知";
    versionLabel.font = [UIFont systemFontOfSize:14];
    versionLabel.textColor = UIColor.secondaryLabelColor;
    versionLabel.textAlignment = NSTextAlignmentCenter;
    versionLabel.adjustsFontSizeToFitWidth = YES;
    versionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:versionLabel];

    [NSLayoutConstraint activateConstraints:@[
        [iconContainer.topAnchor constraintEqualToAnchor:header.topAnchor constant:28],
        [iconContainer.centerXAnchor constraintEqualToAnchor:header.centerXAnchor],
        [iconContainer.widthAnchor constraintEqualToConstant:134],
        [iconContainer.heightAnchor constraintEqualToConstant:134],
        [imageView.topAnchor constraintEqualToAnchor:iconContainer.topAnchor],
        [imageView.bottomAnchor constraintEqualToAnchor:iconContainer.bottomAnchor],
        [imageView.leadingAnchor constraintEqualToAnchor:iconContainer.leadingAnchor],
        [imageView.trailingAnchor constraintEqualToAnchor:iconContainer.trailingAnchor],
        [nameLabel.topAnchor constraintEqualToAnchor:iconContainer.bottomAnchor constant:10],
        [nameLabel.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:16],
        [nameLabel.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-16],
        [nameLabel.heightAnchor constraintEqualToConstant:48],
        [versionLabel.topAnchor constraintEqualToAnchor:nameLabel.bottomAnchor constant:2],
        [versionLabel.leadingAnchor constraintEqualToAnchor:nameLabel.leadingAnchor],
        [versionLabel.trailingAnchor constraintEqualToAnchor:nameLabel.trailingAnchor],
        [versionLabel.heightAnchor constraintEqualToConstant:22],
    ]];
    table.tableHeaderView = header;
    PXLogInfo(@"prefs branding header loaded: version=%@", version.length ? version : @"unknown");
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    UITableView *table = [self pxSettingsTable];
    UIView *header = self.brandingHeader;
    CGFloat width = CGRectGetWidth(table.bounds);
    if (header && width > 0 && CGRectGetWidth(header.bounds) != width) {
        CGRect frame = header.frame;
        frame.size.width = width;
        header.frame = frame;
        table.tableHeaderView = header;
    }
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
        _specifiers = [self pxSpecifiersWithURLSchemeEntry];
        NSMutableArray *items = [_specifiers mutableCopy];
        NSUInteger index = items.count;
        for (PSSpecifier *item in items) {
            if ([item.name isEqualToString:@"编辑器按钮排序"]) {
                index = [items indexOfObject:item] + 1;
                break;
            }
        }
        PSSpecifier *color = [PSSpecifier preferenceSpecifierNamed:@"标记面板颜色与透明度"
            target:self set:NULL get:NULL detail:Nil cell:PSButtonCell edit:Nil];
        color.buttonAction = @selector(pxChoosePanelColor:);
        [items insertObject:color atIndex:index];
        _specifiers = items;
    }
    return _specifiers;
}

- (void)pxChoosePanelColor:(PSSpecifier *)specifier {
    if (self.presentedViewController) return;
    UIColorPickerViewController *picker = [[UIColorPickerViewController alloc] init];
    picker.title = @"标记面板颜色";
    picker.supportsAlpha = YES;
    picker.selectedColor = [PXPanelAppearance tintColor];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)colorPickerViewController:(UIColorPickerViewController *)viewController
                  didSelectColor:(UIColor *)color continuously:(BOOL)continuously {
    [PXPanelAppearance setTintColor:color];
}

- (void)colorPickerViewControllerDidFinish:(UIColorPickerViewController *)viewController {
    [PXPanelAppearance setTintColor:viewController.selectedColor];
}

// plist 加载器不会实例化自定义 cellClass（真机上条目缺动作且显示不全），
// 外部入口使用 PSButtonCell + buttonAction，在代码中构建并插入分组之后。
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
        specifier.buttonAction = @selector(pxCopyAndRunURLScheme:);
        [specifier setProperty:url forKey:@"pxURL"];
        [specifier setProperty:title forKey:@"pxTitle"];
        [specifiers addObject:specifier];
    }
    return specifiers;
}

- (void)pxCopyAndRunURLScheme:(PSSpecifier *)specifier {
    NSString *url = [specifier propertyForKey:@"pxURL"];
    NSString *title = [specifier propertyForKey:@"pxTitle"];
    if (url.length == 0 || title.length == 0) {
        PXLogWarn(@"prefs url-scheme specifier missing url/title");
        return;
    }
    NSString *notification = PXNotificationNameForExternalURL([NSURL URLWithString:url]);
    if (!notification) {
        PXLogWarn(@"prefs external entry rejected: invalid route");
        return;
    }
    UIPasteboard.generalPasteboard.string = url;
    // 与外部 URL 共用解析表，只发送一次请求；不同时 openURL 或追加超时重试。
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge CFStringRef)notification, NULL, NULL, YES);
    PXLogInfo(@"prefs external entry copied and requested: %@", notification);
    UISelectionFeedbackGenerator *haptic = [[UISelectionFeedbackGenerator alloc] init];
    [haptic selectionChanged];

    // 同一行连续点击时，仅最新一轮反馈恢复标题；切走设置页后只恢复模型。
    NSUInteger rowGeneration = [[specifier propertyForKey:@"pxFeedbackGeneration"] unsignedIntegerValue] + 1;
    [specifier setProperty:@(rowGeneration) forKey:@"pxFeedbackGeneration"];
    specifier.name = @"已复制，已发送请求 ✓";
    [self reloadSpecifier:specifier animated:NO];
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if ([[specifier propertyForKey:@"pxFeedbackGeneration"] unsignedIntegerValue] != rowGeneration) return;
        specifier.name = title;
        __strong typeof(weakSelf) self = weakSelf;
        if (self.isViewLoaded && self.view.window) [self reloadSpecifier:specifier animated:NO];
    });

    self.copyFeedbackGeneration++;
    NSInteger generation = self.copyFeedbackGeneration;
    PSSpecifier *group = [self pxExternalEntryGroupIn:_specifiers];
    if (!group) return;
    NSString *feedbackFooter = @"已复制 URL，并发送对应功能请求。";
    if (![group propertyForKey:@"pxOriginalFooter"]) {
        [group setProperty:([group propertyForKey:@"footerText"] ?: @"") forKey:@"pxOriginalFooter"];
    }
    [group setProperty:feedbackFooter forKey:@"footerText"];
    [self reloadSpecifier:group animated:NO];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || generation != self.copyFeedbackGeneration) return;
        [group setProperty:([group propertyForKey:@"pxOriginalFooter"] ?: @"") forKey:@"footerText"];
        if (self.isViewLoaded && self.view.window) [self reloadSpecifier:group animated:NO];
    });
}

@end
