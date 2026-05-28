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

// MARK: - STDLIB-IO-ENC-FN-002: OutputStream.encodingWith(base64)

/// Pure-Swift Base64 alphabet tables for streaming encoding.  Mirrors
/// `decodeBase64String`'s alphabet handling so encoded writes stay in sync
/// with one-shot `Base64.encode(...)` results.
private let standardBase64Alphabet: [UInt8] = Array(
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".utf8
)
private let urlSafeBase64Alphabet: [UInt8] = Array(
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_".utf8
)

/// Returns the alphabet table corresponding to a `Base64RuntimeVariant`.
private func base64AlphabetTable(for variant: Base64RuntimeVariant) -> [UInt8] {
    switch variant {
    case .standard, .mime: standardBase64Alphabet
    case .urlSafe: urlSafeBase64Alphabet
    }
}

/// Sink that incrementally Base64-encodes written bytes and forwards the
/// encoded text to a wrapped `RuntimeOutputStreamBox`.  Used by
/// `OutputStream.encodingWith(base64)` (STDLIB-IO-ENC-FN-002).
private final class RuntimeBase64EncodingOutputStreamSink: RuntimeOutputStreamSink {
    private let downstream: RuntimeOutputStreamBox
    private let variant: Base64RuntimeVariant
    private let paddingOption: Base64PaddingOption
    /// Buffer of unwritten input bytes (always < 3 bytes at rest).
    private var pending: [UInt8]
    /// Column in the current MIME line, used to insert CRLF every 76 chars.
    private var mimeColumn: Int
    private var closed: Bool

    init(downstream: RuntimeOutputStreamBox, variant: Base64RuntimeVariant, paddingOption: Base64PaddingOption) {
        self.downstream = downstream
        self.variant = variant
        self.paddingOption = paddingOption
        self.pending = []
        self.mimeColumn = 0
        self.closed = false
    }

    func write(_ data: Data) throws {
        guard !closed else { return }
        guard !data.isEmpty else { return }
        var buffer = pending + Array(data)
        let completeGroups = buffer.count / 3
        let consumable = completeGroups * 3
        if consumable > 0 {
            let encoded = encodeFullGroups(Array(buffer.prefix(consumable)))
            try writeEncoded(encoded)
        }
        pending = Array(buffer.suffix(buffer.count - consumable))
        buffer.removeAll(keepingCapacity: false)
    }

    func flush() throws {
        guard !closed else { return }
        try downstream.flush()
    }

    func close() {
        guard !closed else { return }
        // Encode any trailing partial group with padding before forwarding close.
        if !pending.isEmpty {
            let tail = encodeTail(pending)
            try? writeEncoded(tail)
        }
        pending.removeAll(keepingCapacity: false)
        downstream.close()
        closed = true
    }

    /// Encodes whole 3-byte groups using the configured alphabet.  Always
    /// produces `(bytes.count / 3) * 4` output characters (no padding).
    private func encodeFullGroups(_ bytes: [UInt8]) -> [UInt8] {
        let alphabet = base64AlphabetTable(for: variant)
        var out: [UInt8] = []
        out.reserveCapacity((bytes.count / 3) * 4)
        var index = 0
        while index + 3 <= bytes.count {
            let b0 = bytes[index]
            let b1 = bytes[index + 1]
            let b2 = bytes[index + 2]
            out.append(alphabet[Int(b0 >> 2)])
            out.append(alphabet[Int(((b0 & 0x03) << 4) | (b1 >> 4))])
            out.append(alphabet[Int(((b1 & 0x0F) << 2) | (b2 >> 6))])
            out.append(alphabet[Int(b2 & 0x3F)])
            index += 3
        }
        return out
    }

    /// Encodes a trailing 1- or 2-byte partial group, applying padding per
    /// the configured `paddingOption`.
    private func encodeTail(_ tail: [UInt8]) -> [UInt8] {
        let alphabet = base64AlphabetTable(for: variant)
        var out: [UInt8] = []
        if tail.count == 1 {
            let b0 = tail[0]
            out.append(alphabet[Int(b0 >> 2)])
            out.append(alphabet[Int((b0 & 0x03) << 4)])
            switch paddingOption {
            case .present, .presentOptional:
                out.append(UInt8(ascii: "="))
                out.append(UInt8(ascii: "="))
            case .absent, .absentOptional:
                break
            }
        } else if tail.count == 2 {
            let b0 = tail[0]
            let b1 = tail[1]
            out.append(alphabet[Int(b0 >> 2)])
            out.append(alphabet[Int(((b0 & 0x03) << 4) | (b1 >> 4))])
            out.append(alphabet[Int((b1 & 0x0F) << 2)])
            switch paddingOption {
            case .present, .presentOptional:
                out.append(UInt8(ascii: "="))
            case .absent, .absentOptional:
                break
            }
        }
        return out
    }

    /// Forwards already-encoded ASCII bytes to the downstream stream,
    /// inserting CRLF every 76 chars for the MIME variant.
    private func writeEncoded(_ encoded: [UInt8]) throws {
        guard !encoded.isEmpty else { return }
        if variant != .mime {
            try downstream.writeBytes(encoded.map { Int($0) })
            return
        }
        // MIME: maintain a running column so CRLF gets inserted every 76 chars.
        var index = 0
        while index < encoded.count {
            let remainingInLine = mimeLineLength - mimeColumn
            if remainingInLine <= 0 {
                try downstream.writeBytes(Array(mimeCRLF.utf8).map { Int($0) })
                mimeColumn = 0
                continue
            }
            let take = min(remainingInLine, encoded.count - index)
            let chunk = Array(encoded[index ..< index + take])
            try downstream.writeBytes(chunk.map { Int($0) })
            mimeColumn += take
            index += take
        }
    }
}

/// Looks up a `RuntimeOutputStreamBox` from a raw handle (file-local helper
/// matching the one in `RuntimeFileIO.swift`).
private func base64OutputStreamBox(from raw: Int) -> RuntimeOutputStreamBox? {
    if raw == runtimeNullSentinelInt { return nil }
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeOutputStreamBox.self)
}

/// `kotlin.io.encoding.encodingWith(base64: Base64): OutputStream` extension
/// on `java.io.OutputStream` (STDLIB-IO-ENC-FN-002).
///
/// JVM semantics: returns a new `OutputStream` that encodes bytes using the
/// supplied `Base64` instance and forwards the encoded text to this stream.
/// `close()` on the returned stream finalises the trailing partial group
/// (applying padding per the `Base64` instance's `PaddingOption`) and then
/// closes the underlying stream.
@_cdecl("kk_output_stream_encodingWith")
public func kk_output_stream_encodingWith(_ streamRaw: Int, _ base64Raw: Int) -> Int {
    guard let downstream = base64OutputStreamBox(from: streamRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_output_stream_encodingWith received invalid OutputStream handle")
    }
    let box = base64BoxOrDefault(from: base64Raw)
    let sink = RuntimeBase64EncodingOutputStreamSink(
        downstream: downstream,
        variant: box.variant,
        paddingOption: box.paddingOption
    )
    return registerRuntimeObject(RuntimeOutputStreamBox(sink: sink))
}
