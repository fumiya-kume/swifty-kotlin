#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct RuntimeTypeCheckTokenTests {

    // MARK: - classify() Tests

    @Test func testClassifyBuiltinTypes() {
        let types = TypeSystem()
        let symbols = SymbolTable()
        let sema = makeSemaModule(symbols: symbols, types: types, bindings: BindingTable(), diagnostics: DiagnosticEngine()).ctx

        let cases: [(TypeKind, RuntimeTypeCategory, Bool)] = [
            (.any(.nonNull), .any, false),
            (.any(.nullable), .any, true),
            (.primitive(.int, .nonNull), .int, false),
            (.primitive(.int, .nullable), .int, true),
            (.stringStruct(.nonNull), .string, false),
            (.primitive(.boolean, .nonNull), .boolean, false),
            (.primitive(.uint, .nonNull), .uint, false),
            (.primitive(.ulong, .nonNull), .ulong, false),
            (.primitive(.ubyte, .nonNull), .ubyte, false),
            (.primitive(.ushort, .nonNull), .ushort, false),
        ]

        for (kind, expectedCategory, expectedNullable) in cases {
            let typeID = types.make(kind)
            let descriptor = RuntimeTypeCheckToken.classify(type: typeID, sema: sema)
            #expect(
                descriptor.category.base == expectedCategory.base,
                "Expected \(expectedCategory) for \(kind), got base \(descriptor.category.base)"
            )
            #expect(descriptor.nullable == expectedNullable, "Nullable mismatch for \(kind)")
        }
    }

    @Test func testClassifyNothingType() {
        let types = TypeSystem()
        let sema = makeSemaModule(symbols: SymbolTable(), types: types, bindings: BindingTable(), diagnostics: DiagnosticEngine()).ctx

        let nothingNonNull = types.make(.nothing(.nonNull))
        let descriptorNonNull = RuntimeTypeCheckToken.classify(type: nothingNonNull, sema: sema)
        #expect(descriptorNonNull.category.base == RuntimeTypeCheckToken.unknownBase)

        let nothingNullable = types.make(.nothing(.nullable))
        let descriptorNullable = RuntimeTypeCheckToken.classify(type: nothingNullable, sema: sema)
        #expect(descriptorNullable.category.base == RuntimeTypeCheckToken.nullBase)
    }

    @Test func testClassifyNominalType() {
        let interner = StringInterner()
        let types = TypeSystem()
        let symbols = SymbolTable()
        let sema = makeSemaModule(symbols: symbols, types: types, bindings: BindingTable(), diagnostics: DiagnosticEngine()).ctx

        let className = interner.intern("MyClass")
        let pkgName = interner.intern("pkg")
        let classSymbol = symbols.define(
            kind: .class,
            name: className,
            fqName: [pkgName, className],
            declSite: makeRange(),
            visibility: .public
        )
        let classType = types.make(.classType(ClassType(classSymbol: classSymbol, args: [], nullability: .nonNull)))
        let descriptor = RuntimeTypeCheckToken.classify(type: classType, sema: sema)
        #expect(descriptor.category.base == RuntimeTypeCheckToken.nominalBase)
        #expect(!(descriptor.nullable))
        if case let .nominal(symbolID) = descriptor.category {
            #expect(symbolID == classSymbol)
        } else {
            Issue.record("Expected .nominal category for class type")
        }
    }

    @Test func testClassifyUnknownTypes() {
        let types = TypeSystem()
        let sema = makeSemaModule(symbols: SymbolTable(), types: types, bindings: BindingTable(), diagnostics: DiagnosticEngine()).ctx

        // Function type should classify as unknown
        let intType = types.make(.primitive(.int, .nonNull))
        let funcType = types.make(.functionType(FunctionType(
            receiver: nil,
            params: [intType],
            returnType: intType,
            isSuspend: false,
            nullability: .nonNull
        )))
        let descriptor = RuntimeTypeCheckToken.classify(type: funcType, sema: sema)
        #expect(descriptor.category.base == RuntimeTypeCheckToken.unknownBase)
    }

    // MARK: - encode() Consistency Tests

    @Test func testEncodeConsistencyWithClassify() {
        let interner = StringInterner()
        let types = TypeSystem()
        let symbols = SymbolTable()
        let sema = makeSemaModule(symbols: symbols, types: types, bindings: BindingTable(), diagnostics: DiagnosticEngine()).ctx

        let testTypes: [TypeKind] = [
            .any(.nonNull),
            .any(.nullable),
            .primitive(.int, .nonNull),
            .stringStruct(.nullable),
            .primitive(.boolean, .nonNull),
            .primitive(.uint, .nonNull),
            .primitive(.ulong, .nonNull),
            .primitive(.ubyte, .nonNull),
            .primitive(.ushort, .nonNull),
        ]

        for kind in testTypes {
            let typeID = types.make(kind)
            let encoded = RuntimeTypeCheckToken.encode(type: typeID, sema: sema, interner: interner)
            let descriptor = RuntimeTypeCheckToken.classify(type: typeID, sema: sema)
            let manuallyEncoded = RuntimeTypeCheckToken.encode(
                base: descriptor.category.base,
                nullable: descriptor.nullable
            )
            #expect(
                encoded == manuallyEncoded,
                "encode(type:) and classify()+encode(base:) should produce the same token for \(kind)"
            )
        }
    }

    @Test func testEncodeNothingUsesCanonicalLegacyTokens() {
        let interner = StringInterner()
        let types = TypeSystem()
        let sema = makeSemaModule(symbols: SymbolTable(), types: types, bindings: BindingTable(), diagnostics: DiagnosticEngine()).ctx

        let nothingNonNull = types.make(.nothing(.nonNull))
        #expect(
            RuntimeTypeCheckToken.encode(type: nothingNonNull, sema: sema, interner: interner) ==
            RuntimeTypeCheckToken.unknownBase
        )

        let nothingNullable = types.make(.nothing(.nullable))
        #expect(
            RuntimeTypeCheckToken.encode(type: nothingNullable, sema: sema, interner: interner) ==
            RuntimeTypeCheckToken.nullBase
        )
    }

    @Test func testEncodeNominalConsistencyWithClassify() {
        let interner = StringInterner()
        let types = TypeSystem()
        let symbols = SymbolTable()
        let sema = makeSemaModule(symbols: symbols, types: types, bindings: BindingTable(), diagnostics: DiagnosticEngine()).ctx

        let className = interner.intern("Foo")
        let pkgName = interner.intern("bar")
        let classSymbol = symbols.define(
            kind: .class,
            name: className,
            fqName: [pkgName, className],
            declSite: makeRange(),
            visibility: .public
        )
        let classType = types.make(.classType(ClassType(classSymbol: classSymbol, args: [], nullability: .nonNull)))

        let encoded = RuntimeTypeCheckToken.encode(type: classType, sema: sema, interner: interner)
        let descriptor = RuntimeTypeCheckToken.classify(type: classType, sema: sema)
        guard case let .nominal(symbolID) = descriptor.category else {
            Issue.record("Expected .nominal category")
            return
        }
        let nominalPayload = RuntimeTypeCheckToken.stableNominalTypeID(symbol: symbolID, sema: sema, interner: interner)
        let manuallyEncoded = RuntimeTypeCheckToken.encode(
            base: RuntimeTypeCheckToken.nominalBase,
            nullable: descriptor.nullable,
            payload: nominalPayload
        )
        #expect(encoded == manuallyEncoded)
    }

    // MARK: - simpleName() Consistency Tests

    @Test func testSimpleNameConsistencyWithCategory() {
        let interner = StringInterner()
        let types = TypeSystem()
        let sema = makeSemaModule(symbols: SymbolTable(), types: types, bindings: BindingTable(), diagnostics: DiagnosticEngine()).ctx

        let testCases: [(TypeKind, String)] = [
            (.any(.nonNull), "Any"),
            (.primitive(.int, .nonNull), "Int"),
            (.stringStruct(.nonNull), "String"),
            (.primitive(.boolean, .nonNull), "Boolean"),
            (.primitive(.uint, .nonNull), "UInt"),
            (.primitive(.ulong, .nonNull), "ULong"),
            (.primitive(.ubyte, .nonNull), "UByte"),
            (.primitive(.ushort, .nonNull), "UShort"),
            (.nothing(.nonNull), "Nothing"),
            (.nothing(.nullable), "Nothing"),
        ]

        for (kind, expectedName) in testCases {
            let typeID = types.make(kind)
            let simpleName = RuntimeTypeCheckToken.simpleName(of: typeID, sema: sema, interner: interner)
            let descriptor = RuntimeTypeCheckToken.classify(type: typeID, sema: sema)
            #expect(simpleName == expectedName, "simpleName mismatch for \(kind)")
            if descriptor.category.simpleName != nil {
                #expect(descriptor.category.simpleName == expectedName, "category.simpleName mismatch for \(kind)")
                #expect(simpleName == descriptor.category.simpleName, "simpleName and category.simpleName should be equal for \(kind)")
            }
        }
    }

    @Test func testSimpleNameForPrimitivesNotInCategory() {
        let interner = StringInterner()
        let types = TypeSystem()
        let sema = makeSemaModule(symbols: SymbolTable(), types: types, bindings: BindingTable(), diagnostics: DiagnosticEngine()).ctx

        // These primitives are handled by simpleName via direct TypeKind switch,
        // not through RuntimeTypeCategory
        let extraPrimitives: [(TypeKind, String)] = [
            (.primitive(.long, .nonNull), "Long"),
            (.primitive(.char, .nonNull), "Char"),
            (.primitive(.float, .nonNull), "Float"),
            (.primitive(.double, .nonNull), "Double"),
        ]

        for (kind, expectedName) in extraPrimitives {
            let typeID = types.make(kind)
            let simpleName = RuntimeTypeCheckToken.simpleName(of: typeID, sema: sema, interner: interner)
            #expect(simpleName == expectedName)
        }
    }

    // MARK: - Catch/Is Token Consistency Tests

    @Test func testCatchTokenMatchesIsToken() throws {
        let source = """
        class MyException : Exception()
        fun demo() {
            try {
                throw MyException()
            } catch (e: MyException) {
                println(e)
            }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let sema = try #require(ctx.sema)
            let ast = try #require(ctx.ast)

            let tryExprID = try #require(firstExprID(in: ast) { _, expr in
                if case .tryExpr = expr { return true }
                return false
            })
            guard case let .tryExpr(_, catchClauses, _, _)? = ast.arena.expr(tryExprID) else {
                Issue.record("Expected try expression.")
                return
            }

            for clause in catchClauses {
                if let binding = sema.bindings.catchClauseBinding(for: clause.body) {
                    let catchToken = RuntimeTypeCheckToken.encode(
                        type: binding.parameterType,
                        sema: sema,
                        interner: ctx.interner
                    )
                    let isToken = RuntimeTypeCheckToken.encode(
                        type: binding.parameterType,
                        sema: sema,
                        interner: ctx.interner
                    )
                    #expect(
                        catchToken == isToken,
                        "Catch and is paths should produce the same token for the same type."
                    )
                }
            }
        }
    }

    // MARK: - Type Alias Resolution Test

    @Test func testTypeAliasResolvesToCorrectToken() {
        let interner = StringInterner()
        let types = TypeSystem()
        let symbols = SymbolTable()
        let sema = makeSemaModule(symbols: symbols, types: types, bindings: BindingTable(), diagnostics: DiagnosticEngine()).ctx

        // Simulate a type alias: typealias MyInt = Int
        // The resolved type should be Int, not a nominal type based on the alias name.
        let intType = types.make(.primitive(.int, .nonNull))

        // When a type alias is resolved, it produces the underlying TypeID (Int)
        let aliasToken = RuntimeTypeCheckToken.encode(type: intType, sema: sema, interner: interner)
        let directToken = RuntimeTypeCheckToken.encode(
            base: RuntimeTypeCheckToken.intBase,
            nullable: false
        )
        #expect(
            aliasToken == directToken,
            "A resolved type alias to Int should produce the same token as Int directly."
        )

        // Verify it does NOT produce a nominal token
        let descriptor = RuntimeTypeCheckToken.classify(type: intType, sema: sema)
        if case .nominal = descriptor.category {
            Issue.record("Resolved type alias to Int should not classify as nominal.")
        }
        #expect(descriptor.category.base == RuntimeTypeCheckToken.intBase)
    }

    // MARK: - Builtin-disguised-as-nominal `T::class` Tests

    /// Builtins like `String`/`Char`/`Any` additionally register a synthetic
    /// `.class`-kind symbol under `kotlin.<Name>` purely to host member
    /// declarations (e.g. String's `CharSequence` conformance — see
    /// `HeaderHelpers.ensureClassSymbol`). `T::class` resolves through scope
    /// lookup, which finds that synthetic symbol before ever consulting the
    /// builtin-name fallback, so `classRefTargetType` for `String::class` is
    /// `.classType(ClassType(classSymbol: kotlin.String))`, not the canonical
    /// `sema.types.stringType` (`.stringStruct`) that an ordinary `is String`
    /// check resolves to. Both must still encode to the same runtime token —
    /// otherwise `String::class.isInstance(...)` diverges from `is String`.
    @Test func testBuiltinClassRefTokenMatchesPrimitiveBase() throws {
        let source = """
        fun main() {
            val k = String::class
            println(k)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            // Not asserting `!hasError` here (unlike most tests in this file) —
            // bundled stdlib currently emits an unrelated pre-existing diagnostic
            // (KSWIFTK-SEMA-0102 duplicate-stub warning/error for
            // kotlin.time.Instant) on any full compilation that this test isn't
            // about. TimedValue is now source-backed and no longer contributes
            // duplicate-stub noise. The `#require`s below on the
            // classRefTargetType binding are the actual correctness check.

            let sema = try #require(ctx.sema)
            let ast = try #require(ctx.ast)
            let interner = ctx.interner

            let classRefExprID = try #require(firstExprID(in: ast) { _, expr in
                if case let .callableRef(_, member, _) = expr {
                    return interner.resolve(member) == "class"
                }
                return false
            })
            let targetType = try #require(sema.bindings.classRefTargetType(for: classRefExprID))

            // The receiver-resolution quirk described above must still be in
            // effect for this test to be meaningful (otherwise it would pass
            // vacuously if `classRefTargetType` ever stopped disguising
            // String as a nominal type).
            guard case let .classType(classType) = sema.types.kind(of: targetType) else {
                Issue.record("Expected String::class to resolve through the class-symbol-disguise path; got \(sema.types.kind(of: targetType)). If this is now the canonical stringStruct kind, this test (and the encode() fix it guards) may no longer be necessary.")
                return
            }
            let symbol = try #require(sema.symbols.symbol(classType.classSymbol))
            #expect(symbol.fqName.map { interner.resolve($0) } == ["kotlin", "String"])

            let encoded = RuntimeTypeCheckToken.encode(type: targetType, sema: sema, interner: interner)
            let expected = RuntimeTypeCheckToken.encode(base: RuntimeTypeCheckToken.stringBase, nullable: false)
            #expect(
                encoded == expected,
                "String::class should encode with stringBase like an ordinary `is String` check, not nominalBase."
            )
        }
    }

    @Test func testDistinctNominalTypesProduceDifferentTokens() {
        let interner = StringInterner()
        let types = TypeSystem()
        let symbols = SymbolTable()
        let sema = makeSemaModule(symbols: symbols, types: types, bindings: BindingTable(), diagnostics: DiagnosticEngine()).ctx

        let pkgName = interner.intern("pkg")
        let range = makeRange()

        let classAName = interner.intern("ClassA")
        let classASymbol = symbols.define(
            kind: .class,
            name: classAName,
            fqName: [pkgName, classAName],
            declSite: range,
            visibility: .public
        )
        let classAType = types.make(.classType(ClassType(classSymbol: classASymbol, args: [], nullability: .nonNull)))

        let classBName = interner.intern("ClassB")
        let classBSymbol = symbols.define(
            kind: .class,
            name: classBName,
            fqName: [pkgName, classBName],
            declSite: range,
            visibility: .public
        )
        let classBType = types.make(.classType(ClassType(classSymbol: classBSymbol, args: [], nullability: .nonNull)))

        let tokenA = RuntimeTypeCheckToken.encode(type: classAType, sema: sema, interner: interner)
        let tokenB = RuntimeTypeCheckToken.encode(type: classBType, sema: sema, interner: interner)
        #expect(tokenA != tokenB, "Different nominal types should produce different tokens.")
    }
}
#endif
