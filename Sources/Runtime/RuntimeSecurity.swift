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
