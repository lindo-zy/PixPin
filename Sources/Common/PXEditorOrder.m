#import "PXEditorOrder.h"
#import "PXConstants.h"

// 目录是按钮 id 的唯一命名来源：编辑器、设置页与解析层都从这里取，禁止散落硬编码。
// 默认顺序即历史版本的固定顺序；dock、collapse 仅在全屏标记模式显示。

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

+ (NSString *)displayNameForActionIdentifier:(NSString *)identifier {
    NSString *custom = [self customNameForActionIdentifier:identifier];
    return custom.length > 0 ? custom : ([self actionDisplayNames][identifier] ?: identifier);
}

+ (NSString *)displayNameForToolIdentifier:(NSString *)identifier {
    NSString *custom = [self customNameForToolIdentifier:identifier];
    return custom.length > 0 ? custom : ([self toolDisplayNames][identifier] ?: identifier);
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
    NSString *custom = [self customIconNameForActionIdentifier:identifier];
    return custom.length > 0 ? custom : [self actionIconNames][identifier];
}

+ (NSString *)iconNameForToolIdentifier:(NSString *)identifier {
    NSString *custom = [self customIconNameForToolIdentifier:identifier];
    return custom.length > 0 ? custom : [self toolIconNames][identifier];
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

+ (NSString *)customIconNameForActionIdentifier:(NSString *)identifier {
    return [self overridesDictionaryForKey:PXKeyEditorActionIcons][identifier];
}

+ (NSString *)customIconNameForToolIdentifier:(NSString *)identifier {
    return [self overridesDictionaryForKey:PXKeyEditorToolIcons][identifier];
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

// MARK: 外观

+ (CGFloat)buttonIconPointSize {
    id value = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)PXKeyEditorButtonIconSize,
                                                           (__bridge CFStringRef)PXPreferencesDomain));
    if ([value isKindOfClass:[NSNumber class]]) {
        return MAX(12.0, MIN(28.0, [(NSNumber *)value doubleValue]));
    }
    return 17.0;
}

+ (void)saveButtonIconPointSize:(CGFloat)size {
    NSNumber *number = @(MAX(12.0, MIN(28.0, size)));
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

+ (NSArray<NSString *> *)resolvedActionOrderFromString:(NSString *)csv {
    return [self resolvedOrderFromString:csv defaults:[self defaultActionIdentifiers]];
}

+ (NSArray<NSString *> *)resolvedToolOrderFromString:(NSString *)csv {
    return [self resolvedOrderFromString:csv defaults:[self defaultToolIdentifiers]];
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
    [effectiveHidden removeObject:@"close"];
    [effectiveHidden removeObject:@"done"];
    NSMutableArray<NSString *> *visible = [[self visibleOrderForOrder:order hidden:effectiveHidden] mutableCopy];
    if (!fullscreenMarkup) {
        [visible removeObject:@"dock"];
        [visible removeObject:@"collapse"];
    }
    if (![visible containsObject:@"close"]) [visible insertObject:@"close" atIndex:0];
    if (![visible containsObject:@"done"]) [visible addObject:@"done"];
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

+ (NSArray<NSString *> *)currentActionOrder {
    return [self resolvedActionOrderFromString:[self preferenceForKey:PXKeyEditorActionOrder]];
}

+ (NSArray<NSString *> *)currentToolOrder {
    return [self resolvedToolOrderFromString:[self preferenceForKey:PXKeyEditorToolOrder]];
}

+ (NSArray<NSString *> *)currentActionHidden {
    return [self normalizedHiddenFromString:[self preferenceForKey:PXKeyEditorActionHidden]
                                   defaults:[self defaultActionIdentifiers]];
}

+ (NSArray<NSString *> *)currentToolHidden {
    return [self normalizedHiddenFromString:[self preferenceForKey:PXKeyEditorToolHidden]
                                   defaults:[self defaultToolIdentifiers]];
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

@end
