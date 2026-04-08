/*
 * IOSurfaceSPI.h - IOSurface SPI declarations
 * Based on Apple's private IOSurface API
 */

#ifndef IOSurfaceSPI_h
#define IOSurfaceSPI_h

#ifdef __cplusplus
extern "C" {
#endif

typedef struct __IOSurface *IOSurfaceRef;
typedef struct __IOSurfaceAccelerator *IOSurfaceAcceleratorRef;

extern const CFStringRef kIOSurfaceAllocSize;
extern const CFStringRef kIOSurfaceBytesPerElement;
extern const CFStringRef kIOSurfaceBytesPerRow;
extern const CFStringRef kIOSurfaceCacheMode;
extern const CFStringRef kIOSurfaceColorSpace;
extern const CFStringRef kIOSurfaceHeight;
extern const CFStringRef kIOSurfacePixelFormat;
extern const CFStringRef kIOSurfaceWidth;
extern const CFStringRef kIOSurfaceElementWidth;
extern const CFStringRef kIOSurfaceElementHeight;

size_t IOSurfaceAlignProperty(CFStringRef property, size_t value);
IOSurfaceRef IOSurfaceCreate(CFDictionaryRef properties);
size_t IOSurfaceGetAllocSize(IOSurfaceRef buffer);
void *IOSurfaceGetBaseAddress(IOSurfaceRef buffer);
size_t IOSurfaceGetBytesPerRow(IOSurfaceRef buffer);
size_t IOSurfaceGetHeight(IOSurfaceRef buffer);
size_t IOSurfaceGetWidth(IOSurfaceRef buffer);
OSType IOSurfaceGetPixelFormat(IOSurfaceRef buffer);
IOReturn IOSurfaceLock(IOSurfaceRef buffer, uint32_t options, uint32_t *seed);
IOReturn IOSurfaceUnlock(IOSurfaceRef buffer, uint32_t options, uint32_t *seed);

IOReturn IOSurfaceAcceleratorCreate(CFAllocatorRef, CFDictionaryRef properties, IOSurfaceAcceleratorRef* acceleratorOut);
CFRunLoopSourceRef IOSurfaceAcceleratorGetRunLoopSource(IOSurfaceAcceleratorRef);
IOReturn IOSurfaceAcceleratorTransferSurface(IOSurfaceAcceleratorRef, IOSurfaceRef sourceBuffer, IOSurfaceRef destinationBuffer, void *, void *, void *, void *);

#ifdef __cplusplus
}
#endif

#endif /* IOSurfaceSPI_h */
