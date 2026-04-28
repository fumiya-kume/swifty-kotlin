@testable import CompilerCore
import XCTest

final class ReflectKClassCastSyntheticTests: XCTestCase {
    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected KClass.cast source to type-check, got: \(ctx.diagnostics.diagnostics)"
            )
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testKClassCastSyntheticStubLinksToRuntimeABI() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "reflect", "KClass", "cast"].map { interner.intern($0) }
        let castSymbol = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: fqName).first { symbolID in
                sema.symbols.externalLinkName(for: symbolID) == "kk_kclass_cast"
            },
            "Expected kotlin.reflect.KClass.cast to link to kk_kclass_cast"
        )
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: castSymbol))

        XCTAssertTrue(signature.canThrow)
        XCTAssertEqual(signature.parameterTypes, [sema.types.nullableAnyType])
        XCTAssertEqual(signature.classTypeParameterCount, 1)
        XCTAssertEqual(signature.typeParameterSymbols.count, 1)
        XCTAssertEqual(signature.valueParameterSymbols.count, 1)
        if case .typeParam = sema.types.kind(of: signature.returnType) {
            // Expected: KClass<T>.cast(value) returns T.
        } else {
            XCTFail("Expected KClass.cast return type to be the receiver type parameter")
        }
    }

    func testKClassCastInfersReceiverArgumentReturnTypes() throws {
        let source = """
        import kotlin.reflect.KClass

        fun castString(value: Any?): String = String::class.cast(value)

        fun castViaLocal(value: Any?): String {
            val klass = String::class
            return klass.cast(value)
        }

        fun <T : Any> castWithClass(klass: KClass<T>, value: Any?): T = klass.cast(value)
        """
        let (sema, interner) = try makeSema(source: source)

        for functionName in ["castString", "castViaLocal"] {
            let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: [interner.intern(functionName)]))
            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbol))
            XCTAssertEqual(
                signature.returnType,
                sema.types.stringType,
                "\(functionName) should infer String from KClass<String>.cast"
            )
        }

        let genericSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [interner.intern("castWithClass")]))
        let genericSignature = try XCTUnwrap(sema.symbols.functionSignature(for: genericSymbol))
        if case .typeParam = sema.types.kind(of: genericSignature.returnType) {
            // Expected: generic KClass<T>.cast preserves T.
        } else {
            XCTFail("Expected generic KClass.cast wrapper to return T")
        }
    }
}
