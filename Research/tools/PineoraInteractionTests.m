// Offscreen controller tests with an in-memory store: no real preferences or notifications.
#import <UIKit/UIKit.h>
#import "../../Preferences/PineoraStore.h"
#import "../../Preferences/PineoraSettingsController.h"

@interface PineoraThemeItem ()
@property (nonatomic, copy, readwrite) NSString *name, *path, *title;
@end
@implementation PineoraThemeItem
@end
@interface PineoraStore ()
@property (nonatomic, copy, readwrite) NSArray<PineoraThemeItem *> *activeThemes, *inactiveThemes;
@property (nonatomic, assign, readwrite) BOOL enabled, hasExplicitSelection, hasUnappliedChanges;
@property (nonatomic, copy, readwrite) NSArray<NSString *> *missingThemeNames, *searchDirectories;
@end
@implementation PineoraStore
- (instancetype)init {
    if ((self = [super init])) {
        PineoraThemeItem *a = [PineoraThemeItem new], *b = [PineoraThemeItem new], *c = [PineoraThemeItem new];
        a.title = @"A"; b.title = @"B"; c.title = @"C";
        _activeThemes = @[a,b]; _inactiveThemes = @[c]; _enabled = YES;
        _hasExplicitSelection = YES; _missingThemeNames = @[]; _searchDirectories = @[];
    }
    return self;
}
- (void)reload {}
- (void)loadDetails:(void (^)(void))completion { completion(); }
- (void)activateTheme:(PineoraThemeItem *)theme {
    self.activeThemes = [self.activeThemes arrayByAddingObject:theme];
    NSMutableArray *items = self.inactiveThemes.mutableCopy; [items removeObject:theme]; self.inactiveThemes = items;
    self.hasUnappliedChanges = YES;
}
- (void)deactivateTheme:(PineoraThemeItem *)theme {
    self.inactiveThemes = [self.inactiveThemes arrayByAddingObject:theme];
    NSMutableArray *items = self.activeThemes.mutableCopy; [items removeObject:theme]; self.activeThemes = items;
    self.hasUnappliedChanges = YES;
}
- (void)moveActiveThemeAtIndex:(NSUInteger)from toIndex:(NSUInteger)to {
    NSMutableArray *items = self.activeThemes.mutableCopy; id item = items[from];
    [items removeObjectAtIndex:from]; [items insertObject:item atIndex:to]; self.activeThemes = items;
    self.hasUnappliedChanges = YES;
}
- (void)apply { self.hasUnappliedChanges = NO; }
@end

static int checks, failures;
static void Check(BOOL ok, const char *message) { checks++; if (!ok) failures++; printf("%s %s\n", ok ? "PASS" : "FAIL", message); }
static NSIndexPath *Row(NSInteger section, NSInteger row) { return [NSIndexPath indexPathForRow:row inSection:section]; }
int main(void) {
    @autoreleasepool {
        PineoraSettingsController *page = [[PineoraSettingsController alloc] initWithStyle:UITableViewStyleInsetGrouped];
        [page loadViewIfNeeded];
        UITableView *table = page.tableView;
        PineoraStore *store = [page valueForKey:@"store"];
        Check(page.editing && table.editing && table.allowsSelectionDuringEditing, "always sortable and selectable");
        [page setEditing:NO animated:NO];
        Check(page.editing && table.editing, "sorting stays available without Edit mode");
        Check([page tableView:table numberOfRowsInSection:2] == 1, "available themes remain visible");
        Check([page tableView:table numberOfRowsInSection:3] == 1, "Apply remains visible");
        Check([page tableView:table titleForFooterInSection:3].length > 0, "Apply footer remains visible");
        UITableViewCell *active = [page tableView:table cellForRowAtIndexPath:Row(1,0)];
        Check(active.showsReorderControl && [page tableView:table canMoveRowAtIndexPath:Row(1,0)], "active theme has reorder handle");
        Check(![page tableView:table canMoveRowAtIndexPath:Row(2,0)] && ![page tableView:table canMoveRowAtIndexPath:Row(3,0)], "available themes and Apply cannot move");
        Check([page tableView:table editingStyleForRowAtIndexPath:Row(1,0)] == UITableViewCellEditingStyleNone, "no delete controls");
        Check(![page tableView:table shouldIndentWhileEditingRowAtIndexPath:Row(1,0)], "no editing indentation");
        Check([[page tableView:table targetIndexPathForMoveFromRowAtIndexPath:Row(1,0) toProposedIndexPath:Row(3,0)] isEqual:Row(1,1)], "drag cannot leave active section");
        [page tableView:table moveRowAtIndexPath:Row(1,0) toIndexPath:Row(1,1)];
        Check([store.activeThemes[0].title isEqual:@"B"] && store.hasUnappliedChanges, "reorder persists priority and pending state");
        [page tableView:table didSelectRowAtIndexPath:Row(2,0)];
        Check(store.activeThemes.count == 3 && store.inactiveThemes.count == 0, "tap enables while sortable");
        [page tableView:table didSelectRowAtIndexPath:Row(1,0)];
        Check(store.activeThemes.count == 2 && store.inactiveThemes.count == 1, "tap disables while sortable");
        [page tableView:table didSelectRowAtIndexPath:Row(3,0)];
        Check(!store.hasUnappliedChanges && [[page valueForKey:@"justApplied"] boolValue], "Apply usable while sortable");
        [store deactivateTheme:store.activeThemes.firstObject];
        Check(![page tableView:table canMoveRowAtIndexPath:Row(1,0)], "single active theme has no meaningless reorder handle");
        printf("RESULT %d checks, %d failures\n", checks, failures);
    }
    return failures ? 1 : 0;
}
