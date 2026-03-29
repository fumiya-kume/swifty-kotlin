@testable import CompilerCore
import XCTest

final class KotlinCompilationCacheTests: XCTestCase {
    func testCompile_cacheBasicUsage() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val cache = Cache(2)
            cache.put(1, 10)
            cache.put(2, 20)
            val a = cache.get(1)
            val size = cache.size()
        }
        """)
    }
}
