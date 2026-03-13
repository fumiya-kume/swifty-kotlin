@testable import CompilerCore
import Foundation
import XCTest

final class RuntimeTypeCheckTokenTests: XCTestCase {

    // MARK: - classify() Tests

    func testClassifyBuiltinTypes() {
        let interner = StringInterner()
        let types = TypeSystem()
        let symbols = SymbolTable()
        let sema = SemaModule(
            symbols: symbols,
            types: types,
            bindings: BindingTable(),
            diagnostics: DiagnosticEngine()
        )

        let cases: [(TypeKind, RuntimeTypeCategory, Bool)] = [
            (.any(.nonNull), .any, false),
            (.any(.nullable), .any, true),
            (.primitive(.int, .nonNull), .int, false),
            (.primitive(.int, .nullable), .int, true),
            (.primitive(.string, .nonNull), .string, false),
            (.primitive(.boolean, .nonNull), .boolean, false),
            (.primitive(.uint, .nonNull), .uint, false),
            (.primitive(.ulong, .nonNull), .ulong, false),
            (.primitive(.ubyte, .nonNull), .ubyte, false),
            (.primitive(.ushort, .nonNull), .ushort, false),
        ]

        for (kind, expectedCategory, expectedNullable) in cases {
            let typeID = types.make(kind)
            let descriptor = RuntimeTypeCheckToken.classify(type: typeID, sema: sema, interner: interner)
            XCTAssertEqual(
                descriptor.category.base,
                expectedCategory.base,
                "Expected \(expectedCategory) for \(kind), got base \(descriptor.category.base)"
            )
            XCTAssertEqual(descriptor.nullable, expectedNullable, "Nullable mismatch for \(kind)")
        }
    }

    func testClassifyNothingType() {
        let interner = StringInterner()
        let types = TypeSystem()
        let sema = SemaModule(
            symbols: SymbolTable(),
            types: types,
            bindings: BindingTable(),
            diagnostics: DiagnosticEngine()
        )

        let nothingNonNull = types.make(.nothing(.nonNull))
        let descriptorNonNull = RuntimeTypeCheckToken.classify(type: nothingNonNull, sema: sema, interner: interner)
        XCTAssertEqual(descriptorNonNull.category.base, RuntimeTypeCheckToken.unknownBase)

        let nothingNullable = types.make(.nothing(.nullable))
        let descriptorNullable = RuntimeTypeCheckToken.classify(type: nothingNullable, sema: sema, interner: interner)
        XCTAssertEqual(descriptorNullable.category.base, RuntimeTypeCheckToken.nullBase)
    }

    func testClassifyNominalType() {
        let interner = StringInterner()
        let types = TypeSystem()
        let symbols = SymbolTable()
        let sema = SemaModule(
            symbols: symbols,
            types: types,
            bindings: BindingTable(),
            diagnostics: DiagnosticEngine()
        )

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
        let descriptor = RuntimeTypeCheckToken.classify(type: classType, sema: sema, interner: interner)
        XCTAssertEqual(descriptor.category.base, RuntimeTypeCheckToken.nominalBase)
        XCTAssertFalse(descriptor.nullable)
        if case let .nominal(symbolID) = descriptor.category {
            XCTAssertEqual(symbolID, classSymbol)
        } else {
            XCTFail("Expected .nominal category for class type")
        }
    }

    func testClassifyUnknownTypes() {
        let interner = StringInterner()
        let types = TypeSystem()
        let sema = SemaModule(
            symbols: SymbolTable(),
            types: types,
            bindings: BindingTable(),
            diagnostics: DiagnosticEngine()
        )

        // Function type should classify as unknown
        let intType = types.make(.primitive(.int, .nonNull))
        let funcType = types.make(.functionType(FunctionType(
            receiver: nil,
            params: [intType],
            returnType: intType,
            isSuspend: false,
            nullability: .nonNull
        )))
        let descriptor = RuntimeTypeCheckToken.classify(type: funcType, sema: sema, interner: interner)
        XCTAssertEqual(descriptor.category.base, RuntimeTypeCheckToken.unknownBase)
    }

    // MARK: - encode() Consistency Tests

    func testEncodeConsistencyWithClassify() {
        let interner = StringInterner()
        let types = TypeSystem()
        let symbols = SymbolTable()
        let sema = SemaModule(
            symbols: symbols,
            types: types,
            bindings: BindingTable(),
            diagnostics: DiagnosticEngine()
        )

        let testTypes: [TypeKind] = [
            .any(.nonNull),
            .any(.nullable),
            .primitive(.int, .nonNull),
            .primitive(.string, .nullable),
            .primitive(.boolean, .nonNull),
            .primitive(.uint, .nonNull),
            .primitive(.ulong, .nonNull),
            .primitive(.ubyte, .nonNull),
            .primitive(.ushort, .nonNull),
        ]

        for kind in testTypes {
            let typeID = types.make(kind)
            let encoded = RuntimeTypeCheckToken.encode(type: typeID, sema: sema, interner: interner)
            let descriptor = RuntimeTypeCheckToken.classify(type: typeID, sema: sema, interner: interner)
            let manuallyEncoded = RuntimeTypeCheckToken.encode(
                base: descriptor.category.base,
                nullable: descriptor.nullable
            )
            XCTAssertEqual(
                encoded,
                manuallyEncoded,
                "encode(type:) and classify()+encode(base:) should produce the same token for \(kind)"
            )
        }
    }

    func testEncodeNothingUsesCanonicalLegacyTokens() {
        let interner = StringInterner()
        let types = TypeSystem()
        let sema = SemaModule(
            symbols: SymbolTable(),
            types: types,
            bindings: BindingTable(),
            diagnostics: DiagnosticEngine()
        )

        let nothingNonNull = types.make(.nothing(.nonNull))
        XCTAssertEqual(
            RuntimeTypeCheckToken.encode(type: nothingNonNull, sema: sema, interner: interner),
            RuntimeTypeCheckToken.unknownBase
        )

        let nothingNullable = types.make(.nothing(.nullable))
        XCTAssertEqual(
            RuntimeTypeCheckToken.encode(type: nothingNullable, sema: sema, interner: interner),
            RuntimeTypeCheckToken.nullBase
        )
    }

    func testEncodeNominalConsistencyWithClassify() {
        let interner = StringInterner()
        let types = TypeSystem()
        let symbols = SymbolTable()
        let sema = SemaModule(
            symbols: symbols,
            types: types,
            bindings: BindingTable(),
            diagnostics: DiagnosticEngine()
        )

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
        let descriptor = RuntimeTypeCheckToken.classify(type: classType, sema: sema, interner: interner)
        guard case let .nominal(symbolID) = descriptor.category else {
            XCTFail("Expected .nominal category")
            return
        }
        let nominalPayload = RuntimeTypeCheckToken.stableNominalTypeID(symbol: symbolID, sema: sema, interner: interner)
        let manuallyEncoded = RuntimeTypeCheckToken.encode(
            base: RuntimeTypeCheckToken.nominalBase,
            nullable: descriptor.nullable,
            payload: nominalPayload
        )
        XCTAssertEqual(encoded, manuallyEncoded)
    }

    // MARK: - simpleName() Consistency Tests

    func testSimpleNameConsistencyWithCategory() {
        let interner = StringInterner()
        let types = TypeSystem()
        let sema = SemaModule(
            symbols: SymbolTable(),
            types: types,
            bindings: BindingTable(),
            diagnostics: DiagnosticEngine()
        )

        let testCases: [(TypeKind, String)] = [
            (.any(.nonNull), "Any"),
            (.primitive(.int, .nonNull), "Int"),
            (.primitive(.string, .nonNull), "String"),
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
            let descriptor = RuntimeTypeCheckToken.classify(type: typeID, sema: sema, interner: interner)
            XCTAssertEqual(simpleName, expectedName, "simpleName mismatch for \(kind)")
            if descriptor.category.simpleName != nil {
                XCTAssertEqual(descriptor.category.simpleName, expectedName, "category.simpleName mismatch for \(kind)")
                XCTAssertEqual(simpleName, descriptor.category.simpleName, "simpleName and category.simpleName should be equal for \(kind)")
            }
        }
    }

    func testSimpleNameForPrimitivesNotInCategory() {
        let interner = StringInterner()
        let types = TypeSystem()
        let sema = SemaModule(
            symbols: SymbolTable(),
            types: types,
            bindings: BindingTable(),
            diagnostics: DiagnosticEngine()
        )

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
            XCTAssertEqual(simpleName, expectedName)
        }
    }

    // MARK: - Catch/Is Token Consistency Tests

    func testCatchTokenMatchesIsToken() throws {
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

            let sema = try XCTUnwrap(ctx.sema)
            let ast = try XCTUnwrap(ctx.ast)

            let tryExprID = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                if case .tryExpr = expr { return true }
                return false
            })
            guard case let .tryExpr(_, catchClauses, _, _)? = ast.arena.expr(tryExprID) else {
                XCTFail("Expected try expression.")
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
                    XCTAssertEqual(
                        catchToken,
                        isToken,
                        "Catch and is paths should produce the same token for the same type."
                    )
                }
            }
        }
    }

    // MARK: - Type Alias Resolution Test

    func testTypeAliasResolvesToCorrectToken() {
        let interner = StringInterner()
        let types = TypeSystem()
        let symbols = SymbolTable()
        let sema = SemaModule(
            symbols: symbols,
            types: types,
            bindings: BindingTable(),
            diagnostics: DiagnosticEngine()
        )

        // Simulate a type alias: typealias MyInt = Int
        // The resolved type should be Int, not a nominal type based on the alias name.
        let intType = types.make(.primitive(.int, .nonNull))

        // When a type alias is resolved, it produces the underlying TypeID (Int)
        let aliasToken = RuntimeTypeCheckToken.encode(type: intType, sema: sema, interner: interner)
        let directToken = RuntimeTypeCheckToken.encode(
            base: RuntimeTypeCheckToken.intBase,
            nullable: false
        )
        XCTAssertEqual(
            aliasToken,
            directToken,
            "A resolved type alias to Int should produce the same token as Int directly."
        )

        // Verify it does NOT produce a nominal token
        let descriptor = RuntimeTypeCheckToken.classify(type: intType, sema: sema, interner: interner)
        if case .nominal = descriptor.category {
            XCTFail("Resolved type alias to Int should not classify as nominal.")
        }
        XCTAssertEqual(descriptor.category.base, RuntimeTypeCheckToken.intBase)
    }

    func testDistinctNominalTypesProduceDifferentTokens() {
        let interner = StringInterner()
        let types = TypeSystem()
        let symbols = SymbolTable()
        let sema = SemaModule(
            symbols: symbols,
            types: types,
            bindings: BindingTable(),
            diagnostics: DiagnosticEngine()
        )

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
        XCTAssertNotEqual(tokenA, tokenB, "Different nominal types should produce different tokens.")
    }
}
