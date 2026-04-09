/*
 * iOSScreenStream - Main tweak implementation
 */

#import <UIKit/UIKit.h>
#import <PreferenceLoader/Preferences.h>

#import "StreamTweak.h"
#import "ScreenCapturer.h"
#import "VideoEncoder.h"
#import "StreamServer.h"
#import "TouchController.h"
#import "Logging.h"

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
    TVLog(@"iOSScreenStream loaded");
    
    StreamTweak *tweak = [[StreamTweak alloc] init];
    [tweak loadSettings];
    
    if (tweak->mIsEnabled) {
        [tweak startStreaming];
    }
}

- (void)loadSettings {
    // Default values
    mIsEnabled = NO;
    mServerIP = @"192.168.1.100";
    mVideoPort = 5001;
    mControlPort = 5002;
    mFPS = 30;
    mBitrate = 2000000;
    
    // Load from preferences
    NSString *plistPath = @"/Library/PreferenceLoader/Preferences/com.yourname.iosscreenstream.plist";
    NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:plistPath];
    
    if (plist) {
        mIsEnabled = [plist[@"enabled"] boolValue];
        mServerIP = plist[@"serverIP"] ?: mServerIP;
        mVideoPort = [plist[@"videoPort"] intValue] ?: mVideoPort;
        mControlPort = [plist[@"controlPort"] intValue] ?: mControlPort;
        mFPS = [plist[@"fps"] intValue] ?: mFPS;
        mBitrate = [plist[@"bitrate"] intValue] ?: mBitrate;
    }
    
    TVLog(@"Settings loaded: enabled=%d, server=%@:%d/%d, fps=%d, bitrate=%d",
          mIsEnabled, mServerIP, mVideoPort, mControlPort, mFPS, mBitrate);
}

- (void)startStreaming {
    TVLog(@"Starting stream...");
    
    // Get screen dimensions
    CGSize screenSize = [[UIScreen mainScreen] _unjailedReferenceBoundsInPixels].size;
    int width = (int)screenSize.width;
    int height = (int)screenSize.height;
    
    // Initialize encoder
    mEncoder = [[VideoEncoder alloc] initWithWidth:width height:height bitrate:mBitrate fps:mFPS];
    mEncoder.delegate = self;
    [mEncoder startEncoding];
    
    // Initialize stream server
    mServer = [[StreamServer alloc] initWithServerIP:mServerIP videoPort:mVideoPort controlPort:mControlPort];
    mServer.delegate = self;
    if (![mServer start]) {
        TVLog(@"Failed to start stream server");
        [self stopStreaming];
        return;
    }
    
    // Initialize screen capturer
    mCapturer = [ScreenCapturer sharedCapturer];
    [mCapturer startCaptureWithFrameHandler:^(CMSampleBufferRef sampleBuffer) {
        [self->mEncoder encodeSampleBuffer:sampleBuffer];
    }];
    
    TVLog(@"Streaming started");
}

- (void)stopStreaming {
    TVLog(@"Stopping stream...");
    
    [mCapturer endCapture];
    [mEncoder stopEncoding];
    [mServer stop];
    
    mCapturer = nil;
    mEncoder = nil;
    mServer = nil;
    
    TVLog(@"Streaming stopped");
}

#pragma mark - VideoEncoderDelegate

- (void)videoEncoder:(id)encoder didEncodeData:(NSData *)data isKeyFrame:(BOOL)isKeyFrame {
    [mServer sendVideoData:data isKeyFrame:isKeyFrame];
}

#pragma mark - StreamServerDelegate

- (void)streamServer:(id)server didReceiveTouchDown:(CGPoint)point {
    TVLog(@"Touch down: %.0f, %.0f", point.x, point.y);
    [[TouchController sharedController] touchDownAtPoint:point];
}

- (void)streamServer:(id)server didReceiveTouchUp:(CGPoint)point {
    TVLog(@"Touch up: %.0f, %.0f", point.x, point.y);
    [[TouchController sharedController] touchUpAtPoint:point];
}

- (void)streamServer:(id)server didReceiveTouchMove:(CGPoint)point {
    [[TouchController sharedController] touchMoveToPoint:point];
}

@end
