@testable import CompilerCore
import Foundation
import XCTest

final class NativeCInteropBooleanVarTypeAliasTests: XCTestCase {
    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected BooleanVar typealias surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
            )
            result = (try XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    private func symbol(
        _ fqPath: [String],
        sema: SemaModule,
        interner: StringInterner,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> SymbolID {
        try XCTUnwrap(
            sema.symbols.lookup(fqName: fqPath.map { interner.intern($0) }),
            "\(fqPath.joined(separator: ".")) must be registered",
            file: file,
            line: line
        )
    }

    func testBooleanVarTypeAliasIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let aliasSymbol = try symbol(["kotlinx", "cinterop", "BooleanVar"], sema: sema, interner: interner)

        XCTAssertEqual(sema.symbols.symbol(aliasSymbol)?.kind, .typeAlias)
    }

    func testBooleanVarUnderlyingTypeIsBooleanVarOfBoolean() throws {
        let (sema, interner) = try makeSema()
        let aliasSymbol = try symbol(["kotlinx", "cinterop", "BooleanVar"], sema: sema, interner: interner)
        let booleanVarOfSymbol = try symbol(["kotlinx", "cinterop", "BooleanVarOf"], sema: sema, interner: interner)
        let expectedUnderlying = sema.types.make(.classType(ClassType(
            classSymbol: booleanVarOfSymbol,
            args: [.invariant(sema.types.booleanType)],
            nullability: .nonNull
        )))

        XCTAssertEqual(sema.symbols.typeAliasUnderlyingType(for: aliasSymbol), expectedUnderlying)
    }

    func testBooleanVarOfSupportSymbolIsGeneric() throws {
        let (sema, interner) = try makeSema()
        let booleanVarOfSymbol = try symbol(["kotlinx", "cinterop", "BooleanVarOf"], sema: sema, interner: interner)
        let typeParameters = sema.types.nominalTypeParameterSymbols(for: booleanVarOfSymbol)

        XCTAssertEqual(sema.symbols.symbol(booleanVarOfSymbol)?.kind, .class)
        XCTAssertEqual(typeParameters.count, 1)
        XCTAssertEqual(sema.symbols.symbol(try XCTUnwrap(typeParameters.first))?.name, interner.intern("T"))
    }

    func testBooleanVarResolvesInSource() throws {
        _ = try makeSema(source: """
        import kotlinx.cinterop.BooleanVar

        fun roundtrip(value: BooleanVar): BooleanVar {
            return value
        }
        """)
    }
}
