/*
 * iOSScreenStream - 触控控制器
 * 使用 TrollVNC 的 STHIDEventGenerator 注入触摸事件
 */

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

@interface TouchController : NSObject

+ (TouchController *)sharedController;

- (void)touchDownAtPoint:(CGPoint)point;
- (void)touchUpAtPoint:(CGPoint)point;
- (void)touchMoveToPoint:(CGPoint)point;
- (void)tapAtPoint:(CGPoint)point;

@end

NS_ASSUME_NONNULL_END
