#import <UIKit/UIKit.h>

@interface PSListController : UIViewController
- (NSMutableArray *)specifiers;
- (void)setSpecifiers:(NSMutableArray *)specifiers;
- (void)loadView;
- (void)viewDidLoad;
- (void)viewWillAppear:(BOOL)animated;
- (id)readPreferenceValue:(id)specifier;
- (void)setPreferenceValue:(id)value specifier:(id)specifier;
- (void)reloadSpecifiers;
@end

@interface PSListItemsController : PSListController
@end
