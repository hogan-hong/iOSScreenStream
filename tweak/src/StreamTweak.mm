/*
 * iOSScreenStream - 主 Tweak 实现
 * 修复：设置动态生效、分辨率自动获取
 */

#import <UIKit/UIKit.h>
#import <PreferenceLoader/Preferences.h>

#import "StreamTweak.h"
#import "ScreenCapturer.h"
#import "VideoEncoder.h"
#import "StreamServer.h"
#import "TouchController.h"
#import "Logging.h"

// 设置变更通知
#define kSettingsChangedNotification "com.hogan.iosscreenstream.settingsChanged"
#define PREFS_ID @"com.hogan.iosscreenstream"

@interface StreamTweak () <VideoEncoderDelegate, StreamServerDelegate>
@end

@implementation StreamTweak {
    ScreenCapturer *mCapturer;
    VideoEncoder *mEncoder;
    StreamServer *mServer;
    
    BOOL mIsEnabled;
    NSString *mServerIP;
    int mVideoPort;
    int mControlPort;
    int mFPS;
    int mBitrate;
}

+ (void)load {
    TVLog(@"iOSScreenStream 已加载");
    
    StreamTweak *tweak = [[StreamTweak alloc] init];
    [tweak loadSettings];
    
    // 监听设置变更
    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge void *)tweak,
        settingsChangedCallback,
        CFSTR(kSettingsChangedNotification),
        NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately
    );
    
    if (tweak->mIsEnabled) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [tweak startStreaming];
        });
    }
}

static void settingsChangedCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    StreamTweak *tweak = (__bridge StreamTweak *)observer;
    TVLog(@"设置已变更，重新加载");
    [tweak reloadSettings];
}

- (void)reloadSettings {
    BOOL wasEnabled = mIsEnabled;
    [self loadSettings];
    
    if (mIsEnabled && !wasEnabled) {
        // 从关闭变为开启
        [self startStreaming];
    } else if (!mIsEnabled && wasEnabled) {
        // 从开启变为关闭
        [self stopStreaming];
    } else if (mIsEnabled) {
        // 设置变更，重启流
        TVLog(@"重启流服务以应用新设置");
        [self stopStreaming];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self startStreaming];
        });
    }
}

- (void)loadSettings {
    // 默认值
    mIsEnabled = NO;
    mServerIP = @"192.168.1.100";
    mVideoPort = 5001;
    mControlPort = 5002;
    mFPS = 30;
    mBitrate = 2000000;
    
    // 从偏好设置读取
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:PREFS_ID];
    
    mIsEnabled = [defaults boolForKey:@"enabled"];
    NSString *ip = [defaults stringForKey:@"serverIP"];
    if (ip.length > 0) mServerIP = ip;
    
    int vp = (int)[defaults integerForKey:@"videoPort"];
    if (vp > 0) mVideoPort = vp;
    
    int cp = (int)[defaults integerForKey:@"controlPort"];
    if (cp > 0) mControlPort = cp;
    
    int fps = (int)[defaults integerForKey:@"fps"];
    if (fps > 0) mFPS = fps;
    
    int br = (int)[defaults integerForKey:@"bitrate"];
    if (br > 0) mBitrate = br * 1000; // 用户设置单位 kbps，转成 bps
    
    TVLog(@"设置已加载: 启用=%d, 服务端=%@:%d/%d, 帧率=%d, 码率=%d",
          mIsEnabled, mServerIP, mVideoPort, mControlPort, mFPS, mBitrate);
}

- (void)startStreaming {
    TVLog(@"启动流服务...");
    
    // 获取屏幕实际分辨率
    CGSize nativeSize = [UIScreen mainScreen].nativeBounds.size;
    int width = (int)nativeSize.width;
    int height = (int)nativeSize.height;
    
    // 确保 width <= height（横竖屏归一化）
    if (width > height) {
        int tmp = width; width = height; height = tmp;
    }
    
    TVLog(@"屏幕分辨率: %dx%d", width, height);
    
    // 初始化编码器
    mEncoder = [[VideoEncoder alloc] initWithWidth:width height:height bitrate:mBitrate fps:mFPS];
    mEncoder.delegate = self;
    [mEncoder startEncoding];
    
    // 初始化流服务
    mServer = [[StreamServer alloc] initWithServerIP:mServerIP videoPort:mVideoPort controlPort:mControlPort];
    mServer.delegate = self;
    if (![mServer start]) {
        TVLog(@"流服务启动失败");
        [self stopStreaming];
        return;
    }
    
    // 初始化屏幕捕获
    mCapturer = [ScreenCapturer sharedCapturer];
    [mCapturer setPreferredFrameRateWithMin:0 preferred:mFPS max:mFPS];
    [mCapturer startCaptureWithFrameHandler:^(CMSampleBufferRef sampleBuffer) {
        [self->mEncoder encodeSampleBuffer:sampleBuffer];
    }];
    
    TVLog(@"流服务已启动");
}

- (void)stopStreaming {
    TVLog(@"停止流服务...");
    
    [mCapturer endCapture];
    [mEncoder stopEncoding];
    [mServer stop];
    
    mCapturer = nil;
    mEncoder = nil;
    mServer = nil;
    
    TVLog(@"流服务已停止");
}

#pragma mark - VideoEncoderDelegate

- (void)videoEncoder:(id)encoder didEncodeData:(NSData *)data isKeyFrame:(BOOL)isKeyFrame {
    [mServer sendVideoData:data isKeyFrame:isKeyFrame];
}

#pragma mark - StreamServerDelegate

- (void)streamServer:(id)server didReceiveTouchDown:(CGPoint)point {
    [[TouchController sharedController] touchDownAtPoint:point];
}

- (void)streamServer:(id)server didReceiveTouchUp:(CGPoint)point {
    [[TouchController sharedController] touchUpAtPoint:point];
}

- (void)streamServer:(id)server didReceiveTouchMove:(CGPoint)point {
    [[TouchController sharedController] touchMoveToPoint:point];
}

@end
