@testable import CompilerCore
import XCTest

/// Tests for STDLIB-IO-TYPE-005: `kotlin.io.FileWalkDirection` enum
/// (entries `TOP_DOWN`, `BOTTOM_UP`) synthetic stub registration and
/// source-level resolution.
final class FileWalkDirectionEnumTests: XCTestCase {
    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testFileWalkDirectionSymbolIsRegisteredAsEnumClass() throws {
        let (sema, interner) = try makeSema()

        let fqName = ["kotlin", "io", "FileWalkDirection"].map { interner.intern($0) }
        let enumSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: fqName),
            "kotlin.io.FileWalkDirection should be registered"
        )
        XCTAssertEqual(sema.symbols.symbol(enumSymbol)?.kind, .enumClass)

        let kotlinIOFQName = ["kotlin", "io"].map { interner.intern($0) }
        let kotlinIOSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: kotlinIOFQName))
        XCTAssertEqual(sema.symbols.parentSymbol(for: enumSymbol), kotlinIOSymbol)

        let enumType = sema.types.make(.classType(ClassType(
            classSymbol: enumSymbol,
            args: [],
            nullability: .nonNull
        )))
        XCTAssertEqual(sema.symbols.propertyType(for: enumSymbol), enumType)
    }

    func testFileWalkDirectionEntriesAreRegistered() throws {
        let (sema, interner) = try makeSema()

        let enumFQName = ["kotlin", "io", "FileWalkDirection"].map { interner.intern($0) }
        let enumSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: enumFQName))
        let enumType = sema.types.make(.classType(ClassType(
            classSymbol: enumSymbol,
            args: [],
            nullability: .nonNull
        )))

        for entry in ["TOP_DOWN", "BOTTOM_UP"] {
            let entryFQName = enumFQName + [interner.intern(entry)]
            let entrySymbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: entryFQName),
                "FileWalkDirection.\(entry) should be registered"
            )
            XCTAssertEqual(sema.symbols.symbol(entrySymbol)?.kind, .field)
            XCTAssertEqual(sema.symbols.parentSymbol(for: entrySymbol), enumSymbol)
            XCTAssertEqual(
                sema.symbols.propertyType(for: entrySymbol),
                enumType,
                "FileWalkDirection.\(entry) should carry enum type"
            )
        }
    }

    func testFileWalkDirectionResolvesInWhenBranches() throws {
        _ = try makeSema(source: """
        import kotlin.io.FileWalkDirection

        fun describe(direction: FileWalkDirection): String =
            when (direction) {
                FileWalkDirection.TOP_DOWN -> "top down"
                FileWalkDirection.BOTTOM_UP -> "bottom up"
            }
        """)
    }

    func testFileWalkDirectionUnqualifiedImportResolves() throws {
        _ = try makeSema(source: """
        import kotlin.io.FileWalkDirection
        import kotlin.io.FileWalkDirection.TOP_DOWN
        import kotlin.io.FileWalkDirection.BOTTOM_UP

        fun pickDefault(): FileWalkDirection = TOP_DOWN
        fun pickReverse(): FileWalkDirection = BOTTOM_UP
        """)
    }
}
