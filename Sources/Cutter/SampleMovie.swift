#if DEBUG
import AVFoundation
import AppKit

/// Writes a short made-up movie, for tests and for the off-screen drawing of the panel:
/// a stand-in for a screen recording that involves no real one.
enum SampleMovie {
    enum Failure: Error {
        case couldNotWrite
    }

    static func write(to url: URL, width: Int = 640, height: Int = 400, hue: CGFloat = 0.6, frames: Int = 6) throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(input)
        guard writer.startWriting() else {
            throw writer.error ?? Failure.couldNotWrite
        }
        writer.startSession(atSourceTime: .zero)

        for frame in 0..<frames {
            let deadline = Date().addingTimeInterval(5)
            while !input.isReadyForMoreMediaData {
                guard Date() < deadline else {
                    throw Failure.couldNotWrite
                }
                Thread.sleep(forTimeInterval: 0.01)
            }
            guard let pool = adaptor.pixelBufferPool else {
                throw Failure.couldNotWrite
            }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else {
                throw Failure.couldNotWrite
            }
            draw(into: buffer, width: width, height: height, hue: hue)
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 6)) else {
                throw writer.error ?? Failure.couldNotWrite
            }
        }
        input.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        guard done.wait(timeout: .now() + 10) == .success, writer.status == .completed else {
            throw writer.error ?? Failure.couldNotWrite
        }
    }

    /// A coloured desktop with a white window on it.
    private static func draw(into buffer: CVPixelBuffer, width: Int, height: Int, hue: CGFloat) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else {
            return
        }
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        context.setFillColor(NSColor(hue: hue, saturation: 0.6, brightness: 0.7, alpha: 1).cgColor)
        context.fill(bounds)
        let window = bounds.insetBy(dx: bounds.width * 0.16, dy: bounds.height * 0.16)
        context.setFillColor(NSColor(white: 0.98, alpha: 1).cgColor)
        context.addPath(CGPath(roundedRect: window, cornerWidth: 12, cornerHeight: 12, transform: nil))
        context.fillPath()
        context.setFillColor(NSColor(white: 0.8, alpha: 1).cgColor)
        for line in 0..<6 {
            context.fill(CGRect(x: window.minX + 24, y: window.maxY - 50 - CGFloat(line) * 26, width: window.width * (line == 3 ? 0.4 : 0.8), height: 10))
        }
    }
}
#endif
