#import <Preferences/PSViewController.h>

/// 图片编辑按钮设置；两个子类分别提供全屏标记与区域选区按钮设置。
/// 编辑模式拖动排序，
/// 顶部实时预览，右上角恢复默认。保存直接写 CFPreferences，编辑器下次打开生效。
/// PSLinkCell 的 detail 必须实现 Preferences 的 specifier / parentController 等接口。
@interface PXEditorOrderController : PSViewController
@end

@interface PXFullscreenButtonController : PXEditorOrderController
@end

@interface PXRegionButtonController : PXEditorOrderController
@end
