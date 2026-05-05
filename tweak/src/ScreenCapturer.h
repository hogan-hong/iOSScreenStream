/*
 * iOSScreenStream - 屏幕捕获（IOSurface 方式）
 * 基于 TrollVNC 实现
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
