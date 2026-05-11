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

// 诊断辅助：追加字符串到文件
static void diagAppend(NSString *msg) {
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:@"/tmp/iosscreenstream_diag.txt"];
    if (fh) {
        [fh seekToEndOfFile];
        [fh writeData:[msg dataUsingEncoding:NSUTF8StringEncoding]];
        [fh closeFile];
    }
}

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
    
    // 使用静态变量保持对象存活，防止 ARC 释放
    static StreamTweak *sTweak = nil;
    sTweak = [[StreamTweak alloc] init];
    [sTweak loadSettings];
    
    // 监听设置变更
    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge void *)sTweak,
        settingsChangedCallback,
        CFSTR(kSettingsChangedNotification),
        NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately
    );
    
    if (sTweak->mIsEnabled) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [sTweak startStreaming];
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
    
    // 从偏好设置读取（key 必须与 Root.plist 中的 key 一致）
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:PREFS_ID];
    
    mIsEnabled = [defaults boolForKey:@"enabled"];
    NSString *ip = [defaults stringForKey:@"client_ip"];
    if (ip.length > 0) mServerIP = ip;
    
    // 也检查旧 key（兼容旧版设置页写入的数据）
    int vp = (int)[defaults integerForKey:@"video_port"];
    if (vp == 0) vp = (int)[defaults integerForKey:@"videoPort"];
    if (vp > 0) mVideoPort = vp;
    
    int cp = (int)[defaults integerForKey:@"control_port"];
    if (cp == 0) cp = (int)[defaults integerForKey:@"controlPort"];
    if (cp > 0) mControlPort = cp;
    
    int fps = (int)[defaults integerForKey:@"fps"];
    if (fps > 0) mFPS = fps;
    
    int br = (int)[defaults integerForKey:@"bitrate"];
    if (br > 0) mBitrate = br * 1000; // 用户设置单位 kbps，转成 bps
    
    TVLog(@"设置已加载: 启用=%d, 服务端=%@:%d/%d, 帧率=%d, 码率=%d",
          mIsEnabled, mServerIP, mVideoPort, mControlPort, mFPS, mBitrate);
    
    // 写诊断文件（排查问题时用）
    NSString *diag = [NSString stringWithFormat:@"enabled=%d\nip=%@\nvideoPort=%d\ncontrolPort=%d\nfps=%d\nbitrate=%d\ntime=%@\n",
          mIsEnabled, mServerIP, mVideoPort, mControlPort, mFPS, mBitrate, [NSDate date]];
    [diag writeToFile:@"/tmp/iosscreenstream_diag.txt" atomically:YES encoding:NSUTF8StringEncoding error:nil];
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
    
    if (width == 0 || height == 0) {
        TVLog(@"屏幕分辨率无效: %dx%d，2秒后重试", width, height);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self startStreaming];
        });
        return;
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
    
    // 写诊断文件
    NSString *diag2 = [NSString stringWithFormat:@"STREAMING_STARTED\nip=%@\nvideoPort=%d\ncontrolPort=%d\nresolution=%dx%d\nfps=%d\nbitrate=%d\ntime=%@\n",
          mServerIP, mVideoPort, mControlPort, width, height, mFPS, mBitrate, [NSDate date]];
    diagAppend(diag2);
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
    
    // 诊断：每 100 帧写一次日志
    static int sFrameCount = 0;
    static NSDate *sFirstFrame = nil;
    sFrameCount++;
    if (sFirstFrame == nil) sFirstFrame = [NSDate date];
    if (sFrameCount == 1) {
        NSString *msg = [NSString stringWithFormat:@"FIRST_ENCODED_FRAME size=%lu key=%d time=%@\n", (unsigned long)data.length, isKeyFrame, [NSDate date]];
        diagAppend(msg);
    }
    if (sFrameCount % 100 == 0) {
        NSTimeInterval elapsed = [[NSDate date] timeIntervalSinceDate:sFirstFrame];
        NSString *msg = [NSString stringWithFormat:@"ENCODED_%d_FRAMES elapsed=%.1fs\n", sFrameCount, elapsed];
        diagAppend(msg);
    }
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
- (void)streamServerDidRequestKeyframe:(id)server {
    // PC 端重连后请求关键帧，强制编码器生成 IDR 帧
    TVLog(@"收到关键帧请求");
    [mEncoder forceKeyframe];
}

- (void)streamServerDidRequestStartStream:(id)server {
    // PC 端请求开始流，重置编码器并发送新的 SPS/PPS
    TVLog(@"收到开始流请求，重置编码器并强制发送关键帧");
    
    // 重置编码器，确保下一次编码是完整的关键帧（包含 SPS/PPS）
    [mEncoder reset];
    
    // 立即强制发送关键帧
    [mEncoder forceKeyframe];
}

@end
