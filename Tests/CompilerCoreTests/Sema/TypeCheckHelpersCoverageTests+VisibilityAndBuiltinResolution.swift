@testable import CompilerCore
import XCTest

extension TypeCheckHelpersCoverageTests {
    func testEmitVisibilityErrorAndBindErrorType() throws {
        let fixture = makeHelpersFixture()
        let helpers = TypeCheckHelpers()

        let privateSymbolID = fixture.symbols.define(
            kind: .function,
            name: fixture.interner.intern("privateFn"),
            fqName: [fixture.interner.intern("privateFn")],
            declSite: makeRange(),
            visibility: .private
        )
        let protectedSymbolID = fixture.symbols.define(
            kind: .function,
            name: fixture.interner.intern("protectedFn"),
            fqName: [fixture.interner.intern("protectedFn")],
            declSite: makeRange(),
            visibility: .protected
        )

        let privateSymbol = fixture.symbols.symbol(privateSymbolID)
        let protectedSymbol = fixture.symbols.symbol(protectedSymbolID)

        try helpers.emitVisibilityError(
            for: XCTUnwrap(privateSymbol),
            name: "privateFn",
            range: makeRange(),
            diagnostics: fixture.diagnostics
        )
        try helpers.emitVisibilityError(
            for: XCTUnwrap(protectedSymbol),
            name: "protectedFn",
            range: makeRange(),
            diagnostics: fixture.diagnostics
        )

        XCTAssertTrue(fixture.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0040" })
        XCTAssertTrue(fixture.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0041" })

        let exprID = ExprID(rawValue: 123)
        let result = helpers.bindAndReturnErrorType(exprID, sema: fixture.sema)
        XCTAssertEqual(result, fixture.types.errorType)
        XCTAssertEqual(fixture.bindings.exprType(for: exprID), fixture.types.errorType)
    }

    func testStableLocalSymbolIterableAndBuiltinReturnTypes() {
        let fixture = makeHelpersFixture()
        let helpers = TypeCheckHelpers()

        let stableLocal = fixture.symbols.define(
            kind: .local,
            name: fixture.interner.intern("stable"),
            fqName: [fixture.interner.intern("stable")],
            declSite: nil,
            visibility: .private
        )
        let mutableLocal = fixture.symbols.define(
            kind: .local,
            name: fixture.interner.intern("mutable"),
            fqName: [fixture.interner.intern("mutable")],
            declSite: nil,
            visibility: .private,
            flags: [.mutable]
        )
        let fnSymbol = fixture.symbols.define(
            kind: .function,
            name: fixture.interner.intern("f"),
            fqName: [fixture.interner.intern("f")],
            declSite: nil,
            visibility: .public
        )

        XCTAssertTrue(helpers.isStableLocalSymbol(stableLocal, sema: fixture.sema))
        XCTAssertFalse(helpers.isStableLocalSymbol(mutableLocal, sema: fixture.sema))
        XCTAssertFalse(helpers.isStableLocalSymbol(fnSymbol, sema: fixture.sema))
        XCTAssertFalse(helpers.isStableLocalSymbol(SymbolID(rawValue: 999), sema: fixture.sema))

        let intArraySymbol = fixture.symbols.define(
            kind: .class,
            name: fixture.interner.intern("IntArray"),
            fqName: [fixture.interner.intern("IntArray")],
            declSite: nil,
            visibility: .public
        )
        let intArrayType = fixture.types.make(
            .classType(ClassType(classSymbol: intArraySymbol, args: [], nullability: .nonNull))
        )

        XCTAssertEqual(
            helpers.arrayElementType(for: intArrayType, sema: fixture.sema, interner: fixture.interner),
            fixture.types.intType
        )
        XCTAssertNil(
            helpers.arrayElementType(for: fixture.types.intType, sema: fixture.sema, interner: fixture.interner)
        )

        XCTAssertEqual(
            helpers.iterableElementType(for: fixture.types.intType, isRangeExpr: true, sema: fixture.sema, interner: fixture.interner),
            fixture.types.intType
        )
        XCTAssertEqual(
            helpers.iterableElementType(for: intArrayType, isRangeExpr: false, sema: fixture.sema, interner: fixture.interner),
            fixture.types.intType
        )

        XCTAssertEqual(
            helpers.kxMiniCoroutineBuiltinReturnType(
                calleeName: fixture.interner.intern("runBlocking"),
                argumentCount: 1,
                sema: fixture.sema,
                interner: fixture.interner
            ),
            fixture.types.anyType
        )
        XCTAssertEqual(
            helpers.kxMiniCoroutineBuiltinReturnType(
                calleeName: fixture.interner.intern("launch"),
                argumentCount: 1,
                sema: fixture.sema,
                interner: fixture.interner
            ),
            fixture.types.nullableAnyType
        )
        XCTAssertEqual(
            helpers.kxMiniCoroutineBuiltinReturnType(
                calleeName: fixture.interner.intern("kk_array_get"),
                argumentCount: 2,
                sema: fixture.sema,
                interner: fixture.interner
            ),
            fixture.types.anyType
        )
        XCTAssertEqual(
            helpers.kxMiniCoroutineBuiltinReturnType(
                calleeName: fixture.interner.intern("kk_list_get"),
                argumentCount: 2,
                sema: fixture.sema,
                interner: fixture.interner
            ),
            fixture.types.anyType
        )
        XCTAssertNil(
            helpers.kxMiniCoroutineBuiltinReturnType(
                calleeName: fixture.interner.intern("unknown"),
                argumentCount: 1,
                sema: fixture.sema,
                interner: fixture.interner
            )
        )
        XCTAssertNil(
            helpers.kxMiniCoroutineBuiltinReturnType(
                calleeName: nil,
                argumentCount: 1,
                sema: fixture.sema,
                interner: fixture.interner
            )
        )
    }

    func testResolveBuiltinAndTypeRefVariants() {
        let fixture = makeHelpersFixture()
        let helpers = TypeCheckHelpers()

        XCTAssertEqual(helpers.resolveBuiltinTypeName("Int", types: fixture.types), fixture.types.intType)
        XCTAssertEqual(helpers.resolveBuiltinTypeName("Any", nullability: .nullable, types: fixture.types), fixture.types.nullableAnyType)
        XCTAssertEqual(helpers.resolveBuiltinTypeName("Nothing", nullability: .nullable, types: fixture.types), fixture.types.nullableNothingType)
        XCTAssertNil(helpers.resolveBuiltinTypeName("Unknown", types: fixture.types))

        let intRef = fixture.astArena.appendTypeRef(
            .named(path: [fixture.interner.intern("Int")], args: [], nullable: false)
        )
        let nullableIntRef = fixture.astArena.appendTypeRef(
            .named(path: [fixture.interner.intern("Int")], args: [], nullable: true)
        )
        let fnRef = fixture.astArena.appendTypeRef(
            .functionType(params: [intRef], returnType: nullableIntRef, isSuspend: true, nullable: false)
        )
        let intersectionRef = fixture.astArena.appendTypeRef(.intersection(parts: [intRef, nullableIntRef]))

        XCTAssertEqual(
            helpers.resolveTypeRef(intRef, ast: fixture.ast, sema: fixture.sema, interner: fixture.interner),
            fixture.types.intType
        )

        let resolvedFn = helpers.resolveTypeRef(fnRef, ast: fixture.ast, sema: fixture.sema, interner: fixture.interner)
        if case let .functionType(ft) = fixture.types.kind(of: resolvedFn) {
            XCTAssertEqual(ft.params, [fixture.types.intType])
            XCTAssertEqual(ft.returnType, fixture.types.make(.primitive(.int, .nullable)))
            XCTAssertTrue(ft.isSuspend)
        } else {
            XCTFail("Expected functionType")
        }

        let resolvedIntersection = helpers.resolveTypeRef(
            intersectionRef,
            ast: fixture.ast,
            sema: fixture.sema,
            interner: fixture.interner
        )
        if case let .intersection(parts) = fixture.types.kind(of: resolvedIntersection) {
            XCTAssertEqual(parts.count, 2)
        } else {
            XCTFail("Expected intersection")
        }

        let unresolvedRef = fixture.astArena.appendTypeRef(
            .named(path: [fixture.interner.intern("MissingType")], args: [], nullable: false)
        )
        let unresolved = helpers.resolveTypeRef(
            unresolvedRef,
            ast: fixture.ast,
            sema: fixture.sema,
            interner: fixture.interner,
            diagnostics: fixture.diagnostics
        )
        XCTAssertEqual(unresolved, fixture.types.errorType)
        XCTAssertTrue(fixture.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0025" })

        XCTAssertEqual(
            helpers.resolveTypeRef(TypeRefID(rawValue: 9999), ast: fixture.ast, sema: fixture.sema, interner: fixture.interner),
            fixture.types.errorType
        )
    }
}
