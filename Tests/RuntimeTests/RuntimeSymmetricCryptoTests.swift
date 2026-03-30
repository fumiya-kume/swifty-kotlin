import Foundation
@testable import Runtime
import XCTest

final class RuntimeSymmetricCryptoTests: IsolatedRuntimeXCTestCase {
    private func runtimeString(_ text: String) -> Int {
        text.withCString { cstr in
            cstr.withMemoryRebound(to: UInt8.self, capacity: text.utf8.count) { ptr in
                Int(bitPattern: kk_string_from_utf8(ptr, Int32(text.utf8.count)))
            }
        }
    }

    private func runtimeBytes(_ bytes: [UInt8]) -> Int {
        let box = RuntimeArrayBox(length: bytes.count)
        for (index, byte) in bytes.enumerated() {
            box.elements[index] = Int(Int8(bitPattern: byte))
        }
        return registerRuntimeObject(box)
    }

    private func byteArray(from raw: Int) -> [UInt8] {
        runtimeArrayBox(from: raw)?.elements.map { UInt8(truncatingIfNeeded: $0) } ?? []
    }

    private func roundTrip(
        transformation: String,
        key: [UInt8],
        iv: [UInt8]?,
        plaintext: [UInt8]
    ) -> [UInt8] {
        let cipher = kk_cipher_getInstance(runtimeString(transformation), nil)
        let keySpec = kk_secretkeyspec_new(runtimeBytes(key), runtimeString(keyAlgorithmName(from: transformation)), nil)
        if let iv {
            let ivSpec = kk_ivparameterspec_new(runtimeBytes(iv), nil)
            _ = kk_cipher_init_with_iv(cipher, 1, keySpec, ivSpec, nil)
        } else {
            _ = kk_cipher_init(cipher, 1, keySpec, nil)
        }
        let encrypted = kk_cipher_doFinal(cipher, runtimeBytes(plaintext), nil)

        let decryptCipher = kk_cipher_getInstance(runtimeString(transformation), nil)
        let decryptKeySpec = kk_secretkeyspec_new(runtimeBytes(key), runtimeString(keyAlgorithmName(from: transformation)), nil)
        if let iv {
            let ivSpec = kk_ivparameterspec_new(runtimeBytes(iv), nil)
            _ = kk_cipher_init_with_iv(decryptCipher, 2, decryptKeySpec, ivSpec, nil)
        } else {
            _ = kk_cipher_init(decryptCipher, 2, decryptKeySpec, nil)
        }
        let decrypted = kk_cipher_doFinal(decryptCipher, encrypted, nil)
        return byteArray(from: decrypted)
    }

    private func keyAlgorithmName(from transformation: String) -> String {
        let component = transformation.split(separator: "/").first.map(String.init) ?? transformation
        switch component.uppercased() {
        case "DESEDE", "TRIPLEDES", "3DES":
            return "DESede"
        default:
            return component
        }
    }

    func testRoundTripsSupportedSymmetricCipherModes() {
        let cases: [(String, [UInt8], [UInt8]?, [UInt8])] = [
            ("AES/CBC/PKCS5Padding", Array(0..<16).map { UInt8($0) }, Array(16..<32).map { UInt8($0) }, Array("hello aes cbc".utf8)),
            ("AES/CFB/NoPadding", Array(16..<32).map { UInt8($0) }, Array(32..<48).map { UInt8($0) }, Array("cfb mode".utf8)),
            ("AES/OFB/NoPadding", Array(repeating: 0x11, count: 16), Array(repeating: 0x22, count: 16), Array("ofb mode bytes".utf8)),
            ("AES/CTR/NoPadding", Array(repeating: 0x33, count: 16), Array(repeating: 0x44, count: 16), Array("ctr mode bytes".utf8)),
            ("DES/ECB/NoPadding", Array(repeating: 0x55, count: 8), nil, Array("12345678".utf8)),
            ("DESede/CBC/PKCS5Padding", Array(0..<24).map { UInt8($0) }, Array(repeating: 0x66, count: 8), Array("3des test".utf8)),
        ]

        for (transformation, key, iv, plaintext) in cases {
            XCTAssertEqual(
                roundTrip(transformation: transformation, key: key, iv: iv, plaintext: plaintext),
                plaintext,
                "Round trip failed for \(transformation)"
            )
        }
    }

    func testCipherDoFinalNoArgProducesEmptyRoundTrip() {
        let transformation = "AES/CBC/PKCS5Padding"
        let key = Array(0..<16).map { UInt8($0) }
        let iv = Array(16..<32).map { UInt8($0) }
        let cipher = kk_cipher_getInstance(runtimeString(transformation), nil)
        let keySpec = kk_secretkeyspec_new(runtimeBytes(key), runtimeString("AES"), nil)
        let ivSpec = kk_ivparameterspec_new(runtimeBytes(iv), nil)
        _ = kk_cipher_init_with_iv(cipher, 1, keySpec, ivSpec, nil)

        let encryptedEmpty = kk_cipher_doFinal_noarg(cipher, nil)
        XCTAssertEqual(byteArray(from: encryptedEmpty).count, 16)

        let decryptCipher = kk_cipher_getInstance(runtimeString(transformation), nil)
        let decryptKeySpec = kk_secretkeyspec_new(runtimeBytes(key), runtimeString("AES"), nil)
        let decryptIvSpec = kk_ivparameterspec_new(runtimeBytes(iv), nil)
        _ = kk_cipher_init_with_iv(decryptCipher, 2, decryptKeySpec, decryptIvSpec, nil)
        let decrypted = kk_cipher_doFinal(decryptCipher, encryptedEmpty, nil)
        XCTAssertEqual(byteArray(from: decrypted), [])
    }
}
