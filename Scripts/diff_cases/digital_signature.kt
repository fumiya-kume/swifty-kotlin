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

    val message = byteArrayOf(1, 2, 3, 4, 5, 6)
    val signerSha1 = Signature.getInstance("SHA1withRSA")
    signerSha1.initSign(keyPair.privateKey)
    signerSha1.update(message)
    val signatureSha1 = signerSha1.sign()

    val verifierSha1 = Signature.getInstance("SHA1withRSA")
    verifierSha1.initVerify(keyPair.publicKey)
    verifierSha1.update(message)
    val verifiedSha1 = verifierSha1.verify(signatureSha1)

    val signerSha256 = Signature.getInstance("SHA256withRSA")
    signerSha256.initSign(keyPair.privateKey)
    signerSha256.update(message)
    val signatureSha256 = signerSha256.sign()

    val verifierSha256 = Signature.getInstance("SHA256withRSA")
    verifierSha256.initVerify(keyPair.publicKey)
    verifierSha256.update(message)
    val verifiedSha256 = verifierSha256.verify(signatureSha256)

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

    val certificateFactory = CertificateFactory.getInstance("X.509")
    val certificate = certificateFactory.generateCertificate(certificatePem)
    val certPath = CertPath(listOf(certificate))
    val trustAnchor = TrustAnchor(certificate)
    val parameters = PKIXParameters(listOf(trustAnchor))
    val validator = CertPathValidator.getInstance("PKIX")
    val valid = validator.validate(certPath, parameters)
}
