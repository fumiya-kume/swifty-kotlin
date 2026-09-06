#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct BundledSyntheticOverlapDiagnosticTests {
    @Test
    func testDiagnosticRegistered() {
        let descriptor = DiagnosticRegistry.lookup("KSWIFTK-SEMA-0102")
        #expect(descriptor != nil)
        #expect(descriptor?.defaultSeverity == .warning)
    }

    @Test
    func testWarnsWhenSyntheticOverlapsBundledIndex() {
        let symbols = SymbolTable()
        let types = TypeSystem()
        types.symbolTable = symbols
        let interner = StringInterner()
        let diagnostics = DiagnosticEngine()

        let listName = interner.intern("List")
        let collectionsPkg: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
        ]
        let listFQName = collectionsPkg + [listName]
        let listSymbol = symbols.define(
            kind: .interface,
            name: listName,
            fqName: listFQName,
            declSite: nil,
            visibility: .public,
            flags: []
        )

        let countName = interner.intern("count")
        let countFQName = listFQName + [countName]
        let bundledCount = symbols.define(
            kind: .function,
            name: countName,
            fqName: countFQName,
            declSite: nil,
            visibility: .public,
            flags: []
        )
        symbols.setParentSymbol(listSymbol, for: bundledCount)
        let elementType = types.anyType
        let receiverType = types.make(.classType(ClassType(
            classSymbol: listSymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))
        let predicateType = types.make(.functionType(FunctionType(
            params: [elementType],
            returnType: types.booleanType,
            isSuspend: false,
            nullability: .nonNull
        )))
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [predicateType],
                returnType: types.intType
            ),
            for: bundledCount
        )

        var bundledIndex = BundledDeclarationIndex.empty
        bundledIndex.insert(
            BundledMemberKey(
                ownerFQName: listFQName,
                name: countName,
                arity: 1
            )
        )

        let syntheticCount = symbols.define(
            kind: .function,
            name: countName,
            fqName: countFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(listSymbol, for: syntheticCount)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [predicateType],
                returnType: types.intType
            ),
            for: syntheticCount
        )

        bundledIndex.warnSyntheticOverlaps(
            symbols: symbols,
            types: types,
            diagnostics: diagnostics,
            interner: interner
        )

        assertHasDiagnostic("KSWIFTK-SEMA-0102", in: makeContext(diagnostics: diagnostics))
        let warning = diagnostics.diagnostics.first { $0.code == "KSWIFTK-SEMA-0102" }
        #expect(warning?.severity == .warning)
        #expect(warning?.message.contains("Synthetic stub 'count'") == true)
        #expect(warning?.message.contains("'kotlin.collections.List' (arity 1)") == true)
    }

    @Test
    func testSourceBackedExtensionPropertyGetterDoesNotWarnAsSyntheticStub() throws {
        let ctx = makeContextFromSource(
            """
            lateinit var value: String

            fun ready(): Boolean = ::value.isInitialized
            """
        )
        try runSema(ctx)

        #expect(!ctx.diagnostics.hasError, "Unexpected errors: \(ctx.diagnostics.diagnostics.map(\.message))")
        let overlapDiagnostics = ctx.diagnostics.diagnostics.filter {
            $0.code == "KSWIFTK-SEMA-0102"
                && $0.message.contains("kotlin.reflect.KProperty0")
        }
        #expect(
            overlapDiagnostics.isEmpty,
            "Source-backed extension property getter was misclassified as a synthetic stub: \(overlapDiagnostics)"
        )
    }

    @Test
    func testNoOverlapWarnings() throws {
        let sources: [String] = [
            """
            package sample0

            fun main() {
                val xs = listOf(1, 2, 3)
                println(xs.count())
                println(xs.reversed())
                println(xs.sorted())
                println(xs.shuffled())
            }
            """,
            """
            package sample1
            @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

            import kotlin.concurrent.atomics.AtomicInt
            import kotlin.concurrent.atomics.AtomicLong

            fun main() {
                val a = AtomicInt(1)
                println(a.fetchAndAdd(3))
                println(a.fetchAndIncrement())
                println(a.fetchAndDecrement())
                println(a.compareAndSet(2, 5))
                val b = AtomicLong(1L)
                println(b.fetchAndAdd(3L))
                println(b.fetchAndIncrement())
                println(b.fetchAndDecrement())
                println(b.compareAndSet(2L, 5L))
            }
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            // KSP-671: fetchAndAdd/fetchAndIncrement/fetchAndDecrement/compareAndSet are
            // bundled Kotlin delegations in AtomicMigration.kt while the runtime-backed
            // synthetic stubs stay registered (their bridge is shared with
            // java.util.concurrent.atomic.AtomicInteger). The retained-overlap guard must
            // both keep the members resolvable and suppress the SEMA-0102 warning.
            #expect(!ctx.diagnostics.hasError, "Unexpected errors: \(ctx.diagnostics.diagnostics.map(\.message))")
            let overlapDiags = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0102" }
            #expect(overlapDiags.isEmpty, "Unexpected overlap warnings: \(overlapDiags.map(\.message))")
        }
    }

    @Test
    func testKSP688AtomicBooleanAndReferenceCompareAndSetUseBundledSource() throws {
        // KSP-688: compareAndSet is a bundled Kotlin wrapper over the retained
        // compareAndExchange runtime core. No synthetic compareAndSet stub or
        // public kk_atomic_* compareAndSet bridge should remain for these types.
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

        import kotlin.concurrent.atomics.AtomicBoolean
        import kotlin.concurrent.atomics.AtomicReference

        data class Token(val id: Int)

        fun main() {
            val flag = AtomicBoolean(true)
            println(flag.compareAndSet(true, false))
            val current = Token(1)
            val equalButDistinct = Token(1)
            val ref = AtomicReference(current)
            println(ref.compareAndSet(equalButDistinct, Token(2)))
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected errors: \(ctx.diagnostics.diagnostics.map(\.message))")
        let overlapDiags = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0102" }
        #expect(overlapDiags.isEmpty, "Unexpected overlap warnings: \(overlapDiags.map(\.message))")
    }

    @Test
    func testKSP696ScalarCompareAndExchangeUsesBundledSource() throws {
        // KSP-696: compareAndExchange is a bundled Kotlin wrapper over the
        // internal scalar runtime bridge for all four atomic scalar types.
        let source = """
        import kotlin.concurrent.AtomicBoolean
        import kotlin.concurrent.AtomicInt
        import kotlin.concurrent.AtomicLong
        import kotlin.concurrent.AtomicReference

        data class Token(val id: Int)

        fun main() {
            val int = AtomicInt(1)
            println(int.compareAndExchange(1, 2))
            println(int.compareAndExchange(1, 3))
            val long = AtomicLong(1L)
            println(long.compareAndExchange(1L, 2L))
            println(long.compareAndExchange(1L, 3L))
            val flag = AtomicBoolean(true)
            println(flag.compareAndExchange(true, false))
            println(flag.compareAndExchange(true, false))
            val current = Token(1)
            val equalButDistinct = Token(1)
            val replacement = Token(2)
            val ref = AtomicReference(current)
            println(ref.compareAndExchange(current, replacement))
            println(ref.compareAndExchange(equalButDistinct, Token(3)))
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected errors: \(ctx.diagnostics.diagnostics.map(\.message))")
        let overlapDiags = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0102" }
        #expect(overlapDiags.isEmpty, "Unexpected overlap warnings: \(overlapDiags.map(\.message))")

        let sema = try #require(ctx.sema)
        let compareAndExchangeFQName = ["kotlin", "concurrent", "compareAndExchange"]
            .map(ctx.interner.intern)
        let sourceSymbols = sema.symbols.lookupAll(fqName: compareAndExchangeFQName)
        #expect(sourceSymbols.count == 4, "Expected one bundled overload per scalar atomic type")
        #expect(
            sourceSymbols.allSatisfy { sema.symbols.externalLinkName(for: $0) == nil },
            "Bundled compareAndExchange wrappers must not expose public runtime links"
        )
        #expect(
            sourceSymbols.allSatisfy { !(sema.symbols.symbol($0)?.flags.contains(.synthetic) ?? true) },
            "Bundled compareAndExchange wrappers must not be synthetic stubs"
        )
    }

    @Test
    func testSourceBackedSequenceRuntimeAliasDoesNotWarn() throws {
        let source = """
        fun main() {
            sequenceOf(1, 2, 1).toHashSet()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let overlapDiagnostics = ctx.diagnostics.diagnostics.filter {
                $0.code == "KSWIFTK-SEMA-0102"
            }
            #expect(
                overlapDiagnostics.isEmpty,
                "Source-backed Sequence runtime alias leaked overlap diagnostics: \(overlapDiagnostics)"
            )
        }
    }

    @Test
    func testImportedSourceBackedOpenEndRangeOverloadDoesNotWarn() {
        let symbols = SymbolTable()
        let types = TypeSystem()
        types.symbolTable = symbols
        let interner = StringInterner()
        let diagnostics = DiagnosticEngine()
        let openEndRangeFQName = ["kotlin", "ranges", "OpenEndRange"].map { interner.intern($0) }
        let containsName = interner.intern("contains")

        let openEndRangeSymbol = symbols.define(
            kind: .interface,
            name: openEndRangeFQName.last!,
            fqName: openEndRangeFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        let typeParameterSymbol = symbols.define(
            kind: .typeParameter,
            name: interner.intern("T"),
            fqName: openEndRangeFQName + [interner.intern("T")],
            declSite: nil,
            visibility: .private,
            flags: []
        )
        symbols.setParentSymbol(openEndRangeSymbol, for: typeParameterSymbol)
        let typeParameterType = types.make(.typeParam(TypeParamType(
            symbol: typeParameterSymbol,
            nullability: .nonNull
        )))
        let genericReceiverType = types.make(.classType(ClassType(
            classSymbol: openEndRangeSymbol,
            args: [.invariant(typeParameterType)],
            nullability: .nonNull
        )))
        let genericSymbol = symbols.define(
            kind: .function,
            name: containsName,
            fqName: openEndRangeFQName + [containsName],
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(openEndRangeSymbol, for: genericSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: genericReceiverType,
                parameterTypes: [typeParameterType],
                returnType: types.booleanType,
                classTypeParameterCount: 1
            ),
            for: genericSymbol
        )

        let importedOverload = symbols.define(
            kind: .function,
            name: containsName,
            fqName: [interner.intern("kotlin"), interner.intern("ranges"), containsName],
            declSite: nil,
            visibility: .public,
            flags: [.importedLibrary]
        )
        let concreteReceiverType = types.make(.classType(ClassType(
            classSymbol: openEndRangeSymbol,
            args: [.invariant(types.intType)],
            nullability: .nonNull
        )))
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: concreteReceiverType,
                parameterTypes: [types.intType],
                returnType: types.booleanType
            ),
            for: importedOverload
        )

        var bundledIndex = BundledDeclarationIndex.empty
        bundledIndex.insert(BundledMemberKey(
            ownerFQName: openEndRangeFQName,
            name: containsName,
            arity: 1
        ))
        bundledIndex.warnSyntheticOverlaps(
            symbols: symbols,
            types: types,
            diagnostics: diagnostics,
            interner: interner
        )

        #expect(
            diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0102" }.isEmpty,
            "Imported source-backed OpenEndRange overload leaked an overlap warning"
        )
    }

    private func makeContext(diagnostics: DiagnosticEngine) -> CompilationContext {
        makeCompilationContext(inputs: ["/tmp/test.kt"], diagnostics: diagnostics)
    }
}
#endif
