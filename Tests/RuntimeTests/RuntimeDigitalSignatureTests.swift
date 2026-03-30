import Foundation
@testable import Runtime
import XCTest

final class RuntimeDigitalSignatureTests: IsolatedRuntimeXCTestCase {
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

    private func runtimeList(_ elements: [Int]) -> Int {
        registerRuntimeObject(RuntimeListBox(elements: elements))
    }

    private func byteArray(from raw: Int) -> [UInt8] {
        runtimeArrayBox(from: raw)?.elements.map { UInt8(truncatingIfNeeded: $0) } ?? []
    }

    private func makeKeyPair() -> Int {
        let generator = kk_keypairgenerator_getInstance(runtimeString("RSA"), nil)
        _ = kk_keypairgenerator_initialize(generator, 2048, nil)
        return kk_keypairgenerator_generateKeyPair(generator, nil)
    }

    private func signatureRoundTrip(algorithm: String, message: [UInt8]) -> Bool {
        let keyPair = makeKeyPair()
        let publicKey = kk_keypair_publicKey(keyPair, nil)
        let privateKey = kk_keypair_privateKey(keyPair, nil)

        let signer = kk_signature_getInstance(runtimeString(algorithm), nil)
        _ = kk_signature_initSign(signer, privateKey, nil)
        _ = kk_signature_update(signer, runtimeBytes(message), nil)
        let signatureBytes = kk_signature_sign(signer, nil)

        let verifier = kk_signature_getInstance(runtimeString(algorithm), nil)
        _ = kk_signature_initVerify(verifier, publicKey, nil)
        _ = kk_signature_update(verifier, runtimeBytes(message), nil)
        return kk_unbox_bool(kk_signature_verify(verifier, signatureBytes, nil)) == 1
    }

    func testSignatureRoundTripsWithSHA1AndSHA256() {
        let message = Array("digital signature".utf8)
        XCTAssertTrue(signatureRoundTrip(algorithm: "SHA1withRSA", message: message))
        XCTAssertTrue(signatureRoundTrip(algorithm: "SHA256withRSA", message: message))
    }

    func testCertificateFactoryAndCertPathValidatorAcceptSelfSignedCertificate() {
        let certPem = """
        -----BEGIN CERTIFICATE-----
        MIIDDjCCAfagAwIBAgIUGqdO1DIpVQyQlOrUms0GWSsS4I8wDQYJKoZIhvcNAQEL
        BQAwFzEVMBMGA1UEAwwMU3dpZnR5SyBUZXN0MCAXDTI2MDMzMDA0NTQzNloYDzIx
        MjYwMzA2MDQ1NDM2WjAXMRUwEwYDVQQDDAxTd2lmdHlLIFRlc3QwggEiMA0GCSqG
        SIb3DQEBAQUAA4IBDwAwggEKAoIBAQDDE4Zf0rQzaCbFfPvhk0xYWVOrM+eERilK
        oqlBcZ0oCpIfMzd9i6cKw09t0EgWVZYhfCiVNChYuNWFF1A6gjCnkg0+aCAiVvwF
        ge23sv6Ze+B71jCQrWLuYrTX7Y9OHFV4vqnVKoJy7TgoxjeFAKMadNEx+eDpiYIy
        gACsDvOvQZe8E8FfFO/6OCUWUgS9dGKAjH6m6tZRAjaYsjSciImbA6YoKVyhdMMr
        Qqkyzl6Ds2JclincuCu7ik5C92Vp1oZ0KCHutVgjg8hgzRlLs/B86zCwlv3mymAN
        nLxFLwHaBzMWOocQFdLJnKp82L+c3/DqOBzdpILXEECxyypApAXlAgMBAAGjUDBO
        MB0GA1UdDgQWBBSTtkADtYymAOwTsNsZ+5RL40faGDAfBgNVHSMEGDAWgBSTtkAD
        tYymAOwTsNsZ+5RL40faGDAMBgNVHRMEBTADAQH/MA0GCSqGSIb3DQEBCwUAA4IB
        AQCsHkaKMFdJq5ddwGDFvg+CJUzUtB0bcDRPvPjtbmcPlM5C+DtqCnJYVu0PpThJ
        u8pEzwvxvFnFGIwXBuIA56DwKmDd9889CCdCjBccbY9mkYdNdUQrL/G9TDDdAEc+
        p/oIgZezMoVGvAJmNSoSQkdJKbfEVE0l5MaGclpRw3MwBAKJZ9RUA8586fe+Ppzy
        QqxJ282n5LSdldCaUFBwnJ46mCogCEwWVxdfneWSis05z4zfrtpghJerDdCd8bWv
        tptIffOOi6JLzz0pc1HbgQ/erEuJKTZ88vi76oMkRZ0l2/SDxRHRDVnI3jQOQs46
        DrfKYpgvcEDd5o7Q+erHRiiv
        -----END CERTIFICATE-----
        """

        let factory = kk_certificatefactory_getInstance(runtimeString("X.509"), nil)
        let certificate = kk_certificatefactory_generateCertificate(factory, runtimeBytes(Array(certPem.utf8)), nil)
        XCTAssertGreaterThan(byteArray(from: kk_x509certificate_getEncoded(certificate, nil)).count, 0)
        XCTAssertNotEqual(kk_x509certificate_getPublicKey(certificate, nil), 0)

        let certPath = kk_certpath_new(runtimeList([certificate]), nil)
        let trustAnchor = kk_trustanchor_new(certificate, nil)
        let parameters = kk_pkixparameters_new(runtimeList([trustAnchor]), nil)
        let validator = kk_certpathvalidator_getInstance(runtimeString("PKIX"), nil)
        XCTAssertEqual(
            kk_unbox_bool(kk_certpathvalidator_validate(validator, certPath, parameters, nil)),
            1
        )
    }
}
