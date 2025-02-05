//
//  AudioVisualizationView.swift
//  Pods
//
//  Created by Bastien Falcou on 12/6/16.
//

import AVFoundation
import UIKit

public protocol AudioVisualizationViewDelegate: AnyObject {
    func progressDotWillBeginDragging(_ visualizationView: AudioVisualizationView)
    func progressDotDragging(_ visualizationView: AudioVisualizationView, currentProgress: Float)
    func progressDotDidEndDragging(_ visualizationView: AudioVisualizationView, currentProgress: Float, shouldResume: Bool)
}

public class AudioVisualizationView: BaseNibView {
    public enum AudioVisualizationMode {
        case read
        case write
    }

    private enum LevelBarType {
        case upper
        case lower
        case single
    }

    @IBInspectable public var meteringLevelBarWidth: CGFloat = 3.0 {
        didSet {
            self.setNeedsDisplay()
        }
    }
    @IBInspectable public var meteringLevelBarInterItem: CGFloat = 2.0 {
        didSet {
            self.setNeedsDisplay()
        }
    }
    @IBInspectable public var meteringLevelBarCornerRadius: CGFloat = 2.0 {
        didSet {
            self.setNeedsDisplay()
        }
    }
    @IBInspectable public var meteringLevelBarSingleStick: Bool = false {
        didSet {
            self.setNeedsDisplay()
        }
    }
    
    public var controlActionEnabled: Bool = false
    public var progressDotColor: UIColor = .orange
    public var progressDotSize: CGSize = CGSize(width: 10.0, height: 10.0)
    public var audioVisualizationMode: AudioVisualizationMode = .read

    public var audioVisualizationTimeInterval: TimeInterval = 0.05 // Time interval between each metering bar representation

    public weak var delegate: AudioVisualizationViewDelegate?
    
    // Specify a `gradientPercentage` to have the width of gradient be that percentage of the view width (starting from left)
    // The rest of the screen will be filled by `self.gradientStartColor` to display nicely.
    // Do not specify any `gradientPercentage` for gradient calculating fitting size automatically.
    public var currentGradientPercentage: Float?

    private var meteringLevelsArray: [Float] = []    // Mutating recording array (values are percentage: 0.0 to 1.0)
    private var meteringLevelsClusteredArray: [Float] = [] // Generated read mode array (values are percentage: 0.0 to 1.0)

    private var currentMeteringLevelsArray: [Float] {
        if !self.meteringLevelsClusteredArray.isEmpty {
            return meteringLevelsClusteredArray
        }
        return meteringLevelsArray
    }
    private var needSwapColor: Bool = true
    private var playChronometer: Chronometer?
    private var timeDuration: TimeInterval = 0.0
    private var slider: UISlider!
    private var shouldResume: Bool = false
    private var currentProgress: Float?
    public var meteringLevels: [Float]? {
        didSet {
            if let meteringLevels = self.meteringLevels {
                self.meteringLevelsClusteredArray = meteringLevels
                self.currentGradientPercentage = 0.0
            }
        }
    }

    static var audioVisualizationDefaultGradientStartColor: UIColor {
        return UIColor(red: 61.0 / 255.0, green: 20.0 / 255.0, blue: 117.0 / 255.0, alpha: 1.0)
    }
    static var audioVisualizationDefaultGradientEndColor: UIColor {
        return UIColor(red: 166.0 / 255.0, green: 150.0 / 255.0, blue: 225.0 / 255.0, alpha: 1.0)
    }

    @IBInspectable public var gradientStartColor: UIColor = AudioVisualizationView.audioVisualizationDefaultGradientStartColor {
        didSet {
            self.setNeedsDisplay()
        }
    }
    @IBInspectable public var gradientEndColor: UIColor = AudioVisualizationView.audioVisualizationDefaultGradientEndColor {
        didSet {
            self.setNeedsDisplay()
        }
    }

    override public init(frame: CGRect) {
        super.init(frame: frame)
        createAudioSlider()
    }

    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        createAudioSlider()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        let selfBounds = self.bounds
        self.slider.frame = CGRect(
            x: -progressDotSize.width*0.5,
            y: (selfBounds.height - progressDotSize.height)*0.5,
            width: selfBounds.width + progressDotSize.width,
            height: progressDotSize.height
        )
    }
    
    override public func draw(_ rect: CGRect) {
        super.draw(rect)

        if let context = UIGraphicsGetCurrentContext() {
            self.drawLevelBarsMaskAndGradient(inContext: context)
        }
    }

    public func reset() {
        self.meteringLevels = nil
        self.currentGradientPercentage = nil
        self.meteringLevelsClusteredArray.removeAll()
        self.meteringLevelsArray.removeAll()
        self.shouldResume = false
        self.timeDuration = 0.0
        self.currentProgress = nil
        self.slider.isHidden = true
        if !needSwapColor {
            self.swapColor()
            self.needSwapColor = true
        }
        self.setNeedsDisplay()
    }

    // MARK: - Record Mode Handling

    public func add(meteringLevel: Float) {
        guard self.audioVisualizationMode == .write else {
            print("AudioVisualizationView: trying to populate audio visualization view in read mode")
            return
        }

        self.meteringLevelsArray.append(meteringLevel)
        self.setNeedsDisplay()
    }

    public func getScaleSoundDataToFitScreen() -> [Float] {
        if self.meteringLevelsArray.isEmpty {
            return []
        }

        var result: [Float] = []
        var lastPosition: Int = 0

        for index in 0..<self.maximumNumberBars {
            let position: Float = Float(index) / Float(self.maximumNumberBars) * Float(self.meteringLevelsArray.count)
            var h: Float = 0.0

            if self.maximumNumberBars > self.meteringLevelsArray.count && floor(position) != position {
                let low: Int = Int(floor(position))
                let high: Int = Int(ceil(position))

                if high < self.meteringLevelsArray.count {
                    h = self.meteringLevelsArray[low] + ((position - Float(low)) * (self.meteringLevelsArray[high] - self.meteringLevelsArray[low]))
                } else {
                    h = self.meteringLevelsArray[low]
                }
            } else {
                for nestedIndex in lastPosition...Int(position) {
                    h += self.meteringLevelsArray[nestedIndex]
                }
                let stepsNumber = Int(1 + position - Float(lastPosition))
                h = h / Float(stepsNumber)
            }

            lastPosition = Int(position)
            result.append(h)
        }
        return result
    }

    public func scaleSoundDataToFitScreen() {
        if self.meteringLevelsArray.isEmpty {
            return
        }
        self.meteringLevelsClusteredArray.removeAll()
        self.meteringLevelsClusteredArray.append(contentsOf: getScaleSoundDataToFitScreen())
        if controlActionEnabled {
            self.slider.isHidden = false
        }
        self.setNeedsDisplay()
    }

    public func setMeteringLevelsAndRefreshDisplay(_ meteringLevels: [Float]) {
        self.meteringLevels = meteringLevels
        self.meteringLevelsClusteredArray = meteringLevels
        self.currentGradientPercentage = 0.0
        if controlActionEnabled {
            self.slider.isHidden = false
        }
        self.swapColor()
        self.needSwapColor = false
        self.setNeedsDisplay()
    }

    // PRAGMA: - Play Mode Handling

    public func play(for duration: TimeInterval) {
        guard self.audioVisualizationMode == .read else {
            print("AudioVisualizationView: trying to read audio visualization in write mode")
            return
        }

        guard self.meteringLevels != nil else {
            print("AudioVisualizationView: trying to read audio visualization of non initialized sound record")
            return
        }
        if needSwapColor {
            swapColor()
            needSwapColor = false
        }

        if let currentChronometer = self.playChronometer {
            if let percentage = self.currentProgress {
                currentChronometer.timerCurrentValue = Double(percentage)*timeDuration
                self.currentProgress = nil
            }
            currentChronometer.start() // resume current
            return
        }
        self.timeDuration = duration
        self.playChronometer = Chronometer(withTimeInterval: self.audioVisualizationTimeInterval)
        if let percentage = self.currentProgress {
            self.playChronometer?.timerCurrentValue = Double(percentage)*timeDuration
            self.currentProgress = nil
        }
        self.playChronometer?.start(shouldFire: false)

        self.playChronometer?.timerDidUpdate = { [weak self] timerDuration in
            guard let this = self else {
                return
            }

            if timerDuration >= duration {
                this.stop()
                return
            }
            let currentProgress = Float(timerDuration) / Float(duration)
            this.currentGradientPercentage = currentProgress
            this.slider.value = currentProgress
            this.setNeedsDisplay()
        }
    }

    public func pause() {
        guard let chronometer = self.playChronometer, chronometer.isPlaying else {
            print("AudioVisualizationView: trying to pause audio visualization view when not playing")
            return
        }
        self.playChronometer?.pause()
    }

    public func stop() {
        self.playChronometer?.stop()
        self.playChronometer = nil
        self.timeDuration = 0.0
        self.shouldResume = false
        self.slider.value = 0.0
        self.currentProgress = nil
        self.currentGradientPercentage = 0.0
        self.setNeedsDisplay()
        if audioVisualizationMode == .write {
            self.currentGradientPercentage = nil
        }
    }
    
    // MARK: - Slider Bar
    private func createAudioSlider() {
        let selfBounds = self.bounds
        let frame = CGRect(
            x: -progressDotSize.width*0.5,
            y: (selfBounds.height - progressDotSize.height)*0.5,
            width: selfBounds.width + progressDotSize.width,
            height: progressDotSize.height
        )
        let slider = UISlider(frame: frame)
        slider.isHidden = true
        slider.minimumTrackTintColor = .clear
        slider.maximumTrackTintColor = .clear
        slider.tintColor = .clear
        slider.thumbTintColor = .orange
        slider.isUserInteractionEnabled = true
        slider.translatesAutoresizingMaskIntoConstraints = false
        let image = UIImage.circleImageWithColor(color: progressDotColor, size: progressDotSize)
        slider.setThumbImage(image, for: .normal)
        slider.setThumbImage(image, for: .highlighted)
        
        slider.addTarget(self, action: #selector(sliderValueDidChange(sender:event:)), for: .valueChanged)
        
        self.addSubview(slider)
        self.bringSubviewToFront(slider)

        slider.centerYAnchor.constraint(equalTo: self.centerYAnchor).isActive = true
        slider.leftAnchor.constraint(equalTo: self.leftAnchor).isActive = true
        slider.rightAnchor.constraint(equalTo: self.rightAnchor).isActive = true
        slider.layoutIfNeeded()
        self.slider = slider
    }
    
    @objc
    private func sliderValueDidChange(sender: UISlider, event: UIEvent) {
        let value = sender.value
        if let touchEvent = event.allTouches?.first {
            switch touchEvent.phase {
            case .began:
                if let chronometer = self.playChronometer, chronometer.isPlaying {
                    chronometer.pause()
                    self.shouldResume = true
                }
                self.delegate?.progressDotWillBeginDragging(self)
            case .moved:
                self.currentGradientPercentage = value
                self.setNeedsDisplay()
                self.delegate?.progressDotDragging(self, currentProgress: value)
            case .ended:
                if let chronometer = self.playChronometer {
                    chronometer.timerCurrentValue = TimeInterval(value*Float(timeDuration))
                    self.delegate?.progressDotDidEndDragging(self, currentProgress: value, shouldResume: shouldResume)
                    if shouldResume {
                        chronometer.start()
                        self.shouldResume = false
                    }
                } else {
                    self.currentProgress = value
                    self.delegate?.progressDotDidEndDragging(self, currentProgress: value, shouldResume: false)
                }
            default:
                break
            }
        }
    }

    // MARK: - Mask + Gradient

    private func swapColor() {
        let currentStartColor = gradientStartColor
        self.gradientStartColor = gradientEndColor
        self.gradientEndColor = currentStartColor
    }
    
    private func drawLevelBarsMaskAndGradient(inContext context: CGContext) {
        if self.currentMeteringLevelsArray.isEmpty {
            return
        }

        context.saveGState()

        UIGraphicsBeginImageContextWithOptions(self.frame.size, false, 0.0)

        let maskContext = UIGraphicsGetCurrentContext()
        UIColor.black.set()

        self.drawMeteringLevelBars(inContext: maskContext!)

        let mask = UIGraphicsGetCurrentContext()?.makeImage()
        UIGraphicsEndImageContext()

        context.clip(to: self.bounds, mask: mask!)

        self.drawGradient(inContext: context)

        context.restoreGState()
    }

    private func drawGradient(inContext context: CGContext) {
        if self.currentMeteringLevelsArray.isEmpty {
            return
        }

        context.saveGState()

        let startPoint = CGPoint(x: 0.0, y: self.centerY)
        var endPoint = CGPoint(x: self.xLeftMostBar() + self.meteringLevelBarWidth, y: self.centerY)

        if let gradientPercentage = self.currentGradientPercentage {
            endPoint = CGPoint(x: self.frame.size.width * CGFloat(gradientPercentage), y: self.centerY)
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let colorLocations: [CGFloat] = [0.0, 1.0]
        let colors = [self.gradientStartColor.cgColor, self.gradientStartColor.cgColor]

        let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: colorLocations)

        context.drawLinearGradient(gradient!, start: startPoint, end: endPoint, options: CGGradientDrawingOptions(rawValue: 0))

        context.restoreGState()

        if self.currentGradientPercentage != nil {
            self.drawPlainBackground(inContext: context, fillFromXCoordinate: endPoint.x)
        }
    }

    private func drawPlainBackground(inContext context: CGContext, fillFromXCoordinate xCoordinate: CGFloat) {
        context.saveGState()

        let squarePath = UIBezierPath()

        squarePath.move(to: CGPoint(x: xCoordinate, y: 0.0))
        squarePath.addLine(to: CGPoint(x: self.frame.size.width, y: 0.0))
        squarePath.addLine(to: CGPoint(x: self.frame.size.width, y: self.frame.size.height))
        squarePath.addLine(to: CGPoint(x: xCoordinate, y: self.frame.size.height))

        squarePath.close()
        squarePath.addClip()

        self.gradientEndColor.setFill()
        squarePath.fill()

        context.restoreGState()
    }

    // MARK: - Bars

    private func drawMeteringLevelBars(inContext context: CGContext) {
        let offset = max(self.currentMeteringLevelsArray.count - self.maximumNumberBars, 0)

        for index in offset..<self.currentMeteringLevelsArray.count {
            if self.meteringLevelBarSingleStick {
                self.drawBar(index - offset, meteringLevelIndex: index, levelBarType: .single, context: context)
            } else {
                self.drawBar(index - offset, meteringLevelIndex: index, levelBarType: .upper, context: context)
                self.drawBar(index - offset, meteringLevelIndex: index, levelBarType: .lower, context: context)
            }
        }
    }

    private func drawBar(_ barIndex: Int, meteringLevelIndex: Int, levelBarType: LevelBarType, context: CGContext) {
        context.saveGState()

        var barRect: CGRect

        let xPointForMeteringLevel = self.xPointForMeteringLevel(barIndex)
        let heightForMeteringLevel = self.heightForMeteringLevel(self.currentMeteringLevelsArray[meteringLevelIndex])

        switch levelBarType {
        case .upper:
            barRect = CGRect(x: xPointForMeteringLevel,
                             y: self.centerY - heightForMeteringLevel,
                             width: self.meteringLevelBarWidth,
                             height: heightForMeteringLevel)
        case .lower:
            barRect = CGRect(x: xPointForMeteringLevel,
                             y: self.centerY,
                             width: self.meteringLevelBarWidth,
                             height: heightForMeteringLevel)
        case .single:
            barRect = CGRect(x: xPointForMeteringLevel,
                             y: self.centerY - heightForMeteringLevel,
                             width: self.meteringLevelBarWidth,
                             height: heightForMeteringLevel * 2)
        }

        let barPath: UIBezierPath = UIBezierPath(roundedRect: barRect, cornerRadius: self.meteringLevelBarCornerRadius)

        UIColor.black.set()
        barPath.fill()

        context.restoreGState()
    }

    // MARK: - Points Helpers

    private var centerY: CGFloat {
        return self.frame.size.height / 2.0
    }

    private var maximumBarHeight: CGFloat {
        return self.frame.size.height
    }

    private var maximumNumberBars: Int {
        return Int(self.frame.size.width / (self.meteringLevelBarWidth + self.meteringLevelBarInterItem))
    }

    private func xLeftMostBar() -> CGFloat {
        return self.xPointForMeteringLevel(min(self.maximumNumberBars - 1, self.currentMeteringLevelsArray.count - 1))
    }

    private func heightForMeteringLevel(_ meteringLevel: Float) -> CGFloat {
        return CGFloat(meteringLevel) * self.maximumBarHeight
    }

    private func xPointForMeteringLevel(_ atIndex: Int) -> CGFloat {
        return CGFloat(atIndex) * (self.meteringLevelBarWidth + self.meteringLevelBarInterItem)
    }
}
