#if canImport(Testing)
@testable import CompilerCore
import Testing

/// KSP-682: regression coverage for binding supertype type arguments when a
/// generic declaration forwards its own type parameters to a generic supertype
/// (e.g. `interface B<T> : A<T>`) or to a function-type supertype
/// (e.g. `interface C<V> : () -> V`). This capability underpins the bundled
/// Kotlin `KProperty0/1/2` shells.
@Suite(.serialized)
struct GenericInterfaceInheritanceTests {
    private static let sharedSource = """
    interface A<T> {
        fun g(): T
    }

    interface B<T> : A<T>

    fun useMember(b: B<Int>): Int = b.g()

    fun upcast(b: B<Int>): A<Int> = b

    interface Producer<V> : () -> V
    """

    private static nonisolated(unsafe) var _sharedSema: (SemaModule, StringInterner)?

    private func sharedSema() throws -> (SemaModule, StringInterner) {
        if let cached = Self._sharedSema { return cached }
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: Self.sharedSource) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
            #expect(!(ctx.diagnostics.hasError), Comment(rawValue: "Expected clean resolution, got: \(diagnostics)"))
            result = (try #require(ctx.sema), ctx.interner)
        }
        let pair = try #require(result)
        Self._sharedSema = pair
        return pair
    }

    @Test func testGenericInterfaceForwardsTypeParameterToSupertype() throws {
        let (sema, interner) = try sharedSema()

        let aSymbol = try #require(sema.symbols.lookup(fqName: [interner.intern("A")]))
        let bSymbol = try #require(sema.symbols.lookup(fqName: [interner.intern("B")]))

        #expect(sema.symbols.directSupertypes(for: bSymbol).contains(aSymbol))

        let bTypeParams = sema.types.nominalTypeParameterSymbols(for: bSymbol)
        #expect(bTypeParams.count == 1)
        let bTypeParam = sema.types.make(.typeParam(TypeParamType(
            symbol: bTypeParams[0],
            nullability: .nonNull
        )))
        #expect(
            sema.symbols.supertypeTypeArgs(for: bSymbol, supertype: aSymbol) == [.invariant(bTypeParam)]
        )
    }

    @Test func testGenericInterfaceUpcastAndInheritedMemberResolve() throws {
        // Upcasting `B<Int>` to `A<Int>` and calling the inherited member both
        // require the forwarded supertype arguments to be bound.
        _ = try sharedSema()
    }

    @Test func testFunctionTypeSupertypeBindsFunctionInterface() throws {
        let (sema, interner) = try sharedSema()

        let producerSymbol = try #require(sema.symbols.lookup(fqName: [interner.intern("Producer")]))
        let function0Symbol = try #require(sema.symbols.lookup(
            fqName: ["kotlin", "Function", "Function0"].map { interner.intern($0) }
        ))

        #expect(sema.symbols.directSupertypes(for: producerSymbol).contains(function0Symbol))

        let typeParams = sema.types.nominalTypeParameterSymbols(for: producerSymbol)
        #expect(typeParams.count == 1)
        let valueType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParams[0],
            nullability: .nonNull
        )))
        #expect(
            sema.symbols.supertypeTypeArgs(for: producerSymbol, supertype: function0Symbol) == [.out(valueType)]
        )
    }
}
#endif
