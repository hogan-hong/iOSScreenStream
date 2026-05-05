/*
 * iOSScreenStream - 设置页面控制器
 * 使用 Root.plist 静态定义 specifiers，控制器只处理动态逻辑
 */

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import <sys/socket.h>
#import <net/if.h>
#import <ifaddrs.h>
#import <netinet/in.h>
#import <arpa/inet.h>

@interface PSListController : UIViewController
@end

@interface ISSPrefsRootListController : PSListController
@end

#define PREFS_ID @"com.hogan.iosscreenstream"
#define kSettingsChangedNotification "com.hogan.iosscreenstream.settingsChanged"

// 获取本机 WiFi IP
static NSString *GetDeviceIPAddress(void) {
    struct ifaddrs *ifaList = NULL;
    if (getifaddrs(&ifaList) != 0 || !ifaList)
        return @"未获取到";

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

@implementation ISSPrefsRootListController

// 读取偏好值（PSListController 通过 selector 调用）
- (id)readPreferenceValue:(PSSpecifier *)specifier {
    // 本机 IP 动态获取
    if ([[specifier propertyForKey:@"key"] isEqualToString:@"deviceIP"]) {
        return GetDeviceIPAddress();
    }

    NSString *key = [specifier propertyForKey:@"key"];
    NSString *defaultsDomain = [specifier propertyForKey:@"defaults"];
    id defaultValue = [specifier propertyForKey:@"default"];

    if (defaultsDomain && key) {
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:defaultsDomain];
        id value = [defaults objectForKey:key];
        return value ?: defaultValue;
    }

    return defaultValue;
}

// 写入偏好值
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    NSString *defaultsDomain = [specifier propertyForKey:@"defaults"];

    if (defaultsDomain && key) {
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:defaultsDomain];
        [defaults setObject:value forKey:key];
        [defaults synchronize];
    }
}

// "应用更改" 按钮回调
- (void)applyChanges {
    [self.view endEditing:YES];

    // 发送 Darwin 通知让 tweak 重新加载设置
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR(kSettingsChangedNotification),
        NULL, NULL, YES
    );

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"已应用"
                        message:@"设置已生效，无需重启"
                 preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好"
                                              style:UIAlertActionStyleDefault
                                            handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
