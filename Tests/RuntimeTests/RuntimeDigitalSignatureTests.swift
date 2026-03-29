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
        return kk_signature_verify(verifier, signatureBytes, nil) == kk_box_bool(1)
    }

    func testSignatureRoundTripsWithSHA1AndSHA256() {
        let message = Array("digital signature".utf8)
        XCTAssertTrue(signatureRoundTrip(algorithm: "SHA1withRSA", message: message))
        XCTAssertTrue(signatureRoundTrip(algorithm: "SHA256withRSA", message: message))
    }

    func testCertificateFactoryAndCertPathValidatorAcceptSelfSignedCertificate() {
        let certPem = """
        -----BEGIN CERTIFICATE-----
        MIIDDzCCAfegAwIBAgIUPZipTM3RP7iQNCwnln2G4iJ6ttEwDQYJKoZIhvcNAQEL
        BQAwFzEVMBMGA1UEAwwMU3dpZnR5SyBUZXN0MB4XDTI2MDMyOTAwMDEwNVoXDTI2
        MDMzMDAwMDEwNVowFzEVMBMGA1UEAwwMU3dpZnR5SyBUZXN0MIIBIjANBgkqhkiG
        9w0BAQEFAAOCAQ8AMIIBCgKCAQEAlku63KxXs326uo5G1N+fgtjPta9Rxf0HHuOF
        o9Et/Vjtg8h8XgHjdx40CJoMCJGvwuEPQwx1HQk1RvscxG+011iQgnHa8TEWKN1R
        paqwO5rWDoEsuNT46Cti13aBNpTyzs3CLLIhUJyskQB0iIGVbnbYWZGTjapAiRJF
        tDxWp/yTITGL4onY6Q+q/XQWxTSMloOE+tQqNppvEF7UHB6P+KaLs5lq8bBLX2JI
        CoPCAUmGO0HRBmadAwPASEWS6PZWLF38xYB6nIjVr1UWy0o863lSVIQuyNn7IPpy
        65neQOwmUT2gAnK8Xibax7x1NIQr6Gjh+uDZrWsun35cLrByewIDAQABo1MwUTAd
        BgNVHQ4EFgQUVYEM+pJQijRnKECUzoTsJSZfqhYwHwYDVR0jBBgwFoAUVYEM+pJQ
        ijRnKECUzoTsJSZfqhYwDwYDVR0TAQH/BAUwAwEB/zANBgkqhkiG9w0BAQsFAAOC
        AQEAdbFxWGSqubmAfM85FYHLwzWee1Sk+jzlUbkiPFw2wg0SEX3yIycQH/hEjUfZ
        BFuPtUPHg3TNrnxEjBipYockhc6zUSmCVW5JLOHCGXL+rpfbeS533o1wTVT7nMVN
        m6/cu4hSF8tbkJMMbA/vnhZZwE7QvhQ38n2vlIau5DSWK1jxK/qV2LmmiLO4Cftw
        AbX3KEWT0hk4kW3SUIcTAG0H+odMSAMMO7gmOnFgMvAKuRPzkkHQIJ2+YaV0qVr8
        6SoR3gHQvbiaQD9KL5USUTvXlfCwaCsXF5ufW5Sjx8R0p3O4tOlmk/H67jk11K1C
        NyQLSdKDXkB4nfAdXyzvenWRxQ==
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
            kk_certpathvalidator_validate(validator, certPath, parameters, nil),
            kk_box_bool(1)
        )
    }
}
