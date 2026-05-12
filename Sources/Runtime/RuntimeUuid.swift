import Foundation

// MARK: - Uuid Runtime Support (kotlin.uuid.Uuid)

/// Internal box holding a UUID value as two 64-bit integers (most significant, least significant).
final class RuntimeUuidBox {
    let mostSignificantBits: Int64
    let leastSignificantBits: Int64

    init(mostSignificantBits: Int64, leastSignificantBits: Int64) {
        self.mostSignificantBits = mostSignificantBits
        self.leastSignificantBits = leastSignificantBits
    }

    /// Format as standard UUID string: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
    var uuidString: String {
        let msb = UInt64(bitPattern: mostSignificantBits)
        let lsb = UInt64(bitPattern: leastSignificantBits)

        let p1 = String(format: "%08x", UInt32(msb >> 32))
        let p2 = String(format: "%04x", UInt16((msb >> 16) & 0xFFFF))
        let p3 = String(format: "%04x", UInt16(msb & 0xFFFF))
        let p4 = String(format: "%04x", UInt16(lsb >> 48))
        let p5 = String(format: "%012llx", lsb & 0x0000_FFFF_FFFF_FFFF)

        return "\(p1)-\(p2)-\(p3)-\(p4)-\(p5)"
    }

    /// Format as hex string without dashes: xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
    var hexString: String {
        let msb = UInt64(bitPattern: mostSignificantBits)
        let lsb = UInt64(bitPattern: leastSignificantBits)
        return String(format: "%016llx%016llx", msb, lsb)
    }

    /// Convert to 16-byte array (big-endian)
    var byteArray: [UInt8] {
        let msb = UInt64(bitPattern: mostSignificantBits)
        let lsb = UInt64(bitPattern: leastSignificantBits)
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<8 {
            bytes[i] = UInt8((msb >> (56 - i * 8)) & 0xFF)
        }
        for i in 0..<8 {
            bytes[8 + i] = UInt8((lsb >> (56 - i * 8)) & 0xFF)
        }
        return bytes
    }

    var version: Int {
        let msb = UInt64(bitPattern: mostSignificantBits)
        return Int((msb >> 12) & 0xF)
    }

    var variant: Int {
        let lsb = UInt64(bitPattern: leastSignificantBits)
        let topThreeBits = (lsb >> 61) & 0x7
        switch topThreeBits {
        case 0b000, 0b001, 0b010, 0b011:
            return 0 // NCS backward compatibility
        case 0b100, 0b101:
            return 2 // RFC 4122 / IETF
        case 0b110:
            return 6 // Microsoft compatibility bucket
        default:
            return 7 // future reserved bucket
        }
    }
}

private final class RuntimeUuidLexicalOrderComparatorBox {}

private let kkUuidLexicalOrderComparator: @convention(c) (
    Int,
    Int,
    Int,
    UnsafeMutablePointer<Int>?
) -> Int = { _, lhsRaw, rhsRaw, outThrown in
    guard let lhs = runtimeUuidBox(from: lhsRaw),
          let rhs = runtimeUuidBox(from: rhsRaw)
    else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "IllegalArgumentException: Uuid.LEXICAL_ORDER.compare expected Uuid arguments"
        )
        return 0
    }
    return runtimeCompareUuidLexically(lhs, rhs)
}

private func runtimeCompareUuidLexically(_ lhs: RuntimeUuidBox, _ rhs: RuntimeUuidBox) -> Int {
    let lhsMsb = UInt64(bitPattern: lhs.mostSignificantBits)
    let rhsMsb = UInt64(bitPattern: rhs.mostSignificantBits)
    if lhsMsb != rhsMsb {
        return lhsMsb < rhsMsb ? -1 : 1
    }
    let lhsLsb = UInt64(bitPattern: lhs.leastSignificantBits)
    let rhsLsb = UInt64(bitPattern: rhs.leastSignificantBits)
    if lhsLsb != rhsLsb {
        return lhsLsb < rhsLsb ? -1 : 1
    }
    return 0
}

/// Extract a RuntimeUuidBox from a raw receiver value.
private func runtimeUuidBox(from rawValue: Int) -> RuntimeUuidBox? {
    resolveRuntimeHandle(rawValue, as: RuntimeUuidBox.self)
}

/// Helper to create a runtime string from a Swift String, returning Int.
private func uuidMakeStringRaw(_ value: String) -> Int {
    Int(bitPattern: value.withCString { cstr in
        cstr.withMemoryRebound(to: UInt8.self, capacity: value.utf8.count) { pointer in
            kk_string_from_utf8(pointer, Int32(value.utf8.count))
        }
    })
}

// MARK: - Uuid.random()

@_cdecl("kk_uuid_random")
public func kk_uuid_random() -> Int {
    // Generate a version-4 (random) UUID
    var rng = SystemRandomNumberGenerator()
    var msb = Int64(bitPattern: rng.next() as UInt64)
    var lsb = Int64(bitPattern: rng.next() as UInt64)

    // Set version to 4 (bits 12-15 of time_hi_and_version)
    msb = msb & ~(0xF << 12) | (4 << 12)
    // Set variant to IETF (bits 62-63 of clock_seq)
    lsb = lsb & ~(0x3 << 62) | (Int64(2) << 62)

    let box = RuntimeUuidBox(mostSignificantBits: msb, leastSignificantBits: lsb)
    return registerRuntimeObject(box)
}

// MARK: - Uuid.NIL

@_cdecl("kk_uuid_nil")
public func kk_uuid_nil() -> Int {
    let box = RuntimeUuidBox(mostSignificantBits: 0, leastSignificantBits: 0)
    return registerRuntimeObject(box)
}

// MARK: - Uuid.LEXICAL_ORDER

@_cdecl("kk_uuid_lexicalOrder")
public func kk_uuid_lexicalOrder() -> Int {
    let raw = registerRuntimeObject(RuntimeUuidLexicalOrderComparatorBox())
    _ = kk_object_register_itable_method(
        raw,
        0,
        0,
        unsafeBitCast(kkUuidLexicalOrderComparator, to: Int.self)
    )
    return raw
}

private func kk_uuid_makeInvalidArgument(
    message: String,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = runtimeAllocateThrowable(message: message)
    return 0
}

private func kk_uuid_parseHexBody(
    _ hex: String,
    invalidMessage: String,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let parsed = kk_uuid_parseHexBodyOrNull(hex)
    if parsed == runtimeNullSentinelInt {
        return kk_uuid_makeInvalidArgument(message: invalidMessage, outThrown: outThrown)
    }
    return parsed
}

private func kk_uuid_parseHexBodyOrNull(_ hex: String) -> Int {
    guard hex.count == 32,
          hex.allSatisfy({ $0.isHexDigit })
    else {
        return runtimeNullSentinelInt
    }

    let msbHex = String(hex.prefix(16))
    let lsbHex = String(hex.suffix(16))

    guard let msbValue = UInt64(msbHex, radix: 16),
          let lsbValue = UInt64(lsbHex, radix: 16)
    else {
        return runtimeNullSentinelInt
    }

    let box = RuntimeUuidBox(
        mostSignificantBits: Int64(bitPattern: msbValue),
        leastSignificantBits: Int64(bitPattern: lsbValue)
    )
    return registerRuntimeObject(box)
}

private func kk_uuid_isHexDashSeparatorOffset(_ offset: Int) -> Bool {
    offset == 8 || offset == 13 || offset == 18 || offset == 23
}

private func kk_uuid_hexFromHexDashString(_ hexDashString: String) -> String? {
    guard hexDashString.count == 36 else {
        return nil
    }

    var hex = ""
    hex.reserveCapacity(32)
    for (offset, character) in hexDashString.enumerated() {
        if kk_uuid_isHexDashSeparatorOffset(offset) {
            guard character == "-" else {
                return nil
            }
        } else {
            guard character.isHexDigit else {
                return nil
            }
            hex.append(character)
        }
    }
    return hex
}

private func kk_uuid_parseStringOrNull(_ uuidString: String) -> Int {
    if uuidString.count == 36 {
        guard let hex = kk_uuid_hexFromHexDashString(uuidString) else {
            return runtimeNullSentinelInt
        }
        return kk_uuid_parseHexBodyOrNull(hex)
    }
    if uuidString.count == 32 {
        return kk_uuid_parseHexBodyOrNull(uuidString)
    }
    return runtimeNullSentinelInt
}

// MARK: - Uuid.parse(string)

@_cdecl("kk_uuid_parse")
public func kk_uuid_parse(_ stringRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0

    // Extract the string from raw
    guard let ptr = UnsafeMutableRawPointer(bitPattern: stringRaw),
          let stringBox = tryCast(ptr, to: RuntimeStringBox.self)
    else {
        return kk_uuid_makeInvalidArgument(
            message: "IllegalArgumentException: Invalid UUID string: null",
            outThrown: outThrown
        )
    }

    let uuidString = stringBox.value
    let invalidMessage = "IllegalArgumentException: Invalid UUID string: \(uuidString)"

    // Parse standard format: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
    // or hex format: xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
    let hex: String
    if uuidString.count == 36 {
        guard let parsedHex = kk_uuid_hexFromHexDashString(uuidString) else {
            return kk_uuid_makeInvalidArgument(message: invalidMessage, outThrown: outThrown)
        }
        hex = parsedHex
    } else if uuidString.count == 32 {
        hex = uuidString
    } else {
        return kk_uuid_makeInvalidArgument(message: invalidMessage, outThrown: outThrown)
    }

    return kk_uuid_parseHexBody(hex, invalidMessage: invalidMessage, outThrown: outThrown)
}

// MARK: - Uuid.parseOrNull(uuidString)

@_cdecl("kk_uuid_parseOrNull")
public func kk_uuid_parseOrNull(_ stringRaw: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: stringRaw),
          let stringBox = tryCast(ptr, to: RuntimeStringBox.self)
    else {
        return runtimeNullSentinelInt
    }

    return kk_uuid_parseStringOrNull(stringBox.value)
}

// MARK: - Uuid.parseHex(hexString)

@_cdecl("kk_uuid_parseHex")
public func kk_uuid_parseHex(_ stringRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0

    guard let ptr = UnsafeMutableRawPointer(bitPattern: stringRaw),
          let stringBox = tryCast(ptr, to: RuntimeStringBox.self)
    else {
        return kk_uuid_makeInvalidArgument(
            message: "IllegalArgumentException: Invalid UUID hex string: null",
            outThrown: outThrown
        )
    }

    let hexString = stringBox.value
    return kk_uuid_parseHexBody(
        hexString,
        invalidMessage: "IllegalArgumentException: Invalid UUID hex string: \(hexString)",
        outThrown: outThrown
    )
}

// MARK: - Uuid.parseHexOrNull(hexString)

@_cdecl("kk_uuid_parseHexOrNull")
public func kk_uuid_parseHexOrNull(_ stringRaw: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: stringRaw),
          let stringBox = tryCast(ptr, to: RuntimeStringBox.self)
    else {
        return runtimeNullSentinelInt
    }

    return kk_uuid_parseHexBodyOrNull(stringBox.value)
}

// MARK: - Uuid.parseHexDash(hexDashString)

@_cdecl("kk_uuid_parseHexDash")
public func kk_uuid_parseHexDash(_ stringRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0

    guard let ptr = UnsafeMutableRawPointer(bitPattern: stringRaw),
          let stringBox = tryCast(ptr, to: RuntimeStringBox.self)
    else {
        return kk_uuid_makeInvalidArgument(
            message: "IllegalArgumentException: Invalid UUID hex-and-dash string: null",
            outThrown: outThrown
        )
    }

    let hexDashString = stringBox.value
    let invalidMessage = "IllegalArgumentException: Invalid UUID hex-and-dash string: \(hexDashString)"
    guard let hex = kk_uuid_hexFromHexDashString(hexDashString) else {
        return kk_uuid_makeInvalidArgument(message: invalidMessage, outThrown: outThrown)
    }
    return kk_uuid_parseHexBody(hex, invalidMessage: invalidMessage, outThrown: outThrown)
}

// MARK: - Uuid.parseHexDashOrNull(hexDashString)

@_cdecl("kk_uuid_parseHexDashOrNull")
public func kk_uuid_parseHexDashOrNull(_ stringRaw: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: stringRaw),
          let stringBox = tryCast(ptr, to: RuntimeStringBox.self)
    else {
        return runtimeNullSentinelInt
    }

    guard let hex = kk_uuid_hexFromHexDashString(stringBox.value) else {
        return runtimeNullSentinelInt
    }
    return kk_uuid_parseHexBodyOrNull(hex)
}

// MARK: - Uuid.toString()

@_cdecl("kk_uuid_toString")
public func kk_uuid_toString(_ receiver: Int) -> Int {
    guard let box = runtimeUuidBox(from: receiver) else {
        return uuidMakeStringRaw("00000000-0000-0000-0000-000000000000")
    }
    return uuidMakeStringRaw(box.uuidString)
}

// MARK: - Uuid.toHexString()

@_cdecl("kk_uuid_toHexString")
public func kk_uuid_toHexString(_ receiver: Int) -> Int {
    guard let box = runtimeUuidBox(from: receiver) else {
        return uuidMakeStringRaw("00000000000000000000000000000000")
    }
    return uuidMakeStringRaw(box.hexString)
}

// MARK: - Uuid.toLongs() -> Pair<Long, Long>

@_cdecl("kk_uuid_toLongs")
public func kk_uuid_toLongs(_ receiver: Int) -> Int {
    guard let box = runtimeUuidBox(from: receiver) else {
        return kk_pair_new(0, 0)
    }
    return kk_pair_new(Int(box.mostSignificantBits), Int(box.leastSignificantBits))
}

// MARK: - Uuid.toByteArray() -> ByteArray

@_cdecl("kk_uuid_toByteArray")
public func kk_uuid_toByteArray(_ receiver: Int) -> Int {
    guard let box = runtimeUuidBox(from: receiver) else {
        let emptyArray = RuntimeArrayBox(length: 16)
        return registerRuntimeObject(emptyArray)
    }
    let bytes = box.byteArray
    let arrayBox = RuntimeArrayBox(length: 16)
    for i in 0..<16 {
        arrayBox.elements[i] = Int(bytes[i])
    }
    return registerRuntimeObject(arrayBox)
}

// MARK: - Uuid.version() / variant()

@_cdecl("kk_uuid_version")
public func kk_uuid_version(_ receiver: Int) -> Int {
    guard let box = runtimeUuidBox(from: receiver) else {
        return 0
    }
    return box.version
}

@_cdecl("kk_uuid_variant")
public func kk_uuid_variant(_ receiver: Int) -> Int {
    guard let box = runtimeUuidBox(from: receiver) else {
        return 0
    }
    return box.variant
}

// MARK: - Uuid.mostSignificantBits / leastSignificantBits

@_cdecl("kk_uuid_mostSignificantBits")
public func kk_uuid_mostSignificantBits(_ receiver: Int) -> Int {
    guard let box = runtimeUuidBox(from: receiver) else {
        return 0
    }
    return Int(box.mostSignificantBits)
}

@_cdecl("kk_uuid_leastSignificantBits")
public func kk_uuid_leastSignificantBits(_ receiver: Int) -> Int {
    guard let box = runtimeUuidBox(from: receiver) else {
        return 0
    }
    return Int(box.leastSignificantBits)
}

// MARK: - Uuid.fromLongs(mostSignificantBits, leastSignificantBits)

/// Create a Uuid from two Long values (MSB and LSB).
/// Maps directly to kotlin.uuid.Uuid.fromLongs().
@_cdecl("kk_uuid_fromLongs")
public func kk_uuid_fromLongs(_ msb: Int, _ lsb: Int) -> Int {
    let box = RuntimeUuidBox(
        mostSignificantBits: Int64(bitPattern: UInt64(bitPattern: Int64(msb))),
        leastSignificantBits: Int64(bitPattern: UInt64(bitPattern: Int64(lsb)))
    )
    return registerRuntimeObject(box)
}

// MARK: - Uuid.fromByteArray(byteArray: ByteArray)

/// Create a Uuid from a 16-byte array (big-endian, MSB first).
/// Throws IllegalArgumentException if the array is not exactly 16 bytes.
@_cdecl("kk_uuid_fromByteArray")
public func kk_uuid_fromByteArray(_ arrayRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0

    guard let ptr = UnsafeMutableRawPointer(bitPattern: arrayRaw),
          let arrayBox = tryCast(ptr, to: RuntimeArrayBox.self)
    else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "IllegalArgumentException: byteArray.size must be 16, was 0"
        )
        return 0
    }

    let size = arrayBox.elements.count
    guard size == 16 else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "IllegalArgumentException: byteArray.size must be 16, was \(size)"
        )
        return 0
    }

    var msb: UInt64 = 0
    var lsb: UInt64 = 0
    for i in 0..<8 {
        msb = (msb << 8) | UInt64(arrayBox.elements[i] & 0xFF)
    }
    for i in 8..<16 {
        lsb = (lsb << 8) | UInt64(arrayBox.elements[i] & 0xFF)
    }

    let box = RuntimeUuidBox(
        mostSignificantBits: Int64(bitPattern: msb),
        leastSignificantBits: Int64(bitPattern: lsb)
    )
    return registerRuntimeObject(box)
}

// MARK: - Uuid.nameUUIDFromBytes(name: ByteArray)

/// Generate a version-3 (MD5-based) UUID from a name byte array.
/// Follows RFC 4122 name-based UUID generation.
@_cdecl("kk_uuid_nameUUIDFromBytes")
public func kk_uuid_nameUUIDFromBytes(_ nameArrayRaw: Int) -> Int {
    var inputBytes: [UInt8]
    if let ptr = UnsafeMutableRawPointer(bitPattern: nameArrayRaw),
       let arrayBox = tryCast(ptr, to: RuntimeArrayBox.self)
    {
        inputBytes = arrayBox.elements.map { UInt8($0 & 0xFF) }
    } else {
        inputBytes = []
    }

    let digest = kk_uuid_md5Digest(inputBytes)

    var msb: UInt64 = 0
    var lsb: UInt64 = 0
    for i in 0..<8 {
        msb = (msb << 8) | UInt64(digest[i])
    }
    for i in 8..<16 {
        lsb = (lsb << 8) | UInt64(digest[i])
    }

    // Set version to 3 (name-based MD5)
    msb = (msb & 0xFFFF_FFFF_FFFF_0FFF) | 0x0000_0000_0000_3000
    // Set variant to IETF RFC 4122
    lsb = (lsb & 0x3FFF_FFFF_FFFF_FFFF) | 0x8000_0000_0000_0000

    let box = RuntimeUuidBox(
        mostSignificantBits: Int64(bitPattern: msb),
        leastSignificantBits: Int64(bitPattern: lsb)
    )
    return registerRuntimeObject(box)
}

/// Compute MD5 digest of input bytes, returning 16 bytes.
private func kk_uuid_md5Digest(_ input: [UInt8]) -> [UInt8] {
    let s: [UInt32] = [
        7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
        5,  9, 14, 20, 5,  9, 14, 20, 5,  9, 14, 20, 5,  9, 14, 20,
        4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
        6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
    ]
    let k: [UInt32] = [
        0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee,
        0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501,
        0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be,
        0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821,
        0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa,
        0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
        0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed,
        0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a,
        0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c,
        0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70,
        0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05,
        0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
        0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039,
        0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
        0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1,
        0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391,
    ]

    var msg = input
    let originalLengthBits = UInt64(input.count) * 8
    msg.append(0x80)
    while msg.count % 64 != 56 {
        msg.append(0x00)
    }
    for i in 0..<8 {
        msg.append(UInt8((originalLengthBits >> (i * 8)) & 0xFF))
    }

    var a0: UInt32 = 0x67452301
    var b0: UInt32 = 0xefcdab89
    var c0: UInt32 = 0x98badcfe
    var d0: UInt32 = 0x10325476

    let chunkCount = msg.count / 64
    for chunkIndex in 0..<chunkCount {
        let offset = chunkIndex * 64
        var m = [UInt32](repeating: 0, count: 16)
        for i in 0..<16 {
            let base = offset + i * 4
            m[i] = UInt32(msg[base])
                | (UInt32(msg[base + 1]) << 8)
                | (UInt32(msg[base + 2]) << 16)
                | (UInt32(msg[base + 3]) << 24)
        }

        var a = a0, b = b0, c = c0, d = d0

        for i in 0..<64 {
            var f: UInt32
            var g: Int
            if i < 16 {
                f = (b & c) | (~b & d)
                g = i
            } else if i < 32 {
                f = (d & b) | (~d & c)
                g = (5 * i + 1) % 16
            } else if i < 48 {
                f = b ^ c ^ d
                g = (3 * i + 5) % 16
            } else {
                f = c ^ (b | ~d)
                g = (7 * i) % 16
            }
            f = f &+ a &+ k[i] &+ m[g]
            a = d
            d = c
            c = b
            b = b &+ ((f << s[i]) | (f >> (32 - s[i])))
        }

        a0 = a0 &+ a
        b0 = b0 &+ b
        c0 = c0 &+ c
        d0 = d0 &+ d
    }

    var digest = [UInt8](repeating: 0, count: 16)
    for (wordIndex, word) in [a0, b0, c0, d0].enumerated() {
        for byteIndex in 0..<4 {
            digest[wordIndex * 4 + byteIndex] = UInt8((word >> (byteIndex * 8)) & 0xFF)
        }
    }
    return digest
}
