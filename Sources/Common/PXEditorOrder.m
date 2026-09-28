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
    return [self actionDisplayNames][identifier] ?: identifier;
}

+ (NSString *)displayNameForToolIdentifier:(NSString *)identifier {
    return [self toolDisplayNames][identifier] ?: identifier;
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

+ (NSString *)stringForOrder:(NSArray<NSString *> *)order {
    return [order componentsJoinedByString:@","];
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

@end
