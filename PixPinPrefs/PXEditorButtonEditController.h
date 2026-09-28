#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 编辑器按钮的图标/名称编辑页：名称输入 + SF Symbol 名称输入/预览 + 精选网格（首项恢复默认）。
/// 由排序页在点击行时模态呈现；保存经 block 回调，由排序页写入 PXEditorOrder。
/// customName/customIconName 传 nil 表示当前无覆盖；onSave 的 name/iconName 为 nil 表示清除覆盖。
@interface PXEditorButtonEditController : UIViewController

- (instancetype)initWithIdentifier:(NSString *)identifier
                          isAction:(BOOL)isAction
                       displayName:(NSString *)displayName
                   defaultIconName:(nullable NSString *)defaultIconName
                        customName:(nullable NSString *)customName
                    customIconName:(nullable NSString *)customIconName
                            onSave:(void (^)(NSString * _Nullable name,
                                             NSString * _Nullable iconName))onSave;

@end

NS_ASSUME_NONNULL_END
