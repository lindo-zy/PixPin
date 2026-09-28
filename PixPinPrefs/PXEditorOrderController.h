#import <Preferences/PSViewController.h>

/// 编辑器按钮排序页：两个分组（操作按钮 / 工具按钮），编辑模式拖动排序，
/// 顶部实时预览，右上角恢复默认。保存直接写 CFPreferences，编辑器下次打开生效。
/// PSLinkCell 的 detail 必须实现 Preferences 的 specifier / parentController 等接口。
@interface PXEditorOrderController : PSViewController
@end
