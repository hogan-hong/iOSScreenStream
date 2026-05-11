/*
 * iOSScreenStream - VideoToolbox H.264 编码器
 * 修复：正确提取 NAL 单元（AVCC → Annex B），自动提取 SPS/PPS
 */

#import <VideoToolbox/VideoToolbox.h>
#import "VideoEncoder.h"
#import "Logging.h"

@implementation VideoEncoder {
    int mWidth;
    int mHeight;
    int mBitrate;
    int mFps;
    
    VTCompressionSessionRef mCompressionSession;
    BOOL mIsEncoding;
    dispatch_queue_t mEncodeQueue;
    
    // SPS/PPS
    NSData *mSPS;
    NSData *mPPS;
    BOOL mSPSPPSSent;
    
    // 强制关键帧标记
    BOOL mForceNextKeyframe;
}

- (instancetype)initWithWidth:(int)width height:(int)height bitrate:(int)bitrate fps:(int)fps {
    self = [super init];
    if (self) {
        mWidth = width;
        mHeight = height;
        mBitrate = bitrate;
        mFps = fps;
        mCompressionSession = NULL;
        mIsEncoding = NO;
        mEncodeQueue = dispatch_queue_create("com.iosscreenstream.encoder", DISPATCH_QUEUE_SERIAL);
        mSPS = nil;
        mPPS = nil;
        mSPSPPSSent = NO;
        mForceNextKeyframe = NO;
    }
    return self;
}

- (void)dealloc {
    [self stopEncoding];
}

- (int)width { return mWidth; }
- (int)height { return mHeight; }
- (BOOL)isEncoding { return mIsEncoding; }

- (void)reset {
    // 重置编码器状态，确保重新发送 SPS/PPS
    TVLog(@"重置编码器");
    
    @synchronized(self) {
        // 重置 SPS/PPS 发送标记
        mSPSPPSSent = NO;
        
        // 强制下一次编码是关键帧
        mForceNextKeyframe = YES;
        
        TVLog(@"编码器已重置，下次编码将发送新的 SPS/PPS");
    }
}

- (void)forceKeyframe {
    if (!mIsEncoding || !mCompressionSession) return;
    
    TVLog(@"强制生成关键帧");
    // 重置 SPS/PPS 发送标记，确保下次关键帧带上 SPS/PPS
    @synchronized(self) {
        mSPSPPSSent = NO;
        mForceNextKeyframe = YES;
    }
}

- (void)startEncoding {
    if (mIsEncoding) return;
    
    OSStatus status;
    
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
        &mCompressionSession
    );
    
    if (status != noErr) {
        TVLog(@"创建编码会话失败: %d", status);
        return;
    }
    
    // 低延迟配置
    VTSessionSetProperty(mCompressionSession, kVTCompressionPropertyKey_RealTime, kCFBooleanTrue);
    VTSessionSetProperty(mCompressionSession, kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse);
    
    // 码率
    CFNumberRef bitrateNum = (__bridge CFNumberRef)@(mBitrate);
    VTSessionSetProperty(mCompressionSession, kVTCompressionPropertyKey_AverageBitRate, bitrateNum);
    
    // 帧率
    CFNumberRef fpsNum = (__bridge CFNumberRef)@(mFps);
    VTSessionSetProperty(mCompressionSession, kVTCompressionPropertyKey_ExpectedFrameRate, fpsNum);
    
    // 编码档位
    VTSessionSetProperty(mCompressionSession, kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_Main_AutoLevel);
    
    // 码率限制
    int64_t dataRateLimitBytesPerSec = mBitrate / 8;
    CFNumberRef dataRateLimits[2];
    dataRateLimits[0] = (__bridge CFNumberRef)[NSNumber numberWithLongLong:dataRateLimitBytesPerSec * 2];
    dataRateLimits[1] = (__bridge CFNumberRef)[NSNumber numberWithLongLong:dataRateLimitBytesPerSec];
    CFArrayRef dataRateLimitsArray = CFArrayCreate(NULL, (const void **)dataRateLimits, 2, &kCFTypeArrayCallBacks);
    VTSessionSetProperty(mCompressionSession, kVTCompressionPropertyKey_DataRateLimits, dataRateLimitsArray);
    CFRelease(dataRateLimitsArray);
    
    // 关键帧间隔（约2秒一个关键帧）
    CFNumberRef maxKeyFrameInterval = (__bridge CFNumberRef)@(mFps * 2);
    VTSessionSetProperty(mCompressionSession, kVTCompressionPropertyKey_MaxKeyFrameInterval, maxKeyFrameInterval);
    
    status = VTCompressionSessionPrepareToEncodeFrames(mCompressionSession);
    if (status != noErr) {
        TVLog(@"编码准备失败: %d", status);
        return;
    }
    
    mIsEncoding = YES;
    mSPSPPSSent = NO;
    mForceNextKeyframe = NO;
    TVLog(@"视频编码器已启动: %dx%d @ %d kbps %d fps", mWidth, mHeight, mBitrate / 1000, mFps);
}

- (void)stopEncoding {
    if (!mIsEncoding) return;
    
    VTCompressionSessionCompleteFrames(mCompressionSession, kCMTimeInvalid);
    CFRelease(mCompressionSession);
    mCompressionSession = NULL;
    mIsEncoding = NO;
    mSPS = nil;
    mPPS = nil;
    mSPSPPSSent = NO;
    mForceNextKeyframe = NO;
    
    TVLog(@"视频编码器已停止");
}

- (void)encodeSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    if (!mIsEncoding || !sampleBuffer) return;
    
    CVImageBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (!pixelBuffer) return;
    
    CMTime presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
    
    // 如果需要强制关键帧，通过帧属性传递
    CFDictionaryRef frameProperties = NULL;
    @synchronized(self) {
        if (mForceNextKeyframe) {
            mForceNextKeyframe = NO;
            const void *keys[] = { kVTEncodeFrameOptionKey_ForceKeyFrame };
            const void *values[] = { kCFBooleanTrue };
            frameProperties = CFDictionaryCreate(NULL, keys, values, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
            TVLog(@"强制关键帧: 通过帧属性请求");
        }
    }
    
    VTEncodeInfoFlags infoFlags;
    OSStatus status = VTCompressionSessionEncodeFrame(
        mCompressionSession,
        pixelBuffer,
        presentationTime,
        kCMTimeInvalid,
        frameProperties,
        (__bridge void *)self,
        &infoFlags
    );
    
    if (frameProperties) {
        CFRelease(frameProperties);
    }
    
    if (status != noErr) {
        TVLog(@"编码帧失败: %d", status);
    }
}

#pragma mark - NAL 单元提取（AVCC 格式 → Annex B）

- (void)handleEncodedData:(CMSampleBufferRef)sampleBuffer {
    if (!sampleBuffer) return;
    
    // 判断是否关键帧
    CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, false);
    BOOL isKeyFrame = NO;
    if (attachments && CFArrayGetCount(attachments) > 0) {
        CFDictionaryRef attachment = (CFDictionaryRef)CFArrayGetValueAtIndex(attachments, 0);
        CFBooleanRef notSync = (CFBooleanRef)CFDictionaryGetValue(attachment, kCMSampleAttachmentKey_NotSync);
        isKeyFrame = !(notSync && CFBooleanGetValue(notSync));
    }
    
    CMBlockBufferRef blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
    if (!blockBuffer) return;
    
    size_t totalLength = 0;
    char *dataPointer = NULL;
    CMBlockBufferGetDataPointer(blockBuffer, 0, NULL, &totalLength, &dataPointer);
    
    if (totalLength == 0) return;
    
    // VideoToolbox 输出的是 AVCC 格式（4字节长度前缀 + NAL 数据）
    // 我们将其转换为 Annex B 格式（00 00 00 01 + NAL 数据）供 FFmpeg 解码
    
    NSMutableData *annexBData = [NSMutableData data];
    
    // 如果是关键帧，先提取并发送 SPS/PPS
    if (isKeyFrame) {
        [self extractSPSPPSFromFormatDescription:CMSampleBufferGetFormatDescription(sampleBuffer)];
        
        if (mSPS && mPPS) {
            // Annex B start code
            uint8_t startCode[] = {0x00, 0x00, 0x00, 0x01};
            [annexBData appendBytes:startCode length:4];
            [annexBData appendData:mSPS];
            [annexBData appendBytes:startCode length:4];
            [annexBData appendData:mPPS];
        }
    }
    
    // 解析 AVCC 格式：4字节大端长度 + NAL 数据，循环处理
    size_t offset = 0;
    while (offset + 4 <= totalLength) {
        uint32_t nalLength = 0;
        memcpy(&nalLength, dataPointer + offset, 4);
        nalLength = CFSwapInt32BigToHost(nalLength);
        
        if (offset + 4 + nalLength > totalLength) {
            TVLog(@"NAL 长度越界: offset=%zu, nalLen=%u, total=%zu", offset, nalLength, totalLength);
            break;
        }
        
        // 写入 Annex B start code + NAL 数据
        uint8_t startCode[] = {0x00, 0x00, 0x00, 0x01};
        [annexBData appendBytes:startCode length:4];
        [annexBData appendBytes:dataPointer + offset + 4 length:nalLength];
        
        offset += 4 + nalLength;
    }
    
    if (annexBData.length > 0) {
        // 直接在编码回调线程调用 delegate，避免主线程阻塞导致编码器卡死
        // （CADisplayLink 在主线程驱动，如果主线程被 UDP 发送阻塞，新帧无法提交）
        [self.delegate videoEncoder:self didEncodeData:[annexBData copy] isKeyFrame:isKeyFrame];
    }
}

- (void)extractSPSPPSFromFormatDescription:(CMFormatDescriptionRef)formatDescription {
    if (!formatDescription) return;
    
    size_t parameterSetCount = 0;
    OSStatus status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
        formatDescription,
        0,  // SPS
        NULL, NULL,
        &parameterSetCount,
        NULL
    );
    
    if (status != noErr) {
        TVLog(@"提取 SPS/PPS 失败: %d", status);
        return;
    }
    
    // 提取 SPS（索引0）
    const uint8_t *spsData = NULL;
    size_t spsSize = 0;
    status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
        formatDescription, 0, &spsData, &spsSize, NULL, NULL
    );
    if (status == noErr && spsData && spsSize > 0) {
        mSPS = [NSData dataWithBytes:spsData length:spsSize];
    }
    
    // 提取 PPS（索引1）
    const uint8_t *ppsData = NULL;
    size_t ppsSize = 0;
    status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
        formatDescription, 1, &ppsData, &ppsSize, NULL, NULL
    );
    if (status == noErr && ppsData && ppsSize > 0) {
        mPPS = [NSData dataWithBytes:ppsData length:ppsSize];
    }
    
    if (mSPS && mPPS) {
        TVLog(@"SPS/PPS 提取成功: SPS=%zu字节, PPS=%zu字节", spsSize, ppsSize);
    }
}

static void didEncodeCallback(void *outputCallbackRefCon, void *sourceFrameRefCon, OSStatus status, VTEncodeInfoFlags infoFlags, CMSampleBufferRef sampleBuffer) {
    if (status != noErr) {
        TVLog(@"编码回调错误: %d", status);
        return;
    }
    
    VideoEncoder *encoder = (__bridge VideoEncoder *)outputCallbackRefCon;
    [encoder handleEncodedData:sampleBuffer];
}

@end
