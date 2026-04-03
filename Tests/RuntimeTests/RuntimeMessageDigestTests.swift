import Foundation
@testable import Runtime
import XCTest

final class RuntimeMessageDigestTests: IsolatedRuntimeXCTestCase {
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

    private func hexBytes(_ hex: String) -> [UInt8] {
        stride(from: 0, to: hex.count, by: 2).map { index in
            let start = hex.index(hex.startIndex, offsetBy: index)
            let end = hex.index(start, offsetBy: 2)
            return UInt8(hex[start..<end], radix: 16) ?? 0
        }
    }

    func testSupportedMessageDigestsMatchKnownVectors() {
        let input = runtimeBytes(Array("abc".utf8))
        let expectedByAlgorithm: [(String, String)] = [
            ("MD5", "900150983cd24fb0d6963f7d28e17f72"),
            ("SHA-1", "a9993e364706816aba3e25717850c26c9cd0d89d"),
            ("SHA-256", "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"),
            ("SHA-512", "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f"),
        ]

        for (algorithm, expectedHex) in expectedByAlgorithm {
            let digest = kk_message_digest_getInstance(runtimeString(algorithm), nil)
            let output = kk_message_digest_digest(digest, input, nil)
            XCTAssertEqual(byteArray(from: output), hexBytes(expectedHex), "Digest mismatch for \(algorithm)")
        }
    }

    func testSupportedHmacAlgorithmsMatchKnownVectors() {
        let expectedByAlgorithm: [(String, String)] = [
            ("HmacMD5", "d2fe98063f876b03193afb49b4979591"),
            ("HmacSHA1", "4fd0b215276ef12f2b3e4c8ecac2811498b656fc"),
            ("HmacSHA256", "9c196e32dc0175f86f4b1cb89289d6619de6bee699e4c378e68309ed97a1a6ab"),
            ("HmacSHA512", "3926a207c8c42b0c41792cbd3e1a1aaaf5f7a25704f62dfc939c4987dd7ce060009c5bb1c2447355b3216f10b537e9afa7b64a4e5391b0d631172d07939e087a"),
        ]

        for (algorithm, expectedHex) in expectedByAlgorithm {
            let mac = kk_mac_getInstance(runtimeString(algorithm), nil)
            let algoKey = kk_secretkeyspec_new(runtimeBytes(Array("key".utf8)), runtimeString(algorithm), nil)
            XCTAssertNotEqual(algoKey, 0)
            XCTAssertEqual(kk_mac_init(mac, algoKey, nil), 0)
            let output = kk_mac_doFinal(mac, runtimeBytes(Array("abc".utf8)), nil)
            XCTAssertEqual(byteArray(from: output), hexBytes(expectedHex), "HMAC mismatch for \(algorithm)")
        }
    }
}
