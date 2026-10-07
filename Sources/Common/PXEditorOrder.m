#import "PXEditorOrder.h"
#import "PXConstants.h"

// 目录是按钮 id 的唯一命名来源：编辑器、设置页与解析层都从这里取，禁止散落硬编码。
// 默认顺序即历史版本的固定顺序；dock、collapse 仅在全屏标记模式显示。

@implementation PXCustomSelectionButton
- (instancetype)initWithIdentifier:(NSString *)identifier
                              name:(NSString *)name
                          iconName:(NSString *)iconName
                               url:(NSString *)url {
    if (self = [super init]) {
        _identifier = identifier;
        _name = name;
        _iconName = iconName;
        _url = url;
    }
    return self;
}
@end

@implementation PXEditorOrder

+ (NSArray<NSString *> *)defaultActionIdentifiers {
    static NSArray<NSString *> *identifiers;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        identifiers = @[@"close", @"undo", @"redo", @"crop", @"rotate",
                        @"copy", @"share", @"save", @"fit", @"delete",
                        @"front", @"dock", @"collapse", @"done"];
    });
    return identifiers;
}

+ (NSArray<NSString *> *)fixedActionIdentifiers {
    static NSArray<NSString *> *identifiers;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // 全屏标记四角键中的目录按钮：图标/名称/顺序/显隐全部写死，设置页不出现。
        identifiers = @[@"close", @"undo", @"done"];
    });
    return identifiers;
}

+ (NSArray<NSString *> *)defaultToolIdentifiers {
    static NSArray<NSString *> *identifiers;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        identifiers = @[@"brush", @"pan", @"rect", @"oval", @"arrow",
                        @"magnifier", @"line", @"mosaic", @"text",
                        @"rectSolid", @"ovalSolid", @"spotlight", @"highlight",
                        @"sticker", @"stamp"];
    });
    return identifiers;
}

+ (NSArray<NSString *> *)defaultSelectionIdentifiers {
    static NSArray<NSString *> *identifiers;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        identifiers = @[@"cancel", @"selectall", @"markup", @"editor", @"float", @"long",
                        @"save", @"copy",
                        @"shellxarea", @"shellxinstant", @"shellxfreeze",
                        @"shellxshot", @"shellxclose",
                        @"shellxhistory", @"shellxopenlast",
                        @"shellxlong", @"shellxfull",
                        @"shellxmark", @"shellxedit",
                        @"shellxai2", @"shellxtranslate", @"shellxscan"];
    });
    return identifiers;
}

+ (NSArray<NSString *> *)shellxSelectionIdentifiers {
    static NSArray<NSString *> *identifiers;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        identifiers = @[@"shellxarea", @"shellxinstant", @"shellxfreeze",
                        @"shellxshot", @"shellxclose",
                        @"shellxhistory", @"shellxopenlast",
                        @"shellxlong", @"shellxfull",
                        @"shellxmark", @"shellxedit",
                        @"shellxai2", @"shellxtranslate", @"shellxscan"];
    });
    return identifiers;
}

+ (NSDictionary<NSString *, NSNumber *> *)shellxSelectionActionMap {
    static NSDictionary<NSString *, NSNumber *> *map;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        map = @{@"shellxarea": @(PXShellXActionArea),
                @"shellxinstant": @(PXShellXActionInstant),
                @"shellxfreeze": @(PXShellXActionFreeze),
                @"shellxshot": @(PXShellXActionAssistive),
                @"shellxclose": @(PXShellXActionClose),
                @"shellxhistory": @(PXShellXActionHistory),
                @"shellxopenlast": @(PXShellXActionOpenLast),
                @"shellxlong": @(PXShellXActionLongShot),
                @"shellxfull": @(PXShellXActionFullShot),
                @"shellxmark": @(PXShellXActionMark),
                @"shellxedit": @(PXShellXActionEdit),
                @"shellxai2": @(PXShellXActionAI2),
                @"shellxtranslate": @(PXShellXActionTranslate),
                @"shellxscan": @(PXShellXActionScan)};
    });
    return map;
}

+ (NSDictionary<NSString *, NSString *> *)actionDisplayNames {
    static NSDictionary<NSString *, NSString *> *names;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        names = @{@"close": @"关闭",
                  @"undo": @"撤销",
                  @"redo": @"重做",
                  @"crop": @"裁剪",
                  @"rotate": @"旋转",
                  @"copy": @"复制",
                  @"share": @"分享",
                  @"save": @"保存",
                  @"fit": @"适屏",
                  @"delete": @"删除",
                  @"front": @"置顶",
                  @"dock": @"面板停靠",
                  @"collapse": @"收起面板",
                  @"done": @"完成"};
    });
    return names;
}

+ (NSDictionary<NSString *, NSString *> *)toolDisplayNames {
    static NSDictionary<NSString *, NSString *> *names;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        names = @{@"brush": @"画笔",
                  @"pan": @"平移",
                  @"rect": @"方框",
                  @"oval": @"椭圆",
                  @"arrow": @"箭头",
                  @"magnifier": @"放大镜",
                  @"line": @"直线",
                  @"mosaic": @"马赛克",
                  @"text": @"文字",
                  @"rectSolid": @"实心方",
                  @"ovalSolid": @"实心圆",
                  @"spotlight": @"聚光",
                  @"highlight": @"荧光",
                  @"sticker": @"贴纸",
                  @"stamp": @"序号图章"};
    });
    return names;
}

+ (NSDictionary<NSString *, NSString *> *)selectionDisplayNames {
    static NSDictionary<NSString *, NSString *> *names;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        names = @{@"cancel": @"取消",
                  @"selectall": @"全屏",
                  @"markup": @"全屏标记",
                  @"editor": @"编辑",
                  @"float": @"悬浮",
                  @"long": @"滚动截图",
                  @"save": @"保存",
                  @"copy": @"复制",
                  @"shellxarea": @"ShellX 区域",
                  @"shellxinstant": @"ShellX 即时",
                  @"shellxfreeze": @"ShellX 冻结",
                  @"shellxshot": @"ShellX 套壳",
                  @"shellxclose": @"ShellX 关闭",
                  @"shellxhistory": @"ShellX 记录",
                  @"shellxopenlast": @"ShellX 最近",
                  @"shellxlong": @"ShellX 长图",
                  @"shellxfull": @"ShellX 整屏",
                  @"shellxmark": @"ShellX 标记",
                  @"shellxedit": @"ShellX 编辑",
                  @"shellxai2": @"ShellX 问答",
                  @"shellxtranslate": @"ShellX 翻译",
                  @"shellxscan": @"ShellX 扫码"};
    });
    return names;
}

+ (NSString *)displayNameForActionIdentifier:(NSString *)identifier {
    // 四角键写死：不吃自定义名称覆盖，保证编辑器各模式下展示一致。
    if ([[self fixedActionIdentifiers] containsObject:identifier]) {
        return [self actionDisplayNames][identifier] ?: identifier;
    }
    NSString *custom = [self customNameForActionIdentifier:identifier];
    return custom.length > 0 ? custom : ([self actionDisplayNames][identifier] ?: identifier);
}

+ (NSString *)displayNameForToolIdentifier:(NSString *)identifier {
    NSString *custom = [self customNameForToolIdentifier:identifier];
    return custom.length > 0 ? custom : ([self toolDisplayNames][identifier] ?: identifier);
}

+ (NSString *)displayNameForSelectionIdentifier:(NSString *)identifier {
    NSString *custom = [self customNameForSelectionIdentifier:identifier];
    if (custom.length > 0) return custom;
    // 自定义 URL 按钮的名称存在记录里，优先于静态目录（目录字典中没有该 id）。
    PXCustomSelectionButton *customButton = [self pxCustomButtonForIdentifier:identifier];
    if (customButton) return customButton.name;
    return [self selectionDisplayNames][identifier] ?: identifier;
}

+ (NSDictionary<NSString *, NSString *> *)actionIconNames {
    static NSDictionary<NSString *, NSString *> *icons;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        icons = @{@"close": @"xmark",
                  @"undo": @"arrow.uturn.backward",
                  @"redo": @"arrow.uturn.forward",
                  @"crop": @"crop.rotate",
                  @"rotate": @"rotate.right",
                  @"copy": @"doc.on.doc",
                  @"share": @"square.and.arrow.up",
                  @"save": @"square.and.arrow.down",
                  @"fit": @"arrow.up.left.and.arrow.down.right",
                  @"delete": @"trash",
                  @"front": @"arrow.up.to.line",
                  @"dock": @"rectangle.topthird.inset.filled",
                  @"collapse": @"rectangle.compress.vertical",
                  @"done": @"checkmark"};
    });
    return icons;
}

+ (NSDictionary<NSString *, NSString *> *)toolIconNames {
    static NSDictionary<NSString *, NSString *> *icons;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        icons = @{@"brush": @"paintbrush",
                  @"pan": @"hand.point.up.left",
                  @"rect": @"rectangle",
                  @"oval": @"ellipse",
                  @"arrow": @"arrow.up.right",
                  @"magnifier": @"plus.magnifyingglass",
                  @"line": @"line.diagonal",
                  @"mosaic": @"squareshape.split.3x3",
                  @"text": @"textformat",
                  @"rectSolid": @"rectangle.fill",
                  @"ovalSolid": @"ellipse.fill",
                  @"spotlight": @"circle.lefthalf.filled",
                  @"highlight": @"pencil",
                  @"sticker": @"photo",
                  @"stamp": @"1.circle"};
    });
    return icons;
}

+ (NSString *)iconNameForActionIdentifier:(NSString *)identifier {
    // 四角键写死：不吃自定义图标覆盖（历史遗留覆盖一并失效）。
    if ([[self fixedActionIdentifiers] containsObject:identifier]) {
        return [self actionIconNames][identifier];
    }
    NSString *custom = [self customIconNameForActionIdentifier:identifier];
    return custom.length > 0 ? custom : [self actionIconNames][identifier];
}

+ (NSString *)iconNameForToolIdentifier:(NSString *)identifier {
    NSString *custom = [self customIconNameForToolIdentifier:identifier];
    return custom.length > 0 ? custom : [self toolIconNames][identifier];
}

+ (NSDictionary<NSString *, NSString *> *)selectionIconNames {
    static NSDictionary<NSString *, NSString *> *icons;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        icons = @{@"cancel": @"xmark.circle",
                  @"selectall": @"viewfinder",
                  @"markup": @"checkmark.rectangle",
                  @"editor": @"pencil.and.outline",
                  @"float": @"rectangle.on.rectangle",
                  @"long": @"arrow.down.to.line.compact",
                  @"save": @"square.and.arrow.down",
                  @"copy": @"doc.on.doc",
                  @"shellxarea": @"camera.viewfinder",
                  @"shellxinstant": @"timer",
                  @"shellxfreeze": @"snowflake",
                  @"shellxshot": @"smartphone",
                  @"shellxclose": @"xmark.app",
                  @"shellxhistory": @"clock.arrow.circlepath",
                  @"shellxopenlast": @"photo.on.rectangle",
                  @"shellxlong": @"arrow.down.to.line",
                  @"shellxfull": @"rectangle.inset.filled",
                  @"shellxmark": @"highlighter",
                  @"shellxedit": @"square.and.pencil",
                  @"shellxai2": @"text.bubble",
                  @"shellxtranslate": @"character.bubble",
                  @"shellxscan": @"qrcode.viewfinder"};
    });
    return icons;
}

+ (NSString *)iconNameForSelectionIdentifier:(NSString *)identifier {
    NSString *custom = [self customIconNameForSelectionIdentifier:identifier];
    if (custom.length > 0) return custom;
    PXCustomSelectionButton *customButton = [self pxCustomButtonForIdentifier:identifier];
    if (customButton) return customButton.iconName.length > 0 ? customButton.iconName : nil;
    return [self selectionIconNames][identifier];
}

// MARK: 自定义名称/图标覆盖（id=值 CSV 字典）

+ (NSDictionary<NSString *, NSString *> *)overridesDictionaryForKey:(NSString *)key {
    NSString *csv = [self preferenceForKey:key];
    if (csv.length == 0) return @{};
    NSMutableDictionary<NSString *, NSString *> *overrides = [NSMutableDictionary dictionary];
    for (NSString *piece in [csv componentsSeparatedByString:@","]) {
        NSArray<NSString *> *pair = [piece componentsSeparatedByString:@"="];
        if (pair.count != 2 || pair[0].length == 0 || pair[1].length == 0) continue;
        overrides[pair[0]] = pair[1];
    }
    return overrides;
}

+ (void)saveOverridesDictionary:(NSDictionary<NSString *, NSString *> *)overrides
                            key:(NSString *)key {
    NSMutableArray<NSString *> *pairs = [NSMutableArray array];
    for (NSString *identifier in overrides) {
        NSString *value = overrides[identifier];
        if (identifier.length == 0 || value.length == 0) continue;
        [pairs addObject:[NSString stringWithFormat:@"%@=%@", identifier, value]];
    }
    NSString *csv = pairs.count > 0 ? [pairs componentsJoinedByString:@","] : nil;
    CFPreferencesSetAppValue((__bridge CFStringRef)key,
                             (__bridge CFStringRef)csv,
                             (__bridge CFStringRef)PXPreferencesDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)PXPreferencesDomain);
}

/// 名称清洗：去除逗号/等号/换行（破坏 CSV 结构的字符），截断到 12 字符。
+ (NSString *)sanitizedOverrideName:(NSString *)name {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (NSString *part in [name componentsSeparatedByCharactersInSet:
        [NSCharacterSet characterSetWithCharactersInString:@",=\n\r"]]) {
        if (part.length > 0) [parts addObject:part];
    }
    NSString *cleaned = [[parts componentsJoinedByString:@" "]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (cleaned.length > 12) {
        cleaned = [cleaned substringToIndex:12];
        // UTF-16 截断可能切断 emoji 代理对，去掉悬挂的高代理位。
        unichar last = [cleaned characterAtIndex:cleaned.length - 1];
        if (CFStringIsSurrogateHighCharacter(last)) {
            cleaned = [cleaned substringToIndex:cleaned.length - 1];
        }
    }
    return cleaned;
}

+ (NSString *)customNameForActionIdentifier:(NSString *)identifier {
    return [self overridesDictionaryForKey:PXKeyEditorActionNames][identifier];
}

+ (NSString *)customNameForToolIdentifier:(NSString *)identifier {
    return [self overridesDictionaryForKey:PXKeyEditorToolNames][identifier];
}

+ (NSString *)customNameForSelectionIdentifier:(NSString *)identifier {
    return [self overridesDictionaryForKey:PXKeySelectionButtonNames][identifier];
}

+ (NSString *)customIconNameForActionIdentifier:(NSString *)identifier {
    return [self overridesDictionaryForKey:PXKeyEditorActionIcons][identifier];
}

+ (NSString *)customIconNameForToolIdentifier:(NSString *)identifier {
    return [self overridesDictionaryForKey:PXKeyEditorToolIcons][identifier];
}

+ (NSString *)customIconNameForSelectionIdentifier:(NSString *)identifier {
    return [self overridesDictionaryForKey:PXKeySelectionButtonIcons][identifier];
}

+ (void)writeOverrideValue:(NSString *)value
                 dictKey:(NSString *)dictKey
              identifier:(NSString *)identifier {
    if (identifier.length == 0) return;
    NSMutableDictionary<NSString *, NSString *> *overrides =
        [[self overridesDictionaryForKey:dictKey] mutableCopy];
    if (value.length > 0) {
        overrides[identifier] = value;
    } else {
        [overrides removeObjectForKey:identifier];   // 空值 = 清除覆盖，回到目录默认
    }
    [self saveOverridesDictionary:overrides key:dictKey];
}

+ (void)saveActionName:(NSString *)name forIdentifier:(NSString *)identifier {
    [self writeOverrideValue:[self sanitizedOverrideName:name]
                      dictKey:PXKeyEditorActionNames
                   identifier:identifier];
}

+ (void)saveToolName:(NSString *)name forIdentifier:(NSString *)identifier {
    [self writeOverrideValue:[self sanitizedOverrideName:name]
                      dictKey:PXKeyEditorToolNames
                   identifier:identifier];
}

+ (void)saveActionIconName:(NSString *)symbolName forIdentifier:(NSString *)identifier {
    [self writeOverrideValue:[symbolName stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]]
                      dictKey:PXKeyEditorActionIcons
                   identifier:identifier];
}

+ (void)saveToolIconName:(NSString *)symbolName forIdentifier:(NSString *)identifier {
    [self writeOverrideValue:[symbolName stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]]
                      dictKey:PXKeyEditorToolIcons
                   identifier:identifier];
}

+ (void)saveSelectionName:(NSString *)name forIdentifier:(NSString *)identifier {
    [self writeOverrideValue:[self sanitizedOverrideName:name]
                      dictKey:PXKeySelectionButtonNames
                   identifier:identifier];
}

+ (void)saveSelectionIconName:(NSString *)symbolName forIdentifier:(NSString *)identifier {
    [self writeOverrideValue:[symbolName stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]]
                      dictKey:PXKeySelectionButtonIcons
                   identifier:identifier];
}

// MARK: 自定义 URL 按钮（行记录 CSV：行间 \n、字段间逗号；icon 允许空串）

+ (PXCustomSelectionButton *)pxCustomButtonForIdentifier:(NSString *)identifier {
    for (PXCustomSelectionButton *button in [self customSelectionButtons]) {
        if ([button.identifier isEqualToString:identifier]) return button;
    }
    return nil;
}

+ (NSArray<PXCustomSelectionButton *> *)customSelectionButtons {
    NSString *csv = [self preferenceForKey:PXKeySelectionCustomButtons];
    if (csv.length == 0) return @[];
    NSMutableArray<PXCustomSelectionButton *> *buttons = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (NSString *line in [csv componentsSeparatedByString:@"\n"]) {
        NSArray<NSString *> *fields = [line componentsSeparatedByString:@","];
        if (fields.count != 4) continue;
        NSString *identifier = fields[0];
        NSString *name = [fields[1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (identifier.length == 0 || name.length == 0 || fields[3].length == 0) continue;
        if ([seen containsObject:identifier]) continue;
        [seen addObject:identifier];
        [buttons addObject:[[PXCustomSelectionButton alloc] initWithIdentifier:identifier
                                                                          name:name
                                                                      iconName:fields[2]
                                                                           url:fields[3]]];
    }
    return [buttons copy];
}

+ (void)pxSaveCustomSelectionButtons:(NSArray<PXCustomSelectionButton *> *)buttons {
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    for (PXCustomSelectionButton *button in buttons) {
        [lines addObject:[NSString stringWithFormat:@"%@,%@,%@,%@",
                          button.identifier, button.name, button.iconName, button.url]];
    }
    NSString *csv = lines.count > 0 ? [lines componentsJoinedByString:@"\n"] : nil;
    CFPreferencesSetAppValue((__bridge CFStringRef)PXKeySelectionCustomButtons,
                             (__bridge CFStringRef)csv,
                             (__bridge CFStringRef)PXPreferencesDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)PXPreferencesDomain);
}

+ (NSString *)pxNextCustomButtonIdentifierIn:(NSArray<PXCustomSelectionButton *> *)buttons {
    NSInteger maxIndex = 0;
    for (PXCustomSelectionButton *button in buttons) {
        if (![button.identifier hasPrefix:@"url"]) continue;
        NSInteger index = [button.identifier substringFromIndex:3].integerValue;
        if (index > maxIndex) maxIndex = index;
    }
    return [NSString stringWithFormat:@"url%ld", (long)(maxIndex + 1)];
}

/// scheme 必填（纯 scheme URL 如 foxnews:// 合法，用于唤起 App）；其余交系统 URL 分发层。
+ (BOOL)pxCustomURLAcceptable:(NSString *)url {
    NSURL *parsed = [NSURL URLWithString:url];
    return parsed && parsed.scheme.length > 0;
}

+ (NSArray<NSString *> *)customSelectionIdentifiers {
    return [[self customSelectionButtons] valueForKey:@"identifier"];
}

+ (nullable NSString *)customURLForSelectionIdentifier:(NSString *)identifier {
    return [self pxCustomButtonForIdentifier:identifier].url;
}

+ (nullable PXCustomSelectionButton *)saveCustomSelectionButtonWithID:(NSString *)identifier
                                                                 name:(NSString *)name
                                                                 icon:(NSString *)iconName
                                                                  url:(NSString *)url {
    NSString *cleanedName = [self sanitizedOverrideName:name];
    // URL 只清洗破坏行/字段结构的字符；scheme 校验交给 pxCustomURLAcceptable。
    NSString *cleanedURL = [[[url componentsSeparatedByCharactersInSet:
        [NSCharacterSet characterSetWithCharactersInString:@",\n\r"]] componentsJoinedByString:@""]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (cleanedURL.length > 500) cleanedURL = [cleanedURL substringToIndex:500];
    if (cleanedName.length == 0 || cleanedURL.length == 0 || ![self pxCustomURLAcceptable:cleanedURL]) {
        return nil;
    }
    NSString *cleanedIcon = [iconName stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";

    NSMutableArray<PXCustomSelectionButton *> *buttons = [[self customSelectionButtons] mutableCopy];
    PXCustomSelectionButton *existing = nil;
    NSUInteger existingIndex = NSNotFound;
    if (identifier.length > 0) {
        // 按.identifier 定位而不是 indexOfObject:：两次解析产出不同实例，指针比较会落空。
        for (NSUInteger i = 0; i < buttons.count; i++) {
            if ([buttons[i].identifier isEqualToString:identifier]) {
                existing = buttons[i];
                existingIndex = i;
                break;
            }
        }
    }
    NSString *finalID = existing.identifier ?: [self pxNextCustomButtonIdentifierIn:buttons];
    PXCustomSelectionButton *button = [[PXCustomSelectionButton alloc] initWithIdentifier:finalID
                                                                                     name:cleanedName
                                                                                 iconName:cleanedIcon
                                                                                      url:cleanedURL];
    if (existing) {
        [buttons replaceObjectAtIndex:existingIndex withObject:button];
    } else {
        [buttons addObject:button];
    }
    [self pxSaveCustomSelectionButtons:buttons];
    return button;
}

+ (void)removeCustomSelectionButtonWithID:(NSString *)identifier {
    if (identifier.length == 0) return;
    NSArray<PXCustomSelectionButton *> *buttons = [self customSelectionButtons];
    NSMutableArray<PXCustomSelectionButton *> *remaining = [NSMutableArray array];
    for (PXCustomSelectionButton *button in buttons) {
        if (![button.identifier isEqualToString:identifier]) [remaining addObject:button];
    }
    if (remaining.count == buttons.count) return;
    // 删除只摘记录；顺序/隐藏 CSV 的残留 id 由解析层当作未知剔除，序号不复用。
    [self pxSaveCustomSelectionButtons:remaining];
}

+ (NSArray<NSString *> *)selectionCatalogIdentifiers {
    NSMutableArray<NSString *> *catalog = [[self defaultSelectionIdentifiers] mutableCopy];
    [catalog addObjectsFromArray:[self customSelectionIdentifiers]];
    return [catalog copy];
}

// MARK: 外观

+ (CGFloat)buttonIconPointSize {
    id value = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)PXKeyEditorButtonIconSize,
                                                           (__bridge CFStringRef)PXPreferencesDomain));
    if ([value isKindOfClass:[NSNumber class]]) {
        return MAX(10.0, MIN(20.0, [(NSNumber *)value doubleValue]));
    }
    return 17.0;
}

+ (void)saveButtonIconPointSize:(CGFloat)size {
    NSNumber *number = @(MAX(10.0, MIN(20.0, size)));
    CFPreferencesSetAppValue((__bridge CFStringRef)PXKeyEditorButtonIconSize,
                             (__bridge CFTypeRef)number,
                             (__bridge CFStringRef)PXPreferencesDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)PXPreferencesDomain);
}

+ (NSString *)defaultIconNameForActionIdentifier:(NSString *)identifier {
    return [self actionIconNames][identifier];
}

+ (NSString *)defaultIconNameForToolIdentifier:(NSString *)identifier {
    return [self toolIconNames][identifier];
}

+ (NSString *)defaultIconNameForSelectionIdentifier:(NSString *)identifier {
    return [self selectionIconNames][identifier];
}

// MARK: 截图按钮外观

+ (PXSelectionButtonStyle)selectionButtonStyle {
    id value = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)PXKeySelectionButtonIconStyle,
                                                           (__bridge CFStringRef)PXPreferencesDomain));
    if ([value isKindOfClass:[NSNumber class]]) {
        for (NSNumber *style in @[@(PXSelectionButtonStyleText), @(PXSelectionButtonStyleIcon),
                                  @(PXSelectionButtonStyleIconAndText)]) {
            if ([(NSNumber *)value isEqualToNumber:style]) return style.integerValue;
        }
    }
    return PXSelectionButtonStyleIcon;
}

+ (void)saveSelectionButtonStyle:(PXSelectionButtonStyle)style {
    if (style < PXSelectionButtonStyleText || style > PXSelectionButtonStyleIconAndText) {
        style = PXSelectionButtonStyleIcon;
    }
    CFPreferencesSetAppValue((__bridge CFStringRef)PXKeySelectionButtonIconStyle,
                             (__bridge CFTypeRef)@(style),
                             (__bridge CFStringRef)PXPreferencesDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)PXPreferencesDomain);
}

+ (NSArray<NSString *> *)resolvedActionOrderFromString:(NSString *)csv {
    return [self resolvedOrderFromString:csv defaults:[self defaultActionIdentifiers]];
}

+ (NSArray<NSString *> *)resolvedToolOrderFromString:(NSString *)csv {
    return [self resolvedOrderFromString:csv defaults:[self defaultToolIdentifiers]];
}

+ (NSArray<NSString *> *)resolvedSelectionOrderFromString:(NSString *)csv {
    return [self resolvedOrderFromString:csv defaults:[self selectionCatalogIdentifiers]];
}

+ (NSArray<NSString *> *)resolvedOrderFromString:(NSString *)csv
                                        defaults:(NSArray<NSString *> *)defaults {
    NSMutableSet<NSString *> *known = [NSMutableSet setWithArray:defaults];
    NSMutableArray<NSString *> *order = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (NSString *piece in [csv componentsSeparatedByString:@","]) {
        NSString *identifier = [piece stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (identifier.length == 0) continue;
        if (![known containsObject:identifier]) continue;   // 未知剔除（含历史版本遗留值）
        if ([seen containsObject:identifier]) continue;     // 去重
        [seen addObject:identifier];
        [order addObject:identifier];
    }
    for (NSString *identifier in defaults) {
        if (![seen containsObject:identifier]) [order addObject:identifier];   // 缺失补尾
    }
    return [order copy];
}

+ (NSArray<NSString *> *)normalizedHiddenFromString:(NSString *)csv
                                           defaults:(NSArray<NSString *> *)defaults {
    NSMutableSet<NSString *> *known = [NSMutableSet setWithArray:defaults];
    NSMutableSet<NSString *> *hidden = [NSMutableSet set];
    for (NSString *piece in [csv componentsSeparatedByString:@","]) {
        NSString *identifier = [piece stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (identifier.length == 0 || ![known containsObject:identifier]) continue;
        [hidden addObject:identifier];
    }
    return [hidden allObjects];
}

+ (NSArray<NSString *> *)visibleOrderForOrder:(NSArray<NSString *> *)order
                                       hidden:(NSArray<NSString *> *)hidden {
    NSSet<NSString *> *hiddenSet = [NSSet setWithArray:hidden];
    NSMutableArray<NSString *> *visible = [NSMutableArray arrayWithCapacity:order.count];
    for (NSString *identifier in order) {
        if (![hiddenSet containsObject:identifier]) [visible addObject:identifier];
    }
    // 全部隐藏时回退为完整顺序：编辑器不允许出现没有任何按钮的面板。
    return visible.count > 0 ? [visible copy] : [order copy];
}

+ (NSString *)stringForOrder:(NSArray<NSString *> *)order {
    return [order componentsJoinedByString:@","];
}

+ (NSArray<NSString *> *)visibleActionOrderForOrder:(NSArray<NSString *> *)order
                                             hidden:(NSArray<NSString *> *)hidden
                                   fullscreenMarkup:(BOOL)fullscreenMarkup {
    NSMutableArray<NSString *> *effectiveHidden = [hidden mutableCopy];
    // 关闭/完成是编辑器唯一出口；撤销随四角键写死后同样不再受显隐偏好。
    [effectiveHidden removeObjectsInArray:[self fixedActionIdentifiers]];
    NSMutableArray<NSString *> *visible = [[self visibleOrderForOrder:order hidden:effectiveHidden] mutableCopy];
    if (fullscreenMarkup) {
        [visible removeObject:@"crop"];
    } else {
        [visible removeObject:@"dock"];
        [visible removeObject:@"collapse"];
    }
    if (![visible containsObject:@"close"]) [visible insertObject:@"close" atIndex:0];
    if (![visible containsObject:@"done"]) [visible addObject:@"done"];
    return [visible copy];
}

+ (NSArray<NSString *> *)orderWithFixedActionButtonsPinned:(NSArray<NSString *> *)order {
    NSMutableArray<NSString *> *pinned = [[NSMutableArray alloc] initWithArray:order];
    NSArray<NSString *> *fixed = [self fixedActionIdentifiers];
    [pinned removeObjectsInArray:fixed];
    // 按目录默认位置钉回：close 首位、undo 次位、done 末位；索引越界时钳到当前尾部。
    // 空表输入产出 [close, undo, done]：约定固定键在任何合法顺序中都必然存在。
    NSDictionary<NSString *, NSNumber *> *defaultIndex = [self indexOfIdentifiers:[self defaultActionIdentifiers]];
    for (NSString *identifier in [self defaultActionIdentifiers]) {
        if (![fixed containsObject:identifier]) continue;
        NSUInteger index = MIN((NSUInteger)defaultIndex[identifier].unsignedIntegerValue, pinned.count);
        [pinned insertObject:identifier atIndex:index];
    }
    return [pinned copy];
}

+ (NSDictionary<NSString *, NSNumber *> *)indexOfIdentifiers:(NSArray<NSString *> *)identifiers {
    NSMutableDictionary<NSString *, NSNumber *> *index = [NSMutableDictionary dictionary];
    [identifiers enumerateObjectsUsingBlock:^(NSString *identifier, NSUInteger idx, BOOL *stop) {
        if (index[identifier] == nil) index[identifier] = @(idx);
    }];
    return index;
}

+ (NSArray<NSString *> *)visibleSelectionOrderForOrder:(NSArray<NSString *> *)order
                                                hidden:(NSArray<NSString *> *)hidden
                                               instant:(BOOL)instant {
    // 取消是选区交互的唯一取消出口，设置页开关对其禁用，这里再兜底。
    // 完成键已随 2.0.8 移除（默认配置下与保存动作完全重复，见 defaultSelectionIdentifiers）。
    NSMutableArray<NSString *> *effectiveHidden = [hidden mutableCopy];
    [effectiveHidden removeObject:@"cancel"];
    NSMutableArray<NSString *> *visible =
        [[self visibleOrderForOrder:order hidden:effectiveHidden] mutableCopy];
    if (instant) {
        // 即时模式保持历史行为：只保留快速两键，其余按钮（含悬浮）不参与。
        NSSet<NSString *> *allowed = [NSSet setWithArray:@[@"cancel", @"selectall"]];
        [visible filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *identifier, NSDictionary *bindings) {
            return [allowed containsObject:identifier];
        }]];
    }
    if (![visible containsObject:@"cancel"]) [visible insertObject:@"cancel" atIndex:0];
    return [visible copy];
}

+ (nullable NSString *)preferenceForKey:(NSString *)key {
    id value = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                           (__bridge CFStringRef)PXPreferencesDomain));
    if ([value isKindOfClass:[NSString class]] && [(NSString *)value length] > 0) {
        return value;
    }
    return nil;
}

// 空字符串是有效的独立默认值，不能当作未迁移而反复继承旧设置。
+ (void)pxPrepareFullscreenPreferences {
    CFStringRef domain = (__bridge CFStringRef)PXPreferencesDomain;
    CFPreferencesAppSynchronize(domain);
    NSDictionary *keys = @{@"MarkupActionOrder": PXKeyEditorActionOrder,
                           @"MarkupToolOrder": PXKeyEditorToolOrder,
                           @"MarkupActionHidden": PXKeyEditorActionHidden,
                           @"MarkupToolHidden": PXKeyEditorToolHidden};
    BOOL changed = NO;
    for (NSString *key in keys) {
        id existing = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, domain));
        if ([existing isKindOfClass:NSString.class]) continue;
        NSString *legacy = [self preferenceForKey:keys[key]] ?: @"";
        CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)legacy, domain);
        changed = YES;
    }
    if (changed) CFPreferencesAppSynchronize(domain);
}

+ (NSArray<NSString *> *)currentActionOrderForFullscreenMarkup:(BOOL)fullscreen {
    [self pxPrepareFullscreenPreferences];
    if (!fullscreen) return [self currentActionOrder];
    return [self resolvedActionOrderFromString:[self preferenceForKey:@"MarkupActionOrder"]];
}

+ (void)saveActionOrderString:(NSString *)csv fullscreenMarkup:(BOOL)fullscreen {
    [self pxPrepareFullscreenPreferences];
    if (!fullscreen) {
        [self saveActionOrderString:csv];
        return;
    }
    CFPreferencesSetAppValue(CFSTR("MarkupActionOrder"), (__bridge CFStringRef)(csv ?: @""),
                            (__bridge CFStringRef)PXPreferencesDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)PXPreferencesDomain);
}

+ (NSArray<NSString *> *)currentActionHiddenForFullscreenMarkup:(BOOL)fullscreen {
    [self pxPrepareFullscreenPreferences];
    if (!fullscreen) return [self currentActionHidden];
    return [self normalizedHiddenFromString:[self preferenceForKey:@"MarkupActionHidden"] defaults:[self defaultActionIdentifiers]];
}

+ (void)saveActionHiddenString:(NSString *)csv fullscreenMarkup:(BOOL)fullscreen {
    [self pxPrepareFullscreenPreferences];
    if (!fullscreen) {
        [self saveActionHiddenString:csv];
        return;
    }
    CFPreferencesSetAppValue(CFSTR("MarkupActionHidden"), (__bridge CFStringRef)(csv ?: @""),
                            (__bridge CFStringRef)PXPreferencesDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)PXPreferencesDomain);
}

+ (NSArray<NSString *> *)currentToolOrderForFullscreenMarkup:(BOOL)fullscreen {
    [self pxPrepareFullscreenPreferences];
    if (!fullscreen) return [self currentToolOrder];
    return [self resolvedToolOrderFromString:[self preferenceForKey:@"MarkupToolOrder"]];
}

+ (void)saveToolOrderString:(NSString *)csv fullscreenMarkup:(BOOL)fullscreen {
    [self pxPrepareFullscreenPreferences];
    if (!fullscreen) {
        [self saveToolOrderString:csv];
        return;
    }
    CFPreferencesSetAppValue(CFSTR("MarkupToolOrder"), (__bridge CFStringRef)(csv ?: @""),
                            (__bridge CFStringRef)PXPreferencesDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)PXPreferencesDomain);
}

+ (NSArray<NSString *> *)currentToolHiddenForFullscreenMarkup:(BOOL)fullscreen {
    [self pxPrepareFullscreenPreferences];
    if (!fullscreen) return [self currentToolHidden];
    return [self normalizedHiddenFromString:[self preferenceForKey:@"MarkupToolHidden"] defaults:[self defaultToolIdentifiers]];
}

+ (void)saveToolHiddenString:(NSString *)csv fullscreenMarkup:(BOOL)fullscreen {
    [self pxPrepareFullscreenPreferences];
    if (!fullscreen) {
        [self saveToolHiddenString:csv];
        return;
    }
    CFPreferencesSetAppValue(CFSTR("MarkupToolHidden"), (__bridge CFStringRef)(csv ?: @""),
                            (__bridge CFStringRef)PXPreferencesDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)PXPreferencesDomain);
}

+ (NSArray<NSString *> *)currentActionOrder {
    return [self resolvedActionOrderFromString:[self preferenceForKey:PXKeyEditorActionOrder]];
}

+ (NSArray<NSString *> *)currentToolOrder {
    return [self resolvedToolOrderFromString:[self preferenceForKey:PXKeyEditorToolOrder]];
}

+ (NSArray<NSString *> *)currentSelectionOrder {
    return [self resolvedSelectionOrderFromString:[self preferenceForKey:PXKeySelectionButtonOrder]];
}

+ (NSArray<NSString *> *)currentActionHidden {
    return [self normalizedHiddenFromString:[self preferenceForKey:PXKeyEditorActionHidden]
                                   defaults:[self defaultActionIdentifiers]];
}

+ (NSArray<NSString *> *)currentToolHidden {
    return [self normalizedHiddenFromString:[self preferenceForKey:PXKeyEditorToolHidden]
                                   defaults:[self defaultToolIdentifiers]];
}

+ (NSArray<NSString *> *)currentSelectionHidden {
    return [self normalizedHiddenFromString:[self preferenceForKey:PXKeySelectionButtonHidden]
                                   defaults:[self selectionCatalogIdentifiers]];
}

+ (void)saveActionOrderString:(NSString *)csv {
    CFPreferencesSetAppValue((__bridge CFStringRef)PXKeyEditorActionOrder,
                             (__bridge CFStringRef)csv,
                             (__bridge CFStringRef)PXPreferencesDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)PXPreferencesDomain);
}

+ (void)saveToolOrderString:(NSString *)csv {
    CFPreferencesSetAppValue((__bridge CFStringRef)PXKeyEditorToolOrder,
                             (__bridge CFStringRef)csv,
                             (__bridge CFStringRef)PXPreferencesDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)PXPreferencesDomain);
}

+ (void)saveSelectionOrderString:(NSString *)csv {
    CFPreferencesSetAppValue((__bridge CFStringRef)PXKeySelectionButtonOrder,
                             (__bridge CFStringRef)csv,
                             (__bridge CFStringRef)PXPreferencesDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)PXPreferencesDomain);
}

+ (void)saveActionHiddenString:(NSString *)csv {
    CFPreferencesSetAppValue((__bridge CFStringRef)PXKeyEditorActionHidden,
                             (__bridge CFStringRef)csv,
                             (__bridge CFStringRef)PXPreferencesDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)PXPreferencesDomain);
}

+ (void)saveToolHiddenString:(NSString *)csv {
    CFPreferencesSetAppValue((__bridge CFStringRef)PXKeyEditorToolHidden,
                             (__bridge CFStringRef)csv,
                             (__bridge CFStringRef)PXPreferencesDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)PXPreferencesDomain);
}

+ (void)saveSelectionHiddenString:(NSString *)csv {
    CFPreferencesSetAppValue((__bridge CFStringRef)PXKeySelectionButtonHidden,
                             (__bridge CFStringRef)csv,
                             (__bridge CFStringRef)PXPreferencesDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)PXPreferencesDomain);
}

@end
