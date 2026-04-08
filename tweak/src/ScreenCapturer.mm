/*
 * iOSScreenStream - Screen capture using IOSurface
 * Based on TrollVNC implementation
 */

#import <UIKit/UIDevice.h>
#import <UIKit/UIScreen.h>
#import <mach/mach.h>

#import "Logging.h"
#import "ScreenCapturer.h"
#import "IOSurfaceSPI.h"
#import "IOKitSPI.h"
#import "UIScreen+Private.h"

#ifdef __cplusplus
extern "C" {
#endif

// CARenderServer functions from TrollVNC
CFIndex CARenderServerGetDirtyFrameCount(void *);
void CARenderServerRenderDisplay(kern_return_t a, CFStringRef b, IOSurfaceRef surface, int x, int y);

#ifdef __cplusplus
}
#endif

static BOOL gShouldApplyOrientationFix = YES;

@implementation ScreenCapturer {
    NSDictionary *mRenderProperties;
    IOSurfaceRef mScreenSurface;
    CADisplayLink *mDisplayLink;
    void (^mFrameHandler)(CMSampleBufferRef sampleBuffer);
    NSInteger mMinFps;
    NSInteger mPreferredFps;
    NSInteger mMaxFps;
}

+ (instancetype)sharedCapturer {
    static ScreenCapturer *_inst = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _inst = [[self alloc] init];
    });
    return _inst;
}

- (instancetype)init {
    self = [super init];
    if (!self)
        return nil;

    int width, height;
    CGSize screenSize = [[UIScreen mainScreen] _unjailedReferenceBoundsInPixels].size;

#if !TARGET_IPHONE_SIMULATOR
    if (gShouldApplyOrientationFix) {
        width = (int)round(screenSize.height);
        height = (int)round(screenSize.width);
    } else {
#endif
        width = (int)round(screenSize.width);
        height = (int)round(screenSize.height);
#if !TARGET_IPHONE_SIMULATOR
    }
#endif

    // Pixel format for Alpha, Red, Green and Blue
    unsigned pixelFormat = 0x42475241; // 'ARGB'
    int bytesPerComponent = sizeof(uint8_t);
    int bytesPerElement = bytesPerComponent * 4;
    int bytesPerRow = (int)IOSurfaceAlignProperty(kIOSurfaceBytesPerRow, bytesPerElement * width);

    CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CFPropertyListRef colorSpacePropertyList = CGColorSpaceCopyPropertyList(colorSpace);
    CGColorSpaceRelease(colorSpace);

    mRenderProperties = @{
        (__bridge NSString *)kIOSurfaceBytesPerElement : @(bytesPerElement),
        (__bridge NSString *)kIOSurfaceBytesPerRow : @(bytesPerRow),
        (__bridge NSString *)kIOSurfaceWidth : @(width),
        (__bridge NSString *)kIOSurfaceHeight : @(height),
        (__bridge NSString *)kIOSurfacePixelFormat : @(pixelFormat),
        (__bridge NSString *)kIOSurfaceAllocSize : @(bytesPerRow * height),
        (__bridge NSString *)kIOSurfaceColorSpace : CFBridgingRelease(colorSpacePropertyList),
    };

    TVLog(@"Screen capture initialized: %dx%d", width, height);

    mScreenSurface = IOSurfaceCreate((__bridge CFDictionaryRef)mRenderProperties);
    mDisplayLink = nil;
    mFrameHandler = NULL;
    mMinFps = 0;
    mPreferredFps = 30;
    mMaxFps = 60;

    return self;
}

static CFIndex sDirtyFrameCount = 0;

- (BOOL)renderDisplayToScreenSurface:(IOSurfaceRef)dstSurface {
#if TARGET_OS_SIMULATOR
    CARenderServerRenderDisplay(0, CFSTR("LCD"), dstSurface, 0, 0);
    return YES;
#else
    static IOSurfaceRef srcSurface;
    static IOSurfaceAcceleratorRef accelerator;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        @autoreleasepool {
            srcSurface = IOSurfaceCreate((__bridge CFDictionaryRef)mRenderProperties);
            IOSurfaceAcceleratorCreate(kCFAllocatorDefault, nil, &accelerator);
            
            CFRunLoopRef runLoop = CFRunLoopGetMain();
            CFRunLoopSourceRef runLoopSource = IOSurfaceAcceleratorGetRunLoopSource(accelerator);
            CFRunLoopAddSource(runLoop, runLoopSource, kCFRunLoopDefaultMode);
        }
    });

    CFIndex dirtyFrameCount = CARenderServerGetDirtyFrameCount(NULL);
    if (dirtyFrameCount == sDirtyFrameCount) {
        return NO; // No change
    }

    // Fast ~20ms, sRGB capture
    CARenderServerRenderDisplay(0, CFSTR("LCD"), srcSurface, 0, 0);
    IOSurfaceAcceleratorTransferSurface(accelerator, srcSurface, dstSurface, NULL, NULL, NULL, NULL);

    sDirtyFrameCount = dirtyFrameCount;
    return YES;
#endif
}

- (BOOL)updateDisplay:(CADisplayLink *)displayLink {
    BOOL surfaceChanged = [self renderDisplayToScreenSurface:mScreenSurface];
    return surfaceChanged;
}

- (NSDictionary *)renderProperties {
    return mRenderProperties;
}

- (void)startCaptureWithFrameHandler:(void (^)(CMSampleBufferRef))frameHandler {
    mFrameHandler = [frameHandler copy];

    if (mDisplayLink) {
        return;
    }

    void (^startBlock)(void) = ^{
        mDisplayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(onDisplayLink:)];

#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 150000
        if (@available(iOS 15.0, *)) {
            CAFrameRateRange range;
            range.minimum = (self->mMinFps > 0) ? self->mMinFps : 0.0;
            range.maximum = (self->mMaxFps > 0) ? self->mMaxFps : 0.0;
            range.preferred = (self->mPreferredFps > 0) ? self->mPreferredFps : 0.0;
            mDisplayLink.preferredFrameRateRange = range;
        } else {
#endif
            NSInteger setFps = (mMaxFps > 0) ? mMaxFps : mPreferredFps;
            if ([mDisplayLink respondsToSelector:@selector(preferredFramesPerSecond)])
                mDisplayLink.preferredFramesPerSecond = (int)setFps;
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 150000
        }
#endif

        [mDisplayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    };

    if ([NSThread isMainThread]) {
        startBlock();
    } else {
        dispatch_async(dispatch_get_main_queue(), startBlock);
    }
}

- (void)endCapture {
    void (^stopBlock)(void) = ^{
        if (mDisplayLink) {
            [mDisplayLink invalidate];
            mDisplayLink = nil;
        }
        mFrameHandler = nil;
    };

    if ([NSThread isMainThread]) {
        stopBlock();
    } else {
        dispatch_async(dispatch_get_main_queue(), stopBlock);
    }
}

- (void)setPreferredFrameRateWithMin:(NSInteger)minFps preferred:(NSInteger)preferredFps max:(NSInteger)maxFps {
    mMinFps = MAX(0, minFps);
    mMaxFps = MAX(0, maxFps);
    mPreferredFps = MAX(0, preferredFps);

    if (mPreferredFps == 0) {
        if (mMaxFps > 0)
            mPreferredFps = mMaxFps;
        else if (mMinFps > 0)
            mPreferredFps = mMinFps;
        else
            mPreferredFps = 30;
    }

    if (mDisplayLink) {
        void (^applyBlock)(void) = ^{
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 150000
            if (@available(iOS 15.0, *)) {
                CAFrameRateRange range;
                range.minimum = (self->mMinFps > 0) ? self->mMinFps : 0.0;
                range.maximum = (self->mMaxFps > 0) ? self->mMaxFps : 0.0;
                range.preferred = (self->mPreferredFps > 0) ? self->mPreferredFps : 0.0;
                self->mDisplayLink.preferredFrameRateRange = range;
            } else {
#endif
                NSInteger setFps = (self->mMaxFps > 0) ? self->mMaxFps : self->mPreferredFps;
                self->mDisplayLink.preferredFramesPerSecond = (int)setFps;
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 150000
            }
#endif
        };

        if ([NSThread isMainThread])
            applyBlock();
        else
            dispatch_async(dispatch_get_main_queue(), applyBlock);
    }
}

- (void)onDisplayLink:(CADisplayLink *)link {
    if (!mFrameHandler)
        return;

    BOOL displayChanged = [self updateDisplay:link];
    if (!displayChanged) {
        return;
    }

    CVPixelBufferRef pixelBuffer = NULL;
    NSDictionary *attrs = @{(NSString *)kCVPixelBufferIOSurfacePropertiesKey : @{}};
    CVReturn cvret = CVPixelBufferCreateWithIOSurface(kCFAllocatorDefault, mScreenSurface,
                                                      (__bridge CFDictionaryRef)attrs, &pixelBuffer);
    if (cvret != kCVReturnSuccess || !pixelBuffer) {
        return;
    }

    CMVideoFormatDescriptionRef formatDesc = NULL;
    OSStatus status = CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, pixelBuffer, &formatDesc);
    if (status != noErr || !formatDesc) {
        CVPixelBufferRelease(pixelBuffer);
        return;
    }

    int32_t timescale = 1000000000;
    CMSampleTimingInfo timing;
    timing.duration = CMTimeMakeWithSeconds(link.duration, timescale);
    timing.presentationTimeStamp = CMTimeMakeWithSeconds(link.timestamp, timescale);
    timing.decodeTimeStamp = kCMTimeInvalid;

    CMSampleBufferRef sampleBuffer = NULL;
    status = CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault, pixelBuffer, true, NULL, NULL, formatDesc, &timing,
                                                &sampleBuffer);

    if (status == noErr && sampleBuffer) {
        mFrameHandler(sampleBuffer);
        CFRelease(sampleBuffer);
    }

    if (formatDesc)
        CFRelease(formatDesc);
    if (pixelBuffer)
        CVPixelBufferRelease(pixelBuffer);
}

@end
