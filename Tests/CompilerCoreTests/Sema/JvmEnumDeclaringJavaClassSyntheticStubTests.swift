@testable import CompilerCore
import XCTest

final class JvmEnumDeclaringJavaClassSyntheticStubTests: XCTestCase {
    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected Enum.declaringJavaClass source to type-check, got: \(ctx.diagnostics.diagnostics)"
            )
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testEnumDeclaringJavaClassPropertySurfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let classSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: ["java", "lang", "Class"].map { interner.intern($0) }),
            "Expected java.lang.Class<T> synthetic class"
        )
        let enumSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: ["kotlin", "Enum"].map { interner.intern($0) }),
            "Expected kotlin.Enum<T> synthetic class"
        )

        let propertyFQName = ["kotlin", "jvm", "declaringJavaClass"].map { interner.intern($0) }
        let propertySymbol = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: propertyFQName).first { symbolID in
                sema.symbols.symbol(symbolID)?.kind == .property
                    && sema.symbols.extensionPropertyReceiverType(for: symbolID) != nil
            },
            "Expected kotlin.jvm.declaringJavaClass extension property"
        )
        XCTAssertEqual(sema.symbols.externalLinkName(for: propertySymbol), "kk_enum_declaringJavaClass")

        let getterSymbol = try XCTUnwrap(sema.symbols.extensionPropertyGetterAccessor(for: propertySymbol))
        XCTAssertEqual(sema.symbols.externalLinkName(for: getterSymbol), "kk_enum_declaringJavaClass")

        let getterSignature = try XCTUnwrap(sema.symbols.functionSignature(for: getterSymbol))
        XCTAssertEqual(getterSignature.parameterTypes, [])
        XCTAssertEqual(getterSignature.typeParameterSymbols.count, 1)
        XCTAssertEqual(getterSignature.classTypeParameterCount, 0)

        let typeParamSymbol = try XCTUnwrap(getterSignature.typeParameterSymbols.first)
        let typeParamType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        let receiverType = sema.types.make(.classType(ClassType(
            classSymbol: enumSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))
        let returnType = sema.types.make(.classType(ClassType(
            classSymbol: classSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))

        XCTAssertEqual(getterSignature.receiverType, receiverType)
        XCTAssertEqual(getterSignature.returnType, returnType)
        XCTAssertEqual(sema.symbols.propertyType(for: propertySymbol), returnType)
        XCTAssertEqual(sema.symbols.extensionPropertyReceiverType(for: propertySymbol), receiverType)
    }

    func testEnumDeclaringJavaClassPropertyResolvesFromSource() throws {
        let source = """
        import java.lang.Class
        import kotlin.jvm.declaringJavaClass

        enum class Color { RED, BLUE }

        fun declaringClassOf(value: Enum<Color>): Class<Color> = value.declaringJavaClass
        """
        let (sema, interner) = try makeSema(source: source)

        let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: [interner.intern("declaringClassOf")]))
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbol))
        guard case .classType = sema.types.kind(of: signature.returnType) else {
            return XCTFail("declaringClassOf should return java.lang.Class<Color>, got \(sema.types.renderType(signature.returnType))")
        }
    }
}
