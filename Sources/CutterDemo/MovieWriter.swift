import AVFoundation
import CoreGraphics

/// Writes frames to an H.264 movie in an MP4 file.
final class MovieWriter {
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let width: Int
    private let height: Int
    private let framesPerSecond: Int32
    private var frameCount: Int64 = 0

    enum Failure: Error {
        case cannotStart(Error?)
        case cannotAppend(Error?)
        case cannotFinish(Error?)
    }

    init(url: URL, width: Int, height: Int, framesPerSecond: Int32) throws {
        self.width = width
        self.height = height
        self.framesPerSecond = framesPerSecond

        try? FileManager.default.removeItem(at: url)
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 5_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoExpectedSourceFrameRateKey: framesPerSecond,
            ],
        ])
        input.expectsMediaDataInRealTime = false
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(input)
        guard writer.startWriting() else {
            throw Failure.cannotStart(writer.error)
        }
        writer.startSession(atSourceTime: .zero)
    }

    func append(_ image: CGImage) throws {
        while !input.isReadyForMoreMediaData {
            Thread.sleep(forTimeInterval: 0.005)
        }
        guard let pool = adaptor.pixelBufferPool else {
            throw Failure.cannotAppend(writer.error)
        }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        guard let buffer else {
            throw Failure.cannotAppend(nil)
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )
        context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        CVPixelBufferUnlockBaseAddress(buffer, [])

        let time = CMTime(value: frameCount, timescale: framesPerSecond)
        guard adaptor.append(buffer, withPresentationTime: time) else {
            throw Failure.cannotAppend(writer.error)
        }
        frameCount += 1
    }

    func finish() throws {
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(value: frameCount, timescale: framesPerSecond))
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting {
            done.signal()
        }
        done.wait()
        guard writer.status == .completed else {
            throw Failure.cannotFinish(writer.error)
        }
    }
}
