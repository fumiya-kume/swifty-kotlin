#if canImport(CommonCrypto)
import CommonCrypto
import Foundation
import Security

// MARK: - Symmetric Crypto Runtime Support (STDLIB-SEC-144)

enum RuntimeCipherAlgorithm: String {
    case aes = "AES"
    case des = "DES"
    case desede = "DESEDE"
    case rsa = "RSA"
    case ec = "EC"
    case dsa = "DSA"

    init?(transformationComponent rawValue: String) {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "AES":
            self = .aes
        case "DES":
            self = .des
        case "DESEDE", "TRIPLEDES", "3DES":
            self = .desede
        case "RSA":
            self = .rsa
        case "EC", "ECDSA":
            self = .ec
        case "DSA":
            self = .dsa
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
        case .rsa, .ec, .dsa:
            fatalError("ccAlgorithm is only valid for symmetric algorithms")
        }
    }

    var blockSize: Int {
        switch self {
        case .aes:
            kCCBlockSizeAES128
        case .des, .desede:
            kCCBlockSizeDES
        case .rsa, .ec, .dsa:
            0
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
        case .rsa, .ec, .dsa:
            []
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
        case .rsa:
            "RSA"
        case .ec:
            "EC"
        case .dsa:
            "DSA"
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
    case pkcs1 = "PKCS1PADDING"
    case none = "NOPADDING"

    init?(transformationComponent rawValue: String) {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "PKCS5PADDING", "PKCS7PADDING":
            self = .pkcs5
        case "PKCS1PADDING":
            self = .pkcs1
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
        case .pkcs1, .pkcs5, .pkcs7:
            CCPadding(ccPKCS7Padding)
        }
    }
}

enum RuntimeCipherKeyHandle {
    case secret(RuntimeSecretKeySpecBox)
    case publicKey(RuntimePublicKeyBox)
    case privateKey(RuntimePrivateKeyBox)

    var algorithm: RuntimeCipherAlgorithm {
        switch self {
        case let .secret(box):
            box.algorithm
        case let .publicKey(box):
            box.algorithm
        case let .privateKey(box):
            box.algorithm
        }
    }
}

enum RuntimeSignatureOperation {
    case sign
    case verify
}

enum RuntimeSignatureAlgorithm {
    case rsaSHA1
    case rsaSHA224
    case rsaSHA256
    case rsaSHA384
    case rsaSHA512
    case ecSHA1
    case ecSHA224
    case ecSHA256
    case ecSHA384
    case ecSHA512
    case dsaSHA1

    init?(name rawValue: String) {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .uppercased()
        switch normalized {
        case "SHA1WITHRSA":
            self = .rsaSHA1
        case "SHA224WITHRSA":
            self = .rsaSHA224
        case "SHA256WITHRSA":
            self = .rsaSHA256
        case "SHA384WITHRSA":
            self = .rsaSHA384
        case "SHA512WITHRSA":
            self = .rsaSHA512
        case "SHA1WITHECDSA", "SHA1WITHEC":
            self = .ecSHA1
        case "SHA224WITHECDSA", "SHA224WITHEC":
            self = .ecSHA224
        case "SHA256WITHECDSA", "SHA256WITHEC":
            self = .ecSHA256
        case "SHA384WITHECDSA", "SHA384WITHEC":
            self = .ecSHA384
        case "SHA512WITHECDSA", "SHA512WITHEC":
            self = .ecSHA512
        case "SHA1WITHDSA":
            self = .dsaSHA1
        default:
            return nil
        }
    }

    var keyAlgorithm: RuntimeCipherAlgorithm {
        switch self {
        case .rsaSHA1, .rsaSHA224, .rsaSHA256, .rsaSHA384, .rsaSHA512:
            .rsa
        case .ecSHA1, .ecSHA224, .ecSHA256, .ecSHA384, .ecSHA512:
            .ec
        case .dsaSHA1:
            .dsa
        }
    }

    var secKeyAlgorithm: SecKeyAlgorithm? {
        switch self {
        case .rsaSHA1:
            .rsaSignatureMessagePKCS1v15SHA1
        case .rsaSHA224:
            .rsaSignatureMessagePKCS1v15SHA224
        case .rsaSHA256:
            .rsaSignatureMessagePKCS1v15SHA256
        case .rsaSHA384:
            .rsaSignatureMessagePKCS1v15SHA384
        case .rsaSHA512:
            .rsaSignatureMessagePKCS1v15SHA512
        case .ecSHA1:
            .ecdsaSignatureMessageX962SHA1
        case .ecSHA224:
            .ecdsaSignatureMessageX962SHA224
        case .ecSHA256:
            .ecdsaSignatureMessageX962SHA256
        case .ecSHA384:
            .ecdsaSignatureMessageX962SHA384
        case .ecSHA512:
            .ecdsaSignatureMessageX962SHA512
        case .dsaSHA1:
            nil
        }
    }

    var displayName: String {
        switch self {
        case .rsaSHA1:
            "SHA1withRSA"
        case .rsaSHA224:
            "SHA224withRSA"
        case .rsaSHA256:
            "SHA256withRSA"
        case .rsaSHA384:
            "SHA384withRSA"
        case .rsaSHA512:
            "SHA512withRSA"
        case .ecSHA1:
            "SHA1withECDSA"
        case .ecSHA224:
            "SHA224withECDSA"
        case .ecSHA256:
            "SHA256withECDSA"
        case .ecSHA384:
            "SHA384withECDSA"
        case .ecSHA512:
            "SHA512withECDSA"
        case .dsaSHA1:
            "SHA1withDSA"
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

final class RuntimePublicKeyBox {
    let secKey: SecKey
    let algorithm: RuntimeCipherAlgorithm

    init(secKey: SecKey, algorithm: RuntimeCipherAlgorithm = .rsa) {
        self.secKey = secKey
        self.algorithm = algorithm
    }
}

final class RuntimePrivateKeyBox {
    let secKey: SecKey
    let algorithm: RuntimeCipherAlgorithm

    init(secKey: SecKey, algorithm: RuntimeCipherAlgorithm = .rsa) {
        self.secKey = secKey
        self.algorithm = algorithm
    }
}

final class RuntimeKeyPairBox {
    let publicKeyRaw: Int
    let privateKeyRaw: Int

    init(publicKeyRaw: Int, privateKeyRaw: Int) {
        self.publicKeyRaw = publicKeyRaw
        self.privateKeyRaw = privateKeyRaw
    }
}

final class RuntimeKeyPairGeneratorBox {
    let algorithm: RuntimeCipherAlgorithm
    var keySizeInBits: Int

    init(algorithm: RuntimeCipherAlgorithm, keySizeInBits: Int = 2048) {
        self.algorithm = algorithm
        self.keySizeInBits = keySizeInBits
    }
}

final class RuntimeSignatureBox {
    let algorithm: RuntimeSignatureAlgorithm
    var operation: RuntimeSignatureOperation?
    var keyRaw: Int?
    var bufferedBytes: [UInt8] = []

    init(algorithm: RuntimeSignatureAlgorithm) {
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
    var asymmetricKeyRaw: Int?
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

private func runtimePublicKeyBox(from raw: Int) -> RuntimePublicKeyBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
        return nil
    }
    return tryCast(ptr, to: RuntimePublicKeyBox.self)
}

private func runtimePrivateKeyBox(from raw: Int) -> RuntimePrivateKeyBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
        return nil
    }
    return tryCast(ptr, to: RuntimePrivateKeyBox.self)
}

private func runtimeKeyPairBox(from raw: Int) -> RuntimeKeyPairBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
        return nil
    }
    return tryCast(ptr, to: RuntimeKeyPairBox.self)
}

private func runtimeKeyPairGeneratorBox(from raw: Int) -> RuntimeKeyPairGeneratorBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
        return nil
    }
    return tryCast(ptr, to: RuntimeKeyPairGeneratorBox.self)
}

private func runtimeSignatureBox(from raw: Int) -> RuntimeSignatureBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
        return nil
    }
    return tryCast(ptr, to: RuntimeSignatureBox.self)
}

private func runtimeSecurityKeyHandle(from raw: Int) -> RuntimeCipherKeyHandle? {
    if let box = runtimeSecretKeySpecBox(from: raw) {
        return .secret(box)
    }
    if let box = runtimePublicKeyBox(from: raw) {
        return .publicKey(box)
    }
    if let box = runtimePrivateKeyBox(from: raw) {
        return .privateKey(box)
    }
    return nil
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

private func runtimeMakeData(_ bytes: [UInt8]) -> Data {
    Data(bytes)
}

private func runtimeBytes(from data: CFData) -> [UInt8] {
    Array((data as Data))
}

private func runtimeSecurityErrorMessage(_ prefix: String, error: Unmanaged<CFError>?) -> String {
    guard let error else {
        return "\(prefix): cryptographic operation failed"
    }
    let description = CFErrorCopyDescription(error.takeRetainedValue()) as String
    return "\(prefix): \(description)"
}

private func runtimeCipherAlgorithmFromSecKey(_ secKey: SecKey) -> RuntimeCipherAlgorithm {
    guard let attributes = SecKeyCopyAttributes(secKey) as? [String: Any],
          let keyType = attributes[kSecAttrKeyType as String] as? String
    else {
        return .rsa
    }
    if keyType == (kSecAttrKeyTypeECSECPrimeRandom as String) || keyType == (kSecAttrKeyTypeEC as String) {
        return .ec
    } else if keyType == (kSecAttrKeyTypeDSA as String) {
        return .dsa
    } else {
        return .rsa
    }
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
        padding = algorithm == .rsa ? .pkcs1 : .pkcs5
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

private func runtimeCipherRSAAlgorithm(for padding: RuntimeCipherPadding) -> SecKeyAlgorithm? {
    switch padding {
    case .pkcs1:
        .rsaEncryptionPKCS1
    case .pkcs5, .pkcs7, .none:
        .rsaEncryptionPKCS1
    }
}

private func runtimeCipherTransformRSA(
    cipher: RuntimeCipherBox,
    inputBytes: [UInt8],
    outThrown: UnsafeMutablePointer<Int>?
) -> [UInt8]? {
    guard let operation = cipher.operation else {
        runtimeSetThrown(outThrown, message: "IllegalStateException: Cipher has not been initialized")
        return nil
    }
    guard let keyRaw = cipher.asymmetricKeyRaw,
          let keyHandle = runtimeSecurityKeyHandle(from: keyRaw)
    else {
        runtimeSetThrown(outThrown, message: "IllegalStateException: Cipher has not been initialized")
        return nil
    }
    guard keyHandle.algorithm == .rsa else {
        runtimeSetThrown(outThrown, message: "InvalidKeyException: expected RSA key")
        return nil
    }
    guard let secAlgorithm = runtimeCipherRSAAlgorithm(for: cipher.padding) else {
        runtimeSetThrown(outThrown, message: "NoSuchAlgorithmException: unsupported RSA padding")
        return nil
    }

    let inputData = runtimeMakeData(inputBytes)
    switch operation {
    case CCOperation(kCCEncrypt):
        guard case let .publicKey(publicKey) = keyHandle else {
            runtimeSetThrown(outThrown, message: "InvalidKeyException: expected PublicKey for RSA encryption")
            return nil
        }
        guard SecKeyIsAlgorithmSupported(publicKey.secKey, .encrypt, secAlgorithm) else {
            runtimeSetThrown(outThrown, message: "InvalidAlgorithmParameterException: RSA encryption algorithm not supported")
            return nil
        }
        var error: Unmanaged<CFError>?
        guard let encrypted = SecKeyCreateEncryptedData(publicKey.secKey, secAlgorithm, inputData as CFData, &error) else {
            runtimeSetThrown(outThrown, message: runtimeSecurityErrorMessage("BadPaddingException", error: error))
            return nil
        }
        return runtimeBytes(from: encrypted)
    case CCOperation(kCCDecrypt):
        guard case let .privateKey(privateKey) = keyHandle else {
            runtimeSetThrown(outThrown, message: "InvalidKeyException: expected PrivateKey for RSA decryption")
            return nil
        }
        guard SecKeyIsAlgorithmSupported(privateKey.secKey, .decrypt, secAlgorithm) else {
            runtimeSetThrown(outThrown, message: "InvalidAlgorithmParameterException: RSA decryption algorithm not supported")
            return nil
        }
        var error: Unmanaged<CFError>?
        guard let decrypted = SecKeyCreateDecryptedData(privateKey.secKey, secAlgorithm, inputData as CFData, &error) else {
            runtimeSetThrown(outThrown, message: runtimeSecurityErrorMessage("BadPaddingException", error: error))
            return nil
        }
        return runtimeBytes(from: decrypted)
    default:
        runtimeSetThrown(outThrown, message: "IllegalStateException: Unsupported RSA operation")
        return nil
    }
}

private func runtimeKeyPairGeneratorCreate(
    algorithm: RuntimeCipherAlgorithm,
    keySizeInBits: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let secKeyType: CFString
    switch algorithm {
    case .rsa:
        secKeyType = kSecAttrKeyTypeRSA
    case .ec:
        secKeyType = kSecAttrKeyTypeECSECPrimeRandom
    case .dsa:
        secKeyType = kSecAttrKeyTypeDSA
    default:
        runtimeSetThrown(outThrown, message: "InvalidAlgorithmException: \(algorithm.displayName) is not a key pair algorithm")
        return 0
    }

    let params: [String: Any] = [
        kSecAttrKeyType as String: secKeyType,
        kSecAttrKeySizeInBits as String: keySizeInBits,
        kSecPrivateKeyAttrs as String: [
            kSecAttrIsPermanent as String: false,
        ],
        kSecPublicKeyAttrs as String: [
            kSecAttrIsPermanent as String: false,
        ],
    ]
    var error: Unmanaged<CFError>?
    guard let privateKey = SecKeyCreateRandomKey(params as CFDictionary, &error) else {
        runtimeSetThrown(outThrown, message: runtimeSecurityErrorMessage("InvalidKeyException", error: error))
        return 0
    }
    guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
        runtimeSetThrown(outThrown, message: "InvalidKeyException: failed to derive public key")
        return 0
    }

    let publicBox = RuntimePublicKeyBox(secKey: publicKey, algorithm: algorithm)
    let privateBox = RuntimePrivateKeyBox(secKey: privateKey, algorithm: algorithm)
    let publicRaw = registerRuntimeObject(publicBox)
    let privateRaw = registerRuntimeObject(privateBox)
    return registerRuntimeObject(RuntimeKeyPairBox(publicKeyRaw: publicRaw, privateKeyRaw: privateRaw))
}

private func runtimeSignatureAlgorithmFromKey(_ algorithm: RuntimeSignatureAlgorithm) -> SecKeyAlgorithm? {
    algorithm.secKeyAlgorithm
}

private func runtimeSignatureTransform(
    signature: RuntimeSignatureBox,
    outThrown: UnsafeMutablePointer<Int>?,
    verifySignatureBytes: [UInt8]? = nil
) -> Int? {
    guard let operation = signature.operation else {
        runtimeSetThrown(outThrown, message: "IllegalStateException: Signature has not been initialized")
        return nil
    }
    guard let keyRaw = signature.keyRaw else {
        runtimeSetThrown(outThrown, message: "IllegalStateException: Signature has not been initialized")
        return nil
    }
    let secAlgorithm = signature.algorithm.secKeyAlgorithm
    guard let secAlgorithm else {
        runtimeSetThrown(outThrown, message: "NoSuchAlgorithmException: unsupported signature algorithm \(signature.algorithm.displayName)")
        return nil
    }

    let messageData = runtimeMakeData(signature.bufferedBytes)
    switch operation {
    case .sign:
        guard let privateKey = runtimePrivateKeyBox(from: keyRaw) else {
            runtimeSetThrown(outThrown, message: "InvalidKeyException: expected PrivateKey")
            return nil
        }
        guard privateKey.algorithm == signature.algorithm.keyAlgorithm else {
            runtimeSetThrown(outThrown, message: "InvalidKeyException: expected \(signature.algorithm.keyAlgorithm.displayName) key")
            return nil
        }
        guard SecKeyIsAlgorithmSupported(privateKey.secKey, .sign, secAlgorithm) else {
            runtimeSetThrown(outThrown, message: "InvalidAlgorithmParameterException: signature algorithm not supported")
            return nil
        }
        var error: Unmanaged<CFError>?
        guard let signed = SecKeyCreateSignature(privateKey.secKey, secAlgorithm, messageData as CFData, &error) else {
            runtimeSetThrown(outThrown, message: runtimeSecurityErrorMessage("SignatureException", error: error))
            return nil
        }
        return runtimeMakeByteArrayRaw(runtimeBytes(from: signed))
    case .verify:
        guard let publicKey = runtimePublicKeyBox(from: keyRaw) else {
            runtimeSetThrown(outThrown, message: "InvalidKeyException: expected PublicKey")
            return nil
        }
        guard publicKey.algorithm == signature.algorithm.keyAlgorithm else {
            runtimeSetThrown(outThrown, message: "InvalidKeyException: expected \(signature.algorithm.keyAlgorithm.displayName) key")
            return nil
        }
        guard let signatureBytes = verifySignatureBytes else {
            runtimeSetThrown(outThrown, message: "IllegalArgumentException: expected ByteArray/List<Int>")
            return nil
        }
        guard SecKeyIsAlgorithmSupported(publicKey.secKey, .verify, secAlgorithm) else {
            runtimeSetThrown(outThrown, message: "InvalidAlgorithmParameterException: signature algorithm not supported")
            return nil
        }
        var error: Unmanaged<CFError>?
        let verified = SecKeyVerifySignature(publicKey.secKey, secAlgorithm, messageData as CFData, runtimeMakeData(signatureBytes) as CFData, &error)
        if error != nil {
            runtimeSetThrown(outThrown, message: runtimeSecurityErrorMessage("SignatureException", error: error))
            return nil
        }
        return verified ? 1 : 0
    }
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
    if cipher.algorithm == .rsa {
        return runtimeCipherTransformRSA(cipher: cipher, inputBytes: inputBytes, outThrown: outThrown)
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

private func runtimeCipherInitialize(
    cipherRaw: Int,
    opmodeRaw: Int,
    keyRaw: Int,
    ivRaw: Int?,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let cipher = runtimeCipherBox(from: cipherRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: cipher init received invalid Cipher handle \(cipherRaw)")
    }
    guard let opmode = runtimeCipherOperation(from: opmodeRaw) else {
        runtimeSetThrown(outThrown, message: "IllegalStateException: Unsupported cipher mode \(opmodeRaw)")
        return 0
    }
    guard let keyHandle = runtimeSecurityKeyHandle(from: keyRaw) else {
        runtimeSetThrown(outThrown, message: "InvalidKeyException: expected Key/SecretKeySpec/PublicKey/PrivateKey")
        return 0
    }
    guard runtimeCipherKeyAlgorithmMatches(cipher.algorithm, keyAlgorithm: keyHandle.algorithm) else {
        runtimeSetThrown(
            outThrown,
            message: "InvalidKeyException: expected \(cipher.algorithm.displayName) key, got \(keyHandle.algorithm.displayName)"
        )
        return 0
    }

    switch cipher.algorithm {
    case .rsa:
        guard ivRaw == nil else {
            runtimeSetThrown(outThrown, message: "InvalidAlgorithmParameterException: RSA does not use an IV")
            return 0
        }
        if opmode == CCOperation(kCCEncrypt) {
            guard case .publicKey = keyHandle else {
                runtimeSetThrown(outThrown, message: "InvalidKeyException: expected PublicKey for RSA encryption")
                return 0
            }
        } else if opmode == CCOperation(kCCDecrypt) {
            guard case .privateKey = keyHandle else {
                runtimeSetThrown(outThrown, message: "InvalidKeyException: expected PrivateKey for RSA decryption")
                return 0
            }
        } else {
            runtimeSetThrown(outThrown, message: "IllegalStateException: Unsupported RSA operation")
            return 0
        }
        cipher.operation = opmode
        cipher.keyBytes = nil
        cipher.asymmetricKeyRaw = keyRaw
        cipher.ivBytes = nil
        return 0
    default:
        guard case let .secret(secretKey) = keyHandle else {
            runtimeSetThrown(outThrown, message: "InvalidKeyException: expected SecretKeySpec")
            return 0
        }
        cipher.operation = opmode
        cipher.keyBytes = runtimeCipherKeyBytes(secretKey)
        cipher.asymmetricKeyRaw = nil
        if let ivRaw {
            guard let ivBox = runtimeIvParameterSpecBox(from: ivRaw) else {
                runtimeSetThrown(outThrown, message: "InvalidAlgorithmParameterException: expected IvParameterSpec")
                return 0
            }
            cipher.ivBytes = runtimeCipherIVBytes(ivBox)
        } else {
            cipher.ivBytes = nil
        }
        return 0
    }
}

private func runtimeKeyPairGeneratorInitialize(
    generatorRaw: Int,
    keySizeInBits: Int
) -> Bool {
    guard let generator = runtimeKeyPairGeneratorBox(from: generatorRaw) else {
        return false
    }
    generator.keySizeInBits = keySizeInBits
    return true
}

@_cdecl("kk_secretkeyspec_new")
public func kk_secretkeyspec_new(_ keyRaw: Int, _ algorithmRaw: Int) -> Int {
    let algorithm = runtimeSecurityString(from: algorithmRaw, caller: #function)
    guard let parsedAlgorithm = RuntimeCipherAlgorithm(transformationComponent: algorithm) else {
        return runtimeAllocateThrowable(message: "NoSuchAlgorithmException: \(algorithm)")
    }
    guard let keyBytes = runtimeSecurityBytes(from: keyRaw, caller: #function) else {
        return runtimeAllocateThrowable(message: "IllegalArgumentException: expected ByteArray/List<Int>")
    }
    return registerRuntimeObject(RuntimeSecretKeySpecBox(keyBytes: keyBytes, algorithm: parsedAlgorithm))
}

@_cdecl("kk_ivparameterspec_new")
public func kk_ivparameterspec_new(_ ivRaw: Int) -> Int {
    guard let ivBytes = runtimeSecurityBytes(from: ivRaw, caller: #function) else {
        return runtimeAllocateThrowable(message: "IllegalArgumentException: expected ByteArray/List<Int>")
    }
    return registerRuntimeObject(RuntimeIvParameterSpecBox(ivBytes: ivBytes))
}

@_cdecl("kk_keypairgenerator_getInstance")
public func kk_keypairgenerator_getInstance(_ algorithmRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let algorithmName = runtimeSecurityString(from: algorithmRaw, caller: #function)
    guard let algorithm = RuntimeCipherAlgorithm(transformationComponent: algorithmName) else {
        runtimeSetThrown(outThrown, message: "NoSuchAlgorithmException: \(algorithmName)")
        return 0
    }
    switch algorithm {
    case .rsa, .ec, .dsa:
        return registerRuntimeObject(RuntimeKeyPairGeneratorBox(algorithm: algorithm))
    default:
        runtimeSetThrown(outThrown, message: "NoSuchAlgorithmException: \(algorithmName)")
        return 0
    }
}

@_cdecl("kk_keypairgenerator_initialize")
public func kk_keypairgenerator_initialize(
    _ generatorRaw: Int,
    _ keySizeRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let generator = runtimeKeyPairGeneratorBox(from: generatorRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_keypairgenerator_initialize received invalid KeyPairGenerator handle \(generatorRaw)")
    }
    generator.keySizeInBits = keySizeRaw
    return 0
}

@_cdecl("kk_keypairgenerator_generateKeyPair")
public func kk_keypairgenerator_generateKeyPair(
    _ generatorRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let generator = runtimeKeyPairGeneratorBox(from: generatorRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_keypairgenerator_generateKeyPair received invalid KeyPairGenerator handle \(generatorRaw)")
    }
    return runtimeKeyPairGeneratorCreate(
        algorithm: generator.algorithm,
        keySizeInBits: generator.keySizeInBits,
        outThrown: outThrown
    )
}

@_cdecl("kk_keypair_public")
public func kk_keypair_public(_ keyPairRaw: Int) -> Int {
    guard let keyPair = runtimeKeyPairBox(from: keyPairRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_keypair_public received invalid KeyPair handle \(keyPairRaw)")
    }
    return keyPair.publicKeyRaw
}

@_cdecl("kk_keypair_private")
public func kk_keypair_private(_ keyPairRaw: Int) -> Int {
    guard let keyPair = runtimeKeyPairBox(from: keyPairRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_keypair_private received invalid KeyPair handle \(keyPairRaw)")
    }
    return keyPair.privateKeyRaw
}

@_cdecl("kk_keypair_new")
public func kk_keypair_new(
    _ publicKeyRaw: Int,
    _ privateKeyRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard runtimePublicKeyBox(from: publicKeyRaw) != nil else {
        runtimeSetThrown(outThrown, message: "IllegalArgumentException: expected PublicKey")
        return 0
    }
    guard runtimePrivateKeyBox(from: privateKeyRaw) != nil else {
        runtimeSetThrown(outThrown, message: "IllegalArgumentException: expected PrivateKey")
        return 0
    }
    return registerRuntimeObject(RuntimeKeyPairBox(publicKeyRaw: publicKeyRaw, privateKeyRaw: privateKeyRaw))
}

@_cdecl("kk_keypair_publicKey")
public func kk_keypair_publicKey(_ keyPairRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let keyPair = runtimeKeyPairBox(from: keyPairRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_keypair_publicKey received invalid KeyPair handle \(keyPairRaw)")
    }
    return keyPair.publicKeyRaw
}

@_cdecl("kk_keypair_privateKey")
public func kk_keypair_privateKey(_ keyPairRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let keyPair = runtimeKeyPairBox(from: keyPairRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_keypair_privateKey received invalid KeyPair handle \(keyPairRaw)")
    }
    return keyPair.privateKeyRaw
}

@_cdecl("kk_signature_getInstance")
public func kk_signature_getInstance(_ algorithmRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let algorithmName = runtimeSecurityString(from: algorithmRaw, caller: #function)
    guard let algorithm = RuntimeSignatureAlgorithm(name: algorithmName) else {
        runtimeSetThrown(outThrown, message: "NoSuchAlgorithmException: \(algorithmName)")
        return 0
    }
    return registerRuntimeObject(RuntimeSignatureBox(algorithm: algorithm))
}

@_cdecl("kk_signature_initSign")
public func kk_signature_initSign(
    _ signatureRaw: Int,
    _ keyRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let signature = runtimeSignatureBox(from: signatureRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_signature_initSign received invalid Signature handle \(signatureRaw)")
    }
    guard let keyBox = runtimePrivateKeyBox(from: keyRaw) else {
        runtimeSetThrown(outThrown, message: "InvalidKeyException: expected PrivateKey")
        return 0
    }
    guard keyBox.algorithm == signature.algorithm.keyAlgorithm else {
        runtimeSetThrown(outThrown, message: "InvalidKeyException: expected \(signature.algorithm.keyAlgorithm.displayName) key")
        return 0
    }
    signature.operation = .sign
    signature.keyRaw = keyRaw
    signature.bufferedBytes.removeAll(keepingCapacity: true)
    return 0
}

@_cdecl("kk_signature_initVerify")
public func kk_signature_initVerify(
    _ signatureRaw: Int,
    _ keyRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let signature = runtimeSignatureBox(from: signatureRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_signature_initVerify received invalid Signature handle \(signatureRaw)")
    }
    guard let keyBox = runtimePublicKeyBox(from: keyRaw) else {
        runtimeSetThrown(outThrown, message: "InvalidKeyException: expected PublicKey")
        return 0
    }
    guard keyBox.algorithm == signature.algorithm.keyAlgorithm else {
        runtimeSetThrown(outThrown, message: "InvalidKeyException: expected \(signature.algorithm.keyAlgorithm.displayName) key")
        return 0
    }
    signature.operation = .verify
    signature.keyRaw = keyRaw
    signature.bufferedBytes.removeAll(keepingCapacity: true)
    return 0
}

@_cdecl("kk_signature_update")
public func kk_signature_update(
    _ signatureRaw: Int,
    _ dataRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let signature = runtimeSignatureBox(from: signatureRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_signature_update received invalid Signature handle \(signatureRaw)")
    }
    guard let bytes = runtimeSecurityBytes(from: dataRaw, caller: #function) else {
        runtimeSetThrown(outThrown, message: "IllegalArgumentException: expected ByteArray/List<Int>")
        return 0
    }
    signature.bufferedBytes.append(contentsOf: bytes)
    return 0
}

@_cdecl("kk_signature_sign")
public func kk_signature_sign(
    _ signatureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let signature = runtimeSignatureBox(from: signatureRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_signature_sign received invalid Signature handle \(signatureRaw)")
    }
    guard let result = runtimeSignatureTransform(signature: signature, outThrown: outThrown) else {
        return 0
    }
    return result
}

@_cdecl("kk_signature_verify")
public func kk_signature_verify(
    _ signatureRaw: Int,
    _ signatureBytesRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let signature = runtimeSignatureBox(from: signatureRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_signature_verify received invalid Signature handle \(signatureRaw)")
    }
    guard let signatureBytes = runtimeSecurityBytes(from: signatureBytesRaw, caller: #function) else {
        runtimeSetThrown(outThrown, message: "IllegalArgumentException: expected ByteArray/List<Int>")
        return 0
    }
    guard let verified = runtimeSignatureTransform(signature: signature, outThrown: outThrown, verifySignatureBytes: signatureBytes) else {
        return 0
    }
    return verified
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
    runtimeCipherInitialize(cipherRaw: cipherRaw, opmodeRaw: opmodeRaw, keyRaw: keyRaw, ivRaw: nil, outThrown: outThrown)
}

@_cdecl("kk_cipher_init_with_iv")
public func kk_cipher_init_with_iv(
    _ cipherRaw: Int,
    _ opmodeRaw: Int,
    _ keyRaw: Int,
    _ ivRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeCipherInitialize(cipherRaw: cipherRaw, opmodeRaw: opmodeRaw, keyRaw: keyRaw, ivRaw: ivRaw, outThrown: outThrown)
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

// MARK: - Digital Signatures / Certificates (STDLIB-SEC-146)

final class RuntimeCertificateFactoryBox {
    let typeName: String

    init(typeName: String) {
        self.typeName = typeName
    }
}

final class RuntimeX509CertificateBox {
    let certificate: SecCertificate
    let encodedBytes: [UInt8]

    init(certificate: SecCertificate, encodedBytes: [UInt8]) {
        self.certificate = certificate
        self.encodedBytes = encodedBytes
    }
}

final class RuntimeCertPathBox {
    let certificatesRaw: [Int]

    init(certificatesRaw: [Int]) {
        self.certificatesRaw = certificatesRaw
    }
}

final class RuntimeTrustAnchorBox {
    let certificateRaw: Int

    init(certificateRaw: Int) {
        self.certificateRaw = certificateRaw
    }
}

final class RuntimePKIXParametersBox {
    var trustAnchorsRaw: [Int]

    init(trustAnchorsRaw: [Int]) {
        self.trustAnchorsRaw = trustAnchorsRaw
    }
}

final class RuntimeCertPathValidatorBox {
    let algorithm: String

    init(algorithm: String) {
        self.algorithm = algorithm
    }
}

private func runtimeCertificateFactoryBox(from raw: Int) -> RuntimeCertificateFactoryBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeCertificateFactoryBox.self)
}

private func runtimeX509CertificateBox(from raw: Int) -> RuntimeX509CertificateBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeX509CertificateBox.self)
}

private func runtimeCertPathBox(from raw: Int) -> RuntimeCertPathBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeCertPathBox.self)
}

private func runtimeTrustAnchorBox(from raw: Int) -> RuntimeTrustAnchorBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeTrustAnchorBox.self)
}

private func runtimePKIXParametersBox(from raw: Int) -> RuntimePKIXParametersBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimePKIXParametersBox.self)
}

private func runtimeCertPathValidatorBox(from raw: Int) -> RuntimeCertPathValidatorBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeCertPathValidatorBox.self)
}

private func runtimeSecurityBytesAsData(from raw: Int, caller: StaticString) -> Data? {
    guard let bytes = runtimeSecurityBytes(from: raw, caller: caller) else {
        return nil
    }
    let data = Data(bytes)
    guard let text = String(data: data, encoding: .utf8) else {
        return data
    }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.contains("-----BEGIN") else {
        return data
    }
    let base64 = trimmed
        .split(separator: "\n")
        .filter { !$0.hasPrefix("-----BEGIN") && !$0.hasPrefix("-----END") }
        .joined()
    return Data(base64Encoded: base64)
}

private func runtimeSecurityCertificate(from data: Data) -> SecCertificate? {
    SecCertificateCreateWithData(nil, data as CFData)
}

private func runtimeSecurityCertPathCertificates(from raw: Int, caller: StaticString) -> [Int]? {
    guard let list = runtimeListBox(from: raw) else {
        return nil
    }
    var certificates: [Int] = []
    for elementRaw in list.elements {
        guard let cert = runtimeX509CertificateBox(from: elementRaw) else {
            return nil
        }
        _ = cert
        certificates.append(elementRaw)
    }
    return certificates
}

@_cdecl("kk_certificatefactory_getInstance")
public func kk_certificatefactory_getInstance(_ typeRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let typeName = runtimeSecurityString(from: typeRaw, caller: #function)
    guard typeName.uppercased() == "X.509" || typeName.uppercased() == "X509" else {
        runtimeSetThrown(outThrown, message: "NoSuchAlgorithmException: \(typeName)")
        return 0
    }
    return registerRuntimeObject(RuntimeCertificateFactoryBox(typeName: typeName))
}

@_cdecl("kk_certificatefactory_generateCertificate")
public func kk_certificatefactory_generateCertificate(
    _ factoryRaw: Int,
    _ dataRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let factory = runtimeCertificateFactoryBox(from: factoryRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_certificatefactory_generateCertificate received invalid CertificateFactory handle \(factoryRaw)")
    }
    guard factory.typeName.uppercased() == "X.509" || factory.typeName.uppercased() == "X509" else {
        runtimeSetThrown(outThrown, message: "CertificateException: unsupported certificate factory \(factory.typeName)")
        return 0
    }
    guard let data = runtimeSecurityBytesAsData(from: dataRaw, caller: #function) else {
        runtimeSetThrown(outThrown, message: "CertificateException: expected ByteArray/List<Int>")
        return 0
    }
    guard let certificate = runtimeSecurityCertificate(from: data) else {
        runtimeSetThrown(outThrown, message: "CertificateException: invalid certificate data")
        return 0
    }
    return registerRuntimeObject(RuntimeX509CertificateBox(certificate: certificate, encodedBytes: Array(data)))
}

@_cdecl("kk_x509certificate_getPublicKey")
public func kk_x509certificate_getPublicKey(_ certificateRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let certificate = runtimeX509CertificateBox(from: certificateRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_x509certificate_getPublicKey received invalid X509Certificate handle \(certificateRaw)")
    }
    guard let publicKey = SecCertificateCopyKey(certificate.certificate) else {
        runtimeSetThrown(outThrown, message: "CertificateException: unable to extract public key")
        return 0
    }
    let algorithm = runtimeCipherAlgorithmFromSecKey(publicKey)
    return registerRuntimeObject(RuntimePublicKeyBox(secKey: publicKey, algorithm: algorithm))
}

@_cdecl("kk_x509certificate_getEncoded")
public func kk_x509certificate_getEncoded(_ certificateRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let certificate = runtimeX509CertificateBox(from: certificateRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_x509certificate_getEncoded received invalid X509Certificate handle \(certificateRaw)")
    }
    return runtimeMakeByteArrayRaw(certificate.encodedBytes)
}

@_cdecl("kk_certpath_new")
public func kk_certpath_new(_ certificatesRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let certificateRaws = runtimeSecurityCertPathCertificates(from: certificatesRaw, caller: #function) else {
        runtimeSetThrown(outThrown, message: "IllegalArgumentException: expected List<X509Certificate>")
        return 0
    }
    return registerRuntimeObject(RuntimeCertPathBox(certificatesRaw: certificateRaws))
}

@_cdecl("kk_certpathvalidator_getInstance")
public func kk_certpathvalidator_getInstance(_ algorithmRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let algorithmName = runtimeSecurityString(from: algorithmRaw, caller: #function)
    guard algorithmName.uppercased() == "PKIX" else {
        runtimeSetThrown(outThrown, message: "NoSuchAlgorithmException: \(algorithmName)")
        return 0
    }
    return registerRuntimeObject(RuntimeCertPathValidatorBox(algorithm: algorithmName))
}

@_cdecl("kk_trustanchor_new")
public func kk_trustanchor_new(_ certificateRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard runtimeX509CertificateBox(from: certificateRaw) != nil else {
        runtimeSetThrown(outThrown, message: "IllegalArgumentException: expected X509Certificate")
        return 0
    }
    return registerRuntimeObject(RuntimeTrustAnchorBox(certificateRaw: certificateRaw))
}

@_cdecl("kk_pkixparameters_new")
public func kk_pkixparameters_new(_ trustAnchorsRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let trustAnchorList = runtimeListBox(from: trustAnchorsRaw) else {
        runtimeSetThrown(outThrown, message: "IllegalArgumentException: expected List<TrustAnchor>")
        return 0
    }
    var anchors: [Int] = []
    for anchorRaw in trustAnchorList.elements {
        guard runtimeTrustAnchorBox(from: anchorRaw) != nil else {
            runtimeSetThrown(outThrown, message: "IllegalArgumentException: expected TrustAnchor")
            return 0
        }
        anchors.append(anchorRaw)
    }
    return registerRuntimeObject(RuntimePKIXParametersBox(trustAnchorsRaw: anchors))
}

@_cdecl("kk_pkixparameters_setTrustAnchors")
public func kk_pkixparameters_setTrustAnchors(
    _ parametersRaw: Int,
    _ trustAnchorsRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let parameters = runtimePKIXParametersBox(from: parametersRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_pkixparameters_setTrustAnchors received invalid PKIXParameters handle \(parametersRaw)")
    }
    guard let trustAnchorList = runtimeListBox(from: trustAnchorsRaw) else {
        runtimeSetThrown(outThrown, message: "IllegalArgumentException: expected List<TrustAnchor>")
        return 0
    }
    var anchors: [Int] = []
    for anchorRaw in trustAnchorList.elements {
        guard runtimeTrustAnchorBox(from: anchorRaw) != nil else {
            runtimeSetThrown(outThrown, message: "IllegalArgumentException: expected TrustAnchor")
            return 0
        }
        anchors.append(anchorRaw)
    }
    parameters.trustAnchorsRaw = anchors
    return 0
}

@_cdecl("kk_certpathvalidator_validate")
public func kk_certpathvalidator_validate(
    _ validatorRaw: Int,
    _ certPathRaw: Int,
    _ parametersRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let validator = runtimeCertPathValidatorBox(from: validatorRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_certpathvalidator_validate received invalid CertPathValidator handle \(validatorRaw)")
    }
    guard validator.algorithm.uppercased() == "PKIX" else {
        runtimeSetThrown(outThrown, message: "NoSuchAlgorithmException: \(validator.algorithm)")
        return 0
    }
    guard let certPath = runtimeCertPathBox(from: certPathRaw),
          let parameters = runtimePKIXParametersBox(from: parametersRaw) else {
        runtimeSetThrown(outThrown, message: "IllegalArgumentException: expected CertPath and PKIXParameters")
        return 0
    }

    let certs: [SecCertificate] = certPath.certificatesRaw.compactMap { raw in
        runtimeX509CertificateBox(from: raw)?.certificate
    }
    guard certs.count == certPath.certificatesRaw.count else {
        runtimeSetThrown(outThrown, message: "IllegalArgumentException: expected X509Certificate path")
        return 0
    }
    let anchors: [SecCertificate] = parameters.trustAnchorsRaw.compactMap { raw in
        guard let certRaw = runtimeTrustAnchorBox(from: raw)?.certificateRaw else {
            return nil
        }
        return runtimeX509CertificateBox(from: certRaw)?.certificate
    }
    guard anchors.count == parameters.trustAnchorsRaw.count else {
        runtimeSetThrown(outThrown, message: "IllegalArgumentException: expected TrustAnchor certificate")
        return 0
    }

    let policy = SecPolicyCreateBasicX509()
    var trust: SecTrust?
    let trustCreateStatus = SecTrustCreateWithCertificates(certs as CFArray, policy, &trust)
    guard trustCreateStatus == errSecSuccess, let trust else {
        runtimeSetThrown(outThrown, message: "CertificateException: failed to create trust evaluation context")
        return 0
    }
    if !anchors.isEmpty {
        SecTrustSetAnchorCertificates(trust, anchors as CFArray)
        SecTrustSetAnchorCertificatesOnly(trust, true)
    }
    let ok = SecTrustEvaluateWithError(trust, nil)
    return kk_box_bool(ok ? 1 : 0)
}
#else
// MARK: - Platform stubs: CommonCrypto/Security not available on Linux

@_cdecl("kk_secretkeyspec_new")
public func kk_secretkeyspec_new(_ keyRaw: Int, _ algorithmRaw: Int) -> Int {
    return runtimeAllocateThrowable(message: "UnsupportedOperationException: crypto not available on this platform")
}

@_cdecl("kk_ivparameterspec_new")
public func kk_ivparameterspec_new(_ ivRaw: Int) -> Int {
    return runtimeAllocateThrowable(message: "UnsupportedOperationException: crypto not available on this platform")
}

@_cdecl("kk_keypairgenerator_getInstance")
public func kk_keypairgenerator_getInstance(_ algorithmRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeSetThrown(outThrown, runtimeAllocateThrowable(message: "UnsupportedOperationException: crypto not available on this platform"))
    return 0
}

@_cdecl("kk_keypairgenerator_initialize")
public func kk_keypairgenerator_initialize(_ generatorRaw: Int, _ keySizeRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeSetThrown(outThrown, runtimeAllocateThrowable(message: "UnsupportedOperationException: crypto not available on this platform"))
    return 0
}

@_cdecl("kk_keypairgenerator_generateKeyPair")
public func kk_keypairgenerator_generateKeyPair(_ generatorRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeSetThrown(outThrown, runtimeAllocateThrowable(message: "UnsupportedOperationException: crypto not available on this platform"))
    return 0
}

@_cdecl("kk_keypair_public")
public func kk_keypair_public(_ keyPairRaw: Int) -> Int {
    return runtimeAllocateThrowable(message: "UnsupportedOperationException: crypto not available on this platform")
}

@_cdecl("kk_keypair_private")
public func kk_keypair_private(_ keyPairRaw: Int) -> Int {
    return runtimeAllocateThrowable(message: "UnsupportedOperationException: crypto not available on this platform")
}

@_cdecl("kk_keypair_new")
public func kk_keypair_new(_ publicKeyRaw: Int, _ privateKeyRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeSetThrown(outThrown, runtimeAllocateThrowable(message: "UnsupportedOperationException: crypto not available on this platform"))
    return 0
}

@_cdecl("kk_keypair_publicKey")
public func kk_keypair_publicKey(_ keyPairRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeSetThrown(outThrown, runtimeAllocateThrowable(message: "UnsupportedOperationException: crypto not available on this platform"))
    return 0
}

@_cdecl("kk_keypair_privateKey")
public func kk_keypair_privateKey(_ keyPairRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeSetThrown(outThrown, runtimeAllocateThrowable(message: "UnsupportedOperationException: crypto not available on this platform"))
    return 0
}

@_cdecl("kk_signature_getInstance")
public func kk_signature_getInstance(_ algorithmRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeSetThrown(outThrown, runtimeAllocateThrowable(message: "UnsupportedOperationException: crypto not available on this platform"))
    return 0
}

@_cdecl("kk_signature_initSign")
public func kk_signature_initSign(_ signatureRaw: Int, _ privateKeyRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeSetThrown(outThrown, runtimeAllocateThrowable(message: "UnsupportedOperationException: crypto not available on this platform"))
    return 0
}

@_cdecl("kk_signature_initVerify")
public func kk_signature_initVerify(_ signatureRaw: Int, _ publicKeyRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeSetThrown(outThrown, runtimeAllocateThrowable(message: "UnsupportedOperationException: crypto not available on this platform"))
    return 0
}

@_cdecl("kk_signature_update")
public func kk_signature_update(_ signatureRaw: Int, _ dataRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeSetThrown(outThrown, runtimeAllocateThrowable(message: "UnsupportedOperationException: crypto not available on this platform"))
    return 0
}

@_cdecl("kk_signature_sign")
public func kk_signature_sign(_ signatureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeSetThrown(outThrown, runtimeAllocateThrowable(message: "UnsupportedOperationException: crypto not available on this platform"))
    return 0
}

@_cdecl("kk_signature_verify")
public func kk_signature_verify(_ signatureRaw: Int, _ sigBytesRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeSetThrown(outThrown, runtimeAllocateThrowable(message: "UnsupportedOperationException: crypto not available on this platform"))
    return 0
}

@_cdecl("kk_cipher_getInstance")
public func kk_cipher_getInstance(_ transformationRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeSetThrown(outThrown, runtimeAllocateThrowable(message: "UnsupportedOperationException: crypto not available on this platform"))
    return 0
}

@_cdecl("kk_cipher_init")
public func kk_cipher_init(
    _ cipherRaw: Int,
    _ opmodeRaw: Int,
    _ keyRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeSetThrown(outThrown, runtimeAllocateThrowable(message: "UnsupportedOperationException: crypto not available on this platform"))
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
    runtimeSetThrown(outThrown, runtimeAllocateThrowable(message: "UnsupportedOperationException: crypto not available on this platform"))
    return 0
}

@_cdecl("kk_cipher_doFinal")
public func kk_cipher_doFinal(
    _ cipherRaw: Int,
    _ dataRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeSetThrown(outThrown, runtimeAllocateThrowable(message: "UnsupportedOperationException: crypto not available on this platform"))
    return 0
}

@_cdecl("kk_cipher_doFinal_noarg")
public func kk_cipher_doFinal_noarg(
    _ cipherRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeSetThrown(outThrown, runtimeAllocateThrowable(message: "UnsupportedOperationException: crypto not available on this platform"))
    return 0
}

@_cdecl("kk_certificatefactory_getInstance")
public func kk_certificatefactory_getInstance(_ typeRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeSetThrown(outThrown, runtimeAllocateThrowable(message: "UnsupportedOperationException: crypto not available on this platform"))
    return 0
}

@_cdecl("kk_certificatefactory_generateCertificate")
public func kk_certificatefactory_generateCertificate(_ factoryRaw: Int, _ dataRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeSetThrown(outThrown, runtimeAllocateThrowable(message: "UnsupportedOperationException: crypto not available on this platform"))
    return 0
}

@_cdecl("kk_x509certificate_getPublicKey")
public func kk_x509certificate_getPublicKey(_ certificateRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeSetThrown(outThrown, runtimeAllocateThrowable(message: "UnsupportedOperationException: crypto not available on this platform"))
    return 0
}

@_cdecl("kk_x509certificate_getEncoded")
public func kk_x509certificate_getEncoded(_ certificateRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeSetThrown(outThrown, runtimeAllocateThrowable(message: "UnsupportedOperationException: crypto not available on this platform"))
    return 0
}

@_cdecl("kk_certpath_new")
public func kk_certpath_new(_ certificatesRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeSetThrown(outThrown, runtimeAllocateThrowable(message: "UnsupportedOperationException: crypto not available on this platform"))
    return 0
}

@_cdecl("kk_certpathvalidator_getInstance")
public func kk_certpathvalidator_getInstance(_ algorithmRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeSetThrown(outThrown, runtimeAllocateThrowable(message: "UnsupportedOperationException: crypto not available on this platform"))
    return 0
}

@_cdecl("kk_trustanchor_new")
public func kk_trustanchor_new(_ certificateRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeSetThrown(outThrown, runtimeAllocateThrowable(message: "UnsupportedOperationException: crypto not available on this platform"))
    return 0
}

@_cdecl("kk_pkixparameters_new")
public func kk_pkixparameters_new(_ trustAnchorsRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeSetThrown(outThrown, runtimeAllocateThrowable(message: "UnsupportedOperationException: crypto not available on this platform"))
    return 0
}

@_cdecl("kk_pkixparameters_setTrustAnchors")
public func kk_pkixparameters_setTrustAnchors(_ parametersRaw: Int, _ trustAnchorsRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeSetThrown(outThrown, runtimeAllocateThrowable(message: "UnsupportedOperationException: crypto not available on this platform"))
    return 0
}

@_cdecl("kk_certpathvalidator_validate")
public func kk_certpathvalidator_validate(_ validatorRaw: Int, _ certPathRaw: Int, _ parametersRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeSetThrown(outThrown, runtimeAllocateThrowable(message: "UnsupportedOperationException: crypto not available on this platform"))
    return 0
}
#endif

// MARK: - MessageDigest Runtime Support (STDLIB-SEC-143)

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
