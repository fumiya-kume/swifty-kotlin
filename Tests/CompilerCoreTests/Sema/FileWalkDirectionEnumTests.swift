@testable import CompilerCore
import Foundation
import XCTest

// MARK: - STDLIB-IO-TYPE-005: kotlin.io.FileWalkDirection enum
//
// Focused coverage for the synthetic `kotlin.io.FileWalkDirection` enum class.
// The enum is registered by `HeaderHelpers+SyntheticFileWalkDirectionStubs.swift`
// via `registerSyntheticFileWalkDirectionStubs`, and its two entries
// (TOP_DOWN, BOTTOM_UP) are exposed as fields whose `propertyType` is the
// enum class type itself so that `FileWalkDirection.TOP_DOWN`-style member
// references resolve through `resolveClassNameMemberValue`.

final class FileWalkDirectionEnumTests: XCTestCase {

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

    /// Canonical entry list matching the Kotlin stdlib `FileWalkDirection` enum.
    private static let allEntries = ["TOP_DOWN", "BOTTOM_UP"]

    // MARK: - Enum class declaration shape

    func testFileWalkDirectionIsRegisteredAsEnumClass() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "io", "FileWalkDirection"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: fqName),
            "kotlin.io.FileWalkDirection must be registered as a synthetic symbol"
        )
        XCTAssertEqual(
            sema.symbols.symbol(symbol)?.kind,
            .enumClass,
            "FileWalkDirection must be registered as enumClass (not regular class)"
        )
    }

    func testFileWalkDirectionIsParentedToKotlinIOPackage() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "io", "FileWalkDirection"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: fqName))

        let parent = try XCTUnwrap(
            sema.symbols.parentSymbol(for: symbol),
            "FileWalkDirection must be parented to the kotlin.io package symbol"
        )
        let parentInfo = try XCTUnwrap(sema.symbols.symbol(parent))
        XCTAssertEqual(parentInfo.kind, .package)
        XCTAssertEqual(
            parentInfo.fqName.map { interner.resolve($0) },
            ["kotlin", "io"],
            "FileWalkDirection's parent must be the kotlin.io package"
        )
    }

    func testFileWalkDirectionHasCorrectPropertyType() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "io", "FileWalkDirection"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: fqName))
        let expectedType = sema.types.make(.classType(ClassType(
            classSymbol: symbol,
            args: [],
            nullability: .nonNull
        )))
        XCTAssertEqual(
            sema.symbols.propertyType(for: symbol),
            expectedType,
            "FileWalkDirection's propertyType must be the enum class type itself"
        )
    }

    // MARK: - Enum entries

    func testBothFileWalkDirectionEntriesAreRegisteredAsFields() throws {
        let (sema, interner) = try makeSema()
        for entry in Self.allEntries {
            let fqName = ["kotlin", "io", "FileWalkDirection", entry].map { interner.intern($0) }
            let symbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: fqName),
                "FileWalkDirection.\(entry) must be present in the symbol table"
            )
            XCTAssertEqual(
                sema.symbols.symbol(symbol)?.kind,
                .field,
                "FileWalkDirection.\(entry) must be registered as field (enum entry)"
            )
        }
    }

    func testFileWalkDirectionEntryPropertyTypesAreEnumType() throws {
        let (sema, interner) = try makeSema()

        let enumFQName = ["kotlin", "io", "FileWalkDirection"].map { interner.intern($0) }
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
                "FileWalkDirection.\(entry) must exist"
            )
            XCTAssertEqual(
                sema.symbols.propertyType(for: entrySymbol),
                expectedType,
                "FileWalkDirection.\(entry) propertyType must equal FileWalkDirection (so member resolution works)"
            )
        }
    }

    func testFileWalkDirectionEntriesAreParentedToEnumClass() throws {
        let (sema, interner) = try makeSema()

        let enumFQName = ["kotlin", "io", "FileWalkDirection"].map { interner.intern($0) }
        let enumSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: enumFQName))

        for entry in Self.allEntries {
            let fqName = enumFQName + [interner.intern(entry)]
            let entrySymbol = try XCTUnwrap(sema.symbols.lookup(fqName: fqName))
            XCTAssertEqual(
                sema.symbols.parentSymbol(for: entrySymbol),
                enumSymbol,
                "FileWalkDirection.\(entry) must be parented to the FileWalkDirection enum class"
            )
        }
    }

    func testFileWalkDirectionHasExactlyTwoEntries() throws {
        let (sema, interner) = try makeSema()
        let enumFQName = ["kotlin", "io", "FileWalkDirection"].map { interner.intern($0) }
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
            "FileWalkDirection enum entries must exactly match the Kotlin stdlib spec (TOP_DOWN, BOTTOM_UP)"
        )
    }

    // MARK: - Member resolution in source

    func testFileWalkDirectionMemberAccessResolves() throws {
        let source = """
        import kotlin.io.FileWalkDirection

        fun pickTopDown(): FileWalkDirection = FileWalkDirection.TOP_DOWN
        fun pickBottomUp(): FileWalkDirection = FileWalkDirection.BOTTOM_UP
        """
        let ctx = runSemaCollectingDiagnostics(source)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected every FileWalkDirection entry to resolve cleanly, got: "
                + "\(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
