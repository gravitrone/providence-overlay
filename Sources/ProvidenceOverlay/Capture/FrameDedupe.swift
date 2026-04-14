import Foundation
import CoreGraphics
import Accelerate

final class FrameDedupe {
    private var lastHash: UInt64 = 0
    private var hasLast: Bool = false

    /// Returns (keep, hash, hammingDistance). Skip if < threshold bits differ.
    func shouldKeep(_ cg: CGImage, threshold: Int = 3) -> (keep: Bool, hash: UInt64, hamming: Int) {
        let hash = Self.dHash(cg)
        if !hasLast {
            lastHash = hash
            hasLast = true
            return (true, hash, 64)
        }
        let hamming = (hash ^ lastHash).nonzeroBitCount
        if hamming < threshold {
            return (false, hash, hamming)
        }
        lastHash = hash
        return (true, hash, hamming)
    }

    /// 9x8 grayscale dHash: bit[i] = (pixel[i] > pixel[i+1]) per row. 64 bits total.
    static func dHash(_ cg: CGImage) -> UInt64 {
        // First, render CGImage to a full-size grayscale buffer.
        guard let grayBytes = renderGray(cg) else { return 0 }
        defer { free(grayBytes.data) }

        var srcBuffer = vImage_Buffer(
            data: grayBytes.data,
            height: vImagePixelCount(grayBytes.height),
            width: vImagePixelCount(grayBytes.width),
            rowBytes: grayBytes.rowBytes
        )

        let dstW = 9, dstH = 8
        var dst = [UInt8](repeating: 0, count: dstW * dstH)
        dst.withUnsafeMutableBufferPointer { ptr in
            var dstBuffer = vImage_Buffer(
                data: ptr.baseAddress,
                height: vImagePixelCount(dstH),
                width: vImagePixelCount(dstW),
                rowBytes: dstW
            )
            _ = vImageScale_Planar8(&srcBuffer, &dstBuffer, nil, vImage_Flags(kvImageHighQualityResampling))
        }

        var hash: UInt64 = 0
        for row in 0..<dstH {
            for col in 0..<(dstW - 1) {
                let i = row * dstW + col
                if dst[i] > dst[i + 1] {
                    let bit = (row * (dstW - 1)) + col  // 0..63
                    hash |= (UInt64(1) << UInt64(bit))
                }
            }
        }
        return hash
    }

    private struct GrayBuffer {
        let data: UnsafeMutableRawPointer
        let width: Int
        let height: Int
        let rowBytes: Int
    }

    private static func renderGray(_ cg: CGImage) -> GrayBuffer? {
        let width = max(1, cg.width)
        let height = max(1, cg.height)
        let bytesPerRow = width
        let size = bytesPerRow * height
        guard let raw = malloc(size) else { return nil }
        let bytes = raw.assumingMemoryBound(to: UInt8.self)
        memset(bytes, 0, size)
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(
            data: bytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            free(raw)
            return nil
        }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        return GrayBuffer(data: raw, width: width, height: height, rowBytes: bytesPerRow)
    }
}
