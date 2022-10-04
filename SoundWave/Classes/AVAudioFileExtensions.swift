//
//  AVAudioFileExtensions.swift
//  Pods-SoundWave_Example
//
//  Created by Bastien Falcou on 4/21/19.
//  Inspired from https://stackoverflow.com/a/52280271
//

import AVFoundation

extension AVAudioFile {
	func buffer() throws -> [[Float]] {
		let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
								   sampleRate: self.fileFormat.sampleRate,
								   channels: self.fileFormat.channelCount,
								   interleaved: false)
		let buffer = AVAudioPCMBuffer(pcmFormat: format!, frameCapacity: UInt32(self.length))!
		try self.read(into: buffer, frameCount: UInt32(self.length))
		return self.analyze(buffer: buffer)
	}

	private func analyze(buffer: AVAudioPCMBuffer) -> [[Float]] {
		let channelCount = Int(buffer.format.channelCount)
		let frameLength = Int(buffer.frameLength)
		var result = Array(repeating: [Float](repeatElement(0, count: frameLength)), count: channelCount)
		for channel in 0..<channelCount {
			for sampleIndex in 0..<frameLength {
				let sqrtV = sqrt(buffer.floatChannelData![channel][sampleIndex*buffer.stride]/Float(buffer.frameLength))
				let dbPower = 20 * log10(sqrtV)
				result[channel][sampleIndex] = dbPower
			}
		}
		print(result)
		return result
	}
}

extension UIImage {
    class func circleImageWithColor(color: UIColor, size: CGSize) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        context.setFillColor(color.cgColor)
        let radius: CGFloat = size.width*0.5
        let maskPath = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size),
                                    byRoundingCorners: .allCorners,
                                    cornerRadii: CGSize(width: radius, height: radius)
        )
        maskPath.addClip()
        maskPath.fill()

        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return image
    }
}
