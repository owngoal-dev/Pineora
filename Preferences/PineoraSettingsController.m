#import "PineoraSettingsController.h"
#import "PineoraStore.h"

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
@end

@implementation PineoraSettingsController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.store = [PineoraStore new];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:kPineoraCell];
    self.tableView.tableHeaderView = [self makeHeaderView];
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
    subtitle.text = @"主屏图标主题";
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

#pragma mark - 编辑

- (void)setEditing:(BOOL)editing animated:(BOOL)animated {
    [super setEditing:editing animated:animated];
    // 编辑态只用来排序；“可用主题”和“应用”在编辑时没意义。
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(PineoraSectionAvailable, 2)]
                  withRowAnimation:UITableViewRowAnimationFade];
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
            return self.editing ? 0 : (NSInteger)self.store.inactiveThemes.count;
        case PineoraSectionApply:
            return self.editing ? 0 : 1;
        default:
            return 0;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    switch (section) {
        case PineoraSectionActive:
            return @"已启用的主题";
        case PineoraSectionAvailable:
            return self.editing || self.store.inactiveThemes.count == 0 ? nil : @"可用主题";
        default:
            return nil;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView;
    PineoraStore *store = self.store;
    switch (section) {
        case PineoraSectionEnable:
            return @"关闭后主屏显示系统原图标。";
        case PineoraSectionActive: {
            NSMutableArray<NSString *> *lines = [NSMutableArray array];
            if (store.activeThemes.count == 0 && store.inactiveThemes.count == 0) {
                [lines addObject:[NSString stringWithFormat:@"把 .theme 放进以下目录：\n%@",
                                  [store.searchDirectories componentsJoinedByString:@"\n"]]];
            } else {
                [lines addObject:@"排在上面的主题优先；点右上角“编辑”拖动排序，点主题停用它。"];
            }
            if (!store.hasExplicitSelection) {
                [lines addObject:@"尚未选择：引擎沿用 SnowBoard 的已选主题，没有时启用全部主题。"];
            }
            if (store.missingThemeNames.count > 0) {
                [lines addObject:[NSString stringWithFormat:@"已保存但找不到：%@",
                                  [store.missingThemeNames componentsJoinedByString:@"、"]]];
            }
            return [lines componentsJoinedByString:@"\n\n"];
        }
        case PineoraSectionApply:
            if (self.editing) {
                return nil;
            }
            return store.hasUnappliedChanges
                ? @"有未应用的更改。"
                : @"改动或更新主题文件后点这里，主屏会重新读取主题。";
        default:
            return nil;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kPineoraCell forIndexPath:indexPath];
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    UIListContentConfiguration *content = [UIListContentConfiguration subtitleCellConfiguration];

    switch (indexPath.section) {
        case PineoraSectionEnable: {
            content = [UIListContentConfiguration cellConfiguration];
            content.text = @"启用";
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
                content.text = self.store.inactiveThemes.count == 0 ? @"没有找到主题" : @"未启用主题";
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
            content = [UIListContentConfiguration cellConfiguration];
            content.text = self.justApplied ? @"已应用" : @"应用更改";
            content.textProperties.color = self.view.tintColor;
            break;
        default:
            break;
    }
    cell.contentConfiguration = content;
    return cell;
}

- (void)configure:(UIListContentConfiguration *)content theme:(PineoraThemeItem *)theme {
    content.text = theme.title;
    content.secondaryText = theme.iconCount < 0 ? @" " : [NSString stringWithFormat:@"%ld 个图标", (long)theme.iconCount];
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
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
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
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                self.justApplied = NO;
                [self reloadApplySection];
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
}

- (void)reloadThemeSections {
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(PineoraSectionActive, 3)]
                  withRowAnimation:UITableViewRowAnimationAutomatic];
}

- (void)reloadApplySection {
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:PineoraSectionApply]
                  withRowAnimation:UITableViewRowAnimationNone];
}

@end
