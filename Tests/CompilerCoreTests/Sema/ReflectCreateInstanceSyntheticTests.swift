@testable import CompilerCore
import XCTest

final class ReflectCreateInstanceSyntheticTests: XCTestCase {
    private func makeSema(
        source: String = "fun noop() {}"
    ) throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
            XCTAssertFalse(ctx.diagnostics.hasError, "Expected createInstance surface to resolve cleanly, got: \(diagnostics)")
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testCreateInstanceSurfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let functionFQName = ["kotlin", "reflect", "full", "createInstance"].map { interner.intern($0) }
        let functionSymbol = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: functionFQName).first,
            "Expected kotlin.reflect.full.createInstance to be registered"
        )
        let symbol = try XCTUnwrap(sema.symbols.symbol(functionSymbol))
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: functionSymbol))

        XCTAssertEqual(symbol.kind, .function)
        XCTAssertEqual(symbol.visibility, .public)
        XCTAssertTrue(symbol.flags.contains(.synthetic))
        XCTAssertEqual(signature.parameterTypes, [])
        XCTAssertEqual(signature.typeParameterSymbols.count, 1)
        XCTAssertEqual(signature.typeParameterUpperBoundsList, [[sema.types.anyType]])

        let typeParam = try XCTUnwrap(signature.typeParameterSymbols.first)
        let typeParamType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParam,
            nullability: .nonNull
        )))
        let kClassSymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: ["kotlin", "reflect", "KClass"].map { interner.intern($0) }
        ))
        XCTAssertEqual(signature.receiverType, sema.types.make(.classType(ClassType(
            classSymbol: kClassSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        ))))
        XCTAssertEqual(signature.returnType, typeParamType)
    }

    func testCreateInstanceResolvesInSource() throws {
        let source = """
        import kotlin.reflect.KClass
        import kotlin.reflect.full.createInstance

        class Box

        fun makeBox(): Box = Box::class.createInstance()

        fun <T : Any> make(kclass: KClass<T>): T =
            kclass.createInstance()
        """

        _ = try makeSema(source: source)
    }
}
