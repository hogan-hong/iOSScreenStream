/*
 * iOSScreenStream - Stream server (UDP video + TCP control)
 */

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

@protocol StreamServerDelegate <NSObject>
- (void)streamServer:(id)server didReceiveTouchDown:(CGPoint)point;
- (void)streamServer:(id)server didReceiveTouchUp:(CGPoint)point;
- (void)streamServer:(id)server didReceiveTouchMove:(CGPoint)point;
@end

@interface StreamServer : NSObject

@property (nonatomic, weak) id<StreamServerDelegate> delegate;
@property (nonatomic, readonly) BOOL isRunning;
@property (nonatomic, readonly) NSString *serverIP;
@property (nonatomic, readonly) int videoPort;
@property (nonatomic, readonly) int controlPort;

- (instancetype)initWithServerIP:(NSString *)ip videoPort:(int)videoPort controlPort:(int)controlPort;
- (BOOL)start;
- (void)stop;
- (void)sendVideoData:(NSData *)data isKeyFrame:(BOOL)isKeyFrame;

@end

NS_ASSUME_NONNULL_END
