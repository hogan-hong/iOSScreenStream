/*
 * STHIDEventGenerator.h
 * 
 * IMPORTANT: This file needs to be copied from TrollVNC:
 * src/STHIDEventGenerator.h
 * 
 * This is TrollVNC's touch event injection implementation.
 * Copy it to this location before building.
 */

#import <CoreGraphics/CGGeometry.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface STHIDEventGenerator : NSObject

+ (STHIDEventGenerator *)sharedGenerator;

- (void)touchDown:(CGPoint)location;
- (void)liftUp:(CGPoint)location;
- (void)touchDown:(CGPoint)location touchCount:(NSUInteger)count;
- (void)liftUp:(CGPoint)location touchCount:(NSUInteger)count;
- (void)tap:(CGPoint)location;
- (void)sendEventStream:(NSDictionary *)eventInfo;

@end

NS_ASSUME_NONNULL_END
