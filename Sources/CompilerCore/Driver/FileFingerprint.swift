import Foundation

/// Represents a fingerprint of a source file for incremental compilation.
/// The content hash is the primary comparison key; mtime serves as a fast-path
/// to avoid re-hashing when the file system reports no modification.
public struct FileFingerprint: Equatable, Codable {
    /// Absolute path of the source file.
    public let path: String

    /// SHA-256 hex digest of the file contents.
    public let contentHash: String

    /// Last-modified time as nanoseconds since the Unix epoch.
    /// Stored as `Int64` to avoid floating-point round-trip issues through JSON.
    public let mtimeNanos: Int64

    public init(path: String, contentHash: String, mtimeNanos: Int64) {
        self.path = path
        self.contentHash = contentHash
        self.mtimeNanos = mtimeNanos
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
        let mtimeNanos = fileMtimeNanos(path: path)
        return FileFingerprint(path: path, contentHash: hash, mtimeNanos: mtimeNanos)
    }

    /// Returns `true` when the content hash differs from `other`.
    public func contentChanged(from other: FileFingerprint) -> Bool {
        contentHash != other.contentHash
    }

    /// Quick mtime-based check: returns `true` when the mtime is unchanged,
    /// meaning we can *probably* skip re-hashing.
    public func mtimeUnchanged(from other: FileFingerprint) -> Bool {
        path == other.path && mtimeNanos == other.mtimeNanos
    }

    // MARK: - Private helpers

    private static func sha256Hex(_ data: Data) -> String {
        if data.isEmpty {
            return "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        }
        var hash = [UInt8](repeating: 0, count: 32)
        let bytes: [UInt8] = Array(data)
        bytes.withUnsafeBufferPointer { buffer in
            guard let ptr = buffer.baseAddress else { return }
            sha256(UnsafeRawPointer(ptr), data.count, &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    /// Minimal SHA-256 implementation (no external dependency).
    private static func sha256(_ data: UnsafeRawPointer, _ length: Int, _ output: inout [UInt8]) {
        let k: [UInt32] = [
            0x428A_2F98, 0x7137_4491, 0xB5C0_FBCF, 0xE9B5_DBA5,
            0x3956_C25B, 0x59F1_11F1, 0x923F_82A4, 0xAB1C_5ED5,
            0xD807_AA98, 0x1283_5B01, 0x2431_85BE, 0x550C_7DC3,
            0x72BE_5D74, 0x80DE_B1FE, 0x9BDC_06A7, 0xC19B_F174,
            0xE49B_69C1, 0xEFBE_4786, 0x0FC1_9DC6, 0x240C_A1CC,
            0x2DE9_2C6F, 0x4A74_84AA, 0x5CB0_A9DC, 0x76F9_88DA,
            0x983E_5152, 0xA831_C66D, 0xB003_27C8, 0xBF59_7FC7,
            0xC6E0_0BF3, 0xD5A7_9147, 0x06CA_6351, 0x1429_2967,
            0x27B7_0A85, 0x2E1B_2138, 0x4D2C_6DFC, 0x5338_0D13,
            0x650A_7354, 0x766A_0ABB, 0x81C2_C92E, 0x9272_2C85,
            0xA2BF_E8A1, 0xA81A_664B, 0xC24B_8B70, 0xC76C_51A3,
            0xD192_E819, 0xD699_0624, 0xF40E_3585, 0x106A_A070,
            0x19A4_C116, 0x1E37_6C08, 0x2748_774C, 0x34B0_BCB5,
            0x391C_0CB3, 0x4ED8_AA4A, 0x5B9C_CA4F, 0x682E_6FF3,
            0x748F_82EE, 0x78A5_636F, 0x84C8_7814, 0x8CC7_0208,
            0x90BE_FFFA, 0xA450_6CEB, 0xBEF9_A3F7, 0xC671_78F2,
        ]

        var h0: UInt32 = 0x6A09_E667
        var h1: UInt32 = 0xBB67_AE85
        var h2: UInt32 = 0x3C6E_F372
        var h3: UInt32 = 0xA54F_F53A
        var h4: UInt32 = 0x510E_527F
        var h5: UInt32 = 0x9B05_688C
        var h6: UInt32 = 0x1F83_D9AB
        var h7: UInt32 = 0x5BE0_CD19

        // Pre-processing: pad the message
        var message = [UInt8](UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: length))
        let originalLength = message.count
        message.append(0x80)
        while message.count % 64 != 56 {
            message.append(0x00)
        }
        let bitLength = UInt64(originalLength) * 8
        for i in stride(from: 56, through: 0, by: -8) {
            message.append(UInt8((bitLength >> i) & 0xFF))
        }

        // Process each 64-byte block
        let blockCount = message.count / 64
        for blockIndex in 0 ..< blockCount {
            var w = [UInt32](repeating: 0, count: 64)
            for t in 0 ..< 16 {
                let offset = blockIndex * 64 + t * 4
                w[t] = UInt32(message[offset]) << 24
                    | UInt32(message[offset + 1]) << 16
                    | UInt32(message[offset + 2]) << 8
                    | UInt32(message[offset + 3])
            }
            for t in 16 ..< 64 {
                let s0 = rightRotate(w[t - 15], by: 7) ^ rightRotate(w[t - 15], by: 18) ^ (w[t - 15] >> 3)
                let s1 = rightRotate(w[t - 2], by: 17) ^ rightRotate(w[t - 2], by: 19) ^ (w[t - 2] >> 10)
                w[t] = w[t - 16] &+ s0 &+ w[t - 7] &+ s1
            }

            var a = h0, b = h1, c = h2, d = h3
            var e = h4, f = h5, g = h6, h = h7

            for t in 0 ..< 64 {
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
            output[i * 4 + 0] = UInt8((word >> 24) & 0xFF)
            output[i * 4 + 1] = UInt8((word >> 16) & 0xFF)
            output[i * 4 + 2] = UInt8((word >> 8) & 0xFF)
            output[i * 4 + 3] = UInt8(word & 0xFF)
        }
    }

    private static func rightRotate(_ value: UInt32, by amount: UInt32) -> UInt32 {
        (value >> amount) | (value << (32 - amount))
    }

    private static func fileMtimeNanos(path: String) -> Int64 {
        let url = URL(fileURLWithPath: path)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let date = attrs[.modificationDate] as? Date
        else {
            return 0
        }
        // Convert to nanoseconds to avoid floating-point round-trip issues.
        return Int64(date.timeIntervalSince1970 * 1_000_000_000)
    }
}
