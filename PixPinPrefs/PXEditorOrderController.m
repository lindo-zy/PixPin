#import "PXEditorOrderController.h"
#import "PXEditorButtonEditController.h"
#import "../Sources/Common/PXConstants.h"
#import "../Sources/Common/PXEditorOrder.h"
#import "../Sources/Common/PXLog.h"

@interface PXEditorOrderController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
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

// 三个入口共用行交互，sectionKinds 只列出当前页面实际拥有的分组。
// kind：0=编辑操作 1=标记工具 2=截图按钮 3=外观滑杆 4=截图按钮显示样式。
// 外观滑杆三页都保留：所有按钮图标共用一个大小，任意页面均可滑动调整。
- (BOOL)pxFullscreen { return NO; }
- (BOOL)pxRegion { return NO; }
- (NSArray<NSNumber *> *)pxSectionKinds {
    if ([self pxRegion]) return @[@2, @4, @3];
    return @[@0, @1, @3];
}
- (NSInteger)pxKindForSection:(NSInteger)section {
    return [self pxSectionKinds][section].integerValue;
}

- (void)loadView {
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.view = self.tableView;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = [self pxRegion] ? @"区域截图按钮" : ([self pxFullscreen] ? @"全屏截图按钮" : @"图片编辑按钮");
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
    PXLogInfo(@"prefs button settings opened: %@", self.title);
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = CGRectGetWidth(self.tableView.bounds);
    if (width > 0 && fabs(width - self.previewWidth) > 0.5) [self pxRefreshPreview];
}

- (void)pxReloadFromPreferences {
    self.actionOrder = [[PXEditorOrder currentActionOrderForFullscreenMarkup:[self pxFullscreen]] mutableCopy];
    self.toolOrder = [[PXEditorOrder currentToolOrderForFullscreenMarkup:[self pxFullscreen]] mutableCopy];
    if (![self pxFullscreen]) {
        [self.actionOrder removeObject:@"dock"];
        [self.actionOrder removeObject:@"collapse"];
    }
    self.selectionOrder = [[PXEditorOrder currentSelectionOrder] mutableCopy];
    self.actionHidden = [[NSMutableSet alloc] initWithArray:[PXEditorOrder currentActionHiddenForFullscreenMarkup:[self pxFullscreen]]];
    [self.actionHidden removeObject:@"close"];
    [self.actionHidden removeObject:@"done"];
    self.toolHidden = [[NSMutableSet alloc] initWithArray:[PXEditorOrder currentToolHiddenForFullscreenMarkup:[self pxFullscreen]]];
    // 出口按钮在设置页始终呈现为开启（与 close/done 同口径）。
    self.selectionHidden = [[NSMutableSet alloc] initWithArray:[PXEditorOrder currentSelectionHidden]];
    [self.selectionHidden removeObject:@"cancel"];
    [self.selectionHidden removeObject:@"confirm"];
}

#pragma mark - 数据源

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

    NSArray<NSString *> *actions = [PXEditorOrder visibleActionOrderForOrder:self.actionOrder
                                                                    hidden:self.actionHidden.allObjects
                                                          fullscreenMarkup:[self pxFullscreen]];
    NSArray<NSString *> *tools = [PXEditorOrder visibleOrderForOrder:self.toolOrder hidden:self.toolHidden.allObjects];
    NSArray<NSString *> *selection = [PXEditorOrder visibleSelectionOrderForOrder:self.selectionOrder
                                                                          hidden:self.selectionHidden.allObjects
                                                                         instant:NO];
    NSArray<NSArray<NSString *> *> *groups = @[actions, tools, selection];
    CGFloat y = 12.0;
    CGFloat iconSize = [PXEditorOrder buttonIconPointSize];
    // 样式偏好整表读一次：预览重建由拖动/开关高频触发，避免每个按钮一次 CFPreferences 读取。
    BOOL selectionShowsIcon = [PXEditorOrder selectionShowsIcon];
    for (NSNumber *kind in [self pxSectionKinds]) {
        NSInteger section = kind.integerValue;
        if (section == 3 || section == 4) continue;
        UILabel *caption = [[UILabel alloc] initWithFrame:CGRectMake(inset + 4, y, contentWidth - 8, 22)];
        caption.text = section == 0 ? @"编辑操作预览" : (section == 1 ? @"标记工具预览" : @"截图按钮预览");
        caption.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        caption.textColor = UIColor.secondaryLabelColor;
        [header addSubview:caption];
        y += 28;
        NSArray<NSString *> *order = groups[section];
        CGFloat scale = section == 2 && !selectionShowsIcon ? 1.0 : iconSize / 17.0;
        CGFloat referenceWidth = contentWidth / MAX(1.0, scale);
        CGFloat gap = 6.0 * scale;
        CGFloat padding = 12.0 * scale;
        NSInteger columns = MAX(1, MIN(7, (NSInteger)floor((referenceWidth - 24.0 + 6.0) / 50.0)));
        CGFloat side = floor((referenceWidth - 24.0 - (columns - 1) * 6.0) / columns) * scale;
        CGFloat originX = (contentWidth - columns * side - (columns - 1) * gap) / 2.0;
        NSInteger rows = (order.count + columns - 1) / columns;
        CGFloat cardHeight = padding * 2 + rows * side + MAX(0, rows - 1) * gap;
        UIView *card = [[UIView alloc] initWithFrame:CGRectMake(inset, y, contentWidth, cardHeight)];
        card.backgroundColor = [UIColor colorWithWhite:0.14 alpha:1.0];
        card.layer.cornerRadius = 22.0 * scale;
        [header addSubview:card];
        for (NSUInteger i = 0; i < order.count; i++) {
            NSString *identifier = order[i];
            NSString *name = [self pxDisplayNameForIdentifier:identifier kind:section];
            NSString *symbol = section == 0 ? [PXEditorOrder iconNameForActionIdentifier:identifier]
                                            : (section == 1 ? [PXEditorOrder iconNameForToolIdentifier:identifier]
                                                            : [PXEditorOrder iconNameForSelectionIdentifier:identifier]);
            UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
            button.frame = CGRectMake(originX + (i % columns) * (side + gap),
                                      padding + (i / columns) * (side + gap), side, side);
            button.backgroundColor = [UIColor colorWithWhite:1 alpha:0.10];
            button.layer.cornerRadius = 10.0 * scale;
            button.tintColor = UIColor.whiteColor;
            button.userInteractionEnabled = NO;
            button.accessibilityLabel = name;
            button.accessibilityTraits = UIAccessibilityTraitImage;
            // 截图按钮预览跟随"以图标显示"开关，文字模式下直接渲染名称。
            BOOL showIcon = section != 2 || selectionShowsIcon;
            UIImage *icon = showIcon && symbol.length ? [UIImage systemImageNamed:symbol] : nil;
            if (icon) {
                [button setImage:[icon imageWithConfiguration:
                    [UIImageSymbolConfiguration configurationWithPointSize:iconSize weight:UIImageSymbolWeightMedium]]
                        forState:UIControlStateNormal];
            } else {
                [button setTitle:name forState:UIControlStateNormal];
                button.titleLabel.font = [UIFont systemFontOfSize:11 * scale weight:UIFontWeightMedium];
                button.titleLabel.adjustsFontSizeToFitWidth = YES;
            }
            [card addSubview:button];
        }
        y += cardHeight + 14;
    }
    UILabel *note = [[UILabel alloc] initWithFrame:CGRectMake(inset + 4, y, contentWidth - 8, 0)];
    note.text = [self pxRegion]
        ? @"拖动手柄排序，开关控制区域选区按钮显隐，点击行修改名称与图标，“显示样式”切换 图标/文字。修改即时保存，下次打开生效；冻结截图共用此配置，即时模式仅显示 取消、全屏、完成。图标大小与编辑器共用。"
        : ([self pxFullscreen] ? @"仅设置全屏标记面板的按钮顺序与显隐，与区域截图和普通图片编辑相互独立；图标大小三处共用，可在任一按钮设置页调整。修改即时保存，下次打开生效。"
                              : @"设置普通图片编辑的按钮顺序与显隐；名称、图标和大小仍与全屏标记共用。修改即时保存，下次打开生效。");
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
    return [self pxSectionKinds].count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    section = [self pxKindForSection:section];
    if (section == 0) return self.actionOrder.count;
    if (section == 1) return self.toolOrder.count;
    if (section == 2) return self.selectionOrder.count;
    return 1;   // 外观：图标大小
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    section = [self pxKindForSection:section];
    if (section == 0) return @"编辑操作图标";
    if (section == 1) return @"标记工具图标";
    if (section == 2) return @"区域截图按钮";
    if (section == 4) return @"显示样式";
    return @"外观";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    section = [self pxKindForSection:section];
    if (section == 0) {
        return [self pxFullscreen] ? @"拖动排序，开关控制全屏标记操作按钮显隐；关闭和完成始终显示。" : @"拖动排序，开关控制普通图片编辑按钮显隐，点击行修改共用图标与名称。关闭和完成始终显示。";
    }
    if (section == 1) {
        return @"工具排序与显隐仅影响当前页面对应的编辑模式。全部工具关闭时回退显示全部工具，打开编辑器默认选中排序后的第一个工具。";
    }
    if (section == 2) {
        return @"区域/冻结截图选区工具栏的按钮排序与显隐；“取消”和“完成”始终显示，“悬浮”把选区结果以可拖动悬浮窗常驻屏幕。即时模式仅显示 取消/全屏/完成。点击行可修改名称与图标。";
    }
    if (section == 4) {
        return @"开启后选区工具栏显示图标，关闭显示文字，下次打开截图生效；名称与图标修改对两种样式都有效。";
    }
    return @"调整按钮图标的显示大小，三个按钮设置页共用同一数值；区域截图在文字样式下不生效。";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSInteger kind = [self pxKindForSection:indexPath.section];
    if (kind == 3) {
        return [self pxSliderCellForTableView:tableView];
    }
    if (kind == 4) {
        return [self pxIconStyleCellForTableView:tableView];
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
    cell.detailTextLabel.text = [self pxFullscreen] ? @"拖动右侧排序" : @"拖动右侧排序 · 点击修改图标";
    NSString *iconName = kind == 0
        ? [PXEditorOrder iconNameForActionIdentifier:identifier]
        : (kind == 1
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
        slider.minimumValue = 6.0;
        slider.maximumValue = 24.0;
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

// 截图按钮显示样式行：开关即保存，预览即时跟随。
- (UITableViewCell *)pxIconStyleCellForTableView:(UITableView *)tableView {
    NSString *reuse = @"PXEditorIconStyleCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:reuse];
        cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
        UISwitch *toggle = [[UISwitch alloc] init];
        [toggle addTarget:self action:@selector(pxIconStyleChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
    }
    UISwitch *toggle = (UISwitch *)cell.accessoryView;
    cell.editingAccessoryView = toggle;
    cell.textLabel.text = @"以图标显示";
    BOOL showIcon = [PXEditorOrder selectionShowsIcon];
    if (toggle.on != showIcon) toggle.on = showIcon;
    toggle.accessibilityLabel = @"以图标显示截图按钮";
    cell.detailTextLabel.text = showIcon ? @"图标" : @"文字";
    cell.showsReorderControl = NO;
    return cell;
}

- (NSString *)identifierAtIndexPath:(NSIndexPath *)indexPath {
    NSInteger kind = [self pxKindForSection:indexPath.section];
    if (kind == 0) return self.actionOrder[indexPath.row];
    if (kind == 1) return self.toolOrder[indexPath.row];
    if (kind == 2) return self.selectionOrder[indexPath.row];
    return @"";
}

- (NSString *)displayNameForIdentifier:(NSString *)identifier section:(NSInteger)section {
    return [self pxDisplayNameForIdentifier:identifier kind:[self pxKindForSection:section]];
}

- (NSString *)pxDisplayNameForIdentifier:(NSString *)identifier kind:(NSInteger)section {
    if (section == 0) return [PXEditorOrder displayNameForActionIdentifier:identifier];
    if (section == 1) return [PXEditorOrder displayNameForToolIdentifier:identifier];
    return [PXEditorOrder displayNameForSelectionIdentifier:identifier];
}

- (NSMutableSet<NSString *> *)hiddenSetForSection:(NSInteger)section {
    section = [self pxKindForSection:section];
    if (section == 0) return self.actionHidden;
    if (section == 1) return self.toolHidden;
    return self.selectionHidden;
}

- (BOOL)isHiddenIdentifier:(NSString *)identifier section:(NSInteger)section {
    return [[self hiddenSetForSection:section] containsObject:identifier];
}

/// 出口按钮（编辑器 关闭/完成、选区 取消/完成）不提供隐藏开关。
- (BOOL)isAlwaysVisibleIdentifier:(NSString *)identifier section:(NSInteger)section {
    section = [self pxKindForSection:section];
    if (section == 0) return ([identifier isEqualToString:@"close"] || [identifier isEqualToString:@"done"]);
    if (section == 2) return ([identifier isEqualToString:@"cancel"] || [identifier isEqualToString:@"confirm"]);
    return NO;
}

#pragma mark - 行点击：编辑图标与名称

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:NO];
    NSInteger kind = [self pxKindForSection:indexPath.section];
    // 外观/样式行与全屏标记页（名称图标共用普通编辑配置）不进编辑页。
    if (kind >= 3 || [self pxFullscreen]) return;
    [self.view endEditing:YES];

    NSString *identifier = [self identifierAtIndexPath:indexPath];
    // 按目录 kind 分流，不能按 indexPath.section：区域页首个 section 就是截图按钮。
    BOOL isAction = kind == 0;
    BOOL isSelection = kind == 2;
    NSString *defaultIcon = isAction
        ? [PXEditorOrder defaultIconNameForActionIdentifier:identifier]
        : (isSelection
            ? [PXEditorOrder defaultIconNameForSelectionIdentifier:identifier]
            : [PXEditorOrder defaultIconNameForToolIdentifier:identifier]);
    NSString *customIcon = isAction
        ? [PXEditorOrder customIconNameForActionIdentifier:identifier]
        : (isSelection
            ? [PXEditorOrder customIconNameForSelectionIdentifier:identifier]
            : [PXEditorOrder customIconNameForToolIdentifier:identifier]);
    NSString *customName = isAction
        ? [PXEditorOrder customNameForActionIdentifier:identifier]
        : (isSelection
            ? [PXEditorOrder customNameForSelectionIdentifier:identifier]
            : [PXEditorOrder customNameForToolIdentifier:identifier]);

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
            } else if (isSelection) {
                [PXEditorOrder saveSelectionName:name forIdentifier:identifier];
                [PXEditorOrder saveSelectionIconName:iconName forIdentifier:identifier];
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
    if (!indexPath || [self pxKindForSection:indexPath.section] >= 3) return;
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
    CGFloat size = MAX(6.0, MIN(24.0, sender.value));
    [PXEditorOrder saveButtonIconPointSize:size];
    self.sizeValueLabel.text = [NSString stringWithFormat:@"%.0fpt", size];
    [self pxRefreshPreview];
}

// 截图按钮 图标/文字 显示切换：即时保存并刷新预览，工具栏下次打开生效。
- (void)pxIconStyleChanged:(UISwitch *)sender {
    [PXEditorOrder saveSelectionShowsIcon:sender.on];
    CGPoint point = [sender convertPoint:CGPointMake(CGRectGetMidX(sender.bounds), CGRectGetMidY(sender.bounds))
                                  toView:self.tableView];
    NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:point];
    if (indexPath) {
        UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
        cell.detailTextLabel.text = sender.on ? @"图标" : @"文字";
    }
    [self pxRefreshPreview];
    PXLogInfo(@"prefs selection icon style saved: %@", sender.on ? @"icon" : @"text");
}

#pragma mark - 拖动排序

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    return [self pxKindForSection:indexPath.section] < 3;
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
    NSInteger kind = [self pxKindForSection:sourceIndexPath.section];
    if (kind >= 3 || sourceIndexPath.section != destinationIndexPath.section) return;
    NSMutableArray<NSString *> *order = nil;
    if (kind == 0) order = self.actionOrder;
    else if (kind == 1) order = self.toolOrder;
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
    if ([self pxRegion]) {
        [PXEditorOrder saveSelectionOrderString:[PXEditorOrder stringForOrder:self.selectionOrder]];
        [PXEditorOrder saveSelectionHiddenString:[PXEditorOrder stringForOrder:self.selectionHidden.allObjects]];
    } else {
        [PXEditorOrder saveActionOrderString:[PXEditorOrder stringForOrder:self.actionOrder] fullscreenMarkup:[self pxFullscreen]];
        [PXEditorOrder saveToolOrderString:[PXEditorOrder stringForOrder:self.toolOrder] fullscreenMarkup:[self pxFullscreen]];
        [PXEditorOrder saveActionHiddenString:[PXEditorOrder stringForOrder:self.actionHidden.allObjects] fullscreenMarkup:[self pxFullscreen]];
        [PXEditorOrder saveToolHiddenString:[PXEditorOrder stringForOrder:self.toolHidden.allObjects] fullscreenMarkup:[self pxFullscreen]];
    }
    PXLogInfo(@"prefs button settings saved: %@", self.title);
}

- (void)pxResetTapped:(UIBarButtonItem *)sender {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"恢复默认"
                                                                   message:([self pxRegion]
        ? @"恢复区域截图按钮顺序与开关，清除自定义名称与图标，显示样式复位为图标；不影响其他模式。"
        : ([self pxFullscreen] ? @"仅恢复当前页面的按钮顺序与开关，不影响其他模式。" : @"恢复图片编辑按钮顺序与开关，以及共用的名称、图标和大小；全屏标记和区域选区的顺序与开关不变。"))
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"恢复" style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *action) {
        if ([self pxRegion]) {
            [PXEditorOrder saveSelectionOrderString:nil];
            [PXEditorOrder saveSelectionHiddenString:nil];
            for (NSString *identifier in [PXEditorOrder defaultSelectionIdentifiers]) {
                [PXEditorOrder saveSelectionName:nil forIdentifier:identifier];
                [PXEditorOrder saveSelectionIconName:nil forIdentifier:identifier];
            }
            [PXEditorOrder saveSelectionShowsIcon:YES];
        } else {
            [PXEditorOrder saveActionOrderString:nil fullscreenMarkup:[self pxFullscreen]];
            [PXEditorOrder saveToolOrderString:nil fullscreenMarkup:[self pxFullscreen]];
            [PXEditorOrder saveActionHiddenString:nil fullscreenMarkup:[self pxFullscreen]];
            [PXEditorOrder saveToolHiddenString:nil fullscreenMarkup:[self pxFullscreen]];
        }
        if (![self pxRegion] && ![self pxFullscreen]) {
            for (NSString *identifier in [PXEditorOrder defaultActionIdentifiers]) {
                [PXEditorOrder saveActionName:nil forIdentifier:identifier];
                [PXEditorOrder saveActionIconName:nil forIdentifier:identifier];
            }
            for (NSString *identifier in [PXEditorOrder defaultToolIdentifiers]) {
                [PXEditorOrder saveToolName:nil forIdentifier:identifier];
                [PXEditorOrder saveToolIconName:nil forIdentifier:identifier];
            }
            [PXEditorOrder saveButtonIconPointSize:17.0];
        }
        [self pxReloadFromPreferences];
        [self.tableView reloadData];
        [self pxRefreshPreview];
        PXLogInfo(@"prefs editor buttons reset to defaults");
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end

@implementation PXFullscreenButtonController
- (BOOL)pxFullscreen { return YES; }
@end

@implementation PXRegionButtonController
- (BOOL)pxRegion { return YES; }
@end
