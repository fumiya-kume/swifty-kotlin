@testable import Runtime
import XCTest

final class RuntimeStringLocaleTests: IsolatedRuntimeXCTestCase {
    private func runtimeString(_ text: String) -> Int {
        text.withCString { cstr in
            cstr.withMemoryRebound(to: UInt8.self, capacity: text.utf8.count) { ptr in
                Int(bitPattern: kk_string_from_utf8(ptr, Int32(text.utf8.count)))
            }
        }
    }

    private func stringValue(_ raw: Int) -> String {
        extractString(from: UnsafeMutableRawPointer(bitPattern: raw)) ?? ""
    }

    private func arrayElements(_ raw: Int) -> [Int] {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: raw),
              let array = tryCast(ptr, to: RuntimeArrayBox.self)
        else {
            return []
        }
        return array.elements
    }

    private func boolValue(_ raw: Int) -> Bool {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: raw),
              let box = tryCast(ptr, to: RuntimeBoolBox.self)
        else {
            return false
        }
        return box.value
    }

    func testLocaleLowercaseUsesTurkishRules() {
        let result = kk_string_lowercase_locale(runtimeString("I"), kk_locale_new(runtimeString("tr")))
        XCTAssertEqual(stringValue(result), "ı")
    }

    func testLocaleUppercaseUsesTurkishRules() {
        let result = kk_string_uppercase_locale(runtimeString("i"), kk_locale_new(runtimeString("tr")))
        XCTAssertEqual(stringValue(result), "İ")
    }

    func testLocaleCompareToMatchesBasicOrdering() {
        let result = kk_string_compareTo_locale(
            runtimeString("abc"),
            runtimeString("abd"),
            kk_locale_new(runtimeString("en_US"))
        )
        XCTAssertEqual(result, -1)
    }

    func testLocalePropertiesExposeLanguageCountryAndVariant() {
        let locale = kk_locale_new_language_country(runtimeString("en"), runtimeString("US"))
        XCTAssertEqual(stringValue(kk_locale_language(locale)), "en")
        XCTAssertEqual(stringValue(kk_locale_country(locale)), "US")
        XCTAssertEqual(stringValue(kk_locale_variant(locale)), "")
    }

    func testLocaleDisplayLanguageUsesDefaultLocale() {
        let original = kk_locale_getDefault(0)
        let japanese = kk_locale_new(runtimeString("ja_JP"))
        _ = kk_locale_setDefault(0, japanese)
        defer { _ = kk_locale_setDefault(0, original) }

        let english = kk_locale_new(runtimeString("en_US"))
        let displayLanguage = stringValue(kk_locale_displayLanguage(english))
        XCTAssertFalse(displayLanguage.isEmpty)
    }

    func testLocaleDefaultCanBeOverridden() {
        let original = kk_locale_getDefault(0)
        let locale = kk_locale_new_language_country(runtimeString("tr"), runtimeString("TR"))
        _ = kk_locale_setDefault(0, locale)
        defer { _ = kk_locale_setDefault(0, original) }

        let current = kk_locale_getDefault(0)
        XCTAssertEqual(stringValue(kk_locale_language(current)), "tr")
        XCTAssertEqual(stringValue(kk_locale_country(current)), "TR")
    }

    func testLocaleEqualityAndHashCodeAreValueBased() {
        let lhs = kk_locale_new_language_country(runtimeString("en"), runtimeString("US"))
        let rhs = kk_locale_new_language_country(runtimeString("en"), runtimeString("US"))

        XCTAssertTrue(boolValue(kk_any_equals(lhs, 0, rhs, 0)))
        XCTAssertEqual(kk_any_hashCode(lhs, 0), kk_any_hashCode(rhs, 0))
    }

    func testSingleArgumentLocaleTreatsInputAsLanguageField() {
        let locale = kk_locale_new(runtimeString("en_US_POSIX"))
        XCTAssertEqual(stringValue(kk_locale_language(locale)), "en_us_posix")
        XCTAssertEqual(stringValue(kk_locale_country(locale)), "")
        XCTAssertEqual(stringValue(kk_locale_variant(locale)), "")
    }

    func testAvailableLocalesContainsKnownLocale() {
        let available = kk_locale_getAvailableLocales(0)
        let identifiers = arrayElements(available).map { stringValue(kk_locale_language($0)) + "_" + stringValue(kk_locale_country($0)) }
        XCTAssertTrue(identifiers.contains("en_US") || identifiers.contains("en_"))
    }
}
