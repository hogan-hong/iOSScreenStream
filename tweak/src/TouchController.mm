/*
 * iOSScreenStream - 触控控制器
 * 使用 TrollVNC 的 STHIDEventGenerator 注入触摸事件
 * 支持：触摸、拖动（finger move）、长按、滚动手势
 *
 * 重要：sendEventStream 的字典格式必须与 TrollVNC 一致
 * 参考：https://github.com/OwnGoalStudio/TrollVNC/blob/main/src/STHIDEventGenerator.h
 */

#import "TouchController.h"
#import "STHIDEventGenerator.h"
#import "Logging.h"
#import <UIKit/UIScreen.h>

// sendEventStream 字典 key 已在 STHIDEventGenerator.h 中定义

@implementation TouchController {
    BOOL _fingerDown;           // 当前是否有手指按下
    NSUInteger _activeFingerId; // 当前活动手指的 ID
    CGPoint _lastDownPoint;     // 上次按下的坐标（点坐标）
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
        _activeFingerId = 2;  // TrollVNC 用 2 作为第一个手指 ID
        _lastDownPoint = CGPointZero;
    }
    return self;
}

#pragma mark - 坐标转换

- (CGPoint)pointToPixel:(CGPoint)point {
    // STHIDEventGenerator 的 touchDown/liftUp 方法内部会自动把点坐标转为像素坐标
    // 但 sendEventStream 不会，它直接传给 IOKit，需要像素坐标
    CGFloat scale = [UIScreen mainScreen].scale;
    return CGPointMake(point.x * scale, point.y * scale);
}

#pragma mark - 基本触摸

- (void)touchDownAtPoint:(CGPoint)point {
    _fingerDown = YES;
    _lastDownPoint = point;
    TVLog(@"[TC] touchDown: (%.1f, %.1f)", point.x, point.y);
    
    // 确保在主线程执行 UI 操作
    dispatch_async(dispatch_get_main_queue(), ^{
        [[STHIDEventGenerator sharedGenerator] touchDown:point];
    });
}

- (void)touchUpAtPoint:(CGPoint)point {
    _fingerDown = NO;
    TVLog(@"[TC] touchUp: (%.1f, %.1f)", point.x, point.y);
    
    // 确保在主线程执行 UI 操作
    dispatch_async(dispatch_get_main_queue(), ^{
        [[STHIDEventGenerator sharedGenerator] liftUp:point];
    });
}

- (void)touchMoveToPoint:(CGPoint)point {
    if (!_fingerDown) {
        [self touchDownAtPoint:point];
        return;
    }
    
    // 使用 sendEventStream 发送 finger move 事件
    // 格式必须与 TrollVNC 的 STHIDEventGenerator 完全一致
    CGPoint pixelFrom = [self pointToPixel:_lastDownPoint];
    CGPoint pixelTo = [self pointToPixel:point];
    
    TVLog(@"[TC] touchMove: (%.1f,%.1f) -> (%.1f,%.1f) [pixels]", pixelFrom.x, pixelFrom.y, pixelTo.x, pixelTo.y);
    
    // 构造 move 事件字典（TrollVNC 格式）
    NSDictionary *startTouch = @{
        HIDEventTouchIDKey: @(_activeFingerId),
        HIDEventPhaseKey: HIDEventPhaseMoved,
        HIDEventXKey: @(pixelFrom.x),
        HIDEventYKey: @(pixelFrom.y),
        HIDEventPressureKey: @(0),
        HIDEventMajorRadiusKey: @(5.0),
        HIDEventMinorRadiusKey: @(5.0),
        HIDEventTwistKey: @(0),
        HIDEventMaskKey: @(0)
    };
    
    NSDictionary *endTouch = @{
        HIDEventTouchIDKey: @(_activeFingerId),
        HIDEventPhaseKey: HIDEventPhaseMoved,
        HIDEventXKey: @(pixelTo.x),
        HIDEventYKey: @(pixelTo.y),
        HIDEventPressureKey: @(0),
        HIDEventMajorRadiusKey: @(5.0),
        HIDEventMinorRadiusKey: @(5.0),
        HIDEventTwistKey: @(0),
        HIDEventMaskKey: @(0)
    };
    
    // 使用 events 数组 + interpolate 实现平滑移动
    // TrollVNC 会在 startEvent 和 endEvent 之间按 timestep 插值移动事件
    NSDictionary *eventInfo = @{
        TopLevelEventInfoKey: @{
            HIDEventInputType: HIDEventInputTypeHand,
            HIDEventTouchesKey: @[endTouch]   // 当前状态
        },
        SecondLevelEventsKey: @[
            @{
                HIDEventInputType: HIDEventInputTypeHand,
                HIDEventTouchesKey: @[startTouch],
                HIDEventTimeOffsetKey: @(0)
            },
            @{
                HIDEventInputType: HIDEventInputTypeHand,
                HIDEventTouchesKey: @[endTouch],
                HIDEventTimeOffsetKey: @(0.064),   // 约 4 步 * 16ms
                HIDEventInterpolateKey: HIDEventInterpolationTypeLinear,
                HIDEventTimestepKey: @(0.016)      // 16ms 每步
            }
        ]
    };
    
    // 确保在主线程执行 UI 操作
    dispatch_async(dispatch_get_main_queue(), ^{
        [[STHIDEventGenerator sharedGenerator] sendEventStream:eventInfo];
    });
    
    _lastDownPoint = point;
}

- (void)tapAtPoint:(CGPoint)point {
    TVLog(@"[TC] tap: (%.1f, %.1f)", point.x, point.y);
    
    // 确保在主线程执行 UI 操作
    dispatch_async(dispatch_get_main_queue(), ^{
        [[STHIDEventGenerator sharedGenerator] tap:point];
    });
}

#pragma mark - 长按（右键映射）

- (void)longPressAtPoint:(CGPoint)point {
    TVLog(@"[TC] longPress: (%.1f, %.1f)", point.x, point.y);
    
    // 长按：按下 → 等待 0.8 秒 → 抬起
    // 0.5 秒太短，iOS 长按检测阈值通常是 0.5-0.8 秒
    
    // 确保在主线程执行 UI 操作
    dispatch_async(dispatch_get_main_queue(), ^{
        [[STHIDEventGenerator sharedGenerator] touchDown:point];
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [[STHIDEventGenerator sharedGenerator] liftUp:point];
        });
    });
}

#pragma mark - 滚动手势（滚轮映射）

- (void)scrollAtPoint:(CGPoint)point direction:(int)direction {
    // 用 sendEventStream 实现真正的滑动（swipe）手势
    // 从 point 向 direction 方向滑动一段距离
    CGFloat distance = 100.0;  // 点坐标距离
    CGFloat startY = point.y;
    CGFloat endY = (direction > 0) ? startY - distance : startY + distance;  // 正=向上滑，负=向下滑
    
    CGPoint startPt = CGPointMake(point.x, startY);
    CGPoint endPt = CGPointMake(point.x, endY);
    
    CGPoint pixelStart = [self pointToPixel:startPt];
    CGPoint pixelEnd = [self pointToPixel:endPt];
    
    TVLog(@"[TC] scroll: dir=%d (%.1f,%.1f) -> (%.1f,%.1f) [pixels]", direction, pixelStart.x, pixelStart.y, pixelEnd.x, pixelEnd.y);
    
    // 滑动：began → moved(插值) → ended
    // 先 touchDown 开始
    NSDictionary *beganTouch = @{
        HIDEventTouchIDKey: @(_activeFingerId),
        HIDEventPhaseKey: HIDEventPhaseBegan,
        HIDEventXKey: @(pixelStart.x),
        HIDEventYKey: @(pixelStart.y),
        HIDEventPressureKey: @(0),
        HIDEventMajorRadiusKey: @(5.0),
        HIDEventMinorRadiusKey: @(5.0),
        HIDEventTwistKey: @(0),
        HIDEventMaskKey: @(0)
    };
    
    NSDictionary *movedTouch = @{
        HIDEventTouchIDKey: @(_activeFingerId),
        HIDEventPhaseKey: HIDEventPhaseMoved,
        HIDEventXKey: @(pixelEnd.x),
        HIDEventYKey: @(pixelEnd.y),
        HIDEventPressureKey: @(0),
        HIDEventMajorRadiusKey: @(5.0),
        HIDEventMinorRadiusKey: @(5.0),
        HIDEventTwistKey: @(0),
        HIDEventMaskKey: @(0)
    };
    
    NSDictionary *endedTouch = @{
        HIDEventTouchIDKey: @(_activeFingerId),
        HIDEventPhaseKey: HIDEventPhaseEnded,
        HIDEventXKey: @(pixelEnd.x),
        HIDEventYKey: @(pixelEnd.y),
        HIDEventPressureKey: @(0),
        HIDEventMajorRadiusKey: @(5.0),
        HIDEventMinorRadiusKey: @(5.0),
        HIDEventTwistKey: @(0),
        HIDEventMaskKey: @(0)
    };
    
    // 滑动速度：约 0.15 秒完成滑动（快速滑动更像真实手势）
    NSTimeInterval swipeDuration = 0.15;
    
    NSDictionary *eventInfo = @{
        TopLevelEventInfoKey: @{
            HIDEventInputType: HIDEventInputTypeHand,
            HIDEventTouchesKey: @[endedTouch]
        },
        SecondLevelEventsKey: @[
            @{
                HIDEventInputType: HIDEventInputTypeHand,
                HIDEventTouchesKey: @[beganTouch],
                HIDEventTimeOffsetKey: @(0)
            },
            @{
                HIDEventInputType: HIDEventInputTypeHand,
                HIDEventTouchesKey: @[movedTouch],
                HIDEventTimeOffsetKey: @(swipeDuration),
                HIDEventInterpolateKey: HIDEventInterpolationTypeLinear,
                HIDEventTimestepKey: @(0.016)    // 16ms 每步
            },
            @{
                HIDEventInputType: HIDEventInputTypeHand,
                HIDEventTouchesKey: @[endedTouch],
                HIDEventTimeOffsetKey: @(swipeDuration + 0.016)
            }
        ]
    };
    
    // 确保在主线程执行 UI 操作
    dispatch_async(dispatch_get_main_queue(), ^{
        [[STHIDEventGenerator sharedGenerator] sendEventStream:eventInfo];
    });
}

@end
