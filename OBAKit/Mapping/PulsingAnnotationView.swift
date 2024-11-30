//
//  PulsingAnnotationView.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 12/26/20.
//

import MapKit

typealias PulsingAnnotationWillMoveAnimationBlock = (PulsingAnnotationView?, UIView?) -> Void

/// Swift port of https://github.com/samvermette/SVPulsingAnnotationView
class PulsingAnnotationView: MKAnnotationView {

    /// Default is same as MKUserLocationView
    public var annotationColor = UIColor(red: 0.0, green: 0.478, blue: 1.0, alpha: 1.0) {
        didSet {
            if superview != nil {
                rebuildLayers()
            }
        }
    }

    /// default is white
    var outerColor: UIColor? = .white

    /// default is same as annotationColor
    var pulseColor: UIColor? {
        get {
            _pulseColor ?? annotationColor
        }
        set {
            _pulseColor = newValue
        }
    }
    var _pulseColor: UIColor?

    override var image: UIImage? {
        get { imageView.image }
        set {
            imageView.image = newValue
            if superview != nil {
                rebuildLayers()
            }
        }
    }
    private var _image: UIImage?

    var headingImage: UIImage? {
        didSet {
            headingImageView.image = headingImage
            if superview != nil {
                rebuildLayers()
            }
        }
    }

    lazy var imageView: UIImageView = {
        let imageView = UIImageView(frame: bounds.insetBy(dx: 10.0, dy: 10.0))
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    lazy var headingImageView: UIImageView = {
        let imageView = UIImageView(frame: CGRect(x: 0, y: 0, width: 120, height: 120))
        imageView.contentMode = .center
        return imageView
    }()

    var outerDotAlpha: CGFloat = 1.0

    var pulseScaleFactor: CGFloat = 5.3

    var pulseAnimationDuration: TimeInterval = 1.5 {
        didSet {
            if superview != nil {
                rebuildLayers()
            }
        }
    }

    var outerPulseAnimationDuration: TimeInterval = 3.0

    var delayBetweenPulseCycles: TimeInterval = 0.0 {
        didSet {
            if superview != nil {
                rebuildLayers()
            }
        }
    }

    var willMoveToSuperviewAnimationBlock: PulsingAnnotationWillMoveAnimationBlock? = { (view: PulsingAnnotationView?, _) in
        let bounceAnimation = CAKeyframeAnimation(keyPath: "transform.scale")
        let easeInOut = CAMediaTimingFunction(name: .easeInEaseOut)
        bounceAnimation.values = [0.05, 1.25, 0.8, 1.1, 0.9, 1.0]
        bounceAnimation.duration = 0.3
        bounceAnimation.timingFunctions = [easeInOut, easeInOut, easeInOut, easeInOut, easeInOut, easeInOut]
        view?.layer.add(bounceAnimation, forKey: "popIn")
    }

    private var outerDotLayer: CALayer
    private var colorDotLayer: CALayer
    private var colorHaloLayer: CALayer
    private var pulseAnimationGroup: CAAnimationGroup

    private let defaultAnnotationSize: CGFloat = 22.0

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        let bounds = CGRect(x: 0, y: 0, width: defaultAnnotationSize, height: defaultAnnotationSize)

        outerDotLayer = PulsingAnnotationView.buildOuterDotLayer(bounds: bounds, outerColor: outerColor!, outerDotAlpha: outerDotAlpha)
        colorDotLayer = PulsingAnnotationView.buildColorDotLayer(bounds: bounds, backgroundColor: annotationColor, delayBetweenPulseCycles: 0.0, pulseAnimationDuration: pulseAnimationDuration)
        pulseAnimationGroup = PulsingAnnotationView.buildPulseAnimationGroup(outerPulseAnimationDuration: outerPulseAnimationDuration, delayBetweenPulseCycles: delayBetweenPulseCycles)
        colorHaloLayer = PulsingAnnotationView.buildColorHaloLayer(bounds: bounds, pulseScaleFactor: pulseScaleFactor, pulseColor: annotationColor, delayBetweenPulseCycles: delayBetweenPulseCycles, pulseAnimationGroup: pulseAnimationGroup)

        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)

        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        calloutOffset = CGPoint(x: 0, y: 4)
        self.bounds = bounds
        
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, previousTraitCollection: UITraitCollection) in
            if self.traitCollection.userInterfaceStyle != previousTraitCollection.userInterfaceStyle {
                self.rebuildLayers()
            }
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func rebuildLayers() {
        outerDotLayer.removeFromSuperlayer()
        outerDotLayer = PulsingAnnotationView.buildOuterDotLayer(bounds: bounds, outerColor: outerColor!, outerDotAlpha: outerDotAlpha)

        colorDotLayer.removeFromSuperlayer()
        colorDotLayer = PulsingAnnotationView.buildColorDotLayer(bounds: bounds, backgroundColor: annotationColor, delayBetweenPulseCycles: 0.0, pulseAnimationDuration: pulseAnimationDuration)

        pulseAnimationGroup = PulsingAnnotationView.buildPulseAnimationGroup(outerPulseAnimationDuration: outerPulseAnimationDuration, delayBetweenPulseCycles: delayBetweenPulseCycles)

        colorHaloLayer.removeFromSuperlayer()
        colorHaloLayer = PulsingAnnotationView.buildColorHaloLayer(bounds: bounds, pulseScaleFactor: pulseScaleFactor, pulseColor: pulseColor, delayBetweenPulseCycles: delayBetweenPulseCycles, pulseAnimationGroup: pulseAnimationGroup)

        if image == nil {
            imageView.removeFromSuperview()
        }

        if headingImage != nil {
            addSubview(headingImageView)
            sendSubviewToBack(headingImageView)
            let sz = frame.width
            headingImageView.frame = CGRect(x: -sz, y: -sz, width: 3.0 * sz, height: 3.0 * sz)
        }
        else {
            headingImageView.removeFromSuperview()
        }

        layer.addSublayer(colorHaloLayer)
        layer.addSublayer(outerDotLayer)
        layer.addSublayer(colorDotLayer)

        if image != nil {
            if imageView.superview == nil {
                addSubview(imageView)
            }
            bringSubviewToFront(imageView)
        }
    }

    override func willMove(toSuperview newSuperview: UIView?) {
        if newSuperview != nil {
            rebuildLayers()
        }

        willMoveToSuperviewAnimationBlock?(self, newSuperview)
    }

    func popIn() {
        let bounceAnimation = CAKeyframeAnimation(keyPath: "transform.scale")
        let easeInOut = CAMediaTimingFunction(name: .easeInEaseOut)
        bounceAnimation.values = [0.05, 1.25, 0.8, 1.1, 0.9, 1.0]
        bounceAnimation.duration = 0.3
        bounceAnimation.timingFunctions = [easeInOut, easeInOut, easeInOut, easeInOut, easeInOut, easeInOut]
        layer.add(bounceAnimation, forKey: "popIn")
    }

    // MARK: - Private Helpers

    private static func buildPulseAnimationGroup(outerPulseAnimationDuration: TimeInterval, delayBetweenPulseCycles: TimeInterval) -> CAAnimationGroup {
        let pulseAnimationGroup = CAAnimationGroup()
        pulseAnimationGroup.duration = outerPulseAnimationDuration + delayBetweenPulseCycles
        pulseAnimationGroup.repeatCount = .infinity
        pulseAnimationGroup.isRemovedOnCompletion = false
        pulseAnimationGroup.timingFunction = CAMediaTimingFunction(name: .default)

        var animations = [CAAnimation]()

        let pulseAnimation = CABasicAnimation(keyPath: "transform.scale.xy")
        pulseAnimation.fromValue = 0.0
        pulseAnimation.toValue = 1.0
        pulseAnimation.duration = outerPulseAnimationDuration
        animations.append(pulseAnimation)

        let animation = CAKeyframeAnimation(keyPath: "opacity")
        animation.duration = outerPulseAnimationDuration
        animation.values = [0.45, 0.45, 0.0]
        animation.keyTimes = [0, 0.2, 1.0]
        animation.isRemovedOnCompletion = false
        animations.append(animation)

        pulseAnimationGroup.animations = animations

        return pulseAnimationGroup
    }

    private static func buildColorHaloLayer(bounds: CGRect, pulseScaleFactor: CGFloat, pulseColor: UIColor?, delayBetweenPulseCycles: TimeInterval, pulseAnimationGroup: CAAnimationGroup) -> CALayer {
        let layer = CALayer()
        let width = bounds.width * pulseScaleFactor
        layer.bounds = CGRect(x: 0, y: 0, width: width, height: width)
        layer.position = CGPoint(x: bounds.width / 2.0, y: bounds.height / 2.0)
        layer.contentsScale = UIScreen.main.scale
        layer.backgroundColor = pulseColor?.cgColor ?? nil
        layer.cornerRadius = width / 2.0
        layer.opacity = 0

        if delayBetweenPulseCycles != .infinity {
            layer.add(pulseAnimationGroup, forKey: "pulse")
        }

        return layer
    }

    private static func buildColorDotLayer(bounds: CGRect, backgroundColor: UIColor?, delayBetweenPulseCycles: TimeInterval, pulseAnimationDuration: TimeInterval) -> CALayer {
        let layer = CALayer()
        let width = bounds.width - 6.0
        layer.bounds = CGRect(x: 0, y: 0, width: width, height: width)
        layer.allowsGroupOpacity = true
        layer.backgroundColor = backgroundColor?.cgColor ?? nil
        layer.cornerRadius = width / 2.0
        layer.position = CGPoint(x: bounds.width / 2.0, y: bounds.height / 2.0)

        if delayBetweenPulseCycles != .infinity {
            let defaultCurve = CAMediaTimingFunction(name: CAMediaTimingFunctionName.default)
            let animationGroup = CAAnimationGroup()
            animationGroup.duration = pulseAnimationDuration
            animationGroup.repeatCount = .infinity
            animationGroup.isRemovedOnCompletion = false
            animationGroup.autoreverses = true
            animationGroup.timingFunction = defaultCurve
            animationGroup.speed = 1.0
            animationGroup.fillMode = .both

            let pulseAnimation = CABasicAnimation(keyPath: "transform.scale.xy")
            pulseAnimation.fromValue = 0.8
            pulseAnimation.toValue = 1.0
            pulseAnimation.duration = pulseAnimationDuration

            let opacityAnimation = CABasicAnimation(keyPath: "opacity")
            opacityAnimation.fromValue = 0.8
            opacityAnimation.toValue = 1.0
            opacityAnimation.duration = pulseAnimationDuration

            animationGroup.animations = [pulseAnimation, opacityAnimation]
            layer.add(animationGroup, forKey: "pulse")
        }

        return layer
    }

    private static func buildOuterDotLayer(bounds: CGRect, outerColor: UIColor, outerDotAlpha: CGFloat) -> CALayer {
        let layer = CALayer()
        layer.bounds = bounds
        layer.contents = buildCircleImage(color: outerColor, height: bounds.height).cgImage
        layer.position = CGPoint(x: bounds.width / 2.0, y: bounds.height / 2.0)
        layer.contentsGravity = .center
        layer.contentsScale = UIScreen.main.scale
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 2)
        layer.shadowRadius = 3.0
        layer.shadowOpacity = 0.3
        layer.opacity = Float(outerDotAlpha)

        return layer
    }

    private static func buildCircleImage(color: UIColor, height: CGFloat) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(CGSize(width: height, height: height), false, 0)
        let fillPath = UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: height, height: height))
        color.setFill()
        fillPath.fill()
        let dotImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return dotImage!
    }
}
