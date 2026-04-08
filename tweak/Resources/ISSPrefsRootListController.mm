/*
 * iOSScreenStream - Preferences Root List Controller
 * Settings UI for configuring screen streaming
 */

#import <Foundation/Foundation.h>
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSListController.h>
#import <UIKit/UIKit.h>
#import <Network/Network.h>

#import "ISSPrefsRootListController.h"

#define PREFS_ID @"com.yourname.iosscreenstream"

NSString *GetDeviceIPAddress(void) {
    struct ifaddrs *ifaList = NULL;
    if (getifaddrs(&ifaList) != 0 || !ifaList)
        return @"未获取到";

    const char *iface = "en0";
    NSString *ipv4 = nil;
    
    for (struct ifaddrs *ifa = ifaList; ifa; ifa = ifa->ifa_next) {
        if (!ifa->ifa_addr || !ifa->ifa_name)
            continue;
        if (strcmp(ifa->ifa_name, iface) != 0)
            continue;
        if (!(ifa->ifa_flags & IFF_UP) || (ifa->ifa_flags & IFF_LOOPBACK))
            continue;

        if (ifa->ifa_addr->sa_family == AF_INET) {
            char buf[INET_ADDRSTRLEN] = {0};
            struct sockaddr_in *sin = (struct sockaddr_in *)ifa->ifa_addr;
            if (inet_ntop(AF_INET, &sin->sin_addr, buf, sizeof(buf))) {
                ipv4 = [NSString stringWithUTF8String:buf];
                break;
            }
        }
    }
    freeifaddrs(ifaList);
    return ipv4 ?: @"未获取到";
}

@interface ISSPrefsRootListController ()
@end

@implementation ISSPrefsRootListController {
    int _notifyToken;
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    NSString *defaultsDomain = [specifier propertyForKey:@"defaults"];
    id defaultValue = [specifier propertyForKey:@"default"];
    
    if ([key isEqualToString:@"deviceIP"]) {
        return GetDeviceIPAddress();
    }
    
    if (defaultsDomain && key) {
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:defaultsDomain];
        id value = [defaults objectForKey:key];
        return value ?: defaultValue;
    }
    
    return defaultValue;
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    NSString *defaultsDomain = [specifier propertyForKey:@"defaults"];
    
    if (defaultsDomain && key) {
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:defaultsDomain];
        [defaults setObject:value forKey:key];
        [defaults synchronize];
    }
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *specs = [NSMutableArray array];
        
        // Header
        PSSpecifier *header = [PSSpecifier groupSpecifierWithIdentifier:@"header"];
        [header setProperty:@"iOSScreenStream v1.0.0\n低延迟屏幕流传输控制" forKey:@"footerText"];
        [specs addObject:header];
        
        // Enable toggle
        PSSpecifier *enabled = [PSSpecifier preferenceSpecifierNamed:@"启用服务"
                                                              target:self
                                                               set:@selector(setPreferenceValue:specifier:)
                                                               get:@selector(readPreferenceValue:)
                                                            detail:Nil
                                                              cell:PSTableViewCellSwitch
                                                              edit:PSTableViewCellAccessoryNone];
        [enabled setProperty:@YES forKey:@"default"];
        [enabled setProperty:PREFS_ID forKey:@"defaults"];
        [enabled setProperty:@"enabled" forKey:@"key"];
        [specs addObject:enabled];
        
        // Separator
        [specs addObject:[PSSpecifier separatorSpecifier]];
        
        // Connection group
        PSSpecifier *connGroup = [PSSpecifier groupSpecifierWithIdentifier:@"connection"];
        [connGroup setProperty:@"连接设置" forKey:@"name"];
        [specs addObject:connGroup];
        
        // Server IP
        PSSpecifier *serverIP = [PSSpecifier preferenceSpecifierNamed:@"电脑 IP 地址"
                                                            target:self
                                                             set:@selector(setPreferenceValue:specifier:)
                                                             get:@selector(readPreferenceValue:)
                                                          detail:PSTableViewCellTypeTextField
                                                             cell:PSTableViewCellTypeTextField
                                                             edit:PSTableViewCellAccessoryNone];
        [serverIP setProperty:@"serverIP" forKey:@"key"];
        [serverIP setProperty:PREFS_ID forKey:@"defaults"];
        [serverIP setProperty:@"192.168.1.100" forKey:@"default"];
        [serverIP setProperty:@"Keyboard" forKey:@"keyboard"];
        [serverIP setProperty:@"url" forKey:@"keyboardType"];
        [specs addObject:serverIP];
        
        // Video Port
        PSSpecifier *videoPort = [PSSpecifier preferenceSpecifierNamed:@"视频端口 (UDP)"
                                                              target:self
                                                               set:@selector(setPreferenceValue:specifier:)
                                                               get:@selector(readPreferenceValue:)
                                                            detail:PSTableViewCellTypeTextField
                                                               cell:PSTableViewCellTypeTextField
                                                               edit:PSTableViewCellAccessoryNone];
        [videoPort setProperty:@"videoPort" forKey:@"key"];
        [videoPort setProperty:PREFS_ID forKey:@"defaults"];
        [videoPort setProperty:@5001 forKey:@"default"];
        [videoPort setProperty:@"Keyboard" forKey:@"keyboard"];
        [videoPort setProperty:@"number" forKey:@"keyboardType"];
        [specs addObject:videoPort];
        
        // Control Port
        PSSpecifier *controlPort = [PSSpecifier preferenceSpecifierNamed:@"控制端口 (TCP)"
                                                                target:self
                                                                 set:@selector(setPreferenceValue:specifier:)
                                                                 get:@selector(readPreferenceValue:)
                                                              detail:PSTableViewCellTypeTextField
                                                                 cell:PSTableViewCellTypeTextField
                                                                 edit:PSTableViewCellAccessoryNone];
        [controlPort setProperty:@"controlPort" forKey:@"key"];
        [controlPort setProperty:PREFS_ID forKey:@"defaults"];
        [controlPort setProperty:@5002 forKey:@"default"];
        [controlPort setProperty:@"Keyboard" forKey:@"keyboard"];
        [controlPort setProperty:@"number" forKey:@"keyboardType"];
        [specs addObject:controlPort];
        
        // Device IP (read-only)
        PSSpecifier *deviceIP = [PSSpecifier preferenceSpecifierNamed:@"本机 IP 地址"
                                                              target:self
                                                               set:nil
                                                               get:@selector(readPreferenceValue:)
                                                            detail:Nil
                                                              cell:PSTableViewCellTypeLabel
                                                              edit:PSTableViewCellAccessoryNone];
        [deviceIP setProperty:@"deviceIP" forKey:@"key"];
        [deviceIP setProperty:@"只读" forKey:@"default"];
        [specs addObject:deviceIP];
        
        // Separator
        [specs addObject:[PSSpecifier separatorSpecifier]];
        
        // Video group
        PSSpecifier *videoGroup = [PSSpecifier groupSpecifierWithIdentifier:@"video"];
        [videoGroup setProperty:@"视频质量" forKey:@"name"];
        [specs addObject:videoGroup];
        
        // FPS
        PSSpecifier *fps = [PSSpecifier preferenceSpecifierNamed:@"帧率 (FPS)"
                                                         target:self
                                                          set:@selector(setPreferenceValue:specifier:)
                                                          get:@selector(readPreferenceValue:)
                                                       detail:PSTableViewCellTypeSlider
                                                          cell:PSTableViewCellTypeSlider
                                                          edit:PSTableViewCellAccessoryNone];
        [fps setProperty:@"fps" forKey:@"key"];
        [fps setProperty:PREFS_ID forKey:@"defaults"];
        [fps setProperty:@30 forKey:@"default"];
        [fps setProperty:@10 forKey:@"min"];
        [fps setProperty:@60 forKey:@"max"];
        [fps setProperty:@1 forKey:@"step"];
        [specs addObject:fps];
        
        // Bitrate
        PSSpecifier *bitrate = [PSSpecifier preferenceSpecifierNamed:@"码率 (kbps)"
                                                            target:self
                                                             set:@selector(setPreferenceValue:specifier:)
                                                             get:@selector(readPreferenceValue:)
                                                          detail:PSTableViewCellTypeSlider
                                                             cell:PSTableViewCellTypeSlider
                                                             edit:PSTableViewCellAccessoryNone];
        [bitrate setProperty:@"bitrate" forKey:@"key"];
        [bitrate setProperty:PREFS_ID forKey:@"defaults"];
        [bitrate setProperty:@2000 forKey:@"default"];
        [bitrate setProperty:@500 forKey:@"min"];
        [bitrate setProperty:@10000 forKey:@"max"];
        [bitrate setProperty:@100 forKey:@"step"];
        [specs addObject:bitrate];
        
        // Separator
        [specs addObject:[PSSpecifier separatorSpecifier]];
        
        // Apply button
        PSSpecifier *apply = [PSSpecifier preferenceSpecifierNamed:@"应用更改"
                                                           target:self
                                                            set:nil
                                                            get:nil
                                                         detail:Nil
                                                            cell:PSTableViewCellTypeButton
                                                            edit:PSTableViewCellAccessoryNone];
        [apply setProperty:@selector(applyChanges) forKey:@"action"];
        [apply setProperty:@YES forKey:@"isDestructive"];
        [specs addObject:apply];
        
        _specifiers = specs;
    }
    return _specifiers;
}

- (void)applyChanges {
    [self.view endEditing:YES];
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"已应用"
                                                                   message:@"请手动重启插件使设置生效"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"iOSScreenStream";
}

@end
