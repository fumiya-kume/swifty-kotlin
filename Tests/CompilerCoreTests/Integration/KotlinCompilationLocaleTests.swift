@testable import CompilerCore
import XCTest

final class KotlinCompilationLocaleTests: XCTestCase {
    func testCompile_localeBasicUsage() throws {
        try assertKotlinCompilesToKIR("""
        import java.util.Locale

        fun main() {
            val byId = Locale("en_US_POSIX")
            val byParts = Locale("en", "US")
            val language = byId.language
            val country = byId.country
            val variant = byId.variant
            val displayLanguage = byId.displayLanguage
            val current = Locale.getDefault()
            Locale.setDefault(byParts)
            val locales = Locale.getAvailableLocales()
            val same = byId.equals(Locale("en_US_POSIX"))
            val hash = byParts.hashCode()
            println(language)
            println(country)
            println(variant)
            println(displayLanguage)
            println(current)
            println(locales.size)
            println(same)
            println(hash)
        }
        """)
    }
}
