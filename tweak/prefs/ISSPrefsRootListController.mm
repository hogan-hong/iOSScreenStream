/*
 * iOSScreenStream - Settings page controller
 * Inherits from PSListController for root list display
 */

#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>

@interface ISSPrefsRootListController : PSListController
@end

@implementation ISSPrefsRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

@end
