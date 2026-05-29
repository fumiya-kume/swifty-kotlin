@testable import CompilerCore
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCompilesBase64EncodeDecodeEdgeCases() throws {
        let source = """
        import kotlin.io.encoding.Base64
        import kotlin.io.encoding.ExperimentalEncodingApi

        @OptIn(ExperimentalEncodingApi::class)
        fun main() {
            val bytes = "foo".encodeToByteArray()
            val encoded = Base64.Default.encode(bytes)
            println(encoded)
            println(Base64.Default.decode(encoded).decodeToString())
            println(Base64.UrlSafe.encode("\\u083e".encodeToByteArray()))
            println(Base64.Mime.decode("Zm9v\\r\\nYmFy").decodeToString())
            println(Base64.Pem.decode("Zm9v\\r\\nYmFy").decodeToString())
            val encodedBytes = Base64.Default.encodeToByteArray(bytes)
            println(Base64.Default.encode(Base64.Default.decodeFromByteArray(encodedBytes)))
            println(Base64.UrlSafe.encode(Base64.UrlSafe.decodeFromByteArray(Base64.UrlSafe.encodeToByteArray("\\u083e".encodeToByteArray()))))
            println(Base64.Default.encode(Base64.Mime.decodeFromByteArray("Zm9v\\r\\nYmFy".encodeToByteArray())))
            val foob = "foob".encodeToByteArray()
            println(Base64.UrlSafe.encode(foob))
            val defaultNoPad = Base64.Default.withPadding(Base64.PaddingOption.ABSENT)
            println(defaultNoPad.encode(foob))
            println(Base64.Default.encode(defaultNoPad.decode("Zm9vYg")))
            val urlSafeNoPad = Base64.UrlSafe.withPadding(Base64.PaddingOption.ABSENT_OPTIONAL)
            println(urlSafeNoPad.encode("\\u083e!".encodeToByteArray()))
            println(Base64.Default.encode(urlSafeNoPad.decode("4KC-IQ==")))
            val mimeNoPad = Base64.Mime.withPadding(Base64.PaddingOption.ABSENT)
            println(mimeNoPad.encode(foob))
        }
        """

        let normalizedStdout = try runCodegenExecutableStdout(source, moduleName: "Base64EdgeCases")
        XCTAssertEqual(
            normalizedStdout,
            """
            Zm9v
            foo
            4KC-
            foobar
            foobar
            Zm9v
            4KC-
            Zm9vYmFy
            Zm9vYg==
            Zm9vYg
            Zm9vYg==
            4KC-IQ
            4KC+IQ==
            Zm9vYg
            """ + "\n"
        )
    }
}
