#import <Foundation/Foundation.h>
#import "PXShellXBridge.h"

NS_ASSUME_NONNULL_BEGIN

// 数值沿用旧 SelectionButtonIconStyle 布尔配置：0=文字，1=图标。
typedef NS_ENUM(NSInteger, PXSelectionButtonStyle) {
    PXSelectionButtonStyleText = 0,
    PXSelectionButtonStyleIcon = 1,
    PXSelectionButtonStyleIconAndText = 2,
};

/// 用户在设置页自定义的 URL scheme 快捷按钮（数量不限，出现在截图按钮工具栏）。
@interface PXCustomSelectionButton : NSObject
/// url<n> 形式；删除后序号不复用，旧顺序 CSV 中的残留 id 由解析层剔除。
@property (nonatomic, readonly) NSString *identifier;
@property (nonatomic, readonly) NSString *name;
/// SF Symbol 名；允许为空串（工具栏回退显示名称）。
@property (nonatomic, readonly) NSString *iconName;
/// 完整 URL 字符串（含 scheme），点击时经 SpringBoard openURL 打开。
@property (nonatomic, readonly) NSString *url;
@end

/// 编辑器按钮目录与顺序解析：主 tweak、设置包、宿主测试三方共用。
/// 顺序偏好以 CSV 存储；解析策略固定：未知剔除、重复只保留首次、缺失按默认顺序补尾。
/// 读取与写入直接走 CFPreferences（编辑器每次打开解析一次，遵循"新配置从下一个任务生效"）。
@interface PXEditorOrder : NSObject

// MARK: 目录（id 顺序即默认顺序）

/// 全部操作按钮 id：关闭/撤销/重做/裁剪/旋转/复制/分享/保存/适屏/删除/置顶/面板停靠/收起面板/完成。
/// dock、collapse 仅全屏标记显示，其他模式解析后自行过滤。
+ (NSArray<NSString *> *)defaultActionIdentifiers;
/// 写死固定的操作按钮 id（关闭/撤销/完成）：图标、名称、顺序、显隐均不随偏好变化，设置页不出现。
/// 全屏标记第四角键“取色”是独立彩虹环按钮，无目录 id，本就不可定制。
+ (NSArray<NSString *> *)fixedActionIdentifiers;
/// 全部工具按钮 id：画笔/平移/方框/椭圆/箭头/放大镜/直线/马赛克/文字/实心方/实心圆/聚光/荧光/贴纸/序号图章。
+ (NSArray<NSString *> *)defaultToolIdentifiers;
/// 区域选区工具栏按钮 id：取消/全屏/全屏标记/编辑/悬浮/滚动截图/保存/复制，外加 SHELLX 扩展组。
/// （「完成」已随 2.0.8 移除：默认配置下与保存动作完全重复。）
+ (NSArray<NSString *> *)defaultSelectionIdentifiers;
/// SHELLX 扩展按钮 id 子集（区域/即时/冻结/套壳/关闭/记录/最近/长图/整屏/标记/编辑/问答/
/// 翻译/扫码）：仅在 SHELLX 在场且总开关打开时由调用方保留在工具栏，其余场合从顺序中
/// 整体剔除（设置页不受此限制）。
+ (NSArray<NSString *> *)shellxSelectionIdentifiers;
/// SHELLX 扩展按钮 id → 外调动作映射。键集合必须与 shellxSelectionIdentifiers 一致：
/// 目录加了按钮而映射漏配时，点击会静默掉进本方输出动作分支，宿主测试钉住这一前提。
+ (NSDictionary<NSString *, NSNumber *> *)shellxSelectionActionMap;

+ (NSString *)displayNameForActionIdentifier:(NSString *)identifier;
+ (NSString *)displayNameForToolIdentifier:(NSString *)identifier;
+ (NSString *)displayNameForSelectionIdentifier:(NSString *)identifier;

/// SF Symbol 名（编辑器按钮与设置页排序条目共用）；无对应符号返回 nil。
/// 均为"自定义覆盖优先，缺省回目录默认"；自定义符号失效时由调用方回退显示名称。
+ (NSString *)iconNameForActionIdentifier:(NSString *)identifier;
+ (NSString *)iconNameForToolIdentifier:(NSString *)identifier;
/// 选区按钮符号：目录默认 + 自定义覆盖合并；图标及图标＋文字样式使用，设置页条目始终展示。
+ (NSString *)iconNameForSelectionIdentifier:(NSString *)identifier;

/// 目录默认符号（不含覆盖），供编辑页展示"默认"项。
+ (NSString *)defaultIconNameForActionIdentifier:(NSString *)identifier;
+ (NSString *)defaultIconNameForToolIdentifier:(NSString *)identifier;
+ (NSString *)defaultIconNameForSelectionIdentifier:(NSString *)identifier;

// MARK: 自定义名称/图标覆盖（设置页"点击行修改"，存 id=值 CSV；nil 值即清除覆盖）

+ (nullable NSString *)customNameForActionIdentifier:(NSString *)identifier;
+ (nullable NSString *)customNameForToolIdentifier:(NSString *)identifier;
+ (nullable NSString *)customNameForSelectionIdentifier:(NSString *)identifier;
+ (nullable NSString *)customIconNameForActionIdentifier:(NSString *)identifier;
+ (nullable NSString *)customIconNameForToolIdentifier:(NSString *)identifier;
+ (nullable NSString *)customIconNameForSelectionIdentifier:(NSString *)identifier;

/// 写入前必须清洗：名称去除逗号/等号并截断到 12 字符；符号传空串清除覆盖。
+ (void)saveActionName:(nullable NSString *)name forIdentifier:(NSString *)identifier;
+ (void)saveToolName:(nullable NSString *)name forIdentifier:(NSString *)identifier;
+ (void)saveSelectionName:(nullable NSString *)name forIdentifier:(NSString *)identifier;
+ (void)saveActionIconName:(nullable NSString *)symbolName forIdentifier:(NSString *)identifier;
+ (void)saveToolIconName:(nullable NSString *)symbolName forIdentifier:(NSString *)identifier;
+ (void)saveSelectionIconName:(nullable NSString *)symbolName forIdentifier:(NSString *)identifier;

// MARK: 自定义 URL 按钮（数量不限；存 SelectionCustomButtons 行记录 CSV：id,name,icon,url）

+ (NSArray<PXCustomSelectionButton *> *)customSelectionButtons;
+ (NSArray<NSString *> *)customSelectionIdentifiers;
/// 自定义按钮的打开地址；非自定义 id 返回 nil。
+ (nullable NSString *)customURLForSelectionIdentifier:(NSString *)identifier;
/// 保存（identifier 传 nil 或不存在时生成新 id）；返回清洗后的记录，name/url 非法返回 nil。
+ (nullable PXCustomSelectionButton *)saveCustomSelectionButtonWithID:(nullable NSString *)identifier
                                                                 name:(NSString *)name
                                                                 icon:(nullable NSString *)iconName
                                                                  url:(NSString *)url;
+ (void)removeCustomSelectionButtonWithID:(NSString *)identifier;
/// 静态目录 + 现存自定义 id 的合并目录；顺序解析与隐藏集过滤共用，保证自定义 id 不被剔除。
+ (NSArray<NSString *> *)selectionCatalogIdentifiers;

// MARK: 截图按钮外观

/// 默认图标；兼容旧布尔配置，无效值回退默认。工具栏与设置预览使用同一枚举。
+ (PXSelectionButtonStyle)selectionButtonStyle;
+ (void)saveSelectionButtonStyle:(PXSelectionButtonStyle)style;

// MARK: 外观

/// 共用按钮图标点大小；区域截图三种样式的图标、文字和布局均按此比例缩放。默认 17，夹取 10–20。
+ (CGFloat)buttonIconPointSize;
+ (void)saveButtonIconPointSize:(CGFloat)size;

// MARK: 解析与序列化

/// 把任意偏好字符串解析为覆盖全部 id 的合法顺序；入参为空返回默认顺序。
+ (NSArray<NSString *> *)resolvedActionOrderFromString:(nullable NSString *)csv;
+ (NSArray<NSString *> *)resolvedToolOrderFromString:(nullable NSString *)csv;
+ (NSArray<NSString *> *)resolvedSelectionOrderFromString:(nullable NSString *)csv;

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

/// 把写死的固定按钮（关闭/撤销/完成）从顺序表摘出，按目录默认位置钉回：
/// 固定键不参与用户排序，其余按钮的相对顺序不变。
+ (NSArray<NSString *> *)orderWithFixedActionButtonsPinned:(NSArray<NSString *> *)order;

/// 选区工具栏可见顺序：兜底保留取消出口；即时模式只保留取消/全屏。
+ (NSArray<NSString *> *)visibleSelectionOrderForOrder:(NSArray<NSString *> *)order
                                                hidden:(NSArray<NSString *> *)hidden
                                               instant:(BOOL)instant;

+ (NSString *)stringForOrder:(NSArray<NSString *> *)order;

// 全屏标记独立配置；首次读取复制旧编辑器配置，此后不再跟随普通编辑器变化。
+ (NSArray<NSString *> *)currentActionOrderForFullscreenMarkup:(BOOL)fullscreen;
+ (NSArray<NSString *> *)currentToolOrderForFullscreenMarkup:(BOOL)fullscreen;
+ (NSArray<NSString *> *)currentActionHiddenForFullscreenMarkup:(BOOL)fullscreen;
+ (NSArray<NSString *> *)currentToolHiddenForFullscreenMarkup:(BOOL)fullscreen;
+ (void)saveActionOrderString:(nullable NSString *)csv fullscreenMarkup:(BOOL)fullscreen;
+ (void)saveToolOrderString:(nullable NSString *)csv fullscreenMarkup:(BOOL)fullscreen;
+ (void)saveActionHiddenString:(nullable NSString *)csv fullscreenMarkup:(BOOL)fullscreen;
+ (void)saveToolHiddenString:(nullable NSString *)csv fullscreenMarkup:(BOOL)fullscreen;

// MARK: 偏好读写（CFPreferences，域 com.pixpin.screenshot）

/// 当前生效顺序：读偏好并解析；未设置时返回默认。
+ (NSArray<NSString *> *)currentActionOrder;
+ (NSArray<NSString *> *)currentToolOrder;
+ (NSArray<NSString *> *)currentSelectionOrder;

/// 当前隐藏集（目录内 id）；未设置时为空集。
+ (NSArray<NSString *> *)currentActionHidden;
+ (NSArray<NSString *> *)currentToolHidden;
+ (NSArray<NSString *> *)currentSelectionHidden;

/// 写入原始 CSV（不做合法化，读取侧统一解析）；供设置页保存完整顺序。
+ (void)saveActionOrderString:(nullable NSString *)csv;
+ (void)saveToolOrderString:(nullable NSString *)csv;
+ (void)saveSelectionOrderString:(nullable NSString *)csv;

/// 写入隐藏集 CSV；传 nil/空串即清空（全部显示）。
+ (void)saveActionHiddenString:(nullable NSString *)csv;
+ (void)saveToolHiddenString:(nullable NSString *)csv;
+ (void)saveSelectionHiddenString:(nullable NSString *)csv;

@end

NS_ASSUME_NONNULL_END
