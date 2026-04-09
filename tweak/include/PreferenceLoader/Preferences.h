// Stub header for PreferenceLoader/Preferences.h
// Provides PSListController for preference bundle compatibility

#import <Foundation/Foundation.h>

@class PSSpecifier;

@interface PSListController : NSObject
- (NSArray *)specifiers;
- (void)reloadSpecifier;
- (void)removeSpecifierAtIndex:(NSUInteger)index animated:(BOOL)animated;
- (id)specifierAtIndex:(NSUInteger)index;
@end
