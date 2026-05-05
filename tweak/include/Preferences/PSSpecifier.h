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

// 旧版常量别名（兼容）
#define PSTableViewCellSwitch       PSTableViewCellTypeSwitch
#define PSTableViewCellTypeLabel    PSTableViewCellTypeLabel

typedef NS_ENUM(NSInteger, PSTableViewCellAccessoryType) {
    PSTableViewCellAccessoryNone = 0,
    PSTableViewCellAccessoryDisclosureIndicator = 1,
    PSTableViewCellAccessoryDetailDisclosureButton = 2,
    PSTableViewCellAccessoryCheckmark = 3,
};

@interface PSSpecifier : NSObject
+ (instancetype)groupSpecifierWithIdentifier:(NSString *)identifier;
+ (instancetype)separatorSpecifier;
+ (instancetype)preferenceSpecifierNamed:(NSString *)name target:(id)target set:(SEL)set get:(SEL)get detail:(Class)detail cell:(PSTableViewCellType)cell edit:(PSTableViewCellAccessoryType)edit;
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
