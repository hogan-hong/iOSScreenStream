/*
 * iOSScreenStream - 触控控制器
 * 使用 TrollVNC 的 STHIDEventGenerator 注入触摸事件
 */

#import "TouchController.h"
#import "STHIDEventGenerator.h"
#import "Logging.h"

@implementation TouchController

+ (TouchController *)sharedController {
    static TouchController *_inst = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _inst = [[self alloc] init];
    });
    return _inst;
}

- (void)touchDownAtPoint:(CGPoint)point {
    [[STHIDEventGenerator sharedGenerator] touchDown:point];
}

- (void)touchUpAtPoint:(CGPoint)point {
    [[STHIDEventGenerator sharedGenerator] liftUp:point];
}

- (void)touchMoveToPoint:(CGPoint)point {
    // STHIDEventGenerator 的 move 实现：
    // 先抬起再按下新位置，或直接用 touchDown 模拟
    // TrollVNC 实际支持 finger move，这里用 touchDown + touchCount 模拟
    [[STHIDEventGenerator sharedGenerator] touchDown:point touchCount:1];
}

- (void)tapAtPoint:(CGPoint)point {
    [[STHIDEventGenerator sharedGenerator] tap:point];
}

@end
