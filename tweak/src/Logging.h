/*
 * iOSScreenStream - Low-latency screen streaming for iOS
 * Logging header
 */

#ifndef Logging_h
#define Logging_h

#import <Foundation/NSObjCRuntime.h>

#ifdef DEBUG
#define TVLog(fmt, ...) \
    NSLog(@"[iOSScreenStream] " fmt, ##__VA_ARGS__)
#else
#define TVLog(fmt, ...) \
    do {} while(0)
#endif

#endif /* Logging_h */
