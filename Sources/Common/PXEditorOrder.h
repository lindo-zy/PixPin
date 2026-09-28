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

// MARK: 解析与序列化

/// 把任意偏好字符串解析为覆盖全部 id 的合法顺序；入参为空返回默认顺序。
+ (NSArray<NSString *> *)resolvedActionOrderFromString:(nullable NSString *)csv;
+ (NSArray<NSString *> *)resolvedToolOrderFromString:(nullable NSString *)csv;

/// 过滤掉不属于全量目录的项并去重，缺失项按默认顺序补尾；不改变已有相对顺序。
+ (NSArray<NSString *> *)resolvedOrderFromString:(nullable NSString *)csv
                                        defaults:(NSArray<NSString *> *)defaults;

+ (NSString *)stringForOrder:(NSArray<NSString *> *)order;

// MARK: 偏好读写（CFPreferences，域 com.pixpin.screenshot）

/// 当前生效顺序：读偏好并解析；未设置时返回默认。
+ (NSArray<NSString *> *)currentActionOrder;
+ (NSArray<NSString *> *)currentToolOrder;

/// 写入原始 CSV（不做合法化，读取侧统一解析）；供设置页保存完整顺序。
+ (void)saveActionOrderString:(nullable NSString *)csv;
+ (void)saveToolOrderString:(nullable NSString *)csv;

@end

NS_ASSUME_NONNULL_END
