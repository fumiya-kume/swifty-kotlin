@testable import CompilerCore
import Foundation
import XCTest

// MARK: - STDLIB-TEXT-TYPE-012: kotlin.text.RegexOption enum
//
// Focused coverage for the synthetic `kotlin.text.RegexOption` enum class.
// The enum is registered as a synthetic symbol by
// `HeaderHelpers+SyntheticRegexStubs.swift` via `ensureRegexOptionEnumClass`,
// and its entries (IGNORE_CASE, MULTILINE, LITERAL, UNIX_LINES, COMMENTS,
// DOT_MATCHES_ALL, CANON_EQ) are exposed as fields whose static `propertyType`
// is the enum class type itself so that `RegexOption.IGNORE_CASE`-style
// member references resolve through `resolveClassNameMemberValue`.
//
// Wider Regex API surface (constructors, members, properties) is covered by
// `RegexAPISurfaceInventoryTests`. This file focuses purely on the enum
// declaration shape and member resolution.

final class RegexOptionEnumTests: XCTestCase {

    // MARK: Helpers

    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    private func runSemaCollectingDiagnostics(_ source: String) -> CompilationContext {
        let ctx = makeContextFromSource(source)
        do {
            try runSema(ctx)
        } catch {
            // Diagnostics are inspected per-test.
        }
        return ctx
    }

    /// Canonical entry list matching the Kotlin stdlib `RegexOption` enum
    /// (mirrors `ensureRegexOptionEnumClass` in
    /// `HeaderHelpers+SyntheticRegexStubs.swift`).
    private static let allEntries = [
        "IGNORE_CASE",
        "MULTILINE",
        "LITERAL",
        "UNIX_LINES",
        "COMMENTS",
        "DOT_MATCHES_ALL",
        "CANON_EQ",
    ]

    // MARK: - Enum class declaration shape

    func testRegexOptionIsRegisteredAsEnumClass() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "text", "RegexOption"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: fqName),
            "kotlin.text.RegexOption must be registered as a synthetic symbol"
        )
        XCTAssertEqual(
            sema.symbols.symbol(symbol)?.kind,
            .enumClass,
            "RegexOption must be registered as enumClass (not regular class)"
        )
    }

    func testRegexOptionIsParentedToKotlinTextPackage() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "text", "RegexOption"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: fqName))

        let parent = try XCTUnwrap(
            sema.symbols.parentSymbol(for: symbol),
            "RegexOption must be parented to the kotlin.text package symbol"
        )
        let parentInfo = try XCTUnwrap(sema.symbols.symbol(parent))
        XCTAssertEqual(parentInfo.kind, .package)
        XCTAssertEqual(
            parentInfo.fqName.map { interner.resolve($0) },
            ["kotlin", "text"],
            "RegexOption's parent must be the kotlin.text package"
        )
    }

    // MARK: - Enum entries

    func testAllSevenRegexOptionEntriesAreRegisteredAsFields() throws {
        let (sema, interner) = try makeSema()
        for entry in Self.allEntries {
            let fqName = ["kotlin", "text", "RegexOption", entry].map { interner.intern($0) }
            let symbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: fqName),
                "RegexOption.\(entry) must be present in the symbol table"
            )
            XCTAssertEqual(
                sema.symbols.symbol(symbol)?.kind,
                .field,
                "RegexOption.\(entry) must be registered as field (enum entry)"
            )
        }
    }

    func testRegexOptionEntryPropertyTypesAreEnumType() throws {
        let (sema, interner) = try makeSema()

        let enumFQName = ["kotlin", "text", "RegexOption"].map { interner.intern($0) }
        let enumSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: enumFQName))
        let expectedType = sema.types.make(.classType(ClassType(
            classSymbol: enumSymbol,
            args: [],
            nullability: .nonNull
        )))

        for entry in Self.allEntries {
            let fqName = enumFQName + [interner.intern(entry)]
            let entrySymbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: fqName),
                "RegexOption.\(entry) must exist"
            )
            XCTAssertEqual(
                sema.symbols.propertyType(for: entrySymbol),
                expectedType,
                "RegexOption.\(entry) propertyType must equal RegexOption (so member resolution works)"
            )
        }
    }

    func testRegexOptionEntriesAreParentedToEnumClass() throws {
        let (sema, interner) = try makeSema()

        let enumFQName = ["kotlin", "text", "RegexOption"].map { interner.intern($0) }
        let enumSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: enumFQName))

        for entry in Self.allEntries {
            let fqName = enumFQName + [interner.intern(entry)]
            let entrySymbol = try XCTUnwrap(sema.symbols.lookup(fqName: fqName))
            XCTAssertEqual(
                sema.symbols.parentSymbol(for: entrySymbol),
                enumSymbol,
                "RegexOption.\(entry) must be parented to the RegexOption enum class"
            )
        }
    }

    func testRegexOptionDoesNotRegisterUnexpectedEntries() throws {
        let (sema, interner) = try makeSema()
        let enumFQName = ["kotlin", "text", "RegexOption"].map { interner.intern($0) }
        let children = sema.symbols.children(ofFQName: enumFQName)
        let fieldNames: Set<String> = Set(
            children.compactMap { child -> String? in
                guard let info = sema.symbols.symbol(child), info.kind == .field else {
                    return nil
                }
                return info.fqName.last.map { interner.resolve($0) }
            }
        )
        XCTAssertEqual(
            fieldNames,
            Set(Self.allEntries),
            "RegexOption enum entries must exactly match the Kotlin stdlib spec"
        )
    }

    // MARK: - Member resolution in source

    func testRegexOptionMemberAccessResolves() throws {
        let source = """
        import kotlin.text.RegexOption

        fun pickIgnoreCase(): RegexOption = RegexOption.IGNORE_CASE
        fun pickMultiline(): RegexOption = RegexOption.MULTILINE
        fun pickLiteral(): RegexOption = RegexOption.LITERAL
        fun pickUnixLines(): RegexOption = RegexOption.UNIX_LINES
        fun pickComments(): RegexOption = RegexOption.COMMENTS
        fun pickDotMatchesAll(): RegexOption = RegexOption.DOT_MATCHES_ALL
        fun pickCanonEq(): RegexOption = RegexOption.CANON_EQ
        """
        let ctx = runSemaCollectingDiagnostics(source)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected every RegexOption entry to resolve cleanly, got: "
                + "\(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    func testRegexOptionPassesThroughRegexConstructor() throws {
        // Round-trip: confirm that an entry can flow into the
        // `Regex(String, RegexOption)` overload registered alongside the enum.
        let source = """
        import kotlin.text.Regex
        import kotlin.text.RegexOption

        fun makeIgnoreCaseRegex(): Regex = Regex("hello", RegexOption.IGNORE_CASE)
        """
        let ctx = runSemaCollectingDiagnostics(source)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Regex(String, RegexOption) must resolve cleanly, got: "
                + "\(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
