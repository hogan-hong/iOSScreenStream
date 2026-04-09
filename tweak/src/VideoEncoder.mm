/*
 * iOSScreenStream - VideoToolbox H.264 encoder
 */

#import <VideoToolbox/VideoToolbox.h>
#import "VideoEncoder.h"
#import "Logging.h"

@implementation VideoEncoder {
    int mWidth;
    int mHeight;
    int mBitrate;
    int mFps;
    
    VTCompressionSessionRef mSession;
    BOOL mIsEncoding;
    dispatch_queue_t mEncodeQueue;
    
    // SPS/PPS for H.264
    NSData *mSPS;
    NSData *mPPS;
}

- (instancetype)initWithWidth:(int)width height:(int)height bitrate:(int)bitrate fps:(int)fps {
    self = [super init];
    if (self) {
        mWidth = width;
        mHeight = height;
        mBitrate = bitrate;
        mFps = fps;
        mSession = NULL;
        mIsEncoding = NO;
        mEncodeQueue = dispatch_queue_create("com.iosscreenstream.encoder", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)dealloc {
    [self stopEncoding];
}

- (int)width { return mWidth; }
- (int)height { return mHeight; }
- (BOOL)isEncoding { return mIsEncoding; }

- (void)startEncoding {
    if (mIsEncoding) return;
    
    OSStatus status;
    
    // Create compression session
    status = VTCompressionSessionCreate(
        kCFAllocatorDefault,
        mWidth,
        mHeight,
        kCMVideoCodecType_H264,
        NULL,
        NULL,
        NULL,
        didEncodeCallback,
        (__bridge void *)self,
        &mSession
    );
    
    if (status != noErr) {
        TVLog(@"Failed to create compression session: %d", status);
        return;
    }
    
    // Configure for low latency
    VTSessionSetProperty(mSession, kVTCompressionPropertyKey_RealTime, kCFBooleanTrue);
    VTSessionSetProperty(mSession, kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse);
    
    // Bitrate
    CFNumberRef bitrateNum = (__bridge CFNumberRef)@(mBitrate);
    VTSessionSetProperty(mSession, kVTCompressionPropertyKey_AverageBitRate, bitrateNum);
    
    // Expected frame rate
    CFNumberRef fpsNum = (__bridge CFNumberRef)@(mFps);
    VTSessionSetProperty(mSession, kVTCompressionPropertyKey_ExpectedFrameRate, fpsNum);
    
    // Profile Level
    VTSessionSetProperty(mSession, kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_Main_AutoLevel);
    
    // Data rate limits (for constant quality) - DataRateLimits expects CFArray[2] of CFNumberRef (bytes/sec)
    int64_t dataRateLimitBytesPerSec = mBitrate / 8;
    CFNumberRef dataRateLimits[2];
    dataRateLimits[0] = (__bridge CFNumberRef)[NSNumber numberWithLongLong:dataRateLimitBytesPerSec * 2];
    dataRateLimits[1] = (__bridge CFNumberRef)[NSNumber numberWithLongLong:dataRateLimitBytesPerSec];
    CFArrayRef dataRateLimitsArray = CFArrayCreate(NULL, (const void **)dataRateLimits, 2, &kCFTypeArrayCallBacks);
    VTSessionSetProperty(mSession, kVTCompressionPropertyKey_DataRateLimits, dataRateLimitsArray);
    CFRelease(dataRateLimitsArray);
    
    // Start encoding
    status = VTCompressionSessionPrepareToEncodeFrames(mSession);
    if (status != noErr) {
        TVLog(@"Failed to prepare encoding: %d", status);
        return;
    }
    
    mIsEncoding = YES;
    TVLog(@"Video encoder started: %dx%d @ %d kbps %d fps", mWidth, mHeight, mBitrate / 1000, mFps);
}

- (void)stopEncoding {
    if (!mIsEncoding) return;
    
    VTCompressionSessionCompleteFrames(mSession, kCMTimeInvalid);
    CFRelease(mSession);
    mSession = NULL;
    mIsEncoding = NO;
    
    TVLog(@"Video encoder stopped");
}

- (void)encodeSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    if (!mIsEncoding || !sampleBuffer) return;
    
    CVImageBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (!pixelBuffer) return;
    
    CMTime presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
    
    VTEncodeInfoFlags infoFlags;
    OSStatus status = VTCompressionSessionEncodeFrame(
        mSession,
        pixelBuffer,
        presentationTime,
        kCMTimeInvalid,
        NULL,
        (__bridge void *)self,
        &infoFlags
    );
    
    if (status != noErr) {
        TVLog(@"Encode frame failed: %d", status);
    }
}

- (void)handleEncodedData:(CMSampleBufferRef)sampleBuffer {
    if (!sampleBuffer) return;
    
    CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, false);
    BOOL isKeyFrame = YES;
    if (attachments && CFArrayGetCount(attachments) > 0) {
        CFDictionaryRef attachment = (CFDictionaryRef)CFArrayGetValueAtIndex(attachments, 0);
        CFBooleanRef notSync = (CFBooleanRef)CFDictionaryGetValue(attachment, kCMSampleAttachmentKey_NotSync);
        isKeyFrame = !(notSync && CFBooleanGetValue(notSync));
    }
    
    // Get H.264 NAL units
    CMBlockBufferRef blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
    if (!blockBuffer) return;
    
    size_t totalLength = 0;
    char *dataPointer = NULL;
    CMBlockBufferGetDataPointer(blockBuffer, 0, NULL, &totalLength, &dataPointer);
    
    // Parse NAL units (Annex B format)
    NSMutableData *encodedData = [NSMutableData data];
    
    size_t offset = 0;
    while (offset < totalLength - 4) {
        // Find start code (0x00000001 or 0x000001)
        uint32_t *ptr = (uint32_t *)(dataPointer + offset);
        uint32_t startCode = *ptr;
        
        // Check for start code
        BOOL hasStartCode = (startCode == 0x01000000) || ((startCode & 0x00FFFFFF) == 0x00010000);
        
        if (hasStartCode) {
            // Find next start code
            size_t nalStart = offset + 4;
            size_t nextOffset = nalStart + 1;
            
            while (nextOffset < totalLength - 4) {
                uint32_t *nextPtr = (uint32_t *)(dataPointer + nextOffset);
                uint32_t nextStartCode = *nextPtr;
                if ((nextStartCode == 0x01000000) || ((nextStartCode & 0x00FFFFFF) == 0x00010000)) {
                    break;
                }
                nextOffset++;
            }
            
            size_t nalLength = nextOffset - nalStart;
            if (nalLength > 0) {
                // Convert to length-prefixed format (4 bytes length + NAL data)
                uint32_t nalLengthNet = htonl(nalLength);
                [encodedData appendBytes:&nalLengthNet length:4];
                [encodedData appendBytes:dataPointer + nalStart length:nalLength];
            }
            
            offset = nextOffset;
        } else {
            offset++;
        }
    }
    
    if (encodedData.length > 0) {
        // Send SPS/PPS with keyframes
        if (isKeyFrame && !mSPS) {
            // Extract SPS/PPS from parameter set
            // For now, use common values or extract from first frame
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate videoEncoder:self didEncodeData:encodedData isKeyFrame:isKeyFrame];
        });
    }
}

static void didEncodeCallback(void *outputCallbackRefCon, void *sourceFrameRefCon, OSStatus status, VTEncodeInfoFlags infoFlags, CMSampleBufferRef sampleBuffer) {
    if (status != noErr) {
        TVLog(@"Encode callback error: %d", status);
        return;
    }
    
    VideoEncoder *encoder = (__bridge VideoEncoder *)outputCallbackRefCon;
    [encoder handleEncodedData:sampleBuffer];
}

@end
