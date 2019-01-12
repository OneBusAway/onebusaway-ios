//
//  SVPulsingAnnotationView.h
//
//  Created by Sam Vermette on 01.03.13.
//  https://github.com/samvermette/SVPulsingAnnotationView
//

@import MapKit;

NS_ASSUME_NONNULL_BEGIN

NS_SWIFT_NAME(PulsingAnnotationView)
@interface SVPulsingAnnotationView : MKAnnotationView

@property(nonatomic, copy) UIColor *annotationColor; // default is same as MKUserLocationView
@property(nonatomic, copy) UIColor *outerColor; // default is white
@property(nonatomic, copy) UIColor *pulseColor; // default is same as annotationColor
@property(nonatomic, strong, nullable) UIImage *image; // default is nil
@property(nonatomic, strong, nullable) UIImage *headingImage; // default is nil
@property(nonatomic, strong) UIImageView *imageView;
@property(nonatomic, strong, readonly) UIImageView *headingImageView;

@property(nonatomic, readwrite) CGFloat outerDotAlpha; // default is 1
@property(nonatomic, readwrite) CGFloat pulseScaleFactor; // default is 5.3
@property(nonatomic, readwrite) NSTimeInterval pulseAnimationDuration; // default is 1s
@property(nonatomic, readwrite) NSTimeInterval outerPulseAnimationDuration; // default is 3s
@property(nonatomic, readwrite) NSTimeInterval delayBetweenPulseCycles; // default is 1s

@property(nonatomic, copy) void (^willMoveToSuperviewAnimationBlock)(SVPulsingAnnotationView *view, UIView *superview); // default is pop animation

- (instancetype)initWithAnnotation:(id<MKAnnotation>)annotation reuseIdentifier:(NSString *)reuseIdentifier size:(CGSize)size;
@end

NS_ASSUME_NONNULL_END
