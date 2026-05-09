/*
 * iOSScreenStream - 触控控制器
 * 使用 TrollVNC 的 STHIDEventGenerator 注入触摸事件
 * 支持：触摸、拖动（finger move）、长按、滚动手势
 */

#import "TouchController.h"
#import "STHIDEventGenerator.h"
#import "Logging.h"

@implementation TouchController {
    BOOL _fingerDown;       // 当前是否有手指按下
    NSUInteger _touchPathIndex;  // touch path 索引（用于 move）
}

+ (TouchController *)sharedController {
    static TouchController *_inst = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _inst = [[self alloc] init];
    });
    return _inst;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _fingerDown = NO;
        _touchPathIndex = 0;
    }
    return self;
}

- (void)touchDownAtPoint:(CGPoint)point {
    _fingerDown = YES;
    _touchPathIndex = 0;
    [[STHIDEventGenerator sharedGenerator] touchDown:point];
}

- (void)touchUpAtPoint:(CGPoint)point {
    _fingerDown = NO;
    [[STHIDEventGenerator sharedGenerator] liftUp:point];
}

- (void)touchMoveToPoint:(CGPoint)point {
    // 真正的 finger move：使用 sendEventStream 发送 touch move 事件
    // 参考 TrollVNC 的 fingerMove 实现
    if (!_fingerDown) {
        // 如果没有按下，先按下
        [self touchDownAtPoint:point];
        return;
    }
    
    _touchPathIndex++;
    // 使用 sendEventStream 发送 move 事件（TrollVNC 风格）
    NSDictionary *eventInfo = @{
        @"type" : @"touch",
        @"action" : @"move",
        @"x" : @(point.x),
        @"y" : @(point.y),
        @"pathIndex" : @(_touchPathIndex)
    };
    [[STHIDEventGenerator sharedGenerator] sendEventStream:eventInfo];
}

- (void)tapAtPoint:(CGPoint)point {
    [[STHIDEventGenerator sharedGenerator] tap:point];
}

- (void)longPressAtPoint:(CGPoint)point {
    // 长按：按下后延迟 0.5 秒抬起
    [[STHIDEventGenerator sharedGenerator] touchDown:point];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[STHIDEventGenerator sharedGenerator] liftUp:point];
    });
}

- (void)scrollAtPoint:(CGPoint)point direction:(int)direction {
    // 滑动手势：从 point 向上/下滑动一段距离
    CGFloat distance = 80.0;  // 滑动像素距离
    CGFloat startY = point.y;
    CGFloat endY = (direction > 0) ? startY - distance : startY + distance;  // 正=向上滑，负=向下滑
    
    // 模拟快速滑动：按下 → move → 抬起
    [[STHIDEventGenerator sharedGenerator] touchDown:point];
    
    // 分步移动，让手势更自然
    int steps = 5;
    CGFloat stepY = (endY - startY) / steps;
    for (int i = 1; i <= steps; i++) {
        CGPoint movePoint = CGPointMake(point.x, startY + stepY * i);
        [[STHIDEventGenerator sharedGenerator] touchDown:movePoint touchCount:1];
    }
    
    CGPoint endPoint = CGPointMake(point.x, endY);
    [[STHIDEventGenerator sharedGenerator] liftUp:endPoint];
}

@end
