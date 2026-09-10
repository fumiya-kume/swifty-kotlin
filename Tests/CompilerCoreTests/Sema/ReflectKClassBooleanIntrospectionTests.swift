#if canImport(Testing)
@testable import CompilerCore
import Testing

/// STDLIB-REFLECT-067: Sema inference for KClass kind/modifier boolean members
/// (`isData` / `isSealed` / `isValue`) on both a class-literal receiver and a
/// stored `KClass<T>` variable receiver.
@Suite(.serialized)
struct ReflectKClassBooleanIntrospectionTests {
    private static let sharedSource = """
    import kotlin.reflect.KClass

    data class Point(val x: Int)

    fun isDataOf(): Boolean = Point::class.isData
    fun isSealedOf(): Boolean = Point::class.isSealed
    fun isValueOf(): Boolean = Point::class.isValue

    fun variableIsDataOf(k: KClass<Point>): Boolean = k.isData
    fun variableIsSealedOf(k: KClass<Point>): Boolean = k.isSealed
    fun variableIsValueOf(k: KClass<Point>): Boolean = k.isValue
    """

    private static nonisolated(unsafe) var _sharedSema: (SemaModule, StringInterner, CompilationContext)?

    private func sharedSema() throws -> (SemaModule, StringInterner, CompilationContext) {
        if let cached = Self._sharedSema { return cached }
        var result: (SemaModule, StringInterner, CompilationContext)?
        try withTemporaryFile(contents: Self.sharedSource) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(
                !(ctx.diagnostics.hasError),
                Comment(rawValue: "Expected KClass boolean introspection source to type-check, got: \(ctx.diagnostics.diagnostics)")
            )
            result = (try #require(ctx.sema), ctx.interner, ctx)
        }
        let triple = try #require(result)
        Self._sharedSema = triple
        return triple
    }

    @Test func testClassLiteralBooleanMembersInferBoolean() throws {
        let (sema, interner, _) = try sharedSema()
        for functionName in ["isDataOf", "isSealedOf", "isValueOf"] {
            let symbol = try #require(sema.symbols.lookup(fqName: [interner.intern(functionName)]))
            let signature = try #require(sema.symbols.functionSignature(for: symbol))
            #expect(
                signature.returnType == sema.types.booleanType,
                Comment(rawValue: "\(functionName) should infer Boolean from a KClass boolean member")
            )
        }
    }

    @Test func testVariableReceiverBooleanMembersInferBoolean() throws {
        let (sema, interner, _) = try sharedSema()
        for functionName in ["variableIsDataOf", "variableIsSealedOf", "variableIsValueOf"] {
            let symbol = try #require(sema.symbols.lookup(fqName: [interner.intern(functionName)]))
            let signature = try #require(sema.symbols.functionSignature(for: symbol))
            #expect(
                signature.returnType == sema.types.booleanType,
                Comment(rawValue: "\(functionName) should infer Boolean from a KClass<T> variable boolean member")
            )
        }
    }
}
#endif
