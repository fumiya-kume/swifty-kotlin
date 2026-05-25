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
        let typeParameter = try XCTUnwrap(typeParameters.first)
        XCTAssertEqual(sema.symbols.symbol(typeParameter)?.name, interner.intern("T"))
        XCTAssertEqual(sema.symbols.typeParameterUpperBounds(for: typeParameter), [sema.types.booleanType])
    }

    func testBooleanVarOfClassSurfaceMatchesNativeShape() throws {
        let (sema, interner) = try makeSema()
        let booleanVarOfSymbol = try symbol(["kotlinx", "cinterop", "BooleanVarOf"], sema: sema, interner: interner)
        let cPrimitiveVarSymbol = try symbol(["kotlinx", "cinterop", "CPrimitiveVar"], sema: sema, interner: interner)
        let cVariableSymbol = try symbol(["kotlinx", "cinterop", "CVariable"], sema: sema, interner: interner)
        let cPointedSymbol = try symbol(["kotlinx", "cinterop", "CPointed"], sema: sema, interner: interner)
        let nativePtrSymbol = try symbol(["kotlinx", "cinterop", "NativePtr"], sema: sema, interner: interner)
        let booleanVarOfFQName = try XCTUnwrap(sema.symbols.symbol(booleanVarOfSymbol)?.fqName)
        let typeParameter = try XCTUnwrap(sema.types.nominalTypeParameterSymbols(for: booleanVarOfSymbol).first)
        let typeParameterType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParameter,
            nullability: .nonNull
        )))
        let booleanVarOfType = sema.types.make(.classType(ClassType(
            classSymbol: booleanVarOfSymbol,
            args: [.invariant(typeParameterType)],
            nullability: .nonNull
        )))
        let nativePtrType = sema.types.make(.classType(ClassType(
            classSymbol: nativePtrSymbol,
            args: [],
            nullability: .nonNull
        )))

        XCTAssertEqual(sema.symbols.directSupertypes(for: booleanVarOfSymbol), [cPrimitiveVarSymbol])
        XCTAssertEqual(sema.symbols.directSupertypes(for: cPrimitiveVarSymbol), [cVariableSymbol])
        XCTAssertEqual(sema.symbols.directSupertypes(for: cVariableSymbol), [cPointedSymbol])

        let constructors = sema.symbols.lookupAll(fqName: booleanVarOfFQName + [interner.intern("<init>")])
        let constructorSignature = try XCTUnwrap(constructors.compactMap { sema.symbols.functionSignature(for: $0) }.first {
            $0.parameterTypes == [nativePtrType] && $0.returnType == booleanVarOfType
        })
        XCTAssertEqual(constructorSignature.typeParameterSymbols, [typeParameter])
        XCTAssertEqual(constructorSignature.classTypeParameterCount, 1)

        let valueSymbol = try symbol(["kotlinx", "cinterop", "BooleanVarOf", "value"], sema: sema, interner: interner)
        XCTAssertEqual(sema.symbols.propertyType(for: valueSymbol), typeParameterType)
    }

    func testBooleanVarResolvesInSource() throws {
        _ = try makeSema(source: """
        import kotlinx.cinterop.BooleanVar

        fun roundtrip(value: BooleanVar): BooleanVar {
            return value
        }
        """)
    }

    func testBooleanVarOfValuePropertyResolvesInSource() throws {
        _ = try makeSema(source: """
        import kotlinx.cinterop.BooleanVarOf

        fun readBoolean(value: BooleanVarOf<Boolean>): Boolean {
            return value.value
        }
        """)
    }
}
