import Foundation

/// Represents a fingerprint of a source file for incremental compilation.
/// The content hash is the primary comparison key; mtime serves as a fast-path
/// to avoid re-hashing when the file system reports no modification.
public struct FileFingerprint: Equatable, Codable {
    /// Absolute path of the source file.
    public let path: String

    /// SHA-256 hex digest of the file contents.
    public let contentHash: String

    /// Last-modified time as seconds since the Unix epoch.
    public let mtime: Double

    public init(path: String, contentHash: String, mtime: Double) {
        self.path = path
        self.contentHash = contentHash
        self.mtime = mtime
    }

    /// Computes a fingerprint for the file at the given path.
    /// Returns `nil` if the file cannot be read.
    public static func compute(for path: String) -> FileFingerprint? {
        let url = URL(fileURLWithPath: path)
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return compute(for: path, contents: data)
    }

    /// Computes a fingerprint from already-loaded file contents.
    public static func compute(for path: String, contents: Data) -> FileFingerprint {
        let hash = sha256Hex(contents)
        let mtime = fileMtime(path: path)
        return FileFingerprint(path: path, contentHash: hash, mtime: mtime)
    }

    /// Returns `true` when the content hash differs from `other`.
    public func contentChanged(from other: FileFingerprint) -> Bool {
        contentHash != other.contentHash
    }

    /// Quick mtime-based check: returns `true` when the mtime is unchanged,
    /// meaning we can *probably* skip re-hashing.
    public func mtimeUnchanged(from other: FileFingerprint) -> Bool {
        path == other.path && mtime == other.mtime
    }

    // MARK: - Private helpers

    private static func sha256Hex(_ data: Data) -> String {
        var hash = [UInt8](repeating: 0, count: 32)
        let bytes: [UInt8] = Array(data)
        bytes.withUnsafeBufferPointer { buffer in
            let ptr = buffer.baseAddress ?? UnsafePointer<UInt8>(bitPattern: 1)!
            sha256(UnsafeRawPointer(ptr), data.count, &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    /// Minimal SHA-256 implementation (no external dependency).
    private static func sha256(_ data: UnsafeRawPointer, _ length: Int, _ output: inout [UInt8]) {
        let k: [UInt32] = [
            0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
            0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
            0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
            0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
            0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
            0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
            0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
            0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
            0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
            0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
            0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
            0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
            0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
            0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
            0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
            0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
        ]

        var h0: UInt32 = 0x6a09e667
        var h1: UInt32 = 0xbb67ae85
        var h2: UInt32 = 0x3c6ef372
        var h3: UInt32 = 0xa54ff53a
        var h4: UInt32 = 0x510e527f
        var h5: UInt32 = 0x9b05688c
        var h6: UInt32 = 0x1f83d9ab
        var h7: UInt32 = 0x5be0cd19

        // Pre-processing: pad the message
        var message = [UInt8](UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: length))
        let originalLength = message.count
        message.append(0x80)
        while message.count % 64 != 56 {
            message.append(0x00)
        }
        let bitLength = UInt64(originalLength) * 8
        for i in stride(from: 56, through: 0, by: -8) {
            message.append(UInt8((bitLength >> i) & 0xff))
        }

        // Process each 64-byte block
        let blockCount = message.count / 64
        for blockIndex in 0..<blockCount {
            var w = [UInt32](repeating: 0, count: 64)
            for t in 0..<16 {
                let offset = blockIndex * 64 + t * 4
                w[t] = UInt32(message[offset]) << 24
                    | UInt32(message[offset + 1]) << 16
                    | UInt32(message[offset + 2]) << 8
                    | UInt32(message[offset + 3])
            }
            for t in 16..<64 {
                let s0 = rightRotate(w[t - 15], by: 7) ^ rightRotate(w[t - 15], by: 18) ^ (w[t - 15] >> 3)
                let s1 = rightRotate(w[t - 2], by: 17) ^ rightRotate(w[t - 2], by: 19) ^ (w[t - 2] >> 10)
                w[t] = w[t - 16] &+ s0 &+ w[t - 7] &+ s1
            }

            var a = h0, b = h1, c = h2, d = h3
            var e = h4, f = h5, g = h6, h = h7

            for t in 0..<64 {
                let S1 = rightRotate(e, by: 6) ^ rightRotate(e, by: 11) ^ rightRotate(e, by: 25)
                let ch = (e & f) ^ (~e & g)
                let temp1 = h &+ S1 &+ ch &+ k[t] &+ w[t]
                let S0 = rightRotate(a, by: 2) ^ rightRotate(a, by: 13) ^ rightRotate(a, by: 22)
                let maj = (a & b) ^ (a & c) ^ (b & c)
                let temp2 = S0 &+ maj

                h = g; g = f; f = e; e = d &+ temp1
                d = c; c = b; b = a; a = temp1 &+ temp2
            }

            h0 = h0 &+ a; h1 = h1 &+ b; h2 = h2 &+ c; h3 = h3 &+ d
            h4 = h4 &+ e; h5 = h5 &+ f; h6 = h6 &+ g; h7 = h7 &+ h
        }

        let result: [UInt32] = [h0, h1, h2, h3, h4, h5, h6, h7]
        for (i, word) in result.enumerated() {
            output[i * 4 + 0] = UInt8((word >> 24) & 0xff)
            output[i * 4 + 1] = UInt8((word >> 16) & 0xff)
            output[i * 4 + 2] = UInt8((word >> 8) & 0xff)
            output[i * 4 + 3] = UInt8(word & 0xff)
        }
    }

    private static func rightRotate(_ value: UInt32, by amount: UInt32) -> UInt32 {
        (value >> amount) | (value << (32 - amount))
    }

    private static func fileMtime(path: String) -> Double {
        let url = URL(fileURLWithPath: path)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let date = attrs[.modificationDate] as? Date else {
            return 0
        }
        return date.timeIntervalSince1970
    }
}
