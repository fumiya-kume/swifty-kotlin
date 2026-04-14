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
        let generator = kk_keypairgenerator_getInstance(0, runtimeString("RSA"), nil)
        _ = kk_keypairgenerator_initialize(generator, 2048, nil)
        return kk_keypairgenerator_generateKeyPair(generator, nil)
    }

    private func signatureRoundTrip(algorithm: String, message: [UInt8]) -> Bool {
        let keyPair = makeKeyPair()
        guard keyPair != 0 else {
            XCTFail("Key pair generation failed")
            return false
        }
        let publicKey = kk_keypair_publicKey(keyPair, nil)
        guard publicKey != 0 else {
            XCTFail("Public key extraction failed")
            return false
        }
        let privateKey = kk_keypair_privateKey(keyPair, nil)
        guard privateKey != 0 else {
            XCTFail("Private key extraction failed")
            return false
        }

        let signer = kk_signature_getInstance(0, runtimeString(algorithm), nil)
        _ = kk_signature_initSign(signer, privateKey, nil)
        _ = kk_signature_update(signer, runtimeBytes(message), nil)
        let signatureBytes = kk_signature_sign(signer, nil)
        guard signatureBytes != 0 else {
            XCTFail("Signature creation returned null")
            return false
        }

        let verifier = kk_signature_getInstance(0, runtimeString(algorithm), nil)
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
        MIIDETCCAfmgAwIBAgIUcxF2L3bduVaHSKZgnMkuXiPhUq0wDQYJKoZIhvcNAQEL
        BQAwFzEVMBMGA1UEAwwMU3dpZnR5SyBUZXN0MCAXDTI2MDMzMDA1MzMxOVoYDzIx
        MjYwMzA2MDUzMzE5WjAXMRUwEwYDVQQDDAxTd2lmdHlLIFRlc3QwggEiMA0GCSqG
        SIb3DQEBAQUAA4IBDwAwggEKAoIBAQClxokntX5Xk6MnHIS4tmtch2dmAldd8p2p
        1BxQ8CmcirtKjT0HaDj+0PCFXz7wYXJTPI+MxmUeOljZ4qXC1YiuOUKNGdocAvON
        Q8QhW3oGhYq5hRQFxSAc9tedSr+i7nQ834h5R305HC1XGFQMhFukPjKI4NlqvfAF
        nf69Oig3ORa92A3pzo26/owcxsnz2K5pwZ8Mi8bgDKqrq/3fAQtAvAi0mqK5WUbs
        nqf49hpdev3QtAjpvJlaKSFVqzaC3rL5zkQu+Zv+1Uet6c5dXvVPe0YniZk9Kdb1
        e48Fq4afxzjf3Q6PlXjOa/5v1uMqRtxdHUTCE9rOS9jJvqYFy8AjAgMBAAGjUzBR
        MB0GA1UdDgQWBBSPJ+Hv9iVf0u+bEPdKqikI5zjJyTAfBgNVHSMEGDAWgBSPJ+Hv
        9iVf0u+bEPdKqikI5zjJyTAPBgNVHRMBAf8EBTADAQH/MA0GCSqGSIb3DQEBCwUA
        A4IBAQAIdP1M8HY2R6PEsWK9gIiGR0CIaIrGiP5VshD81Mdd6FBShljEFLwzmFQ6
        4NK42mPI5LM12N3cC9RlIHecWTxsXXEoi5WMPaJESWRLX9TmdghZoUb3/OqYvRD1
        gUn0/gp953+jQI++vhSFYoxdFMxYmn1uEDWMGR5kL6ZTk9yWqnjP0btge5uI9OdZ
        C6bJ1m9z93Qi2TFvpNihj90nzZbo/Love3HhZmkdMzPp0MSBDMk/0AUD2dtXr8pE
        zprZgaiWWRxlWLZdOiK1MY8YiRpCChD5wD14r7A7yqm3YfsMUjd+oFy9TsUGvqmS
        MZoskJV+S+JCSRI+6c7i54cdin4E
        -----END CERTIFICATE-----
        """

        let factory = kk_certificatefactory_getInstance(0, runtimeString("X.509"), nil)

        // Convert PEM to DER bytes before passing to the native certificate factory
        let pemLines = certPem
            .split(separator: "\n")
            .filter { !$0.hasPrefix("-----") && !$0.isEmpty }
        let derDataOptional = Data(base64Encoded: pemLines.joined())

        guard let derData = derDataOptional else {
            XCTFail("Failed to decode certificate PEM to DER")
            return
        }

        let certificate = kk_certificatefactory_generateCertificate(factory, runtimeBytes(Array(derData)), nil)
        XCTAssertNotEqual(certificate, 0, "certificate factory returned null")
        XCTAssertGreaterThan(byteArray(from: kk_x509certificate_getEncoded(certificate, nil)).count, 0)
        XCTAssertNotEqual(kk_x509certificate_getPublicKey(certificate, nil), 0)

        let certPath = kk_certpath_new(runtimeList([certificate]), nil)
        let trustAnchor = kk_trustanchor_new(certificate, nil)
        let parameters = kk_pkixparameters_new(runtimeList([trustAnchor]), nil)
        let validator = kk_certpathvalidator_getInstance(0, runtimeString("PKIX"), nil)
        XCTAssertEqual(
            kk_unbox_bool(kk_certpathvalidator_validate(validator, certPath, parameters, nil)),
            1
        )
    }
}
