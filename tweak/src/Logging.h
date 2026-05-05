/*
 * iOSScreenStream - 日志工具
 */

#import <Foundation/Foundation.h>

#ifdef DEBUG
#define TVLog(fmt, ...) NSLog(@"[iOSScreenStream] " fmt, ##__VA_ARGS__)
#else
#define TVLog(fmt, ...) NSLog(@"[iOSScreenStream] " fmt, ##__VA_ARGS__)
#endif
