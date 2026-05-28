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

private enum Base64RuntimeVariant {
    case standard
    case urlSafe
    case mime
}

private final class RuntimeBase64Box {
    let variant: Base64RuntimeVariant
    let paddingOption: Base64PaddingOption

    init(variant: Base64RuntimeVariant, paddingOption: Base64PaddingOption) {
        self.variant = variant
        self.paddingOption = paddingOption
    }
}

// MARK: - Private Helpers

/// Converts a PaddingOption raw Int to the enum, defaulting to .present.
private func paddingOption(from raw: Int) -> Base64PaddingOption {
    Base64PaddingOption(rawValue: raw) ?? .present
}

private func registerBase64Box(variant: Base64RuntimeVariant, paddingOptionRaw: Int) -> Int {
    registerRuntimeObject(RuntimeBase64Box(
        variant: variant,
        paddingOption: paddingOption(from: paddingOptionRaw)
    ))
}

private func base64Box(from raw: Int) -> RuntimeBase64Box? {
    if raw == runtimeNullSentinelInt { return nil }
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeBase64Box.self)
}

private func base64BoxOrDefault(from raw: Int) -> RuntimeBase64Box {
    base64Box(from: raw) ?? RuntimeBase64Box(variant: .standard, paddingOption: .present)
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
    return s + String(repeating: "=", count: 4 - rem)
}

private let mimeBase64ScalarSet = CharacterSet(
    charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/="
)

/// MIME decoders ignore every character outside the Base64 alphabet (RFC 2045).
private func mimeFilterBase64Alphabet(_ s: String) -> String {
    String(s.unicodeScalars.filter { mimeBase64ScalarSet.contains($0) })
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

// MARK: - Configured Base64 instances

@_cdecl("kk_base64_withPadding_default")
public func kk_base64_withPadding_default(_ paddingOptionRaw: Int) -> Int {
    registerBase64Box(variant: .standard, paddingOptionRaw: paddingOptionRaw)
}

@_cdecl("kk_base64_withPadding_urlsafe")
public func kk_base64_withPadding_urlsafe(_ paddingOptionRaw: Int) -> Int {
    registerBase64Box(variant: .urlSafe, paddingOptionRaw: paddingOptionRaw)
}

@_cdecl("kk_base64_withPadding_mime")
public func kk_base64_withPadding_mime(_ paddingOptionRaw: Int) -> Int {
    registerBase64Box(variant: .mime, paddingOptionRaw: paddingOptionRaw)
}

@_cdecl("kk_base64_withPadding_instance")
public func kk_base64_withPadding_instance(_ instanceRaw: Int, _ paddingOptionRaw: Int) -> Int {
    let existing = base64BoxOrDefault(from: instanceRaw)
    return registerBase64Box(variant: existing.variant, paddingOptionRaw: paddingOptionRaw)
}

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
    // Predefined UrlSafe uses PRESENT padding; custom instances choose via option.
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
    // MIME: ignore all non-alphabet characters (whitespace, control chars, etc.).
    let sanitized = mimeFilterBase64Alphabet(input)
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

// MARK: - decodeFromByteArray variants (input is ASCII ByteArray)

private func base64StringRawFromByteArray(
    _ bytesRaw: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let bytes = base64BytesFromRaw(bytesRaw),
          let string = String(bytes: bytes, encoding: .utf8)
    else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "Invalid base64 byte array")
        return runtimeNullSentinelInt
    }
    return base64MakeStringRaw(string)
}

@_cdecl("kk_base64_decodeFromByteArray_default")
public func kk_base64_decodeFromByteArray_default(
    _ bytesRaw: Int,
    _ paddingOptionRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let strRaw = base64StringRawFromByteArray(bytesRaw, outThrown: outThrown)
    if let outThrown, outThrown.pointee != 0 {
        return runtimeNullSentinelInt
    }
    return kk_base64_decode_default(strRaw, paddingOptionRaw, outThrown)
}

@_cdecl("kk_base64_decodeFromByteArray_urlsafe")
public func kk_base64_decodeFromByteArray_urlsafe(
    _ bytesRaw: Int,
    _ paddingOptionRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let strRaw = base64StringRawFromByteArray(bytesRaw, outThrown: outThrown)
    if let outThrown, outThrown.pointee != 0 {
        return runtimeNullSentinelInt
    }
    return kk_base64_decode_urlsafe(strRaw, paddingOptionRaw, outThrown)
}

@_cdecl("kk_base64_decodeFromByteArray_mime")
public func kk_base64_decodeFromByteArray_mime(
    _ bytesRaw: Int,
    _ paddingOptionRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let strRaw = base64StringRawFromByteArray(bytesRaw, outThrown: outThrown)
    if let outThrown, outThrown.pointee != 0 {
        return runtimeNullSentinelInt
    }
    return kk_base64_decode_mime(strRaw, paddingOptionRaw, outThrown)
}

// MARK: - Configured instance dispatch

@_cdecl("kk_base64_encode_instance")
public func kk_base64_encode_instance(_ instanceRaw: Int, _ bytesRaw: Int) -> Int {
    let box = base64BoxOrDefault(from: instanceRaw)
    switch box.variant {
    case .standard:
        return kk_base64_encode_default(bytesRaw, box.paddingOption.rawValue)
    case .urlSafe:
        return kk_base64_encode_urlsafe(bytesRaw, box.paddingOption.rawValue)
    case .mime:
        return kk_base64_encode_mime(bytesRaw, box.paddingOption.rawValue)
    }
}

@_cdecl("kk_base64_decode_instance")
public func kk_base64_decode_instance(
    _ instanceRaw: Int,
    _ strRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let box = base64BoxOrDefault(from: instanceRaw)
    switch box.variant {
    case .standard:
        return kk_base64_decode_default(strRaw, box.paddingOption.rawValue, outThrown)
    case .urlSafe:
        return kk_base64_decode_urlsafe(strRaw, box.paddingOption.rawValue, outThrown)
    case .mime:
        return kk_base64_decode_mime(strRaw, box.paddingOption.rawValue, outThrown)
    }
}

@_cdecl("kk_base64_encodeToByteArray_instance")
public func kk_base64_encodeToByteArray_instance(_ instanceRaw: Int, _ bytesRaw: Int) -> Int {
    let box = base64BoxOrDefault(from: instanceRaw)
    switch box.variant {
    case .standard:
        return kk_base64_encodeToByteArray_default(bytesRaw, box.paddingOption.rawValue)
    case .urlSafe:
        return kk_base64_encodeToByteArray_urlsafe(bytesRaw, box.paddingOption.rawValue)
    case .mime:
        return kk_base64_encodeToByteArray_mime(bytesRaw, box.paddingOption.rawValue)
    }
}

@_cdecl("kk_base64_decodeFromByteArray_instance")
public func kk_base64_decodeFromByteArray_instance(
    _ instanceRaw: Int,
    _ bytesRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let box = base64BoxOrDefault(from: instanceRaw)
    switch box.variant {
    case .standard:
        return kk_base64_decodeFromByteArray_default(bytesRaw, box.paddingOption.rawValue, outThrown)
    case .urlSafe:
        return kk_base64_decodeFromByteArray_urlsafe(bytesRaw, box.paddingOption.rawValue, outThrown)
    case .mime:
        return kk_base64_decodeFromByteArray_mime(bytesRaw, box.paddingOption.rawValue, outThrown)
    }
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
        let len = input.count
        let prefix = String(input.prefix(24))
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "Illegal base64 character in input (length=\(len), prefix=\(prefix))"
        )
        return runtimeNullSentinelInt
    }
    return base64MakeByteArrayRaw(Array(data))
}

// MARK: - STDLIB-IO-ENC-FN-001: InputStream.decodingWith(base64)

/// Casts a raw Int handle to a `RuntimeInputStreamBox`, or returns nil when the
/// raw value does not encode a live stream box.  Local to RuntimeBase64.swift
/// so this file does not depend on internals of `RuntimeFileIO.swift`.
private func base64InputStreamBox(from raw: Int) -> RuntimeInputStreamBox? {
    if raw == runtimeNullSentinelInt { return nil }
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeInputStreamBox.self)
}

/// Drains all remaining bytes from an `InputStream` into a Swift `Data`.
/// Uses the public `readByte()` accessor to avoid touching private storage.
private func drainInputStream(_ stream: RuntimeInputStreamBox) -> Data {
    var bytes = Data()
    while true {
        let byte = stream.readByte()
        if byte == -1 { break }
        bytes.append(UInt8(truncatingIfNeeded: byte))
    }
    return bytes
}

/// Decodes a buffer of Base64-encoded bytes according to the provided
/// `Base64` runtime configuration (variant + padding option).  Used by
/// `kk_input_stream_decodingWith` to lazily resolve a stream's contents.
private func decodeBase64Bytes(
    _ bytes: Data,
    variant: Base64RuntimeVariant,
    paddingOption: Base64PaddingOption
) -> Data {
    // The input is Base64 text encoded as bytes (typically ASCII).
    guard let text = String(data: bytes, encoding: .utf8) else {
        return Data()
    }
    let sanitized: String
    let alphabet: Base64Alphabet
    switch variant {
    case .standard:
        sanitized = text
        alphabet = .standard
    case .urlSafe:
        sanitized = text
        alphabet = .urlSafe
    case .mime:
        // MIME ignores non-alphabet characters during decoding (RFC 2045).
        sanitized = mimeFilterBase64Alphabet(text)
        alphabet = .standard
    }

    // Normalise URL-safe alphabet → standard before handing to Foundation.
    var normalised = sanitized
    if alphabet == .urlSafe {
        normalised = normalised
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
    }

    // For PaddingOption.absent, leave the data unpadded; Foundation requires
    // padding, so we always pad before decoding here.  The `decodingWith`
    // surface does not validate padding errors — it follows JVM semantics of
    // surfacing IOException on read, which is not modelled in the MVP.
    _ = paddingOption
    let padded = addPadding(normalised)
    return Data(base64Encoded: padded) ?? Data()
}

/// `kotlin.io.encoding.decodingWith(base64: Base64): InputStream` extension
/// on `java.io.InputStream`.  Returns a new `InputStream` whose readable bytes
/// are the Base64-decoded form of the underlying stream's bytes.
///
/// MVP semantics: eagerly drain the source stream, decode, and return a
/// fresh `RuntimeInputStreamBox` over the decoded bytes.  Matches JVM
/// behaviour for the common "decode then consume" flow.  An invalid Base64
/// payload yields an empty stream rather than a runtime exception so that
/// the synthetic ABI stays infallible (the throwing path is reserved for
/// future work alongside MIME line-handling refinements).
@_cdecl("kk_input_stream_decodingWith")
public func kk_input_stream_decodingWith(_ streamRaw: Int, _ base64Raw: Int) -> Int {
    let box = base64BoxOrDefault(from: base64Raw)
    guard let source = base64InputStreamBox(from: streamRaw) else {
        return registerRuntimeObject(RuntimeInputStreamBox(data: Data()))
    }
    let raw = drainInputStream(source)
    let decoded = decodeBase64Bytes(
        raw,
        variant: box.variant,
        paddingOption: box.paddingOption
    )
    return registerRuntimeObject(RuntimeInputStreamBox(data: decoded))
}
