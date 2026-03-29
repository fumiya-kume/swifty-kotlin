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
    """.trimIndent().toByteArray()

    val certificateFactory = CertificateFactory.getInstance("X.509")
    val certificate = certificateFactory.generateCertificate(certificatePem)
    val certPath = CertPath(listOf(certificate))
    val trustAnchor = TrustAnchor(certificate)
    val parameters = PKIXParameters(listOf(trustAnchor))
    val validator = CertPathValidator.getInstance("PKIX")
    val valid = validator.validate(certPath, parameters)
}
