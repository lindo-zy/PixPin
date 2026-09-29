#import "PXEditorOrderController.h"
#import "PXEditorButtonEditController.h"
#import "../Sources/Common/PXConstants.h"
#import "../Sources/Common/PXEditorOrder.h"
#import "../Sources/Common/PXLog.h"

@interface PXEditorOrderController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISegmentedControl *previewMode;
@property (nonatomic, assign) CGFloat previewWidth;
// 必须 strong：copy 语义会把 NSMutableArray 存成不可变 NSArray，拖动时 removeObjectAtIndex 直接崩溃。
@property (nonatomic, strong) NSMutableArray<NSString *> *actionOrder;
@property (nonatomic, strong) NSMutableArray<NSString *> *toolOrder;
@property (nonatomic, strong) NSMutableArray<NSString *> *selectionOrder;
@property (nonatomic, strong) NSMutableSet<NSString *> *actionHidden;
@property (nonatomic, strong) NSMutableSet<NSString *> *toolHidden;
@property (nonatomic, strong) NSMutableSet<NSString *> *selectionHidden;
@property (nonatomic, weak) UILabel *sizeValueLabel;
@end

@implementation PXEditorOrderController

- (void)loadView {
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.view = self.tableView;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"编辑器与截图按钮排序";
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"恢复默认" style:UIBarButtonItemStylePlain
                                      target:self action:@selector(pxResetTapped:)];
    [self pxReloadFromPreferences];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = 64.0;
    // 编辑模式使用 editingAccessoryView，保留右侧拖动手柄。
    self.tableView.editing = YES;
    self.tableView.allowsSelectionDuringEditing = YES;
    self.previewMode = [[UISegmentedControl alloc] initWithItems:@[@"图片编辑", @"全屏标记"]];
    self.previewMode.selectedSegmentIndex = 0;
    [self.previewMode addTarget:self action:@selector(pxPreviewModeChanged:)
              forControlEvents:UIControlEventValueChanged];
    PXLogInfo(@"prefs editor order opened");
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = CGRectGetWidth(self.tableView.bounds);
    if (width > 0 && fabs(width - self.previewWidth) > 0.5) [self pxRefreshPreview];
}

- (void)pxReloadFromPreferences {
    self.actionOrder = [[PXEditorOrder currentActionOrder] mutableCopy];
    self.toolOrder = [[PXEditorOrder currentToolOrder] mutableCopy];
    self.selectionOrder = [[PXEditorOrder currentSelectionOrder] mutableCopy];
    self.actionHidden = [[NSMutableSet alloc] initWithArray:[PXEditorOrder currentActionHidden]];
    [self.actionHidden removeObject:@"close"];
    [self.actionHidden removeObject:@"done"];
    self.toolHidden = [[NSMutableSet alloc] initWithArray:[PXEditorOrder currentToolHidden]];
    // 出口按钮在设置页始终呈现为开启（与 close/done 同口径）。
    self.selectionHidden = [[NSMutableSet alloc] initWithArray:[PXEditorOrder currentSelectionHidden]];
    [self.selectionHidden removeObject:@"cancel"];
    [self.selectionHidden removeObject:@"confirm"];
}

#pragma mark - 数据源

- (void)pxPreviewModeChanged:(UISegmentedControl *)sender {
    [self pxRefreshPreview];
}

// 预览只展示可排序的按钮；和编辑器共用顺序、显隐、模式过滤及图标来源。
// 不创建截图窗口、不启动编辑任务，所有更新由 UIKit 主线程事件驱动。
- (void)pxRefreshPreview {
    CGFloat width = CGRectGetWidth(self.tableView.bounds);
    if (width <= 0) return;
    self.previewWidth = width;
    CGFloat inset = MAX(16.0, self.tableView.safeAreaInsets.left + 16.0);
    CGFloat rightInset = MAX(16.0, self.tableView.safeAreaInsets.right + 16.0);
    CGFloat contentWidth = MAX(1.0, width - inset - rightInset);
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 1)];
    self.previewMode.frame = CGRectMake(inset, 12, contentWidth, 32);
    [header addSubview:self.previewMode];

    NSArray<NSString *> *actions = [PXEditorOrder visibleActionOrderForOrder:self.actionOrder
                                                                    hidden:self.actionHidden.allObjects
                                                          fullscreenMarkup:self.previewMode.selectedSegmentIndex == 1];
    NSArray<NSString *> *tools = [PXEditorOrder visibleOrderForOrder:self.toolOrder hidden:self.toolHidden.allObjects];
    NSArray<NSString *> *selection = [PXEditorOrder visibleSelectionOrderForOrder:self.selectionOrder
                                                                          hidden:self.selectionHidden.allObjects
                                                                         instant:NO];
    NSArray<NSArray<NSString *> *> *groups = @[actions, tools, selection];
    CGFloat y = 58.0;
    CGFloat gap = 6.0;
    CGFloat padding = 12.0;
    NSInteger columns = MAX(1, MIN(7, (NSInteger)floor((contentWidth - 2 * padding + gap) / (44.0 + gap))));
    CGFloat side = floor((contentWidth - 2 * padding - (columns - 1) * gap) / columns);
    CGFloat iconSize = [PXEditorOrder buttonIconPointSize];
    for (NSInteger section = 0; section < 3; section++) {
        UILabel *caption = [[UILabel alloc] initWithFrame:CGRectMake(inset + 4, y, contentWidth - 8, 22)];
        caption.text = section == 0 ? @"编辑操作预览" : (section == 1 ? @"标记工具预览" : @"截图按钮预览");
        caption.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        caption.textColor = UIColor.secondaryLabelColor;
        [header addSubview:caption];
        y += 28;
        NSArray<NSString *> *order = groups[section];
        NSInteger rows = (order.count + columns - 1) / columns;
        CGFloat cardHeight = padding * 2 + rows * side + MAX(0, rows - 1) * gap;
        UIView *card = [[UIView alloc] initWithFrame:CGRectMake(inset, y, contentWidth, cardHeight)];
        card.backgroundColor = [UIColor colorWithWhite:0.14 alpha:1.0];
        card.layer.cornerRadius = 22.0;
        [header addSubview:card];
        for (NSUInteger i = 0; i < order.count; i++) {
            NSString *identifier = order[i];
            NSString *name = [self displayNameForIdentifier:identifier section:section];
            NSString *symbol = section == 0 ? [PXEditorOrder iconNameForActionIdentifier:identifier]
                                            : (section == 1 ? [PXEditorOrder iconNameForToolIdentifier:identifier]
                                                            : [PXEditorOrder iconNameForSelectionIdentifier:identifier]);
            UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
            button.frame = CGRectMake(padding + (i % columns) * (side + gap),
                                      padding + (i / columns) * (side + gap), side, side);
            button.backgroundColor = [UIColor colorWithWhite:1 alpha:0.10];
            button.layer.cornerRadius = 10.0;
            button.tintColor = UIColor.whiteColor;
            button.userInteractionEnabled = NO;
            button.accessibilityLabel = name;
            button.accessibilityTraits = UIAccessibilityTraitImage;
            UIImage *icon = symbol.length ? [UIImage systemImageNamed:symbol] : nil;
            if (icon) {
                [button setImage:[icon imageWithConfiguration:
                    [UIImageSymbolConfiguration configurationWithPointSize:iconSize weight:UIImageSymbolWeightMedium]]
                        forState:UIControlStateNormal];
            } else {
                [button setTitle:name forState:UIControlStateNormal];
                button.titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
                button.titleLabel.adjustsFontSizeToFitWidth = YES;
            }
            [card addSubview:button];
        }
        y += cardHeight + 14;
    }
    UILabel *note = [[UILabel alloc] initWithFrame:CGRectMake(inset + 4, y, contentWidth - 8, 0)];
    note.text = @"拖动下方手柄排序，预览实时更新。两种模式共用排序；实际面板按可用宽度换行。截图按钮出现在区域选区工具栏，即时模式只显示 取消/全屏/完成。";
    note.font = [UIFont systemFontOfSize:12];
    note.textColor = UIColor.secondaryLabelColor;
    note.numberOfLines = 0;
    CGSize noteSize = [note sizeThatFits:CGSizeMake(contentWidth - 8, CGFLOAT_MAX)];
    note.frame = CGRectMake(inset + 4, y, contentWidth - 8, noteSize.height);
    [header addSubview:note];
    header.frame = CGRectMake(0, 0, width, y + noteSize.height + 8);
    self.tableView.tableHeaderView = header;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 4;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return self.actionOrder.count;
    if (section == 1) return self.toolOrder.count;
    if (section == 2) return self.selectionOrder.count;
    return 1;   // 外观：图标大小
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"编辑操作图标";
    if (section == 1) return @"标记工具图标";
    if (section == 2) return @"截图按钮";
    return @"外观";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) {
        return @"拖动手柄调整顺序，开关控制按钮是否在编辑器显示，点击行可修改图标与名称；修改即时保存，编辑器下次打开生效。“关闭”和“完成”是编辑器唯一出口，始终显示；区域/冻结/即时编辑不含“面板停靠”和“收起面板”。";
    }
    if (section == 1) {
        return @"排序、显隐与自定义图标/名称同时应用于区域编辑和全屏标记的工具面板；全部工具关闭时编辑器会回退为显示全部工具。打开编辑器时默认选中排序后的第一个工具。";
    }
    if (section == 2) {
        return @"区域/冻结截图选区工具栏的按钮排序与显隐；“取消”和“完成”始终显示，“悬浮”把选区结果以可拖动悬浮窗常驻屏幕。即时模式固定为 取消/全屏/完成。";
    }
    return @"调整编辑器按钮图标的显示大小。";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 3) {
        return [self pxSliderCellForTableView:tableView];
    }

    NSString *reuse = @"PXEditorOrderCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuse];
        cell.imageView.tintColor = [UIColor systemBlueColor];
        cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    }
    NSString *identifier = [self identifierAtIndexPath:indexPath];
    NSString *displayName = [self displayNameForIdentifier:identifier section:indexPath.section];
    cell.textLabel.text = displayName;
    // 截图按钮不支持自定义名称/图标：工具栏本体显示文字，点击行不进编辑页。
    cell.detailTextLabel.text = indexPath.section == 2 ? @"拖动右侧排序" : @"拖动右侧排序 · 点击修改图标";
    NSString *iconName = indexPath.section == 0
        ? [PXEditorOrder iconNameForActionIdentifier:identifier]
        : (indexPath.section == 1
            ? [PXEditorOrder iconNameForToolIdentifier:identifier]
            : [PXEditorOrder iconNameForSelectionIdentifier:identifier]);
    cell.imageView.image = iconName.length ? [UIImage systemImageNamed:iconName] : nil;

    UISwitch *toggle = (UISwitch *)cell.accessoryView;
    if (![toggle isKindOfClass:[UISwitch class]]) {
        toggle = [[UISwitch alloc] init];
        [toggle addTarget:self action:@selector(pxVisibilityChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
    }
    cell.editingAccessoryView = toggle;
    // 复用会换行，开关的无障碍名称必须每次随行重设。
    toggle.accessibilityLabel = [NSString stringWithFormat:@"显示%@", displayName ?: @""];
    BOOL alwaysVisible = [self isAlwaysVisibleIdentifier:identifier section:indexPath.section];
    toggle.on = ![self isHiddenIdentifier:identifier section:indexPath.section];
    toggle.enabled = !alwaysVisible;
    cell.showsReorderControl = YES;
    return cell;
}

- (UITableViewCell *)pxSliderCellForTableView:(UITableView *)tableView {
    NSString *reuse = @"PXEditorSizeCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:reuse];
        cell.textLabel.text = @"按钮图标大小";
        UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(0, 0, 150, 31)];
        slider.minimumValue = 12.0;
        slider.maximumValue = 28.0;
        [slider addTarget:self action:@selector(pxIconSizeChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = slider;
        self.sizeValueLabel = cell.detailTextLabel;
    }
    UISlider *slider = (UISlider *)cell.accessoryView;
    cell.editingAccessoryView = slider;
    CGFloat size = [PXEditorOrder buttonIconPointSize];
    if (slider.value != size) slider.value = size;   // 拖动中重入时避免打断
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%.0fpt", size];
    // 复用路径也会走这里，弱引用必须每次重绑到当前 cell 的标签。
    self.sizeValueLabel = cell.detailTextLabel;
    cell.showsReorderControl = NO;
    return cell;
}

- (NSString *)identifierAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) return self.actionOrder[indexPath.row];
    if (indexPath.section == 1) return self.toolOrder[indexPath.row];
    if (indexPath.section == 2) return self.selectionOrder[indexPath.row];
    return @"";
}

- (NSString *)displayNameForIdentifier:(NSString *)identifier section:(NSInteger)section {
    if (section == 0) return [PXEditorOrder displayNameForActionIdentifier:identifier];
    if (section == 1) return [PXEditorOrder displayNameForToolIdentifier:identifier];
    return [PXEditorOrder displayNameForSelectionIdentifier:identifier];
}

- (NSMutableSet<NSString *> *)hiddenSetForSection:(NSInteger)section {
    if (section == 0) return self.actionHidden;
    if (section == 1) return self.toolHidden;
    return self.selectionHidden;
}

- (BOOL)isHiddenIdentifier:(NSString *)identifier section:(NSInteger)section {
    return [[self hiddenSetForSection:section] containsObject:identifier];
}

/// 出口按钮（编辑器 关闭/完成、选区 取消/完成）不提供隐藏开关。
- (BOOL)isAlwaysVisibleIdentifier:(NSString *)identifier section:(NSInteger)section {
    if (section == 0) return ([identifier isEqualToString:@"close"] || [identifier isEqualToString:@"done"]);
    if (section == 2) return ([identifier isEqualToString:@"cancel"] || [identifier isEqualToString:@"confirm"]);
    return NO;
}

#pragma mark - 行点击：编辑图标与名称

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:NO];
    if (indexPath.section >= 2) return;   // 外观行与截图按钮（无自定义图标/名称）不进编辑页
    [self.view endEditing:YES];

    NSString *identifier = [self identifierAtIndexPath:indexPath];
    BOOL isAction = indexPath.section == 0;
    NSString *defaultIcon = isAction
        ? [PXEditorOrder defaultIconNameForActionIdentifier:identifier]
        : [PXEditorOrder defaultIconNameForToolIdentifier:identifier];
    NSString *customIcon = isAction
        ? [PXEditorOrder customIconNameForActionIdentifier:identifier]
        : [PXEditorOrder customIconNameForToolIdentifier:identifier];
    NSString *customName = isAction
        ? [PXEditorOrder customNameForActionIdentifier:identifier]
        : [PXEditorOrder customNameForToolIdentifier:identifier];

    __weak typeof(self) weakSelf = self;
    PXEditorButtonEditController *editor =
        [[PXEditorButtonEditController alloc] initWithIdentifier:identifier
                                                       isAction:isAction
                                                    displayName:[self displayNameForIdentifier:identifier section:indexPath.section]
                                                defaultIconName:defaultIcon
                                                     customName:customName
                                                 customIconName:customIcon
                                                         onSave:^(NSString *name, NSString *iconName) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || !self.presentedViewController.view.window) return;
            if (isAction) {
                [PXEditorOrder saveActionName:name forIdentifier:identifier];
                [PXEditorOrder saveActionIconName:iconName forIdentifier:identifier];
            } else {
                [PXEditorOrder saveToolName:name forIdentifier:identifier];
                [PXEditorOrder saveToolIconName:iconName forIdentifier:identifier];
            }
            PXLogInfo(@"prefs editor button override saved: %@", identifier);
            [self.tableView reloadRowsAtIndexPaths:@[indexPath]
                                  withRowAnimation:UITableViewRowAnimationNone];
            [self pxRefreshPreview];
            [self dismissViewControllerAnimated:YES completion:nil];
        }];
    [self presentViewController:[[UINavigationController alloc] initWithRootViewController:editor]
                       animated:YES completion:nil];
}

#pragma mark - 显隐开关

- (void)pxVisibilityChanged:(UISwitch *)sender {
    CGPoint point = [sender convertPoint:CGPointMake(CGRectGetMidX(sender.bounds), CGRectGetMidY(sender.bounds))
                                  toView:self.tableView];
    NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:point];
    if (!indexPath || indexPath.section >= 3) return;
    NSString *identifier = [self identifierAtIndexPath:indexPath];
    NSMutableSet<NSString *> *hidden = [self hiddenSetForSection:indexPath.section];
    if (sender.on) {
        [hidden removeObject:identifier];
    } else {
        [hidden addObject:identifier];
    }
    [self pxPersistAll];
    [self pxRefreshPreview];
    [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
}

#pragma mark - 图标大小

- (void)pxIconSizeChanged:(UISlider *)sender {
    CGFloat size = MAX(12.0, MIN(28.0, sender.value));
    [PXEditorOrder saveButtonIconPointSize:size];
    self.sizeValueLabel.text = [NSString stringWithFormat:@"%.0fpt", size];
    [self pxRefreshPreview];
}

#pragma mark - 拖动排序

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section < 3;
}

// 只允许同分组内移动，跨组拖动落点无效。
- (NSIndexPath *)tableView:(UITableView *)tableView
   targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)sourceIndexPath
                          toProposedIndexPath:(NSIndexPath *)proposedIndexPath {
    if (sourceIndexPath.section != proposedIndexPath.section) return sourceIndexPath;
    return proposedIndexPath;
}

- (void)tableView:(UITableView *)tableView
    moveRowAtIndexPath:(NSIndexPath *)sourceIndexPath
           toIndexPath:(NSIndexPath *)destinationIndexPath {
    if (sourceIndexPath.section >= 3 || sourceIndexPath.section != destinationIndexPath.section) return;
    NSMutableArray<NSString *> *order = nil;
    if (sourceIndexPath.section == 0) order = self.actionOrder;
    else if (sourceIndexPath.section == 1) order = self.toolOrder;
    else order = self.selectionOrder;
    if (sourceIndexPath.row >= order.count || destinationIndexPath.row >= order.count) return;
    NSString *identifier = order[sourceIndexPath.row];
    [order removeObjectAtIndex:sourceIndexPath.row];
    [order insertObject:identifier atIndex:destinationIndexPath.row];
    [self pxPersistAll];
    [self pxRefreshPreview];
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    return UITableViewCellEditingStyleNone;
}

- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath {
    return NO;
}

#pragma mark - 持久化

- (void)pxPersistAll {
    [PXEditorOrder saveActionOrderString:[PXEditorOrder stringForOrder:self.actionOrder]];
    [PXEditorOrder saveToolOrderString:[PXEditorOrder stringForOrder:self.toolOrder]];
    [PXEditorOrder saveSelectionOrderString:[PXEditorOrder stringForOrder:self.selectionOrder]];
    [PXEditorOrder saveActionHiddenString:[PXEditorOrder stringForOrder:self.actionHidden.allObjects]];
    [PXEditorOrder saveToolHiddenString:[PXEditorOrder stringForOrder:self.toolHidden.allObjects]];
    [PXEditorOrder saveSelectionHiddenString:[PXEditorOrder stringForOrder:self.selectionHidden.allObjects]];
    PXLogInfo(@"prefs editor buttons saved: actions=%@ hidden=%@ tools=%@ hidden=%@ selection=%@ hidden=%@",
              [PXEditorOrder stringForOrder:self.actionOrder],
              [PXEditorOrder stringForOrder:self.actionHidden.allObjects],
              [PXEditorOrder stringForOrder:self.toolOrder],
              [PXEditorOrder stringForOrder:self.toolHidden.allObjects],
              [PXEditorOrder stringForOrder:self.selectionOrder],
              [PXEditorOrder stringForOrder:self.selectionHidden.allObjects]);
}

- (void)pxResetTapped:(UIBarButtonItem *)sender {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"恢复默认"
                                                                   message:@"顺序、显隐、自定义图标/名称和图标大小都会恢复默认。"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"恢复" style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *action) {
        [PXEditorOrder saveActionOrderString:nil];
        [PXEditorOrder saveToolOrderString:nil];
        [PXEditorOrder saveSelectionOrderString:nil];
        [PXEditorOrder saveActionHiddenString:nil];
        [PXEditorOrder saveToolHiddenString:nil];
        [PXEditorOrder saveSelectionHiddenString:nil];
        for (NSString *identifier in [PXEditorOrder defaultActionIdentifiers]) {
            [PXEditorOrder saveActionName:nil forIdentifier:identifier];
            [PXEditorOrder saveActionIconName:nil forIdentifier:identifier];
        }
        for (NSString *identifier in [PXEditorOrder defaultToolIdentifiers]) {
            [PXEditorOrder saveToolName:nil forIdentifier:identifier];
            [PXEditorOrder saveToolIconName:nil forIdentifier:identifier];
        }
        [PXEditorOrder saveButtonIconPointSize:17.0];
        [self pxReloadFromPreferences];
        [self.tableView reloadData];
        [self pxRefreshPreview];
        PXLogInfo(@"prefs editor buttons reset to defaults");
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
