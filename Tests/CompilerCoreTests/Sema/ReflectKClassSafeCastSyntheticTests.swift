@testable import CompilerCore
import XCTest

final class ReflectKClassSafeCastSyntheticTests: XCTestCase {
    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected KClass.safeCast source to type-check, got: \(ctx.diagnostics.diagnostics)"
            )
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testKClassSafeCastSyntheticStubLinksToRuntimeABI() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "reflect", "KClass", "safeCast"].map { interner.intern($0) }
        let safeCastSymbol = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: fqName).first { symbolID in
                sema.symbols.externalLinkName(for: symbolID) == "kk_kclass_safeCast"
            },
            "Expected kotlin.reflect.KClass.safeCast to link to kk_kclass_safeCast"
        )
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: safeCastSymbol))

        XCTAssertFalse(signature.canThrow)
        XCTAssertEqual(signature.parameterTypes, [sema.types.nullableAnyType])
        XCTAssertEqual(signature.classTypeParameterCount, 1)
        XCTAssertEqual(signature.typeParameterSymbols.count, 1)
        XCTAssertEqual(signature.valueParameterSymbols.count, 1)
        if case let .typeParam(typeParam) = sema.types.kind(of: signature.returnType) {
            XCTAssertEqual(typeParam.nullability, .nullable)
        } else {
            XCTFail("Expected KClass.safeCast return type to be nullable receiver type parameter")
        }
    }

    func testKClassSafeCastInfersNullableReceiverArgumentReturnTypes() throws {
        let source = """
        import kotlin.reflect.KClass

        fun safeCastString(value: Any?): String? = String::class.safeCast(value)

        fun safeCastViaLocal(value: Any?): String? {
            val klass = String::class
            return klass.safeCast(value)
        }

        fun <T : Any> safeCastWithClass(klass: KClass<T>, value: Any?): T? = klass.safeCast(value)
        """
        let (sema, interner) = try makeSema(source: source)
        let nullableStringType = sema.types.makeNullable(sema.types.stringType)

        for functionName in ["safeCastString", "safeCastViaLocal"] {
            let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: [interner.intern(functionName)]))
            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbol))
            XCTAssertEqual(
                signature.returnType,
                nullableStringType,
                "\(functionName) should infer String? from KClass<String>.safeCast"
            )
        }

        let genericSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [interner.intern("safeCastWithClass")]))
        let genericSignature = try XCTUnwrap(sema.symbols.functionSignature(for: genericSymbol))
        if case let .typeParam(typeParam) = sema.types.kind(of: genericSignature.returnType) {
            XCTAssertEqual(typeParam.nullability, .nullable)
        } else {
            XCTFail("Expected generic KClass.safeCast wrapper to return nullable T")
        }
    }
}
