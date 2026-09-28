#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 编辑器按钮目录与顺序解析：主 tweak、设置包、宿主测试三方共用。
/// 顺序偏好以 CSV 存储；解析策略固定：未知剔除、重复只保留首次、缺失按默认顺序补尾。
/// 读取与写入直接走 CFPreferences（编辑器每次打开解析一次，遵循"新配置从下一个任务生效"）。
@interface PXEditorOrder : NSObject

// MARK: 目录（id 顺序即默认顺序）

/// 全部操作按钮 id：关闭/撤销/重做/裁剪/旋转/复制/分享/保存/适屏/删除/置顶/面板停靠/收起面板/完成。
/// dock、collapse 仅全屏标记显示，其他模式解析后自行过滤。
+ (NSArray<NSString *> *)defaultActionIdentifiers;
/// 全部工具按钮 id：画笔/平移/方框/椭圆/箭头/放大镜/直线/马赛克/文字/实心方/实心圆/聚光/荧光/贴纸/序号图章。
+ (NSArray<NSString *> *)defaultToolIdentifiers;

+ (NSString *)displayNameForActionIdentifier:(NSString *)identifier;
+ (NSString *)displayNameForToolIdentifier:(NSString *)identifier;

/// SF Symbol 名（编辑器按钮与设置页排序条目共用）；无对应符号返回 nil。
/// 均为"自定义覆盖优先，缺省回目录默认"；自定义符号失效时由调用方回退显示名称。
+ (NSString *)iconNameForActionIdentifier:(NSString *)identifier;
+ (NSString *)iconNameForToolIdentifier:(NSString *)identifier;

/// 目录默认符号（不含覆盖），供编辑页展示"默认"项。
+ (NSString *)defaultIconNameForActionIdentifier:(NSString *)identifier;
+ (NSString *)defaultIconNameForToolIdentifier:(NSString *)identifier;

// MARK: 自定义名称/图标覆盖（设置页"点击行修改"，存 id=值 CSV；nil 值即清除覆盖）

+ (nullable NSString *)customNameForActionIdentifier:(NSString *)identifier;
+ (nullable NSString *)customNameForToolIdentifier:(NSString *)identifier;
+ (nullable NSString *)customIconNameForActionIdentifier:(NSString *)identifier;
+ (nullable NSString *)customIconNameForToolIdentifier:(NSString *)identifier;

/// 写入前必须清洗：名称去除逗号/等号并截断到 12 字符；符号传空串清除覆盖。
+ (void)saveActionName:(nullable NSString *)name forIdentifier:(NSString *)identifier;
+ (void)saveToolName:(nullable NSString *)name forIdentifier:(NSString *)identifier;
+ (void)saveActionIconName:(nullable NSString *)symbolName forIdentifier:(NSString *)identifier;
+ (void)saveToolIconName:(nullable NSString *)symbolName forIdentifier:(NSString *)identifier;

// MARK: 外观

/// 编辑器按钮图标点大小（操作与工具通用），默认 17，夹取 12–28。
+ (CGFloat)buttonIconPointSize;
+ (void)saveButtonIconPointSize:(CGFloat)size;

// MARK: 解析与序列化

/// 把任意偏好字符串解析为覆盖全部 id 的合法顺序；入参为空返回默认顺序。
+ (NSArray<NSString *> *)resolvedActionOrderFromString:(nullable NSString *)csv;
+ (NSArray<NSString *> *)resolvedToolOrderFromString:(nullable NSString *)csv;

/// 过滤掉不属于全量目录的项并去重，缺失项按默认顺序补尾；不改变已有相对顺序。
+ (NSArray<NSString *> *)resolvedOrderFromString:(nullable NSString *)csv
                                        defaults:(NSArray<NSString *> *)defaults;

/// 隐藏集：只保留目录内 id 并去重（乱序无关）；入参为空返回空集。
+ (NSArray<NSString *> *)normalizedHiddenFromString:(nullable NSString *)csv
                                           defaults:(NSArray<NSString *> *)defaults;

/// 可见项 = 顺序表中不在隐藏集内的项；全部被隐藏时回退为完整顺序（编辑器不允许空面板）。
+ (NSArray<NSString *> *)visibleOrderForOrder:(NSArray<NSString *> *)order
                                       hidden:(NSArray<NSString *> *)hidden;

/// 编辑器与设置预览共用：按模式过滤操作，并兜底保留关闭、完成两个出口。
+ (NSArray<NSString *> *)visibleActionOrderForOrder:(NSArray<NSString *> *)order
                                             hidden:(NSArray<NSString *> *)hidden
                                   fullscreenMarkup:(BOOL)fullscreenMarkup;

+ (NSString *)stringForOrder:(NSArray<NSString *> *)order;

// MARK: 偏好读写（CFPreferences，域 com.pixpin.screenshot）

/// 当前生效顺序：读偏好并解析；未设置时返回默认。
+ (NSArray<NSString *> *)currentActionOrder;
+ (NSArray<NSString *> *)currentToolOrder;

/// 当前隐藏集（目录内 id）；未设置时为空集。
+ (NSArray<NSString *> *)currentActionHidden;
+ (NSArray<NSString *> *)currentToolHidden;

/// 写入原始 CSV（不做合法化，读取侧统一解析）；供设置页保存完整顺序。
+ (void)saveActionOrderString:(nullable NSString *)csv;
+ (void)saveToolOrderString:(nullable NSString *)csv;

/// 写入隐藏集 CSV；传 nil/空串即清空（全部显示）。
+ (void)saveActionHiddenString:(nullable NSString *)csv;
+ (void)saveToolHiddenString:(nullable NSString *)csv;

@end

NS_ASSUME_NONNULL_END
