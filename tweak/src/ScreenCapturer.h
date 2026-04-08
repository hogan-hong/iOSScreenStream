/*
 * iOSScreenStream - Screen capture using IOSurface
 * Based on TrollVNC implementation
 */

#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>

NS_ASSUME_NONNULL_BEGIN

@interface ScreenCapturer : NSObject

+ (instancetype)sharedCapturer;

- (NSDictionary *)renderProperties;
- (void)startCaptureWithFrameHandler:(void (^)(CMSampleBufferRef sampleBuffer))frameHandler;
- (void)endCapture;
- (void)setPreferredFrameRateWithMin:(NSInteger)minFps preferred:(NSInteger)preferredFps max:(NSInteger)maxFps;

@end

NS_ASSUME_NONNULL_END
