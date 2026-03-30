@testable import CompilerCore
import XCTest

final class KotlinCompilationDigitalSignatureTests: XCTestCase {
    func testCompile_digitalSignatureBasicUsage() throws {
        try assertKotlinCompilesToKIR(##"""
        import java.security.KeyPairGenerator
        import java.security.Signature
        import java.security.cert.CertPath
        import java.security.cert.CertPathValidator
        import java.security.cert.CertificateFactory
        import java.security.cert.PKIXParameters
        import java.security.cert.TrustAnchor

        fun main() {
            val generator = KeyPairGenerator.getInstance("RSA")
            generator.initialize(2048)
            val keyPair = generator.generateKeyPair()

            val message = byteArrayOf(1, 2, 3, 4)
            val signer = Signature.getInstance("SHA256withRSA")
            signer.initSign(keyPair.privateKey)
            signer.update(message)
            val sha256Signature = signer.sign()

            val verifier = Signature.getInstance("SHA1withRSA")
            verifier.initVerify(keyPair.publicKey)
            verifier.update(message)
            val verified = verifier.verify(sha256Signature)

            val certificatePem = """
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
            """.trimIndent().toByteArray()

            val factory = CertificateFactory.getInstance("X.509")
            val certificate = factory.generateCertificate(certificatePem)
            val path = CertPath(listOf(certificate))
            val trustAnchor = TrustAnchor(certificate)
            val parameters = PKIXParameters(listOf(trustAnchor))
            val validator = CertPathValidator.getInstance("PKIX")
            val valid = validator.validate(path, parameters)
        }
        """##)
    }
}
