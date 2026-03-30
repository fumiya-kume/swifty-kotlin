#if canImport(CryptoKit)
import Foundation
import CryptoKit

final class RuntimeMessageDigestBox {
    let algorithm: String

    init(algorithm: String) {
        self.algorithm = algorithm
    }
}

private func runtimeMessageDigestBox(from raw: Int) -> RuntimeMessageDigestBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeMessageDigestBox.self)
}

private func securityString(from raw: Int, caller: StaticString) -> String {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw),
          let value = extractString(from: ptr)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: \(caller) received invalid string handle")
    }
    return value
}

private func bytesFromListRaw(_ raw: Int) -> [UInt8]? {
    guard let list = runtimeListBox(from: raw) else { return nil }
    return list.elements.map { UInt8(truncatingIfNeeded: $0) }
}

@_cdecl("kk_message_digest_getInstance")
public func kk_message_digest_getInstance(_ algorithmRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let algorithm = securityString(from: algorithmRaw, caller: #function).uppercased()
    let supported = ["MD5", "SHA-1", "SHA-256", "SHA-512"]
    guard supported.contains(algorithm) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "NoSuchAlgorithmException: \(algorithm)")
        return 0
    }
    return registerRuntimeObject(RuntimeMessageDigestBox(algorithm: algorithm))
}

@_cdecl("kk_message_digest_digest")
public func kk_message_digest_digest(_ digestRaw: Int, _ dataRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let digest = runtimeMessageDigestBox(from: digestRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_message_digest_digest received invalid MessageDigest handle")
    }
    guard let bytes = bytesFromListRaw(dataRaw) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IllegalArgumentException: expected ByteArray/List<Int>")
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    let output: [UInt8]
    switch digest.algorithm {
    case "MD5":
        output = Array(Insecure.MD5.hash(data: Data(bytes)))
    case "SHA-1":
        output = Array(Insecure.SHA1.hash(data: Data(bytes)))
    case "SHA-256":
        output = Array(SHA256.hash(data: Data(bytes)))
    case "SHA-512":
        output = Array(SHA512.hash(data: Data(bytes)))
    default:
        output = []
    }
    return registerRuntimeObject(RuntimeListBox(elements: output.map { Int(Int8(bitPattern: $0)) }))
}
#else
// MARK: - Platform stubs: CryptoKit not available on Linux

@_cdecl("kk_message_digest_getInstance")
public func kk_message_digest_getInstance(_ algorithmRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = runtimeAllocateThrowable(message: "UnsupportedOperationException: MessageDigest not available on this platform")
    return 0
}

@_cdecl("kk_message_digest_digest")
public func kk_message_digest_digest(_ digestRaw: Int, _ dataRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = runtimeAllocateThrowable(message: "UnsupportedOperationException: MessageDigest not available on this platform")
    return 0
}
#endif

#if canImport(CommonCrypto)
import CommonCrypto
import Foundation

// MARK: - Symmetric Crypto Runtime Support (STDLIB-SEC-144)

enum RuntimeCipherAlgorithm: String {
    case aes = "AES"
    case des = "DES"
    case desede = "DESEDE"

    init?(transformationComponent rawValue: String) {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "AES":
            self = .aes
        case "DES":
            self = .des
        case "DESEDE", "TRIPLEDES", "3DES":
            self = .desede
        default:
            return nil
        }
    }

    var ccAlgorithm: CCAlgorithm {
        switch self {
        case .aes:
            CCAlgorithm(kCCAlgorithmAES128)
        case .des:
            CCAlgorithm(kCCAlgorithmDES)
        case .desede:
            CCAlgorithm(kCCAlgorithm3DES)
        }
    }

    var blockSize: Int {
        switch self {
        case .aes:
            kCCBlockSizeAES128
        case .des, .desede:
            kCCBlockSizeDES
        }
    }

    var acceptedKeyLengths: Set<Int> {
        switch self {
        case .aes:
            [kCCKeySizeAES128, kCCKeySizeAES192, kCCKeySizeAES256]
        case .des:
            [kCCKeySizeDES]
        case .desede:
            [kCCKeySize3DES]
        }
    }

    var displayName: String {
        switch self {
        case .aes:
            "AES"
        case .des:
            "DES"
        case .desede:
            "DESede"
        }
    }
}

enum RuntimeCipherMode: String {
    case ecb = "ECB"
    case cbc = "CBC"
    case cfb = "CFB"
    case ofb = "OFB"
    case ctr = "CTR"

    init?(transformationComponent rawValue: String) {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "ECB":
            self = .ecb
        case "CBC":
            self = .cbc
        case "CFB":
            self = .cfb
        case "OFB":
            self = .ofb
        case "CTR":
            self = .ctr
        default:
            return nil
        }
    }

    var ccMode: CCMode {
        switch self {
        case .ecb:
            CCMode(1)
        case .cbc:
            CCMode(2)
        case .cfb:
            CCMode(3)
        case .ctr:
            CCMode(4)
        case .ofb:
            CCMode(7)
        }
    }

    var requiresIV: Bool {
        self != .ecb
    }
}

enum RuntimeCipherPadding: String {
    case pkcs5 = "PKCS5PADDING"
    case pkcs7 = "PKCS7PADDING"
    case none = "NOPADDING"

    init?(transformationComponent rawValue: String) {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "PKCS5PADDING", "PKCS7PADDING":
            self = .pkcs5
        case "NOPADDING":
            self = .none
        default:
            return nil
        }
    }

    var ccPadding: CCPadding {
        switch self {
        case .none:
            CCPadding(ccNoPadding)
        case .pkcs5, .pkcs7:
            CCPadding(ccPKCS7Padding)
        }
    }
}

final class RuntimeSecretKeySpecBox {
    let keyBytes: [UInt8]
    let algorithm: RuntimeCipherAlgorithm

    init(keyBytes: [UInt8], algorithm: RuntimeCipherAlgorithm) {
        self.keyBytes = keyBytes
        self.algorithm = algorithm
    }
}

final class RuntimeIvParameterSpecBox {
    let ivBytes: [UInt8]

    init(ivBytes: [UInt8]) {
        self.ivBytes = ivBytes
    }
}

final class RuntimeCipherBox {
    let transformation: String
    let algorithm: RuntimeCipherAlgorithm
    let mode: RuntimeCipherMode
    let padding: RuntimeCipherPadding
    var operation: CCOperation?
    var keyBytes: [UInt8]?
    var ivBytes: [UInt8]?

    init(transformation: String, algorithm: RuntimeCipherAlgorithm, mode: RuntimeCipherMode, padding: RuntimeCipherPadding) {
        self.transformation = transformation
        self.algorithm = algorithm
        self.mode = mode
        self.padding = padding
    }
}

private func runtimeCipherBox(from raw: Int) -> RuntimeCipherBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
        return nil
    }
    return tryCast(ptr, to: RuntimeCipherBox.self)
}

private func runtimeSetThrown(_ outThrown: UnsafeMutablePointer<Int>?, message: String) {
    runtimeSetThrown(outThrown, runtimeAllocateThrowable(message: message))
}

private func runtimeSecretKeySpecBox(from raw: Int) -> RuntimeSecretKeySpecBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
        return nil
    }
    return tryCast(ptr, to: RuntimeSecretKeySpecBox.self)
}

private func runtimeIvParameterSpecBox(from raw: Int) -> RuntimeIvParameterSpecBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
        return nil
    }
    return tryCast(ptr, to: RuntimeIvParameterSpecBox.self)
}

private func runtimeSecurityString(from raw: Int, caller: StaticString) -> String {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw),
          let value = extractString(from: ptr)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: \(caller) received invalid string handle")
    }
    return value
}

private func runtimeSecurityBytes(from raw: Int, caller: StaticString) -> [UInt8]? {
    guard let box = runtimeArrayBox(from: raw) else {
        return nil
    }
    return box.elements.map { UInt8(truncatingIfNeeded: $0) }
}

private func runtimeMakeByteArrayRaw(_ bytes: [UInt8]) -> Int {
    let box = RuntimeArrayBox(length: bytes.count)
    for (index, byte) in bytes.enumerated() {
        box.elements[index] = Int(Int8(bitPattern: byte))
    }
    return registerRuntimeObject(box)
}

private func runtimeCipherParseTransformation(_ transformation: String) -> (RuntimeCipherAlgorithm, RuntimeCipherMode, RuntimeCipherPadding)? {
    let parts = transformation
        .split(separator: "/")
        .map { String($0) }

    guard !parts.isEmpty, parts.count <= 3 else {
        return nil
    }

    guard let algorithm = RuntimeCipherAlgorithm(transformationComponent: parts[0]) else {
        return nil
    }
    let mode: RuntimeCipherMode
    if parts.count >= 2 {
        guard let parsedMode = RuntimeCipherMode(transformationComponent: parts[1]) else {
            return nil
        }
        mode = parsedMode
    } else {
        mode = .ecb
    }

    let padding: RuntimeCipherPadding
    if parts.count == 3 {
        guard let parsedPadding = RuntimeCipherPadding(transformationComponent: parts[2]) else {
            return nil
        }
        padding = parsedPadding
    } else {
        padding = .pkcs5
    }

    return (algorithm, mode, padding)
}

private func runtimeCipherKeyAlgorithmMatches(_ cipherAlgorithm: RuntimeCipherAlgorithm, keyAlgorithm: RuntimeCipherAlgorithm) -> Bool {
    cipherAlgorithm == keyAlgorithm
}

private func runtimeCipherKeyBytes(_ box: RuntimeSecretKeySpecBox) -> [UInt8] {
    box.keyBytes
}

private func runtimeCipherIVBytes(_ box: RuntimeIvParameterSpecBox) -> [UInt8] {
    box.ivBytes
}

private func runtimeCipherOperation(from raw: Int) -> CCOperation? {
    switch raw {
    case 1:
        CCOperation(kCCEncrypt)
    case 2:
        CCOperation(kCCDecrypt)
    default:
        nil
    }
}

private func runtimeCipherFailureMessage(status: CCCryptorStatus) -> String {
    if status == kCCAlignmentError {
        return "IllegalBlockSizeException: cryptographic input is not block aligned"
    }
    if status == kCCDecodeError {
        return "BadPaddingException: cryptographic input has invalid padding"
    }
    if status == kCCParamError {
        return "InvalidParameterException: cryptographic parameters were invalid"
    }
    return "IllegalStateException: cryptographic operation failed with status \(status)"
}

private func runtimeCipherTransform(
    cipher: RuntimeCipherBox,
    inputBytes: [UInt8],
    outThrown: UnsafeMutablePointer<Int>?
) -> [UInt8]? {
    outThrown?.pointee = 0

    guard let operation = cipher.operation else {
        runtimeSetThrown(outThrown, message: "IllegalStateException: Cipher has not been initialized")
        return nil
    }
    guard let keyBytes = cipher.keyBytes else {
        runtimeSetThrown(outThrown, message: "IllegalStateException: Cipher has not been initialized")
        return nil
    }

    guard cipher.algorithm.acceptedKeyLengths.contains(keyBytes.count) else {
        runtimeSetThrown(
            outThrown,
            message: "InvalidKeyException: Invalid key length \(keyBytes.count) for \(cipher.algorithm.displayName)"
        )
        return nil
    }

    let effectivePadding: CCPadding = switch cipher.mode {
    case .ecb, .cbc:
        cipher.padding.ccPadding
    case .cfb, .ofb, .ctr:
        CCPadding(ccNoPadding)
    }

    let ivBytes: [UInt8]?
    if cipher.mode.requiresIV {
        ivBytes = cipher.ivBytes ?? Array(repeating: 0, count: cipher.algorithm.blockSize)
        if let ivBytes, ivBytes.count != cipher.algorithm.blockSize {
            runtimeSetThrown(
                outThrown,
                message: "InvalidAlgorithmParameterException: IV length must be \(cipher.algorithm.blockSize) for \(cipher.transformation)"
            )
            return nil
        }
    } else {
        ivBytes = nil
    }

    var cryptor: CCCryptorRef?
    let createStatus: CCCryptorStatus = keyBytes.withUnsafeBytes { keyBuffer in
        if let ivBytes {
            return ivBytes.withUnsafeBytes { ivBuffer in
                CCCryptorCreateWithMode(
                    operation,
                    cipher.mode.ccMode,
                    cipher.algorithm.ccAlgorithm,
                    effectivePadding,
                    ivBuffer.baseAddress,
                    keyBuffer.baseAddress,
                    keyBytes.count,
                    nil,
                    0,
                    0,
                    cipher.mode == .ctr ? CCModeOptions(kCCModeOptionCTR_BE) : 0,
                    &cryptor
                )
            }
        } else {
            return CCCryptorCreateWithMode(
                operation,
                cipher.mode.ccMode,
                cipher.algorithm.ccAlgorithm,
                effectivePadding,
                nil,
                keyBuffer.baseAddress,
                keyBytes.count,
                nil,
                0,
                0,
                cipher.mode == .ctr ? CCModeOptions(kCCModeOptionCTR_BE) : 0,
                &cryptor
            )
        }
    }

    guard createStatus == CCCryptorStatus(kCCSuccess), let cryptor else {
        runtimeSetThrown(outThrown, message: runtimeCipherFailureMessage(status: createStatus))
        return nil
    }
    defer { CCCryptorRelease(cryptor) }

    let outputLength = CCCryptorGetOutputLength(cryptor, inputBytes.count, true)
    if outputLength == 0 {
        return []
    }

    var output = [UInt8](repeating: 0, count: outputLength)
    var updateMoved: size_t = 0
    var finalMoved: size_t = 0

    let updateStatus: CCCryptorStatus = if inputBytes.isEmpty {
        CCCryptorStatus(kCCSuccess)
    } else {
        inputBytes.withUnsafeBytes { inputBuffer in
            output.withUnsafeMutableBytes { outputBuffer in
                CCCryptorUpdate(
                    cryptor,
                    inputBuffer.baseAddress,
                    inputBytes.count,
                    outputBuffer.baseAddress,
                    outputBuffer.count,
                    &updateMoved
                )
            }
        }
    }

    guard updateStatus == CCCryptorStatus(kCCSuccess) else {
        runtimeSetThrown(outThrown, message: runtimeCipherFailureMessage(status: updateStatus))
        return nil
    }

    let finalStatus: CCCryptorStatus = output.withUnsafeMutableBytes { outputBuffer in
        guard let base = outputBuffer.baseAddress else {
            return CCCryptorStatus(kCCSuccess)
        }
        return CCCryptorFinal(
            cryptor,
            base.advanced(by: updateMoved),
            outputBuffer.count - updateMoved,
            &finalMoved
        )
    }

    guard finalStatus == CCCryptorStatus(kCCSuccess) else {
        runtimeSetThrown(outThrown, message: runtimeCipherFailureMessage(status: finalStatus))
        return nil
    }

    let totalCount = updateMoved + finalMoved
    if totalCount == 0 {
        return []
    }
    return Array(output.prefix(totalCount))
}

@_cdecl("kk_secretkeyspec_new")
public func kk_secretkeyspec_new(_ keyRaw: Int, _ algorithmRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let algorithm = runtimeSecurityString(from: algorithmRaw, caller: #function)
    guard let parsedAlgorithm = RuntimeCipherAlgorithm(transformationComponent: algorithm) else {
        runtimeSetThrown(outThrown, runtimeAllocateThrowable(message: "NoSuchAlgorithmException: \(algorithm)"))
        return 0
    }
    guard let keyBytes = runtimeSecurityBytes(from: keyRaw, caller: #function) else {
        runtimeSetThrown(outThrown, runtimeAllocateThrowable(message: "IllegalArgumentException: expected ByteArray/List<Int>"))
        return 0
    }
    return registerRuntimeObject(RuntimeSecretKeySpecBox(keyBytes: keyBytes, algorithm: parsedAlgorithm))
}

@_cdecl("kk_ivparameterspec_new")
public func kk_ivparameterspec_new(_ ivRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let ivBytes = runtimeSecurityBytes(from: ivRaw, caller: #function) else {
        runtimeSetThrown(outThrown, runtimeAllocateThrowable(message: "IllegalArgumentException: expected ByteArray/List<Int>"))
        return 0
    }
    return registerRuntimeObject(RuntimeIvParameterSpecBox(ivBytes: ivBytes))
}

@_cdecl("kk_cipher_getInstance")
public func kk_cipher_getInstance(_ transformationRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let transformation = runtimeSecurityString(from: transformationRaw, caller: #function)
    guard let parsed = runtimeCipherParseTransformation(transformation) else {
        runtimeSetThrown(outThrown, message: "NoSuchAlgorithmException: \(transformation)")
        return 0
    }
    let box = RuntimeCipherBox(
        transformation: transformation,
        algorithm: parsed.0,
        mode: parsed.1,
        padding: parsed.2
    )
    return registerRuntimeObject(box)
}

@_cdecl("kk_cipher_init")
public func kk_cipher_init(
    _ cipherRaw: Int,
    _ opmodeRaw: Int,
    _ keyRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let cipher = runtimeCipherBox(from: cipherRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_cipher_init received invalid Cipher handle \(cipherRaw)")
    }
    guard let opmode = runtimeCipherOperation(from: opmodeRaw) else {
        runtimeSetThrown(outThrown, message: "IllegalStateException: Unsupported cipher mode \(opmodeRaw)")
        return 0
    }
    guard let keyBox = runtimeSecretKeySpecBox(from: keyRaw) else {
        runtimeSetThrown(outThrown, message: "InvalidKeyException: expected SecretKeySpec")
        return 0
    }
    guard runtimeCipherKeyAlgorithmMatches(cipher.algorithm, keyAlgorithm: keyBox.algorithm) else {
        runtimeSetThrown(
            outThrown,
            message: "InvalidKeyException: expected \(cipher.algorithm.displayName) key, got \(keyBox.algorithm.displayName)"
        )
        return 0
    }
    cipher.operation = opmode
    cipher.keyBytes = runtimeCipherKeyBytes(keyBox)
    cipher.ivBytes = nil
    return 0
}

@_cdecl("kk_cipher_init_with_iv")
public func kk_cipher_init_with_iv(
    _ cipherRaw: Int,
    _ opmodeRaw: Int,
    _ keyRaw: Int,
    _ ivRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let cipher = runtimeCipherBox(from: cipherRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_cipher_init_with_iv received invalid Cipher handle \(cipherRaw)")
    }
    guard let opmode = runtimeCipherOperation(from: opmodeRaw) else {
        runtimeSetThrown(outThrown, message: "IllegalStateException: Unsupported cipher mode \(opmodeRaw)")
        return 0
    }
    guard let keyBox = runtimeSecretKeySpecBox(from: keyRaw) else {
        runtimeSetThrown(outThrown, message: "InvalidKeyException: expected SecretKeySpec")
        return 0
    }
    guard let ivBox = runtimeIvParameterSpecBox(from: ivRaw) else {
        runtimeSetThrown(outThrown, message: "InvalidAlgorithmParameterException: expected IvParameterSpec")
        return 0
    }
    guard runtimeCipherKeyAlgorithmMatches(cipher.algorithm, keyAlgorithm: keyBox.algorithm) else {
        runtimeSetThrown(
            outThrown,
            message: "InvalidKeyException: expected \(cipher.algorithm.displayName) key, got \(keyBox.algorithm.displayName)"
        )
        return 0
    }
    cipher.operation = opmode
    cipher.keyBytes = runtimeCipherKeyBytes(keyBox)
    cipher.ivBytes = runtimeCipherIVBytes(ivBox)
    return 0
}

@_cdecl("kk_cipher_doFinal")
public func kk_cipher_doFinal(
    _ cipherRaw: Int,
    _ dataRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let cipher = runtimeCipherBox(from: cipherRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_cipher_doFinal received invalid Cipher handle \(cipherRaw)")
    }
    guard let input = runtimeSecurityBytes(from: dataRaw, caller: #function) else {
        runtimeSetThrown(outThrown, message: "IllegalArgumentException: expected ByteArray/List<Int>")
        return 0
    }
    guard let output = runtimeCipherTransform(cipher: cipher, inputBytes: input, outThrown: outThrown) else {
        return 0
    }
    return runtimeMakeByteArrayRaw(output)
}

@_cdecl("kk_cipher_doFinal_noarg")
public func kk_cipher_doFinal_noarg(
    _ cipherRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let cipher = runtimeCipherBox(from: cipherRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_cipher_doFinal_noarg received invalid Cipher handle \(cipherRaw)")
    }
    guard let output = runtimeCipherTransform(cipher: cipher, inputBytes: [], outThrown: outThrown) else {
        return 0
    }
    return runtimeMakeByteArrayRaw(output)
}
#else
// MARK: - Platform stubs: CommonCrypto not available on Linux

private let kCryptoUnavailable = "UnsupportedOperationException: symmetric crypto not available on this platform"

@_cdecl("kk_secretkeyspec_new")
public func kk_secretkeyspec_new(_ keyRaw: Int, _ algorithmRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = runtimeAllocateThrowable(message: kCryptoUnavailable)
    return 0
}

@_cdecl("kk_ivparameterspec_new")
public func kk_ivparameterspec_new(_ ivRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = runtimeAllocateThrowable(message: kCryptoUnavailable)
    return 0
}

@_cdecl("kk_cipher_getInstance")
public func kk_cipher_getInstance(_ transformationRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = runtimeAllocateThrowable(message: kCryptoUnavailable)
    return 0
}

@_cdecl("kk_cipher_init")
public func kk_cipher_init(
    _ cipherRaw: Int,
    _ opmodeRaw: Int,
    _ keyRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = runtimeAllocateThrowable(message: kCryptoUnavailable)
    return 0
}

@_cdecl("kk_cipher_init_with_iv")
public func kk_cipher_init_with_iv(
    _ cipherRaw: Int,
    _ opmodeRaw: Int,
    _ keyRaw: Int,
    _ ivRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = runtimeAllocateThrowable(message: kCryptoUnavailable)
    return 0
}

@_cdecl("kk_cipher_doFinal")
public func kk_cipher_doFinal(
    _ cipherRaw: Int,
    _ dataRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = runtimeAllocateThrowable(message: kCryptoUnavailable)
    return 0
}

@_cdecl("kk_cipher_doFinal_noarg")
public func kk_cipher_doFinal_noarg(
    _ cipherRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = runtimeAllocateThrowable(message: kCryptoUnavailable)
    return 0
}
#endif
