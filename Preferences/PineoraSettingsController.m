#import "PineoraSettingsController.h"
#import "PineoraStore.h"
#import "PineoraLocalization.h"

typedef NS_ENUM(NSInteger, PineoraSection) {
    PineoraSectionEnable,
    PineoraSectionActive,
    PineoraSectionAvailable,
    PineoraSectionApply,
    PineoraSectionCount,
};

static NSString *const kPineoraCell = @"cell";

@interface PineoraSettingsController ()
@property (nonatomic, strong) PineoraStore *store;
@property (nonatomic, assign) BOOL justApplied;
@property (nonatomic, assign) NSUInteger applyGeneration;
@end

@implementation PineoraSettingsController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.store = [PineoraStore new];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:kPineoraCell];
    self.tableView.tableHeaderView = [self makeHeaderView];
    // Keep reorder handles available without a separate Edit/Done mode.
    self.tableView.allowsSelectionDuringEditing = YES;
    [self setEditing:YES animated:NO];
    [self reloadFromStore];
}

- (void)reloadFromStore {
    if (self.store == nil) {
        return;
    }
    [self.store reload];
    [self.tableView reloadData];
    [self.store loadDetails:^{
        [self.tableView reloadData];
    }];
}

#pragma mark - 头部

- (UIView *)makeHeaderView {
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:30 weight:UIImageSymbolWeightSemibold];
    UIImageView *glyph = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"paintbrush.pointed.fill" withConfiguration:config]];
    glyph.tintColor = [UIColor whiteColor];
    glyph.contentMode = UIViewContentModeCenter;
    glyph.translatesAutoresizingMaskIntoConstraints = NO;

    UIView *tile = [UIView new];
    tile.backgroundColor = [UIColor systemIndigoColor];
    tile.layer.cornerRadius = 16;
    tile.layer.cornerCurve = kCACornerCurveContinuous;
    tile.translatesAutoresizingMaskIntoConstraints = NO;
    [tile addSubview:glyph];

    UILabel *title = [UILabel new];
    title.text = @"Pineora";
    title.font = [UIFont systemFontOfSize:28 weight:UIFontWeightBold];
    title.textAlignment = NSTextAlignmentCenter;

    UILabel *subtitle = [UILabel new];
    subtitle.text = PineoraLocalizedString(@"settings.subtitle");
    subtitle.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    subtitle.textColor = [UIColor secondaryLabelColor];
    subtitle.textAlignment = NSTextAlignmentCenter;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[tile, title, subtitle]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.spacing = 6;
    [stack setCustomSpacing:12 afterView:tile];
    stack.translatesAutoresizingMaskIntoConstraints = NO;

    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 170)];
    [header addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [tile.widthAnchor constraintEqualToConstant:64],
        [tile.heightAnchor constraintEqualToConstant:64],
        [glyph.centerXAnchor constraintEqualToAnchor:tile.centerXAnchor],
        [glyph.centerYAnchor constraintEqualToAnchor:tile.centerYAnchor],
        [stack.centerXAnchor constraintEqualToAnchor:header.centerXAnchor],
        [stack.centerYAnchor constraintEqualToAnchor:header.centerYAnchor constant:4],
    ]];
    return header;
}

#pragma mark - 排序模式

- (void)setEditing:(BOOL)editing animated:(BOOL)animated {
    // Sorting is always available; there is no separate editing UI.
    (void)editing;
    [super setEditing:YES animated:animated];
}

#pragma mark - 数据源

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return PineoraSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    switch (section) {
        case PineoraSectionEnable:
            return 1;
        case PineoraSectionActive:
            return MAX((NSInteger)self.store.activeThemes.count, 1);  // 空时放一行说明
        case PineoraSectionAvailable:
            return (NSInteger)self.store.inactiveThemes.count;
        case PineoraSectionApply:
            return 1;
        default:
            return 0;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    switch (section) {
        case PineoraSectionActive:
            return PineoraLocalizedString(@"themes.active");
        case PineoraSectionAvailable:
            return self.store.inactiveThemes.count == 0 ? nil : PineoraLocalizedString(@"themes.available");
        default:
            return nil;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView;
    PineoraStore *store = self.store;
    switch (section) {
        case PineoraSectionEnable:
            return PineoraLocalizedString(@"settings.disabled_footer");
        case PineoraSectionActive: {
            NSMutableArray<NSString *> *lines = [NSMutableArray array];
            if (store.activeThemes.count == 0 && store.inactiveThemes.count == 0) {
                [lines addObject:[NSString stringWithFormat:PineoraLocalizedString(@"themes.install_footer"),
                                  [store.searchDirectories componentsJoinedByString:@"\n"]]];
            } else {
                [lines addObject:PineoraLocalizedString(@"themes.order_footer")];
            }
            if (!store.hasExplicitSelection) {
                [lines addObject:PineoraLocalizedString(@"themes.default_footer")];
            }
            if (store.missingThemeNames.count > 0) {
                [lines addObject:[NSString stringWithFormat:PineoraLocalizedString(@"themes.missing_footer"),
                                  [store.missingThemeNames componentsJoinedByString:PineoraLocalizedString(@"themes.list_separator")]]];
            }
            return [lines componentsJoinedByString:@"\n\n"];
        }
        case PineoraSectionApply:
            return store.hasUnappliedChanges
                ? PineoraLocalizedString(@"settings.unapplied_footer")
                : PineoraLocalizedString(@"settings.apply_footer");
        default:
            return nil;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kPineoraCell forIndexPath:indexPath];
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.showsReorderControl = indexPath.section == PineoraSectionActive && self.store.activeThemes.count > 1;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    UIListContentConfiguration *content = [UIListContentConfiguration subtitleCellConfiguration];

    switch (indexPath.section) {
        case PineoraSectionEnable: {
            content = [UIListContentConfiguration cellConfiguration];
            content.text = PineoraLocalizedString(@"settings.enable");
            UISwitch *toggle = [UISwitch new];
            toggle.on = self.store.enabled;
            [toggle addTarget:self action:@selector(enabledChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = toggle;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            break;
        }
        case PineoraSectionActive:
            if (self.store.activeThemes.count == 0) {
                content = [UIListContentConfiguration cellConfiguration];
                content.text = self.store.inactiveThemes.count == 0 ? PineoraLocalizedString(@"themes.empty") : PineoraLocalizedString(@"themes.none_active");
                content.textProperties.color = [UIColor secondaryLabelColor];
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
            } else {
                [self configure:content theme:self.store.activeThemes[indexPath.row]];
                cell.accessoryType = UITableViewCellAccessoryCheckmark;
            }
            break;
        case PineoraSectionAvailable:
            [self configure:content theme:self.store.inactiveThemes[indexPath.row]];
            break;
        case PineoraSectionApply:
            content = [self applyContent];
            break;
        default:
            break;
    }
    cell.contentConfiguration = content;
    return cell;
}

- (UIListContentConfiguration *)applyContent {
    UIListContentConfiguration *content = [UIListContentConfiguration cellConfiguration];
    content.text = self.justApplied ? PineoraLocalizedString(@"settings.applied") : PineoraLocalizedString(@"settings.apply");
    content.textProperties.color = self.view.tintColor;
    return content;
}

- (void)configure:(UIListContentConfiguration *)content theme:(PineoraThemeItem *)theme {
    content.text = theme.title;
    content.secondaryText = theme.summary ?: (theme.iconCount < 0 ? @" " : [NSString stringWithFormat:PineoraLocalizedString(@"theme.icon_count"), (long)theme.iconCount]);
    content.secondaryTextProperties.color = [UIColor secondaryLabelColor];
    UIImage *placeholder = [UIImage systemImageNamed:@"square.dashed"];
    content.image = theme.preview ?: placeholder;
    content.imageProperties.tintColor = [UIColor tertiaryLabelColor];
    content.imageProperties.maximumSize = CGSizeMake(29, 29);
    content.imageProperties.reservedLayoutSize = CGSizeMake(29, 29);
}

#pragma mark - 排序

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    return indexPath.section == PineoraSectionActive && self.store.activeThemes.count > 1;
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    return [self tableView:tableView canEditRowAtIndexPath:indexPath];
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    (void)indexPath;
    return UITableViewCellEditingStyleNone;
}

- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    (void)indexPath;
    return NO;
}

- (NSIndexPath *)tableView:(UITableView *)tableView targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)source
       toProposedIndexPath:(NSIndexPath *)proposed {
    (void)tableView;
    if (proposed.section < PineoraSectionActive) {
        return [NSIndexPath indexPathForRow:0 inSection:PineoraSectionActive];
    }
    if (proposed.section > PineoraSectionActive) {
        return [NSIndexPath indexPathForRow:(NSInteger)self.store.activeThemes.count - 1 inSection:PineoraSectionActive];
    }
    (void)source;
    return proposed;
}

- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)source toIndexPath:(NSIndexPath *)destination {
    [self.store moveActiveThemeAtIndex:(NSUInteger)source.row toIndex:(NSUInteger)destination.row];
    [self markChanged];
    // 移动后刷新脚注里的“未应用”提示，不重载被移动的行。
    dispatch_async(dispatch_get_main_queue(), ^{
        [tableView reloadData];
    });
}

#pragma mark - 选择

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    // “应用”行的文字切换不要任何动画，连取消高亮也直接完成。
    [tableView deselectRowAtIndexPath:indexPath animated:indexPath.section != PineoraSectionApply];
    switch (indexPath.section) {
        case PineoraSectionActive:
            if (self.store.activeThemes.count > 0) {
                [self.store deactivateTheme:self.store.activeThemes[indexPath.row]];
                [self markChanged];
                [self reloadThemeSections];
            }
            break;
        case PineoraSectionAvailable:
            [self.store activateTheme:self.store.inactiveThemes[indexPath.row]];
            [self markChanged];
            [self reloadThemeSections];
            break;
        case PineoraSectionApply: {
            [self.store apply];
            [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess];
            self.justApplied = YES;
            [self reloadApplySection];
            // 连点时只让最后一次的计时把文字改回去。
            NSUInteger generation = ++self.applyGeneration;
            __weak __typeof__(self) weakSelf = self;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (weakSelf == nil || weakSelf.applyGeneration != generation) {
                    return;
                }
                weakSelf.justApplied = NO;
                [weakSelf reloadApplySection];
            });
            break;
        }
        default:
            break;
    }
}

- (void)enabledChanged:(UISwitch *)toggle {
    [self.store setEnabled:toggle.on];
    [self markChanged];
    [self reloadApplySection];
}

- (void)markChanged {
    self.justApplied = NO;
    self.applyGeneration++;
}

- (void)reloadThemeSections {
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(PineoraSectionActive, 2)]
                  withRowAnimation:UITableViewRowAnimationAutomatic];
    [self reloadApplySection];
}

/// 原地改“应用”行和它的脚注，不 reloadSections：重载会换一个新 cell，
/// 新旧 cell 在过渡里叠在一起，正好撞上取消选中的动画，就是截图里的重影。
- (void)reloadApplySection {
    NSIndexPath *row = [NSIndexPath indexPathForRow:0 inSection:PineoraSectionApply];
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:row];
    UITableViewHeaderFooterView *footer = [self.tableView footerViewForSection:PineoraSectionApply];
    NSString *footerText = [self tableView:self.tableView titleForFooterInSection:PineoraSectionApply];
    [UIView performWithoutAnimation:^{
        cell.contentConfiguration = [self applyContent];
        id footerContent = footer.contentConfiguration;
        if ([footerContent isKindOfClass:[UIListContentConfiguration class]]) {
            UIListContentConfiguration *updated = [footerContent copy];
            updated.text = footerText;
            footer.contentConfiguration = updated;
        } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            footer.textLabel.text = footerText;
#pragma clang diagnostic pop
            [footer setNeedsLayout];
        }
        // 脚注行数变了时只重算高度，不重建任何视图。
        [self.tableView beginUpdates];
        [self.tableView endUpdates];
    }];
}

@end
