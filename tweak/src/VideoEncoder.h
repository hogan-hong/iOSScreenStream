/*
 * iOSScreenStream - VideoToolbox H.264 encoder
 */

#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>

NS_ASSUME_NONNULL_BEGIN

@protocol VideoEncoderDelegate <NSObject>
- (void)videoEncoder:(id)encoder didEncodeData:(NSData *)data isKeyFrame:(BOOL)isKeyFrame;
@end

@interface VideoEncoder : NSObject

@property (nonatomic, weak) id<VideoEncoderDelegate> delegate;
@property (nonatomic, readonly) int width;
@property (nonatomic, readonly) int height;
@property (nonatomic, readonly) BOOL isEncoding;

- (instancetype)initWithWidth:(int)width height:(int)height bitrate:(int)bitrate fps:(int)fps;
- (void)startEncoding;
- (void)stopEncoding;
- (void)encodeSampleBuffer:(CMSampleBufferRef)sampleBuffer;

@end

NS_ASSUME_NONNULL_END
