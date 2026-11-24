import Foundation

/// Writes an animated GIF that loops forever.
///
/// ImageIO can write GIFs too, but it stores every frame whole and picks colours frame by
/// frame. This encoder uses one palette for the whole clip, so still areas do not shimmer,
/// and stores for each frame only the rectangle that changed, with unchanged pixels inside
/// it left transparent. Frames that do not change at all extend the frame before them.
/// For a clip that mostly holds still, that makes the file several times smaller.
struct GIFEncoder {
    /// Up to 255 colours. Index 255 is kept for "same as the frame before".
    let palette: [RGB]
    let width: Int
    let height: Int

    private var output = Data()
    /// What a viewer has on screen after the frames written so far.
    private var canvas: [UInt8]?
    /// The latest frame, not written yet because the next one may only extend it.
    private var pending: (pixels: [UInt8], hundredths: Int)?

    private static let transparent: UInt8 = 255

    init(width: Int, height: Int, palette: [RGB]) {
        precondition(palette.count <= 255, "index 255 is reserved")
        self.width = width
        self.height = height
        self.palette = palette

        output.append(contentsOf: Array("GIF89a".utf8))
        appendShort(width)
        appendShort(height)
        // A global colour table of 256 entries, 8 bits per channel.
        output.append(contentsOf: [0xF7, 0, 0])
        for index in 0..<256 {
            let color = index < palette.count ? palette[index] : RGB(red: 0, green: 0, blue: 0)
            output.append(contentsOf: [color.red, color.green, color.blue])
        }
        // The Netscape extension: repeat without end.
        output.append(contentsOf: [0x21, 0xFF, 0x0B])
        output.append(contentsOf: Array("NETSCAPE2.0".utf8))
        output.append(contentsOf: [0x03, 0x01, 0x00, 0x00, 0x00])
    }

    /// Adds a frame of palette indices, one per pixel, row by row from the top.
    mutating func add(_ pixels: [UInt8], hundredths: Int) {
        precondition(pixels.count == width * height)
        if let current = pending {
            if current.pixels == pixels {
                pending?.hundredths += hundredths
                return
            }
            write(current.pixels, hundredths: current.hundredths)
        }
        pending = (pixels, hundredths)
    }

    mutating func finish() -> Data {
        if let current = pending {
            write(current.pixels, hundredths: current.hundredths)
            pending = nil
        }
        output.append(0x3B)
        return output
    }

    private mutating func write(_ pixels: [UInt8], hundredths: Int) {
        var region = (x: 0, y: 0, width: width, height: height)
        var data = pixels
        var usesTransparency = false

        if let canvas {
            // The smallest rectangle holding every changed pixel.
            var minX = width, minY = height, maxX = -1, maxY = -1
            for y in 0..<height {
                let row = y * width
                for x in 0..<width where pixels[row + x] != canvas[row + x] {
                    minX = min(minX, x)
                    maxX = max(maxX, x)
                    minY = min(minY, y)
                    maxY = max(maxY, y)
                }
            }
            guard maxX >= 0 else {
                return
            }
            region = (minX, minY, maxX - minX + 1, maxY - minY + 1)
            data = []
            data.reserveCapacity(region.width * region.height)
            for y in minY...maxY {
                let row = y * width
                for x in minX...maxX {
                    let pixel = pixels[row + x]
                    data.append(pixel == canvas[row + x] ? Self.transparent : pixel)
                }
            }
            usesTransparency = true
        }
        canvas = pixels

        // Graphic control: leave the frame in place afterwards, delay, transparent index.
        output.append(contentsOf: [0x21, 0xF9, 0x04, usesTransparency ? 0x05 : 0x04])
        appendShort(hundredths)
        output.append(contentsOf: [Self.transparent, 0x00])

        output.append(0x2C)
        appendShort(region.x)
        appendShort(region.y)
        appendShort(region.width)
        appendShort(region.height)
        output.append(0x00)

        output.append(8)
        let compressed = Self.compress(data)
        var offset = 0
        while offset < compressed.count {
            let count = min(255, compressed.count - offset)
            output.append(UInt8(count))
            output.append(contentsOf: compressed[offset..<offset + count])
            offset += count
        }
        output.append(0x00)
    }

    private mutating func appendShort(_ value: Int) {
        output.append(UInt8(value & 0xFF))
        output.append(UInt8((value >> 8) & 0xFF))
    }

    /// GIF's LZW with 8-bit symbols and codes of 9 to 12 bits.
    private static func compress(_ pixels: [UInt8]) -> [UInt8] {
        let clearCode = 256
        let endCode = 257
        var table: [Int: Int] = [:]
        table.reserveCapacity(4096)
        var nextCode = 258
        var codeSize = 9

        var bytes: [UInt8] = []
        bytes.reserveCapacity(pixels.count / 2)
        var bitBuffer = 0
        var bitCount = 0
        func emit(_ code: Int) {
            bitBuffer |= code << bitCount
            bitCount += codeSize
            while bitCount >= 8 {
                bytes.append(UInt8(bitBuffer & 0xFF))
                bitBuffer >>= 8
                bitCount -= 8
            }
        }

        emit(clearCode)
        guard var prefix = pixels.first.map(Int.init) else {
            emit(endCode)
            if bitCount > 0 {
                bytes.append(UInt8(bitBuffer & 0xFF))
            }
            return bytes
        }
        for pixel in pixels.dropFirst() {
            let key = prefix << 8 | Int(pixel)
            if let code = table[key] {
                prefix = code
                continue
            }
            emit(prefix)
            if nextCode < 4096 {
                // A decoder widens its codes once the table outgrows the current width.
                if nextCode == 1 << codeSize {
                    codeSize += 1
                }
                table[key] = nextCode
                nextCode += 1
            } else {
                emit(clearCode)
                table.removeAll(keepingCapacity: true)
                nextCode = 258
                codeSize = 9
            }
            prefix = Int(pixel)
        }
        emit(prefix)
        emit(endCode)
        if bitCount > 0 {
            bytes.append(UInt8(bitBuffer & 0xFF))
        }
        return bytes
    }
}

struct RGB: Hashable {
    var red: UInt8
    var green: UInt8
    var blue: UInt8
}

/// Picks the clip's palette and maps every pixel to it.
struct ColorQuantizer {
    let palette: [RGB]
    /// Palette entries by their exact colour.
    private let exact: [RGB: UInt8]
    /// The nearest palette entry for every 18-bit colour, filled in as colours turn up.
    private var nearest = [Int16](repeating: -1, count: 1 << 18)

    /// `fixed` colours go into the palette as they are. The rest of the palette is a
    /// median cut over the other colours of some sample frames. Each frame is RGBX bytes.
    init(samples: [[UInt8]], colorCount: Int, fixed: [RGB] = []) {
        let fixedColors = Set(fixed)
        struct Bin {
            var count = 0
            var red = 0
            var green = 0
            var blue = 0
        }
        var bins = [Bin](repeating: Bin(), count: 1 << 15)
        for sample in samples {
            var offset = 0
            while offset < sample.count {
                if fixedColors.contains(RGB(red: sample[offset], green: sample[offset + 1], blue: sample[offset + 2])) {
                    offset += 4
                    continue
                }
                let index = Self.bin(sample[offset], sample[offset + 1], sample[offset + 2])
                bins[index].count += 1
                bins[index].red += Int(sample[offset])
                bins[index].green += Int(sample[offset + 1])
                bins[index].blue += Int(sample[offset + 2])
                offset += 4
            }
        }

        struct Entry {
            var color: RGB
            var count: Int
        }
        var boxes: [[Entry]] = [bins.filter { $0.count > 0 }.map { bin in
            Entry(
                color: RGB(red: UInt8(bin.red / bin.count), green: UInt8(bin.green / bin.count), blue: UInt8(bin.blue / bin.count)),
                count: bin.count
            )
        }]

        func channels(_ color: RGB) -> [Int] {
            [Int(color.red), Int(color.green), Int(color.blue)]
        }
        func widestChannel(_ box: [Entry]) -> (channel: Int, range: Int) {
            var best = (channel: 0, range: -1)
            for channel in 0..<3 {
                let values = box.map { channels($0.color)[channel] }
                let range = (values.max() ?? 0) - (values.min() ?? 0)
                if range > best.range {
                    best = (channel, range)
                }
            }
            return best
        }

        while boxes.count < colorCount - fixed.count {
            // Split the box whose colours are furthest apart, at its median pixel.
            guard let target = boxes.indices.filter({ boxes[$0].count > 1 }).max(by: {
                widestChannel(boxes[$0]).range < widestChannel(boxes[$1]).range
            }) else {
                break
            }
            let channel = widestChannel(boxes[target]).channel
            let sorted = boxes[target].sorted { channels($0.color)[channel] < channels($1.color)[channel] }
            let half = sorted.reduce(0) { $0 + $1.count } / 2
            var running = 0
            var split = 1
            for (index, entry) in sorted.enumerated() {
                running += entry.count
                if running >= half {
                    split = min(max(index + 1, 1), sorted.count - 1)
                    break
                }
            }
            boxes[target] = Array(sorted[..<split])
            boxes.append(Array(sorted[split...]))
        }

        palette = fixed + boxes.filter { !$0.isEmpty }.map { box in
            let total = max(box.reduce(0) { $0 + $1.count }, 1)
            func mean(_ channel: Int) -> UInt8 {
                UInt8(box.reduce(0) { $0 + channels($1.color)[channel] * $1.count } / total)
            }
            return RGB(red: mean(0), green: mean(1), blue: mean(2))
        }
        var exact: [RGB: UInt8] = [:]
        for (index, color) in palette.enumerated() where exact[color] == nil {
            exact[color] = UInt8(index)
        }
        self.exact = exact
    }

    /// Palette indices for a frame of RGBX bytes, `width` pixels wide.
    ///
    /// A colour that is in the palette keeps its entry. Any other colour, such as a soft
    /// shadow over the wallpaper, is dithered between the entries around it. The dither
    /// pattern depends only on the pixel's position, so a still area comes out the same
    /// in every frame and the encoder can leave it out.
    mutating func indices(for frame: [UInt8], width: Int) -> [UInt8] {
        var result = [UInt8](repeating: 0, count: frame.count / 4)
        var offset = 0
        for pixel in 0..<result.count {
            let red = frame[offset]
            let green = frame[offset + 1]
            let blue = frame[offset + 2]
            offset += 4
            if let index = exact[RGB(red: red, green: green, blue: blue)] {
                result[pixel] = index
                continue
            }
            let nudge = Self.ditherPattern[(pixel / width) & 7][(pixel % width) & 7]
            func nudged(_ value: UInt8) -> UInt8 {
                UInt8(min(max(Int(value) + nudge, 0), 255))
            }
            let (r, g, b) = (nudged(red), nudged(green), nudged(blue))
            let bin = Int(r >> 2) << 12 | Int(g >> 2) << 6 | Int(b >> 2)
            if nearest[bin] < 0 {
                nearest[bin] = Int16(closest(to: r, g, b))
            }
            result[pixel] = UInt8(nearest[bin])
        }
        return result
    }

    /// An 8 by 8 ordered-dither matrix, as offsets of up to about 9 levels either way.
    private static let ditherPattern: [[Int]] = {
        let bayer: [[Int]] = [
            [0, 32, 8, 40, 2, 34, 10, 42],
            [48, 16, 56, 24, 50, 18, 58, 26],
            [12, 44, 4, 36, 14, 46, 6, 38],
            [60, 28, 52, 20, 62, 30, 54, 22],
            [3, 35, 11, 43, 1, 33, 9, 41],
            [51, 19, 59, 27, 49, 17, 57, 25],
            [15, 47, 7, 39, 13, 45, 5, 37],
            [63, 31, 55, 23, 61, 29, 53, 21],
        ]
        return bayer.map { row in row.map { ($0 * 18) / 63 - 9 } }
    }()

    private func closest(to red: UInt8, _ green: UInt8, _ blue: UInt8) -> Int {
        var best = 0
        var bestDistance = Int.max
        for (index, color) in palette.enumerated() {
            let dr = Int(color.red) - Int(red)
            let dg = Int(color.green) - Int(green)
            let db = Int(color.blue) - Int(blue)
            let distance = dr * dr + dg * dg + db * db
            if distance < bestDistance {
                best = index
                bestDistance = distance
            }
        }
        return best
    }

    private static func bin(_ red: UInt8, _ green: UInt8, _ blue: UInt8) -> Int {
        Int(red >> 3) << 10 | Int(green >> 3) << 5 | Int(blue >> 3)
    }
}
