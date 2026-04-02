// SKIP-DIFF: uses JDK security stubs (KeyPairGenerator, Signature, etc.) that kswiftc provides natively but kotlinc rejects due to protected/abstract constructors
import java.security.KeyPairGenerator
import java.security.Signature
import java.io.ByteArrayInputStream
import java.security.cert.CertPathValidator
import java.security.cert.CertificateFactory
import java.security.cert.PKIXParameters
import java.security.cert.TrustAnchor
import java.security.cert.X509Certificate

fun main() {
    val generator = KeyPairGenerator("RSA")
    generator.initialize(2048)
    val keyPair = generator.generateKeyPair()

    val message = byteArrayOf(1, 2, 3, 4, 5, 6)
    val signerSha1 = Signature.getInstance("SHA1withRSA")
    signerSha1.initSign(keyPair.private)
    signerSha1.update(message)
    val signatureSha1 = signerSha1.sign()

    val verifierSha1 = Signature.getInstance("SHA1withRSA")
    verifierSha1.initVerify(keyPair.public)
    verifierSha1.update(message)
    val verifiedSha1 = verifierSha1.verify(signatureSha1)
    check(verifiedSha1) { "SHA1withRSA verification failed" }

    val signerSha256 = Signature.getInstance("SHA256withRSA")
    signerSha256.initSign(keyPair.private)
    signerSha256.update(message)
    val signatureSha256 = signerSha256.sign()

    val verifierSha256 = Signature.getInstance("SHA256withRSA")
    verifierSha256.initVerify(keyPair.public)
    verifierSha256.update(message)
    val verifiedSha256 = verifierSha256.verify(signatureSha256)
    check(verifiedSha256) { "SHA256withRSA verification failed" }

    val certificatePem = """
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
    """.trimIndent().toByteArray()

    val certificateFactory = CertificateFactory("X.509")
    val certificate = certificateFactory.generateCertificate(certificatePem)
    val certPath = certificateFactory.generateCertPath(listOf(certificate))
    val trustAnchor = TrustAnchor(certificate, null)
    val parameters = PKIXParameters(setOf(trustAnchor))
    val validator = CertPathValidator("PKIX")
    val valid = validator.validate(certPath, parameters)
}
