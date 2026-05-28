@testable import CompilerCore
import Foundation
import XCTest

// MARK: - STDLIB-IO-TYPE-007: kotlin.io.OnErrorAction enum
//
// Focused coverage for the synthetic `kotlin.io.OnErrorAction` enum class.
// The enum is registered as a synthetic symbol by
// `HeaderHelpers+SyntheticKotlinIOEnumStubs.swift` via
// `ensureOnErrorActionEnumClass`, with two Kotlin stdlib entries exposed as
// field-kind children of the enum class:
//   SKIP      — skip the problematic file and continue the recursive copy
//   TERMINATE — stop the recursive copy and return false
//
// Each entry's propertyType is set to the OnErrorAction class type so that
// `resolveClassNameMemberValue` can resolve `OnErrorAction.SKIP`-style
// qualified references.

final class OnErrorActionEnumTests: XCTestCase {

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

    /// Canonical entry list matching the Kotlin stdlib `OnErrorAction` enum.
    private static let allEntries = ["SKIP", "TERMINATE"]

    // MARK: - Enum class declaration shape

    func testOnErrorActionIsRegisteredAsEnumClass() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "io", "OnErrorAction"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: fqName),
            "kotlin.io.OnErrorAction must be registered as a synthetic symbol"
        )
        XCTAssertEqual(
            sema.symbols.symbol(symbol)?.kind,
            .enumClass,
            "OnErrorAction must be registered as enumClass (not regular class)"
        )
    }

    func testOnErrorActionIsParentedToKotlinIOPackage() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "io", "OnErrorAction"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: fqName))

        let parent = try XCTUnwrap(
            sema.symbols.parentSymbol(for: symbol),
            "OnErrorAction must be parented to the kotlin.io package symbol"
        )
        let parentInfo = try XCTUnwrap(sema.symbols.symbol(parent))
        XCTAssertEqual(parentInfo.kind, .package)
        XCTAssertEqual(
            parentInfo.fqName.map { interner.resolve($0) },
            ["kotlin", "io"],
            "OnErrorAction's parent must be the kotlin.io package"
        )
    }

    // MARK: - Enum entries

    func testBothOnErrorActionEntriesAreRegisteredAsFields() throws {
        let (sema, interner) = try makeSema()
        for entry in Self.allEntries {
            let fqName = ["kotlin", "io", "OnErrorAction", entry].map { interner.intern($0) }
            let symbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: fqName),
                "OnErrorAction.\(entry) must be present in the symbol table"
            )
            XCTAssertEqual(
                sema.symbols.symbol(symbol)?.kind,
                .field,
                "OnErrorAction.\(entry) must be registered as field (enum entry)"
            )
        }
    }

    func testOnErrorActionEntryPropertyTypesAreEnumType() throws {
        let (sema, interner) = try makeSema()

        let enumFQName = ["kotlin", "io", "OnErrorAction"].map { interner.intern($0) }
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
                "OnErrorAction.\(entry) must exist"
            )
            XCTAssertEqual(
                sema.symbols.propertyType(for: entrySymbol),
                expectedType,
                "OnErrorAction.\(entry) propertyType must equal OnErrorAction (so member resolution works)"
            )
        }
    }

    func testOnErrorActionEntriesAreParentedToEnumClass() throws {
        let (sema, interner) = try makeSema()

        let enumFQName = ["kotlin", "io", "OnErrorAction"].map { interner.intern($0) }
        let enumSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: enumFQName))

        for entry in Self.allEntries {
            let fqName = enumFQName + [interner.intern(entry)]
            let entrySymbol = try XCTUnwrap(sema.symbols.lookup(fqName: fqName))
            XCTAssertEqual(
                sema.symbols.parentSymbol(for: entrySymbol),
                enumSymbol,
                "OnErrorAction.\(entry) must be parented to the OnErrorAction enum class"
            )
        }
    }

    func testOnErrorActionDoesNotRegisterUnexpectedEntries() throws {
        let (sema, interner) = try makeSema()
        let enumFQName = ["kotlin", "io", "OnErrorAction"].map { interner.intern($0) }
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
            "OnErrorAction enum entries must exactly match the Kotlin stdlib spec (SKIP, TERMINATE)"
        )
    }

    // MARK: - Member resolution in source

    func testOnErrorActionMemberAccessResolves() throws {
        let source = """
        import kotlin.io.OnErrorAction

        fun pickSkip(): OnErrorAction = OnErrorAction.SKIP
        fun pickTerminate(): OnErrorAction = OnErrorAction.TERMINATE
        """
        let ctx = runSemaCollectingDiagnostics(source)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected every OnErrorAction entry to resolve cleanly, got: "
                + "\(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
