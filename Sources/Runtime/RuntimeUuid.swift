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
}

/// Extract a RuntimeUuidBox from a raw receiver value.
private func runtimeUuidBox(from rawValue: Int) -> RuntimeUuidBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: rawValue) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return nil
    }
    return tryCast(ptr, to: RuntimeUuidBox.self)
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

// MARK: - Uuid.parse(string)

@_cdecl("kk_uuid_parse")
public func kk_uuid_parse(_ stringRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0

    // Extract the string from raw
    guard let ptr = UnsafeMutableRawPointer(bitPattern: stringRaw),
          let stringBox = tryCast(ptr, to: RuntimeStringBox.self)
    else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "IllegalArgumentException: Invalid UUID string: null"
        )
        return 0
    }

    let uuidString = stringBox.value.trimmingCharacters(in: .whitespaces)

    // Parse standard format: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
    // or hex format: xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
    let hex: String
    if uuidString.count == 36, uuidString.contains("-") {
        let parts = uuidString.split(separator: "-")
        guard parts.count == 5,
              parts[0].count == 8,
              parts[1].count == 4,
              parts[2].count == 4,
              parts[3].count == 4,
              parts[4].count == 12
        else {
            outThrown?.pointee = runtimeAllocateThrowable(
                message: "IllegalArgumentException: Invalid UUID string: \(uuidString)"
            )
            return 0
        }
        hex = parts.joined()
    } else if uuidString.count == 32 {
        hex = uuidString
    } else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "IllegalArgumentException: Invalid UUID string: \(uuidString)"
        )
        return 0
    }

    guard hex.count == 32,
          hex.allSatisfy({ $0.isHexDigit })
    else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "IllegalArgumentException: Invalid UUID string: \(uuidString)"
        )
        return 0
    }

    let msbHex = String(hex.prefix(16))
    let lsbHex = String(hex.suffix(16))

    guard let msbValue = UInt64(msbHex, radix: 16),
          let lsbValue = UInt64(lsbHex, radix: 16)
    else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "IllegalArgumentException: Invalid UUID string: \(uuidString)"
        )
        return 0
    }

    let box = RuntimeUuidBox(
        mostSignificantBits: Int64(bitPattern: msbValue),
        leastSignificantBits: Int64(bitPattern: lsbValue)
    )
    return registerRuntimeObject(box)
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
