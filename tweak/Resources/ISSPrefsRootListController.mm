/*
 * iOSScreenStream - 设置页面控制器
 * 修改：包名更正、应用按钮通知 tweak 重新加载
 */

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSListController.h>

#import <sys/socket.h>
#import <net/if.h>
#import <ifaddrs.h>
#import <netinet/in.h>
#import <arpa/inet.h>

#import "ISSPrefsRootListController.h"

#define PREFS_ID @"com.hogan.iosscreenstream"
#define kSettingsChangedNotification "com.hogan.iosscreenstream.settingsChanged"

NSString *GetDeviceIPAddress(void) {
    struct ifaddrs *ifaList = NULL;
    if (getifaddrs(&ifaList) != 0 || !ifaList)
        return @"未获取到";

    // 优先 en0（WiFi），其次 en1
    const char *ifaces[] = {"en0", "en1", NULL};
    NSString *ipv4 = nil;
    
    for (int i = 0; ifaces[i] != NULL; i++) {
        for (struct ifaddrs *ifa = ifaList; ifa; ifa = ifa->ifa_next) {
            if (!ifa->ifa_addr || !ifa->ifa_name)
                continue;
            if (strcmp(ifa->ifa_name, ifaces[i]) != 0)
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
        if (ipv4) break;
    }
    freeifaddrs(ifaList);
    return ipv4 ?: @"未获取到";
}

@interface ISSPrefsRootListController ()
@end

@implementation ISSPrefsRootListController

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
        
        // 头部说明
        PSSpecifier *header = [PSSpecifier groupSpecifierWithIdentifier:@"header"];
        [header setProperty:@"iOSScreenStream v1.1.0\n低延迟屏幕流传输与反向触控" forKey:@"footerText"];
        [specs addObject:header];
        
        // 启用开关
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
        
        [specs addObject:[PSSpecifier separatorSpecifier]];
        
        // 连接设置
        PSSpecifier *connGroup = [PSSpecifier groupSpecifierWithIdentifier:@"connection"];
        [connGroup setProperty:@"连接设置" forKey:@"name"];
        [specs addObject:connGroup];
        
        // 电脑 IP
        PSSpecifier *serverIP = [PSSpecifier preferenceSpecifierNamed:@"电脑 IP 地址"
                                                            target:self
                                                             set:@selector(setPreferenceValue:specifier:)
                                                             get:@selector(readPreferenceValue:)
                                                          detail:Nil
                                                             cell:PSTableViewCellTypeTextField
                                                             edit:PSTableViewCellAccessoryNone];
        [serverIP setProperty:@"serverIP" forKey:@"key"];
        [serverIP setProperty:PREFS_ID forKey:@"defaults"];
        [serverIP setProperty:@"192.168.1.100" forKey:@"default"];
        [serverIP setProperty:@"Keyboard" forKey:@"keyboard"];
        [serverIP setProperty:@"url" forKey:@"keyboardType"];
        [specs addObject:serverIP];
        
        // 视频端口
        PSSpecifier *videoPort = [PSSpecifier preferenceSpecifierNamed:@"视频端口 (UDP)"
                                                              target:self
                                                               set:@selector(setPreferenceValue:specifier:)
                                                               get:@selector(readPreferenceValue:)
                                                            detail:Nil
                                                               cell:PSTableViewCellTypeTextField
                                                               edit:PSTableViewCellAccessoryNone];
        [videoPort setProperty:@"videoPort" forKey:@"key"];
        [videoPort setProperty:PREFS_ID forKey:@"defaults"];
        [videoPort setProperty:@5001 forKey:@"default"];
        [videoPort setProperty:@"Keyboard" forKey:@"keyboard"];
        [videoPort setProperty:@"number" forKey:@"keyboardType"];
        [specs addObject:videoPort];
        
        // 控制端口
        PSSpecifier *controlPort = [PSSpecifier preferenceSpecifierNamed:@"控制端口 (TCP)"
                                                                target:self
                                                                 set:@selector(setPreferenceValue:specifier:)
                                                                 get:@selector(readPreferenceValue:)
                                                              detail:Nil
                                                                 cell:PSTableViewCellTypeTextField
                                                                 edit:PSTableViewCellAccessoryNone];
        [controlPort setProperty:@"controlPort" forKey:@"key"];
        [controlPort setProperty:PREFS_ID forKey:@"defaults"];
        [controlPort setProperty:@5002 forKey:@"default"];
        [controlPort setProperty:@"Keyboard" forKey:@"keyboard"];
        [controlPort setProperty:@"number" forKey:@"keyboardType"];
        [specs addObject:controlPort];
        
        // 本机 IP（只读）
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
        
        [specs addObject:[PSSpecifier separatorSpecifier]];
        
        // 视频质量
        PSSpecifier *videoGroup = [PSSpecifier groupSpecifierWithIdentifier:@"video"];
        [videoGroup setProperty:@"视频质量" forKey:@"name"];
        [specs addObject:videoGroup];
        
        // 帧率
        PSSpecifier *fps = [PSSpecifier preferenceSpecifierNamed:@"帧率 (FPS)"
                                                         target:self
                                                          set:@selector(setPreferenceValue:specifier:)
                                                          get:@selector(readPreferenceValue:)
                                                       detail:Nil
                                                          cell:PSTableViewCellTypeSlider
                                                          edit:PSTableViewCellAccessoryNone];
        [fps setProperty:@"fps" forKey:@"key"];
        [fps setProperty:PREFS_ID forKey:@"defaults"];
        [fps setProperty:@30 forKey:@"default"];
        [fps setProperty:@10 forKey:@"min"];
        [fps setProperty:@60 forKey:@"max"];
        [fps setProperty:@1 forKey:@"step"];
        [specs addObject:fps];
        
        // 码率
        PSSpecifier *bitrate = [PSSpecifier preferenceSpecifierNamed:@"码率 (kbps)"
                                                            target:self
                                                             set:@selector(setPreferenceValue:specifier:)
                                                             get:@selector(readPreferenceValue:)
                                                          detail:Nil
                                                             cell:PSTableViewCellTypeSlider
                                                             edit:PSTableViewCellAccessoryNone];
        [bitrate setProperty:@"bitrate" forKey:@"key"];
        [bitrate setProperty:PREFS_ID forKey:@"defaults"];
        [bitrate setProperty:@2000 forKey:@"default"];
        [bitrate setProperty:@500 forKey:@"min"];
        [bitrate setProperty:@10000 forKey:@"max"];
        [bitrate setProperty:@100 forKey:@"step"];
        [specs addObject:bitrate];
        
        [specs addObject:[PSSpecifier separatorSpecifier]];
        
        // 应用按钮
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
    
    // 发送 Darwin 通知让 tweak 重新加载设置
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR(kSettingsChangedNotification),
        NULL, NULL, YES
    );
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"已应用"
                                                                   message:@"设置已生效，无需重启"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"iOSScreenStream";
}

@end
