/*
 * iOSScreenStream - Touch controller using STHIDEventGenerator
 * Based on TrollVNC's touch injection implementation
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
    // STHIDEventGenerator doesn't have a direct move method
    // We use the event stream approach
    NSDictionary *eventInfo = @{
        @"eventInfo": @{
            @"events": @[
                @{
                    @"inputType": @"finger",
                    @"phase": @"moved",
                    @"x": @(point.x),
                    @"y": @(point.y),
                    @"interpolate": @NO
                }
            ]
        }
    };
    [[STHIDEventGenerator sharedGenerator] sendEventStream:eventInfo];
}

- (void)tapAtPoint:(CGPoint)point {
    [[STHIDEventGenerator sharedGenerator] tap:point];
}

@end
