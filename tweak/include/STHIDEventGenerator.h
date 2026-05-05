/*
 * STHIDEventGenerator.h
 *
 * 重要：此文件需从 TrollVNC 复制：
 * src/STHIDEventGenerator.h
 *
 * 这是 TrollVNC 的触摸事件注入实现。
 * 编译前请复制到此位置。
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
