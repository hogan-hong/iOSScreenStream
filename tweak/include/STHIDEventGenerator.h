/*
 * STHIDEventGenerator.h
 *
 * 重要：此文件需从 TrollVNC 复制：
 * src/STHIDEventGenerator.h
 *
 * 这是 TrollVNC 的触摸事件注入实现。
 * 编译前请复制到此位置。
 *
 * 如果没有 TrollVNC 的完整头文件，此处提供最小兼容定义。
 */

#import <CoreGraphics/CGGeometry.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - sendEventStream 字典 Key（与 TrollVNC STHIDEventGenerator.h 一致）

static NSString *const TopLevelEventInfoKey = @"eventInfo";
static NSString *const SecondLevelEventsKey = @"events";
static NSString *const HIDEventInputType = @"inputType";
static NSString *const HIDEventTimeOffsetKey = @"timeOffset";
static NSString *const HIDEventTouchesKey = @"touches";
static NSString *const HIDEventPhaseKey = @"phase";
static NSString *const HIDEventInterpolateKey = @"interpolate";
static NSString *const HIDEventTimestepKey = @"timestep";
static NSString *const HIDEventCoordinateSpaceKey = @"coordinateSpace";
static NSString *const HIDEventStartEventKey = @"startEvent";
static NSString *const HIDEventEndEventKey = @"endEvent";
static NSString *const HIDEventTouchIDKey = @"id";
static NSString *const HIDEventPressureKey = @"pressure";
static NSString *const HIDEventXKey = @"x";
static NSString *const HIDEventYKey = @"y";
static NSString *const HIDEventTwistKey = @"twist";
static NSString *const HIDEventMaskKey = @"mask";
static NSString *const HIDEventMajorRadiusKey = @"majorRadius";
static NSString *const HIDEventMinorRadiusKey = @"minorRadius";
static NSString *const HIDEventFingerKey = @"finger";

// HIDEventInputType 值
static NSString *const HIDEventInputTypeHand = @"hand";
static NSString *const HIDEventInputTypeFinger = @"finger";
static NSString *const HIDEventInputTypeStylus = @"stylus";

// HIDEventCoordinateSpaceKey 值
static NSString *const HIDEventCoordinateSpaceTypeGlobal = @"global";
static NSString *const HIDEventCoordinateSpaceTypeContent = @"content";

static NSString *const HIDEventInterpolationTypeLinear = @"linear";
static NSString *const HIDEventInterpolationTypeSimpleCurve = @"simpleCurve";

// HIDEventPhaseKey 值
static NSString *const HIDEventPhaseBegan = @"began";
static NSString *const HIDEventPhaseStationary = @"stationary";
static NSString *const HIDEventPhaseMoved = @"moved";
static NSString *const HIDEventPhaseEnded = @"ended";
static NSString *const HIDEventPhaseCanceled = @"canceled";

// 最大触摸点数
static NSUInteger const HIDMaxTouchCount = 30;

#pragma mark - STHIDEventGenerator 接口

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
