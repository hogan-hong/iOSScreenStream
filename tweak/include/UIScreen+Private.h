/*
 * UIScreen+Private.h - Private UIScreen API
 */

#import <UIKit/UIKit.h>

@interface UIScreen (Private)
- (CGRect)_unjailedReferenceBoundsInPixels;
@end
