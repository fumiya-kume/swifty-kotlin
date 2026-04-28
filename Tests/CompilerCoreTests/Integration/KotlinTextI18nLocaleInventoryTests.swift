@testable import CompilerCore
import XCTest

// MARK: - STDLIB-I18N-COMMON-001: kotlin.text / common formatting and locale inventory
//
// This file documents which Kotlin common-scope i18n / locale APIs are implemented
// in the KSwiftK runtime and which are absent (gaps).
//
// Implemented (common scope, backed by runtime functions):
//   - String.lowercase()                   → kk_string_lowercase
//   - String.uppercase()                   → kk_string_uppercase
//   - String.lowercase(Locale)             → kk_string_lowercase_locale
//   - String.uppercase(Locale)             → kk_string_uppercase_locale
//   - String.compareTo(String, Locale)     → kk_string_compareTo_locale
//   - String.toInt(radix)                  → kk_string_toInt_radix  (throwing)
//   - String.toIntOrNull()                 → kk_string_toIntOrNull  (no-radix variant)
//   - String.toIntOrNull(radix)            → kk_string_toIntOrNull_radix
//   - String.format(format, vararg args)   → kk_string_format  (platform fmt, no locale overload)
//   - Char.uppercase()                     → kk_char_uppercase  (returns String per Kotlin spec)
//   - Char.lowercase()                     → kk_char_lowercase  (returns String per Kotlin spec)
//   - Char.titlecase()                     → kk_char_titlecase
//
// Gaps (absent in common scope):
//   - String.format(locale, format, vararg args)  — locale-parameterised overload absent
//   - Char.uppercase(Locale)  — locale-aware single-char conversion absent
//   - Char.lowercase(Locale)  — locale-aware single-char conversion absent
//   - NumberFormat (java.text) is JVM/platform only, not common multiplatform

final class KotlinTextI18nLocaleInventoryTests: XCTestCase {

    // MARK: - String.lowercase() / String.uppercase() — no locale (common)

    func testStringLowercaseNoLocale() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val s = "Hello WORLD"
            val lower = s.lowercase()
            println(lower)
        }
        """)
    }

    func testStringUppercaseNoLocale() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val s = "hello world"
            val upper = s.uppercase()
            println(upper)
        }
        """)
    }

    // MARK: - String.lowercase(Locale) / String.uppercase(Locale)

    func testStringLowercaseWithLocale_enUS() throws {
        try assertKotlinCompilesToKIR("""
        import java.util.Locale

        fun main() {
            val locale = Locale("en", "US")
            val s = "HELLO WORLD"
            val lower = s.lowercase(locale)
            println(lower)
        }
        """)
    }

    func testStringUppercaseWithLocale_enUS() throws {
        try assertKotlinCompilesToKIR("""
        import java.util.Locale

        fun main() {
            val locale = Locale("en", "US")
            val s = "hello world"
            val upper = s.uppercase(locale)
            println(upper)
        }
        """)
    }

    func testStringLowercaseWithLocale_trTR() throws {
        // Turkish locale: dotted-I (I) lowercases to 'i' in tr-TR context
        try assertKotlinCompilesToKIR("""
        import java.util.Locale

        fun main() {
            val tr = Locale("tr", "TR")
            val result = "I".lowercase(tr)
            println(result)
        }
        """)
    }

    func testStringUppercaseWithLocale_trTR() throws {
        // Turkish locale: 'i' uppercases to 'I' with locale context
        try assertKotlinCompilesToKIR("""
        import java.util.Locale

        fun main() {
            val tr = Locale("tr", "TR")
            val result = "i".uppercase(tr)
            println(result)
        }
        """)
    }

    // MARK: - String.compareTo with Locale

    func testStringCompareToWithLocale() throws {
        try assertKotlinCompilesToKIR("""
        import java.util.Locale

        fun main() {
            val locale = Locale("en", "US")
            val cmp = "apple".compareTo("banana", locale)
            println(cmp)
        }
        """)
    }

    // MARK: - String.toInt(radix) — throwing variant

    func testStringToIntRadix2() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val n = "1010".toInt(2)
            println(n)
        }
        """)
    }

    func testStringToIntRadix16() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val n = "ff".toInt(16)
            println(n)
        }
        """)
    }

    func testStringToIntRadixInvalidThrows() throws {
        // radix outside 2..36 must throw IllegalArgumentException
        try assertKotlinCompilesToKIR("""
        fun main() {
            try {
                val n = "10".toInt(1)
            } catch (e: IllegalArgumentException) {
                println("caught: " + e.message)
            }
        }
        """)
    }

    func testStringToIntRadixBadInputThrows() throws {
        // input not representable in given radix must throw NumberFormatException
        try assertKotlinCompilesToKIR("""
        fun main() {
            try {
                val n = "xyz".toInt(10)
            } catch (e: NumberFormatException) {
                println("caught")
            }
        }
        """)
    }

    // MARK: - String.toIntOrNull() / String.toIntOrNull(radix)

    func testStringToIntOrNullValid() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val n: Int? = "42".toIntOrNull()
            println(n)
        }
        """)
    }

    func testStringToIntOrNullInvalid() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val n: Int? = "not_a_number".toIntOrNull()
            println(n)
        }
        """)
    }

    func testStringToIntOrNullRadixValid() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val n: Int? = "ff".toIntOrNull(16)
            println(n)
        }
        """)
    }

    func testStringToIntOrNullRadixInvalid() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val n: Int? = "xz".toIntOrNull(16)
            println(n)
        }
        """)
    }

    // MARK: - String.format (no-locale overload — implemented)

    func testStringFormatNoLocale() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val result = String.format("Hello, %s! You are %d years old.", "Alice", 30)
            println(result)
        }
        """)
    }

    func testStringFormatFloatSpecifier() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val result = String.format("Pi is approximately %.2f", 3.14159)
            println(result)
        }
        """)
    }

    // MARK: - Char.uppercase() / Char.lowercase() — no locale (common)

    func testCharUppercaseNoLocale() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val c = 'a'
            val upper = c.uppercase()
            println(upper)
        }
        """)
    }

    func testCharLowercaseNoLocale() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val c = 'Z'
            val lower = c.lowercase()
            println(lower)
        }
        """)
    }

    func testCharTitlecase() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val c = 'a'
            val title = c.titlecase()
            println(title)
        }
        """)
    }

    // MARK: - Char classification helpers used in i18n context

    func testCharIsUpperCase() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val result = 'A'.isUpperCase()
            println(result)
        }
        """)
    }

    func testCharIsLowerCase() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            val result = 'a'.isLowerCase()
            println(result)
        }
        """)
    }

    // MARK: - Locale construction edge cases

    func testLocaleByIdentifier() throws {
        try assertKotlinCompilesToKIR("""
        import java.util.Locale

        fun main() {
            val locale = Locale("en_US")
            println(locale.language)
            println(locale.country)
        }
        """)
    }

    func testLocaleByLanguageAndCountry() throws {
        try assertKotlinCompilesToKIR("""
        import java.util.Locale

        fun main() {
            val locale = Locale("de", "DE")
            println(locale.language)
            println(locale.country)
        }
        """)
    }

    func testLocaleGetDefault() throws {
        try assertKotlinCompilesToKIR("""
        import java.util.Locale

        fun main() {
            val def = Locale.getDefault()
            println(def.language)
        }
        """)
    }

    func testLocaleSetDefault() throws {
        try assertKotlinCompilesToKIR("""
        import java.util.Locale

        fun main() {
            val fr = Locale("fr", "FR")
            Locale.setDefault(fr)
            val def = Locale.getDefault()
            println(def.language)
        }
        """)
    }

    func testLocaleDisplayLanguage() throws {
        try assertKotlinCompilesToKIR("""
        import java.util.Locale

        fun main() {
            val locale = Locale("en", "US")
            println(locale.displayLanguage)
        }
        """)
    }

    func testLocaleEquality() throws {
        try assertKotlinCompilesToKIR("""
        import java.util.Locale

        fun main() {
            val a = Locale("en", "US")
            val b = Locale("en", "US")
            val same = a.equals(b)
            println(same)
        }
        """)
    }

    func testLocaleHashCode() throws {
        try assertKotlinCompilesToKIR("""
        import java.util.Locale

        fun main() {
            val locale = Locale("en", "US")
            val hash = locale.hashCode()
            println(hash)
        }
        """)
    }
}
