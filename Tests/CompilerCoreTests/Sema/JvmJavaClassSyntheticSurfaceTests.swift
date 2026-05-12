@testable import CompilerCore
import XCTest

final class JvmJavaClassSyntheticSurfaceTests: XCTestCase {
    private func makeSema(
        source: String = "fun noop() {}"
    ) throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected JVM class surface to resolve cleanly, got: \(diagnostics)"
            )
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testJavaClassRootExtensionPropertyIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let kotlinPackage = [interner.intern("kotlin")]
        let javaLangPackage = ["java", "lang"].map { interner.intern($0) }
        let javaClassSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: javaLangPackage + [interner.intern("Class")])
        )
        let javaClassTypeParameters = sema.types.nominalTypeParameterSymbols(for: javaClassSymbol)
        let javaClassTypeParameter = try XCTUnwrap(javaClassTypeParameters.first)

        XCTAssertEqual(javaClassTypeParameters.count, 1)
        XCTAssertEqual(sema.types.nominalTypeParameterVariances(for: javaClassSymbol), [.invariant])

        let propertySymbol = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: kotlinPackage + [interner.intern("javaClass")]).first { symbolID in
                sema.symbols.symbol(symbolID)?.kind == .property
                    && sema.symbols.extensionPropertyReceiverType(for: symbolID) != nil
            },
            "Expected kotlin.T.javaClass root extension property"
        )
        let getterSymbol = try XCTUnwrap(sema.symbols.extensionPropertyGetterAccessor(for: propertySymbol))
        let getterSignature = try XCTUnwrap(sema.symbols.functionSignature(for: getterSymbol))
        let propertyType = try XCTUnwrap(sema.symbols.propertyType(for: propertySymbol))

        guard case let .typeParam(receiverTypeParam) = sema.types.kind(
            of: try XCTUnwrap(sema.symbols.extensionPropertyReceiverType(for: propertySymbol))
        ) else {
            return XCTFail("Expected javaClass receiver to be generic T")
        }
        guard case let .classType(classType) = sema.types.kind(of: propertyType) else {
            return XCTFail("Expected javaClass return type to be java.lang.Class<T>")
        }
        guard case let .invariant(classArgType) = classType.args.first else {
            return XCTFail("Expected javaClass return type argument to be invariant")
        }
        guard case let .typeParam(classArgTypeParam) = sema.types.kind(of: classArgType) else {
            return XCTFail("Expected javaClass return type argument to be generic T")
        }

        XCTAssertEqual(classType.classSymbol, javaClassSymbol)
        XCTAssertEqual(javaClassTypeParameter, try XCTUnwrap(javaClassTypeParameters.first))
        XCTAssertEqual(receiverTypeParam.symbol, classArgTypeParam.symbol)
        XCTAssertEqual(getterSignature.receiverType, sema.symbols.extensionPropertyReceiverType(for: propertySymbol))
        XCTAssertEqual(getterSignature.returnType, propertyType)
        XCTAssertEqual(getterSignature.typeParameterSymbols, [receiverTypeParam.symbol])
        XCTAssertEqual(sema.symbols.externalLinkName(for: propertySymbol), "kk_any_javaClass")
        XCTAssertEqual(sema.symbols.externalLinkName(for: getterSymbol), "kk_any_javaClass")
    }

    func testJavaClassPropertyResolvesInSource() throws {
        let source = """
        import java.lang.Class

        fun sample(value: String): Class<String> {
            return value.javaClass
        }
        """

        let (sema, interner) = try makeSema(source: source)
        let sampleSymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: [interner.intern("sample")]
        ))

        XCTAssertNotNil(sema.symbols.functionSignature(for: sampleSymbol))
    }
}
