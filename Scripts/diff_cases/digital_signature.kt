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
        MIIDDzCCAfegAwIBAgIUcFVKxN1SswLgzUjzHyPAjHfPjGkwDQYJKoZIhvcNAQEL
        BQAwFzEVMBMGA1UEAwwMU3dpZnR5SyBUZXN0MB4XDTI2MDQwMjAxMDczMVoXDTM2
        MDMzMDAxMDczMVowFzEVMBMGA1UEAwwMU3dpZnR5SyBUZXN0MIIBIjANBgkqhkiG
        9w0BAQEFAAOCAQ8AMIIBCgKCAQEAqPFu3Cqkgi/m0kXqKzCslYne96Qn+U2jWkFq
        DSTIe6ODCUicHjdraDCshKdh2b2ji0x5jTyOqPiphDZAfQGVMKRmBLfwRSVr6GSC
        +ZzHl7sjJzC+sy/nGpl3o6CDXqcFqxpAWZ1LjDxrrXUauupjT+D6XQgHcl+xMb6+
        doDuGVrh9ISJ9N5k5v/1rwDbAtONJN1/nnIG8c/2KIbyC/Bi68syGWU7qPMKvEp2
        NB5kkN4Ou1QWnOThOAFLY6aZYJ+hVAHx1EDWhh4RKNWOc5rK/Mfcfl3i9seozjfb
        f7Ud2yx+XzCovGzFYhAvxULwRS3KowPxZx8TqGedE2uc4L9cUwIDAQABo1MwUTAd
        BgNVHQ4EFgQUVkcRtpz46E2fkLbaezb/6mm+fFAwHwYDVR0jBBgwFoAUVkcRtpz4
        6E2fkLbaezb/6mm+fFAwDwYDVR0TAQH/BAUwAwEB/zANBgkqhkiG9w0BAQsFAAOC
        AQEAdSCqrLnSX86r+9xTj8eMTP+qh29MB96KOpw2GWToOsrbs//XJauhMfyZ4kkl
        7O5QTs97N1u2OomBpH9KFOR1ksm7Py0cOyx4SGEgqSV0rJjm0Funclv4BaKqJ96s
        XLj5k1BftgTWWymkfK/uFy+2VfdEu+v0H4CInon7LY3mN/8jseRnz2QCTFmItodN
        e2yo/y1PRxiTpKYaWb2gCh21oV5A+jXCM7yXVBhNZVkJA9pscCSvnqtnZdzeFwaE
        NBWCMzK0AGJUUihDIp41CsnCKKD13PRq38SHhF6W66hQXpGvLU4S1zWEH4OPLHwS
        qubAN1ZdyYrmalZrl5TR0XqmPw==
        -----END CERTIFICATE-----
    """.trimIndent().toByteArray()

    val certificateFactory = CertificateFactory.getInstance("X.509")
    val certificate = certificateFactory.generateCertificate(certificatePem)
    val certPath = certificateFactory.generateCertPath(listOf(certificate))
    val trustAnchor = TrustAnchor(certificate, null)
    val parameters = PKIXParameters(listOf(trustAnchor))
    val validator = CertPathValidator.getInstance("PKIX")
    val valid = validator.validate(certPath, parameters)
}
