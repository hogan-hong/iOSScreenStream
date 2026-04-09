// Stub for Preferences/PSSpecifier.h
// Used by ISSPrefsRootListController

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, PSTableViewCellType) {
    PSTableViewCellTypeDefault = 0,
    PSTableViewCellTypeSwitch = 2,
    PSTableViewCellTypeTextField = 3,
    PSTableViewCellTypeSlider = 4,
    PSTableViewCellTypeButton = 5,
    PSTableViewCellTypeLabel = 6
};

@interface PSSpecifier : NSObject
+ (id)groupSpecifierWithIdentifier:(id)identifier;
+ (id)separatorSpecifier;
+ (id)preferenceSpecifierNamed:(id)name target:(id)target set:(SEL)set get:(SEL)get detail:(id)detail cell:(PSTableViewCellType)cell edit:(id)edit;
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *footerText;
@property (nonatomic, retain) id target;
@property (nonatomic, assign) SEL setSelector;
@property (nonatomic, assign) SEL getSelector;
@property (nonatomic, assign) PSTableViewCellType cellType;
@property (nonatomic, retain) NSString *cellConfiguration;
@property (nonatomic, retain) NSDictionary *properties;
- (void)setProperty:(id)value forKey:(NSString *)key;
- (id)propertyForKey:(NSString *)key;
@end
