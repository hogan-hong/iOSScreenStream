/*
 * iOSScreenStream - Stream server implementation
 */

#import "StreamServer.h"
#import "Logging.h"
#import <UIKit/UIKit.h>

#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>

@interface StreamServer () <NSStreamDelegate>
@end

@implementation StreamServer {
    NSString *mServerIP;
    int mVideoPort;
    int mControlPort;
    BOOL mIsRunning;
    
    int mUdpSocket;
    struct sockaddr_in mServerAddr;
    
    NSInputStream *mControlInputStream;
    NSOutputStream *mControlOutputStream;
    NSMutableData *mReceivedData;
}

- (instancetype)initWithServerIP:(NSString *)ip videoPort:(int)videoPort controlPort:(int)controlPort {
    self = [super init];
    if (self) {
        mServerIP = ip;
        mVideoPort = videoPort;
        mControlPort = controlPort;
        mIsRunning = NO;
        mUdpSocket = -1;
        mReceivedData = [NSMutableData data];
    }
    return self;
}

- (void)dealloc {
    [self stop];
}

- (BOOL)isRunning { return mIsRunning; }
- (NSString *)serverIP { return mServerIP; }
- (int)videoPort { return mVideoPort; }
- (int)controlPort { return mControlPort; }

- (BOOL)start {
    if (mIsRunning) return YES;
    
    // Create UDP socket for video
    mUdpSocket = socket(AF_INET, SOCK_DGRAM, 0);
    if (mUdpSocket < 0) {
        TVLog(@"Failed to create UDP socket");
        return NO;
    }
    
    // Set server address
    memset(&mServerAddr, 0, sizeof(mServerAddr));
    mServerAddr.sin_family = AF_INET;
    mServerAddr.sin_port = htons(mVideoPort);
    inet_pton(AF_INET, [mServerIP UTF8String], &mServerAddr.sin_addr);
    
    // Connect UDP
    if (connect(mUdpSocket, (struct sockaddr *)&mServerAddr, sizeof(mServerAddr)) < 0) {
        TVLog(@"Failed to connect UDP socket");
        close(mUdpSocket);
        mUdpSocket = -1;
        return NO;
    }
    
    // Start TCP connection for control
    if (![self startControlConnection]) {
        close(mUdpSocket);
        mUdpSocket = -1;
        return NO;
    }
    
    mIsRunning = YES;
    TVLog(@"Stream server started: %@:%d (video) %d (control)", mServerIP, mVideoPort, mControlPort);
    return YES;
}

- (BOOL)startControlConnection {
    CFReadStreamRef readStream;
    CFWriteStreamRef writeStream;
    
    CFStreamCreatePairWithSocketToHost(
        kCFAllocatorDefault,
        (__bridge CFStringRef)mServerIP,
        mControlPort,
        &readStream,
        &writeStream
    );
    
    mControlInputStream = (__bridge_transfer NSInputStream *)readStream;
    mControlOutputStream = (__bridge_transfer NSOutputStream *)writeStream;
    
    if (!mControlInputStream || !mControlOutputStream) {
        TVLog(@"Failed to create control streams");
        return NO;
    }
    
    mControlInputStream.delegate = self;
    mControlOutputStream.delegate = self;
    
    [mControlInputStream scheduleInRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
    [mControlOutputStream scheduleInRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
    
    [mControlInputStream open];
    [mControlOutputStream open];
    
    return YES;
}

- (void)stop {
    if (!mIsRunning) return;
    
    if (mUdpSocket >= 0) {
        close(mUdpSocket);
        mUdpSocket = -1;
    }
    
    [mControlInputStream close];
    [mControlOutputStream close];
    [mControlInputStream removeFromRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
    [mControlOutputStream removeFromRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
    mControlInputStream = nil;
    mControlOutputStream = nil;
    
    mIsRunning = NO;
    TVLog(@"Stream server stopped");
}

- (void)sendVideoData:(NSData *)data isKeyFrame:(BOOL)isKeyFrame {
    if (!mIsRunning || mUdpSocket < 0) return;
    
    ssize_t sent = send(mUdpSocket, data.bytes, data.length, 0);
    if (sent < 0) {
        TVLog(@"Failed to send video data");
    }
}

#pragma mark - NSStreamDelegate

- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode {
    switch (eventCode) {
        case NSStreamEventOpenCompleted:
            TVLog(@"Control stream opened");
            break;
            
        case NSStreamEventHasBytesAvailable:
            if (aStream == mControlInputStream) {
                uint8_t buffer[4096];
                NSInteger bytesRead = [mControlInputStream read:buffer maxLength:sizeof(buffer)];
                if (bytesRead > 0) {
                    [mReceivedData appendBytes:buffer length:bytesRead];
                    [self processReceivedData];
                }
            }
            break;
            
        case NSStreamEventErrorOccurred:
            TVLog(@"Control stream error: %@", aStream.streamError);
            // Try to reconnect
            [self reconnectControl];
            break;
            
        case NSStreamEventEndEncountered:
            TVLog(@"Control stream ended");
            [self reconnectControl];
            break;
            
        default:
            break;
    }
}

- (void)processReceivedData {
    // Process complete JSON messages (newline separated)
    NSData *data = mReceivedData;
    NSString *string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!string) return;
    
    NSArray *lines = [string componentsSeparatedByString:@"\n"];
    for (NSString *line in lines) {
        if (line.length == 0) continue;
        
        NSError *error;
        NSDictionary *msg = [NSJSONSerialization JSONObjectWithData:[line dataUsingEncoding:NSUTF8StringEncoding]
                                                            options:0
                                                              error:&error];
        if (error || ![msg isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        
        NSString *type = msg[@"type"];
        if ([type isEqualToString:@"touch"]) {
            [self handleTouchMessage:msg];
        }
    }
    
    // Keep unprocessed data
    NSString *remaining = [string substringFromIndex:string.length - (string.length % [data length])];
    if (remaining.length > 0) {
        mReceivedData = [NSMutableData dataWithData:[remaining dataUsingEncoding:NSUTF8StringEncoding]];
    } else {
        [mReceivedData setLength:0];
    }
}

- (void)handleTouchMessage:(NSDictionary *)msg {
    NSString *action = msg[@"action"];
    CGFloat x = [msg[@"x"] floatValue];
    CGFloat y = [msg[@"y"] floatValue];
    
    // Get screen bounds
    CGSize screenSize = [[UIScreen mainScreen] bounds].size;
    CGPoint point = CGPointMake(x * screenSize.width, y * screenSize.height);
    
    if ([action isEqualToString:@"down"]) {
        [self.delegate streamServer:self didReceiveTouchDown:point];
    } else if ([action isEqualToString:@"up"]) {
        [self.delegate streamServer:self didReceiveTouchUp:point];
    } else if ([action isEqualToString:@"move"]) {
        [self.delegate streamServer:self didReceiveTouchMove:point];
    }
}

- (void)reconnectControl {
    [mControlInputStream close];
    [mControlOutputStream close];
    mReceivedData = [NSMutableData data];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [self startControlConnection];
    });
}

@end
