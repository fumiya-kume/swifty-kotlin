@testable import CompilerCore
import XCTest

final class KotlinCompilationMessageDigestTests: XCTestCase {
    func testCompile_messageDigestBasicUsage() throws {
        try assertKotlinCompilesToKIR("""
        import java.security.getInstance

        fun main() {
            val md = getInstance("SHA-256")
            val bytes = byteArrayOf(97, 98, 99)
            val digest = md.digest(bytes)
        }
        """)
    }

    func testCompile_hmacBasicUsage() throws {
        try assertKotlinCompilesToKIR("""
        import javax.crypto.Mac
        import javax.crypto.spec.SecretKeySpec

        fun main() {
            val key = SecretKeySpec(byteArrayOf(107, 101, 121), "HmacSHA256")
            val mac = Mac.getInstance("HmacSHA256")
            mac.init(key)
            val bytes = byteArrayOf(97, 98, 99)
            val digest = mac.doFinal(bytes)
        }
        """)
    }
}
