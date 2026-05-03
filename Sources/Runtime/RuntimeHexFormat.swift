import Foundation

// MARK: - HexFormat Runtime Types

/// Runtime representation of kotlin.text.HexFormat.
final class RuntimeHexFormatBox {
    var upperCase: Bool
    var byteSeparator: String
    /// HexFormat.number.prefix — prepended during encode, required during decode (STDLIB-031-ABI-002).
    var numberPrefix: String
    /// HexFormat.number.suffix — appended during encode, required during decode (STDLIB-031-ABI-002).
    var numberSuffix: String
    /// HexFormat.number.removeLeadingZeros — strips leading zeros during encode (STDLIB-031-ABI-002).
    var removeLeadingZeros: Bool

    init(
        upperCase: Bool = false,
        byteSeparator: String = "",
        numberPrefix: String = "",
        numberSuffix: String = "",
        removeLeadingZeros: Bool = false
    ) {
        self.upperCase = upperCase
        self.byteSeparator = byteSeparator
        self.numberPrefix = numberPrefix
        self.numberSuffix = numberSuffix
        self.removeLeadingZeros = removeLeadingZeros
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

// MARK: - HexFormat.number.prefix / suffix setters (STDLIB-031-ABI-002)

/// Sets the number prefix on the given HexFormat box and returns the format raw value.
@_cdecl("kk_hexformat_prefix")
public func kk_hexformat_prefix(_ formatRaw: Int, _ prefixRaw: Int) -> Int {
    guard let format = hexFormatBoxFromRaw(formatRaw) else { return formatRaw }
    format.numberPrefix = hexFormatStringFromRaw(prefixRaw) ?? ""
    return formatRaw
}

/// Sets the number suffix on the given HexFormat box and returns the format raw value.
@_cdecl("kk_hexformat_suffix")
public func kk_hexformat_suffix(_ formatRaw: Int, _ suffixRaw: Int) -> Int {
    guard let format = hexFormatBoxFromRaw(formatRaw) else { return formatRaw }
    format.numberSuffix = hexFormatStringFromRaw(suffixRaw) ?? ""
    return formatRaw
}

// MARK: - Private encode helper

/// Applies prefix, case, removeLeadingZeros and suffix to a raw hex string.
private func hexFormatApplyNumberFormat(_ rawHex: String, format: RuntimeHexFormatBox?) -> String {
    var hex = rawHex
    if format?.removeLeadingZeros == true {
        let stripped = hex.drop(while: { $0 == "0" })
        hex = stripped.isEmpty ? "0" : String(stripped)
    }
    if format?.upperCase == true {
        hex = hex.uppercased()
    }
    let prefix = format?.numberPrefix ?? ""
    let suffix = format?.numberSuffix ?? ""
    return prefix + hex + suffix
}

// MARK: - Int.toHexString(format)

@_cdecl("kk_int_toHexString")
public func kk_int_toHexString(_ receiverRaw: Int, _ formatRaw: Int) -> Int {
    let format = hexFormatBoxFromRaw(formatRaw)
    // Kotlin: Int.toHexString() produces zero-padded 8-char two's-complement hex
    let unsigned = UInt32(bitPattern: Int32(truncatingIfNeeded: receiverRaw))
    let rawHex = String(format: "%08x", unsigned)
    let result = hexFormatApplyNumberFormat(rawHex, format: format)
    return hexFormatMakeStringRaw(result)
}

// MARK: - Long.toHexString(format)

@_cdecl("kk_long_toHexString")
public func kk_long_toHexString(_ receiverRaw: Int, _ formatRaw: Int) -> Int {
    // Int64.min == runtimeNullSentinelInt, so kk_box_long passes it through
    // unboxed and kk_unbox_long would return 0 (null-sentinel path).
    // Detect this case before unboxing and treat it as the actual Long.MIN_VALUE.
    let longValue: Int
    if receiverRaw == runtimeNullSentinelInt {
        longValue = Int.min
    } else {
        longValue = Int(kk_unbox_long(receiverRaw))
    }
    let format = hexFormatBoxFromRaw(formatRaw)
    let rawHex: String
    if longValue < 0 {
        // Kotlin: negative Long.toHexString produces 16-char two's-complement hex
        let unsigned = UInt64(bitPattern: Int64(longValue))
        rawHex = String(unsigned, radix: 16)
    } else {
        rawHex = String(longValue, radix: 16)
    }
    let result = hexFormatApplyNumberFormat(rawHex, format: format)
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

// MARK: - Private decode helper

/// Strips expected prefix and suffix from a hex string, throwing NumberFormatException if absent.
/// Returns the stripped hex digits (prefix/suffix removed) on success, or nil on failure.
private func hexFormatStripPrefixSuffix(
    _ str: String,
    format: RuntimeHexFormatBox?
) -> String? {
    let prefix = format?.numberPrefix ?? ""
    let suffix = format?.numberSuffix ?? ""

    var working = str

    if !prefix.isEmpty {
        guard working.hasPrefix(prefix) else { return nil }
        working = String(working.dropFirst(prefix.count))
    }

    if !suffix.isEmpty {
        guard working.hasSuffix(suffix) else { return nil }
        working = String(working.dropLast(suffix.count))
    }

    return working
}

// MARK: - String.hexToInt(format)

@_cdecl("kk_string_hexToInt")
public func kk_string_hexToInt(
    _ receiverRaw: Int,
    _ formatRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let str = hexFormatStringFromRaw(receiverRaw) ?? ""
    let format = hexFormatBoxFromRaw(formatRaw)
    guard let cleaned = hexFormatStripPrefixSuffix(str, format: format) else {
        let prefix = format?.numberPrefix ?? ""
        let suffix = format?.numberSuffix ?? ""
        let msg: String
        if !prefix.isEmpty && !str.hasPrefix(prefix) {
            msg = "NumberFormatException: For hex string \"\(str)\": missing required prefix \"\(prefix)\""
        } else {
            msg = "NumberFormatException: For hex string \"\(str)\": missing required suffix \"\(suffix)\""
        }
        outThrown?.pointee = runtimeAllocateThrowable(message: msg)
        return 0
    }
    guard let value = UInt32(cleaned, radix: 16) else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "NumberFormatException: For hex string \"\(cleaned)\": not valid hexadecimal"
        )
        return 0
    }
    return Int(Int32(bitPattern: value))
}

// MARK: - String.hexToLong(format)

@_cdecl("kk_string_hexToLong")
public func kk_string_hexToLong(
    _ receiverRaw: Int,
    _ formatRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let str = hexFormatStringFromRaw(receiverRaw) ?? ""
    let format = hexFormatBoxFromRaw(formatRaw)
    guard let cleaned = hexFormatStripPrefixSuffix(str, format: format) else {
        let prefix = format?.numberPrefix ?? ""
        let suffix = format?.numberSuffix ?? ""
        let msg: String
        if !prefix.isEmpty && !str.hasPrefix(prefix) {
            msg = "NumberFormatException: For hex string \"\(str)\": missing required prefix \"\(prefix)\""
        } else {
            msg = "NumberFormatException: For hex string \"\(str)\": missing required suffix \"\(suffix)\""
        }
        outThrown?.pointee = runtimeAllocateThrowable(message: msg)
        return kk_box_long(0)
    }
    guard let value = UInt64(cleaned, radix: 16) else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "NumberFormatException: For hex string \"\(cleaned)\": not valid hexadecimal"
        )
        return kk_box_long(0)
    }
    return kk_box_long(Int(Int64(bitPattern: value)))
}

// MARK: - String.hexToUInt(format)

@_cdecl("kk_string_hexToUInt")
public func kk_string_hexToUInt(
    _ receiverRaw: Int,
    _ formatRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let str = hexFormatStringFromRaw(receiverRaw) ?? ""
    let format = hexFormatBoxFromRaw(formatRaw)
    guard let cleaned = hexFormatStripPrefixSuffix(str, format: format) else {
        let prefix = format?.numberPrefix ?? ""
        let suffix = format?.numberSuffix ?? ""
        let msg: String
        if !prefix.isEmpty && !str.hasPrefix(prefix) {
            msg = "NumberFormatException: For hex string \"\(str)\": missing required prefix \"\(prefix)\""
        } else {
            msg = "NumberFormatException: For hex string \"\(str)\": missing required suffix \"\(suffix)\""
        }
        outThrown?.pointee = runtimeAllocateThrowable(message: msg)
        return 0
    }
    guard let value = UInt32(cleaned, radix: 16) else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "NumberFormatException: For hex string \"\(cleaned)\": not valid hexadecimal"
        )
        return 0
    }
    return Int(value)
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
