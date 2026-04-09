// Stub for Preferences/PSListController.h
// Used by ISSPrefsRootListController

#import <Foundation/Foundation.h>

@class PSSpecifier;

@interface PSListController : NSObject
- (NSArray *)specifiers;
- (void)reloadSpecifier;
- (void)removeSpecifierAtIndex:(NSUInteger)index animated:(BOOL)animated;
- (id)specifierAtIndex:(NSUInteger)index;
@property (nonatomic, retain) NSMutableArray *specifiers;
@end

@interface PSController : NSObject
@end
