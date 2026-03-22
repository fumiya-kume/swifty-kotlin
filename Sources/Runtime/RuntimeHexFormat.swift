import Foundation

// MARK: - HexFormat Runtime Types

/// Runtime representation of kotlin.text.HexFormat.
final class RuntimeHexFormatBox {
    var upperCase: Bool
    var byteSeparator: String

    init(upperCase: Bool = false, byteSeparator: String = "") {
        self.upperCase = upperCase
        self.byteSeparator = byteSeparator
    }
}

// MARK: - Private Helpers

private func hexFormatStringFromRaw(_ raw: Int) -> String? {
    if raw == runtimeNullSentinelInt { return nil }
    guard let pointer = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return extractString(from: pointer)
}

private func hexFormatMakeStringRaw(_ value: String) -> Int {
    Int(bitPattern: value.withCString { cstr in
        cstr.withMemoryRebound(to: UInt8.self, capacity: value.utf8.count) { pointer in
            kk_string_from_utf8(pointer, Int32(value.utf8.count))
        }
    })
}

private func hexFormatBoxFromRaw(_ raw: Int) -> RuntimeHexFormatBox? {
    if raw == runtimeNullSentinelInt { return nil }
    guard let pointer = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(pointer, to: RuntimeHexFormatBox.self)
}

private func hexFormatMakeListRaw(_ values: [Int]) -> Int {
    let box = RuntimeListBox(elements: values)
    return registerRuntimeObject(box)
}

private let cachedDefaultHexFormatRaw: Int = registerRuntimeObject(RuntimeHexFormatBox())

// MARK: - HexFormat.Default companion property

@_cdecl("kk_hexformat_default")
public func kk_hexformat_default() -> Int {
    cachedDefaultHexFormatRaw
}

// MARK: - HexFormat { } builder DSL

@_cdecl("kk_hexformat_create")
public func kk_hexformat_create(
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let format = RuntimeHexFormatBox()
    let formatRaw = registerRuntimeObject(format)
    // Invoke the builder lambda with the format object as receiver
    var thrown = 0
    _ = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: formatRaw, outThrown: &thrown)
    if thrown != 0 {
        outThrown?.pointee = thrown
        return registerRuntimeObject(RuntimeHexFormatBox())
    }
    return formatRaw
}

// MARK: - HexFormat.upperCase property

@_cdecl("kk_hexformat_upperCase")
public func kk_hexformat_upperCase(_ formatRaw: Int) -> Int {
    guard let format = hexFormatBoxFromRaw(formatRaw) else {
        return kk_box_bool(0)
    }
    return kk_box_bool(format.upperCase ? 1 : 0)
}

// MARK: - HexFormat.bytes property (returns self for chaining)

@_cdecl("kk_hexformat_bytes")
public func kk_hexformat_bytes(_ formatRaw: Int) -> Int {
    // In Kotlin, .bytes returns a BytesHexFormat sub-object.
    // We simplify: return the same HexFormat (it carries byteSeparator).
    return formatRaw
}

// MARK: - Int.toHexString(format)

@_cdecl("kk_int_toHexString")
public func kk_int_toHexString(_ receiverRaw: Int, _ formatRaw: Int) -> Int {
    let value = Int(Int32(truncatingIfNeeded: receiverRaw))
    let format = hexFormatBoxFromRaw(formatRaw)
    let hex: String
    if value < 0 {
        // Kotlin: negative Int.toHexString produces 8-char two's-complement hex
        let unsigned = UInt32(bitPattern: Int32(truncatingIfNeeded: value))
        hex = String(unsigned, radix: 16)
    } else {
        hex = String(value, radix: 16)
    }
    let result = (format?.upperCase ?? false) ? hex.uppercased() : hex.lowercased()
    return hexFormatMakeStringRaw(result)
}

// MARK: - Long.toHexString(format)

@_cdecl("kk_long_toHexString")
public func kk_long_toHexString(_ receiverRaw: Int, _ formatRaw: Int) -> Int {
    let longValue = Int(kk_unbox_long(receiverRaw))
    let format = hexFormatBoxFromRaw(formatRaw)
    let hex: String
    if longValue < 0 {
        // Kotlin: negative Long.toHexString produces 16-char two's-complement hex
        let unsigned = UInt64(bitPattern: Int64(longValue))
        hex = String(unsigned, radix: 16)
    } else {
        hex = String(longValue, radix: 16)
    }
    let result = (format?.upperCase ?? false) ? hex.uppercased() : hex.lowercased()
    return hexFormatMakeStringRaw(result)
}

// MARK: - ByteArray.toHexString(format)

@_cdecl("kk_bytearray_toHexString")
public func kk_bytearray_toHexString(_ arrayRaw: Int, _ formatRaw: Int) -> Int {
    let format = hexFormatBoxFromRaw(formatRaw)
    let upper = format?.upperCase ?? false
    let separator = format?.byteSeparator ?? ""

    // Extract byte values from the list
    let bytes = runtimeListElements(from: arrayRaw)
    var hexParts: [String] = []
    for byteRaw in bytes {
        let byteValue = UInt8(truncatingIfNeeded: byteRaw & 0xFF)
        let hex = String(format: "%02x", byteValue)
        hexParts.append(upper ? hex.uppercased() : hex)
    }
    let result = hexParts.joined(separator: separator)
    return hexFormatMakeStringRaw(result)
}

// MARK: - String.hexToInt(format)

@_cdecl("kk_string_hexToInt")
public func kk_string_hexToInt(_ receiverRaw: Int, _ formatRaw: Int) -> Int {
    let str = hexFormatStringFromRaw(receiverRaw) ?? ""
    let cleaned = str
    guard let value = UInt32(cleaned, radix: 16) else {
        return 0
    }
    return Int(Int32(bitPattern: value))
}

// MARK: - String.hexToLong(format)

@_cdecl("kk_string_hexToLong")
public func kk_string_hexToLong(_ receiverRaw: Int, _ formatRaw: Int) -> Int {
    let str = hexFormatStringFromRaw(receiverRaw) ?? ""
    let cleaned = str
    guard let value = UInt64(cleaned, radix: 16) else {
        return kk_box_long(0)
    }
    return kk_box_long(Int(Int64(bitPattern: value)))
}

// MARK: - String.hexToByteArray(format)

@_cdecl("kk_string_hexToByteArray")
public func kk_string_hexToByteArray(_ receiverRaw: Int, _ formatRaw: Int) -> Int {
    let str = hexFormatStringFromRaw(receiverRaw) ?? ""
    let format = hexFormatBoxFromRaw(formatRaw)
    let separator = format?.byteSeparator ?? ""

    // If there's a separator, split by it; otherwise parse as contiguous hex
    let hexString: String
    if !separator.isEmpty {
        hexString = str.components(separatedBy: separator).joined()
    } else {
        hexString = str
    }

    // Parse pairs of hex digits into bytes
    var bytes: [Int] = []
    var index = hexString.startIndex
    while index < hexString.endIndex {
        let nextIndex = hexString.index(index, offsetBy: 2, limitedBy: hexString.endIndex) ?? hexString.endIndex
        let hexPair = String(hexString[index ..< nextIndex])
        if let byte = UInt8(hexPair, radix: 16) {
            bytes.append(Int(Int8(bitPattern: byte)))
        }
        index = nextIndex
    }
    return hexFormatMakeListRaw(bytes)
}

// MARK: - Runtime List Element Extraction Helper

/// Extracts element raw values from a runtime list.
private func runtimeListElements(from listRaw: Int) -> [Int] {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: listRaw) else { return [] }
    guard let listBox = tryCast(pointer, to: RuntimeListBox.self) else { return [] }
    return listBox.elements
}
