import Foundation

// MARK: - Base64 Runtime (STDLIB-031-ABI-001)

/// Mirrors kotlin.io.encoding.Base64.PaddingOption
/// Raw values must match the constants used by lowering stubs.
enum Base64PaddingOption: Int {
    /// Padding is mandatory (RFC 4648 §3.2). Decode rejects absent padding.
    case present = 0
    /// Padding is omitted. Decode rejects present padding.
    case absent = 1
    /// Padding is present in output. Decode accepts both padded and unpadded input.
    case presentOptional = 2
    /// Padding is absent in output. Decode accepts both padded and unpadded input.
    case absentOptional = 3
}

// MARK: - Private Helpers

/// Converts a PaddingOption raw Int to the enum, defaulting to .present.
private func paddingOption(from raw: Int) -> Base64PaddingOption {
    Base64PaddingOption(rawValue: raw) ?? .present
}

/// Extracts a Swift String from a runtime raw Int.
private func base64StringFromRaw(_ raw: Int) -> String? {
    if raw == runtimeNullSentinelInt { return nil }
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return extractString(from: ptr)
}

/// Wraps a Swift String into a runtime raw Int.
private func base64MakeStringRaw(_ value: String) -> Int {
    Int(bitPattern: value.withCString { cstr in
        cstr.withMemoryRebound(to: UInt8.self, capacity: value.utf8.count) { ptr in
            kk_string_from_utf8(ptr, Int32(value.utf8.count))
        }
    })
}

/// Wraps a [UInt8] byte sequence into a runtime ByteArray (RuntimeListBox).
private func base64MakeByteArrayRaw(_ bytes: [UInt8]) -> Int {
    // Kotlin ByteArray elements are signed (Int8 bit-pattern stored as Int)
    let intElements = bytes.map { Int(Int8(bitPattern: $0)) }
    return registerRuntimeObject(RuntimeListBox(elements: intElements))
}

/// Extracts a [UInt8] from a runtime ByteArray / List raw Int.
private func base64BytesFromRaw(_ raw: Int) -> [UInt8]? {
    if raw == runtimeNullSentinelInt { return nil }
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw),
          let box = tryCast(ptr, to: RuntimeListBox.self) else { return nil }
    return box.elements.map { UInt8(truncatingIfNeeded: $0) }
}

/// Strips padding characters from a base64 string.
private func stripPadding(_ s: String) -> String {
    s.replacingOccurrences(of: "=", with: "")
}

/// Adds padding to bring length to next multiple of 4.
private func addPadding(_ s: String) -> String {
    let rem = s.count % 4
    guard rem != 0 else { return s }
    return s + String(repeating: "=", with: 4 - rem)
}

extension String {
    fileprivate init(repeating scalar: Character, with count: Int) {
        self = String(repeating: scalar, count: count)
    }
}

/// Validates that no padding characters appear in the string.
private func containsPadding(_ s: String) -> Bool {
    s.contains("=")
}

// MARK: - PaddingOption constant ABI entry points

@_cdecl("kk_base64_padding_present")
public func kk_base64_padding_present() -> Int { Base64PaddingOption.present.rawValue }

@_cdecl("kk_base64_padding_absent")
public func kk_base64_padding_absent() -> Int { Base64PaddingOption.absent.rawValue }

@_cdecl("kk_base64_padding_present_optional")
public func kk_base64_padding_present_optional() -> Int { Base64PaddingOption.presentOptional.rawValue }

@_cdecl("kk_base64_padding_absent_optional")
public func kk_base64_padding_absent_optional() -> Int { Base64PaddingOption.absentOptional.rawValue }

// MARK: - Default (RFC 4648 §4) Alphabet  `+/`

@_cdecl("kk_base64_encode_default")
public func kk_base64_encode_default(_ bytesRaw: Int, _ paddingOptionRaw: Int) -> Int {
    guard let bytes = base64BytesFromRaw(bytesRaw) else {
        return base64MakeStringRaw("")
    }
    let option = paddingOption(from: paddingOptionRaw)
    var result = Data(bytes).base64EncodedString()
    switch option {
    case .present, .presentOptional:
        break // Foundation always pads
    case .absent, .absentOptional:
        result = stripPadding(result)
    }
    return base64MakeStringRaw(result)
}

@_cdecl("kk_base64_decode_default")
public func kk_base64_decode_default(
    _ strRaw: Int,
    _ paddingOptionRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let input = base64StringFromRaw(strRaw) else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "Invalid base64 string: null input")
        return runtimeNullSentinelInt
    }
    let option = paddingOption(from: paddingOptionRaw)
    return decodeBase64String(input, option: option, alphabet: .standard, outThrown: outThrown)
}

// MARK: - URL-safe (RFC 4648 §5) Alphabet `-_`

@_cdecl("kk_base64_encode_urlsafe")
public func kk_base64_encode_urlsafe(_ bytesRaw: Int, _ paddingOptionRaw: Int) -> Int {
    guard let bytes = base64BytesFromRaw(bytesRaw) else {
        return base64MakeStringRaw("")
    }
    let option = paddingOption(from: paddingOptionRaw)
    // Foundation uses standard alphabet; swap + → - and / → _
    var result = Data(bytes).base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
    // URL-safe default: no padding (Kotlin default is ABSENT for UrlSafe)
    switch option {
    case .present, .presentOptional:
        break
    case .absent, .absentOptional:
        result = stripPadding(result)
    }
    return base64MakeStringRaw(result)
}

@_cdecl("kk_base64_decode_urlsafe")
public func kk_base64_decode_urlsafe(
    _ strRaw: Int,
    _ paddingOptionRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let input = base64StringFromRaw(strRaw) else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "Invalid base64 string: null input")
        return runtimeNullSentinelInt
    }
    let option = paddingOption(from: paddingOptionRaw)
    return decodeBase64String(input, option: option, alphabet: .urlSafe, outThrown: outThrown)
}

// MARK: - MIME (RFC 2045) Alphabet `+/`, CRLF every 76 chars

private let mimeLineLength = 76
private let mimeCRLF = "\r\n"

@_cdecl("kk_base64_encode_mime")
public func kk_base64_encode_mime(_ bytesRaw: Int, _ paddingOptionRaw: Int) -> Int {
    guard let bytes = base64BytesFromRaw(bytesRaw) else {
        return base64MakeStringRaw("")
    }
    let option = paddingOption(from: paddingOptionRaw)
    // Foundation: standard alphabet, padded by default
    var base = Data(bytes).base64EncodedString()
    switch option {
    case .present, .presentOptional:
        break
    case .absent, .absentOptional:
        base = stripPadding(base)
    }
    // Insert CRLF every 76 characters
    var result = ""
    var index = base.startIndex
    while index < base.endIndex {
        let end = base.index(index, offsetBy: mimeLineLength, limitedBy: base.endIndex) ?? base.endIndex
        if !result.isEmpty { result += mimeCRLF }
        result += base[index ..< end]
        index = end
    }
    return base64MakeStringRaw(result)
}

@_cdecl("kk_base64_decode_mime")
public func kk_base64_decode_mime(
    _ strRaw: Int,
    _ paddingOptionRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let input = base64StringFromRaw(strRaw) else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "Invalid base64 string: null input")
        return runtimeNullSentinelInt
    }
    // MIME tolerates whitespace — strip CR/LF/spaces before decoding
    let sanitized = input
        .replacingOccurrences(of: "\r\n", with: "")
        .replacingOccurrences(of: "\r", with: "")
        .replacingOccurrences(of: "\n", with: "")
        .replacingOccurrences(of: " ", with: "")
        .replacingOccurrences(of: "\t", with: "")
    let option = paddingOption(from: paddingOptionRaw)
    return decodeBase64String(sanitized, option: option, alphabet: .standard, outThrown: outThrown)
}

// MARK: - encodeToByteArray variants (output is ByteArray, not String)

@_cdecl("kk_base64_encodeToByteArray_default")
public func kk_base64_encodeToByteArray_default(_ bytesRaw: Int, _ paddingOptionRaw: Int) -> Int {
    let strRaw = kk_base64_encode_default(bytesRaw, paddingOptionRaw)
    guard let str = base64StringFromRaw(strRaw) else { return registerRuntimeObject(RuntimeListBox(elements: [])) }
    return base64MakeByteArrayRaw(Array(str.utf8))
}

@_cdecl("kk_base64_encodeToByteArray_urlsafe")
public func kk_base64_encodeToByteArray_urlsafe(_ bytesRaw: Int, _ paddingOptionRaw: Int) -> Int {
    let strRaw = kk_base64_encode_urlsafe(bytesRaw, paddingOptionRaw)
    guard let str = base64StringFromRaw(strRaw) else { return registerRuntimeObject(RuntimeListBox(elements: [])) }
    return base64MakeByteArrayRaw(Array(str.utf8))
}

@_cdecl("kk_base64_encodeToByteArray_mime")
public func kk_base64_encodeToByteArray_mime(_ bytesRaw: Int, _ paddingOptionRaw: Int) -> Int {
    let strRaw = kk_base64_encode_mime(bytesRaw, paddingOptionRaw)
    guard let str = base64StringFromRaw(strRaw) else { return registerRuntimeObject(RuntimeListBox(elements: [])) }
    return base64MakeByteArrayRaw(Array(str.utf8))
}

// MARK: - Shared Decode Implementation

private enum Base64Alphabet {
    case standard   // +/
    case urlSafe    // -_
}

private func decodeBase64String(
    _ input: String,
    option: Base64PaddingOption,
    alphabet: Base64Alphabet,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    // Validate padding presence against option
    let hasPadding = containsPadding(input)
    switch option {
    case .present:
        // Padding must be present (and Foundation requires it)
        if !hasPadding {
            // Try to pad and decode, but reject if original had no padding and
            // length is not a multiple of 4 (indicating missing pad)
            let rem = input.count % 4
            if rem != 0 {
                outThrown?.pointee = runtimeAllocateIllegalArgumentException(
                    message: "Missing base64 padding")
                return runtimeNullSentinelInt
            }
        }
    case .absent:
        if hasPadding {
            outThrown?.pointee = runtimeAllocateIllegalArgumentException(
                message: "Unexpected base64 padding in ABSENT mode")
            return runtimeNullSentinelInt
        }
    case .presentOptional, .absentOptional:
        break // Accept either form
    }

    // URL-safe alphabet rejects standard `+/` (RFC 4648 §5); do not normalise them away.
    if alphabet == .urlSafe, input.contains("+") || input.contains("/") {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "Illegal base64 character in URL-safe input")
        return runtimeNullSentinelInt
    }

    // Normalise: for URL-safe, swap - → + and _ → /
    var normalised = input
    if alphabet == .urlSafe {
        normalised = normalised
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
    }

    // Foundation requires padding; add it if missing
    let padded = addPadding(normalised)

    guard let data = Data(base64Encoded: padded) else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "Illegal base64 character in input: \"\(input)\"")
        return runtimeNullSentinelInt
    }
    return base64MakeByteArrayRaw(Array(data))
}
