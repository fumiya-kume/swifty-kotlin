@testable import CompilerCore
import Foundation
import XCTest

extension LoweringABIAndPropertyRegressionTests {
    // MARK: - Property Lowering Tests

    func testPropertyLoweringRewritesGetterCallToDirectAccessorSymbol() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()

        let propertySym = SymbolID(rawValue: 50)
        let callerSym = SymbolID(rawValue: 51)

        let receiver = arena.appendExpr(.temporary(0), type: types.anyType)
        let result = arena.appendExpr(.temporary(1), type: types.anyType)

        let callerFn = KIRFunction(
            symbol: callerSym,
            name: interner.intern("caller"),
            params: [],
            returnType: types.unitType,
            body: [
                .call(
                    symbol: propertySym,
                    callee: interner.intern("get"),
                    arguments: [receiver],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ),
                .returnUnit,
            ],
            isSuspend: false,
            isInline: false
        )

        let fnID = arena.appendDecl(.function(callerFn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [fnID])], arena: arena)

        _ = try runLowering(module: module, interner: interner, moduleName: "PropGetter")

        guard case let .function(lowered)? = module.arena.decl(fnID) else {
            XCTFail("expected function")
            return
        }

        let expectedGetterSymbol = SymbolID(rawValue: -12000 - propertySym.rawValue)
        let callSymbols = lowered.body.compactMap { instruction -> SymbolID? in
            guard case let .call(sym, _, _, _, _, _, _) = instruction else { return nil }
            return sym
        }
        XCTAssertTrue(callSymbols.contains(expectedGetterSymbol),
                      "Expected synthetic getter symbol \(expectedGetterSymbol), got: \(callSymbols)")

        let callees = extractCallees(from: lowered.body, interner: interner)
        XCTAssertFalse(callees.contains("kk_property_access"))
    }

    func testPropertyLoweringRewritesSetterCallToDirectAccessorSymbol() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()

        let propertySym = SymbolID(rawValue: 60)
        let callerSym = SymbolID(rawValue: 61)

        let receiver = arena.appendExpr(.temporary(0), type: types.anyType)
        let value = arena.appendExpr(.temporary(1), type: types.anyType)
        let result = arena.appendExpr(.temporary(2), type: types.unitType)

        let callerFn = KIRFunction(
            symbol: callerSym,
            name: interner.intern("setter_caller"),
            params: [],
            returnType: types.unitType,
            body: [
                .call(
                    symbol: propertySym,
                    callee: interner.intern("set"),
                    arguments: [receiver, value],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ),
                .returnUnit,
            ],
            isSuspend: false,
            isInline: false
        )

        let fnID = arena.appendDecl(.function(callerFn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [fnID])], arena: arena)

        _ = try runLowering(module: module, interner: interner, moduleName: "PropSetter")

        guard case let .function(lowered)? = module.arena.decl(fnID) else {
            XCTFail("expected function")
            return
        }

        let expectedSetterSymbol = SymbolID(rawValue: -13000 - propertySym.rawValue)
        let callSymbols = lowered.body.compactMap { instruction -> SymbolID? in
            guard case let .call(sym, _, _, _, _, _, _) = instruction else { return nil }
            return sym
        }
        XCTAssertTrue(callSymbols.contains(expectedSetterSymbol),
                      "Expected synthetic setter symbol \(expectedSetterSymbol), got: \(callSymbols)")

        let callees = extractCallees(from: lowered.body, interner: interner)
        XCTAssertFalse(callees.contains("kk_property_access"))
    }

    func testPropertyLoweringPreservesGetSetCallsWithoutSymbol() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()

        let callerSym = SymbolID(rawValue: 70)
        let receiver = arena.appendExpr(.temporary(0), type: types.anyType)
        let result = arena.appendExpr(.temporary(1), type: types.anyType)

        let callerFn = KIRFunction(
            symbol: callerSym,
            name: interner.intern("no_sym_caller"),
            params: [],
            returnType: types.unitType,
            body: [
                .call(
                    symbol: nil,
                    callee: interner.intern("get"),
                    arguments: [receiver],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ),
                .returnUnit,
            ],
            isSuspend: false,
            isInline: false
        )

        let fnID = arena.appendDecl(.function(callerFn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [fnID])], arena: arena)

        _ = try runLowering(module: module, interner: interner, moduleName: "PropNoSym")

        guard case let .function(lowered)? = module.arena.decl(fnID) else {
            XCTFail("expected function")
            return
        }

        let callees = extractCallees(from: lowered.body, interner: interner)
        XCTAssertTrue(callees.contains("get"))
        XCTAssertFalse(callees.contains("kk_property_access"))
    }

    func testPropertyLoweringRewritesBackingFieldCopyToDirectSetterCall() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let symbols = SymbolTable()

        let propertySym = symbols.define(
            kind: .property,
            name: interner.intern("myProp"),
            fqName: [interner.intern("Foo"), interner.intern("myProp")],
            declSite: nil,
            visibility: .public,
            flags: []
        )
        let backingFieldSym = symbols.define(
            kind: .backingField,
            name: interner.intern("$backing_myProp"),
            fqName: [interner.intern("Foo"), interner.intern("$backing_myProp")],
            declSite: nil,
            visibility: .private,
            flags: []
        )
        symbols.setBackingFieldSymbol(backingFieldSym, for: propertySym)

        let callerSym = SymbolID(rawValue: 100)
        let fromExpr = arena.appendExpr(.intLiteral(42), type: types.anyType)
        let toExpr = arena.appendExpr(.symbolRef(backingFieldSym), type: types.anyType)

        let callerFn = KIRFunction(
            symbol: callerSym,
            name: interner.intern("bf_setter"),
            params: [],
            returnType: types.unitType,
            body: [
                .copy(from: fromExpr, to: toExpr),
                .returnUnit,
            ],
            isSuspend: false,
            isInline: false
        )

        let fnID = arena.appendDecl(.function(callerFn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [fnID])], arena: arena)

        let sema = SemaModule(symbols: symbols, types: types, bindings: BindingTable(), diagnostics: DiagnosticEngine())
        _ = try runLowering(module: module, interner: interner, moduleName: "BFSetter", sema: sema)

        guard case let .function(lowered)? = module.arena.decl(fnID) else {
            XCTFail("expected function")
            return
        }

        let expectedSetterSymbol = SymbolID(rawValue: -13000 - propertySym.rawValue)
        let callSymbols = lowered.body.compactMap { instruction -> SymbolID? in
            guard case let .call(sym, _, _, _, _, _, _) = instruction else { return nil }
            return sym
        }
        XCTAssertTrue(callSymbols.contains(expectedSetterSymbol),
                      "Expected setter symbol \(expectedSetterSymbol) for backing field copy, got: \(callSymbols)")

        let callees = extractCallees(from: lowered.body, interner: interner)
        XCTAssertTrue(callees.contains("set"))
        XCTAssertFalse(callees.contains("kk_property_access"))

        let hasCopy = lowered.body.contains { instruction in
            if case .copy = instruction { return true }
            return false
        }
        XCTAssertFalse(hasCopy, "Backing field copy should have been rewritten to a setter call")
    }

    func testPropertyLoweringRewritesComputedPropertySymbolRefToGetterCall() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let symbols = SymbolTable()

        let propertySym = symbols.define(
            kind: .property,
            name: interner.intern("computed"),
            fqName: [interner.intern("Foo"), interner.intern("computed")],
            declSite: nil,
            visibility: .public,
            flags: []
        )
        // Emit a getter accessor function so PropertyLoweringPass recognises
        // this property as a computed property (it checks that the getter
        // function actually exists in the KIR module).
        let getterSymbol = SymbolID(rawValue: -12000 - propertySym.rawValue)
        let getterRetExpr = arena.appendExpr(.stringLiteral(interner.intern("hello")), type: types.anyType)
        let getterFn = KIRFunction(
            symbol: getterSymbol,
            name: interner.intern("get"),
            params: [],
            returnType: types.anyType,
            body: [
                .constValue(result: getterRetExpr, value: .stringLiteral(interner.intern("hello"))),
                .returnValue(getterRetExpr),
            ],
            isSuspend: false,
            isInline: false
        )
        _ = arena.appendDecl(.function(getterFn))

        let callerSym = SymbolID(rawValue: 200)
        let propRef = arena.appendExpr(.symbolRef(propertySym), type: types.anyType)

        let callerFn = KIRFunction(
            symbol: callerSym,
            name: interner.intern("caller"),
            params: [],
            returnType: types.unitType,
            body: [
                .constValue(result: propRef, value: .symbolRef(propertySym)),
                .returnUnit,
            ],
            isSuspend: false,
            isInline: false
        )

        let fnID = arena.appendDecl(.function(callerFn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [fnID])], arena: arena)

        let sema = SemaModule(symbols: symbols, types: types, bindings: BindingTable(), diagnostics: DiagnosticEngine())
        _ = try runLowering(module: module, interner: interner, moduleName: "ComputedProp", sema: sema)

        guard case let .function(lowered)? = module.arena.decl(fnID) else {
            XCTFail("expected function")
            return
        }

        let expectedGetterSymbol = SymbolID(rawValue: -12000 - propertySym.rawValue)
        let callSymbols = lowered.body.compactMap { instruction -> SymbolID? in
            guard case let .call(sym, _, _, _, _, _, _) = instruction else { return nil }
            return sym
        }
        XCTAssertTrue(callSymbols.contains(expectedGetterSymbol),
                      "Expected getter call for computed property, got: \(callSymbols)")

        let hasSymbolRef = lowered.body.contains { instruction in
            if case let .constValue(_, value) = instruction,
               case let .symbolRef(sym) = value,
               sym == propertySym
            {
                return true
            }
            return false
        }
        XCTAssertFalse(hasSymbolRef,
                       "constValue(.symbolRef) for computed property should have been rewritten to a getter call")
    }

    func testPropertyLoweringPreservesBackedPropertySymbolRef() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let symbols = SymbolTable()

        let propertySym = symbols.define(
            kind: .property,
            name: interner.intern("backed"),
            fqName: [interner.intern("Foo"), interner.intern("backed")],
            declSite: nil,
            visibility: .public,
            flags: [.mutable]
        )
        let backingFieldSym = symbols.define(
            kind: .backingField,
            name: interner.intern("$backing_backed"),
            fqName: [interner.intern("Foo"), interner.intern("$backing_backed")],
            declSite: nil,
            visibility: .private,
            flags: []
        )
        symbols.setBackingFieldSymbol(backingFieldSym, for: propertySym)

        let callerSym = SymbolID(rawValue: 300)
        let propRef = arena.appendExpr(.symbolRef(propertySym), type: types.anyType)

        let callerFn = KIRFunction(
            symbol: callerSym,
            name: interner.intern("caller"),
            params: [],
            returnType: types.unitType,
            body: [
                .constValue(result: propRef, value: .symbolRef(propertySym)),
                .returnUnit,
            ],
            isSuspend: false,
            isInline: false
        )

        let funcID = arena.appendDecl(.function(callerFn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [funcID])], arena: arena)

        let sema = SemaModule(symbols: symbols, types: types, bindings: BindingTable(), diagnostics: DiagnosticEngine())
        _ = try runLowering(module: module, interner: interner, moduleName: "BackedProp", sema: sema)

        guard case let .function(lowered)? = module.arena.decl(funcID) else {
            XCTFail("expected function")
            return
        }

        let hasSymbolRef = lowered.body.contains { instruction in
            if case let .constValue(_, value) = instruction,
               case let .symbolRef(sym) = value,
               sym == propertySym
            {
                return true
            }
            return false
        }
        XCTAssertTrue(hasSymbolRef,
                      "constValue(.symbolRef) for backed property should NOT be rewritten")
    }

    func testGetterOnlyComputedPropertyEmitsNoGlobal() throws {
        let source = """
        package test

        class Widget {
            val computed: String get() = "hello"

            var backed: Int = 0
                get() = field
                set(value) { field = value }
        }
        """
        let ctx = makeContextFromSource(source)
        try runToLowering(ctx)

        guard let module = ctx.kir else {
            XCTFail("KIR module not available")
            return
        }

        let interner = ctx.interner

        var globalSymbols: [SymbolID] = []
        for decl in module.arena.declarations {
            if case let .global(global) = decl {
                globalSymbols.append(global.symbol)
            }
        }

        let computedName = interner.intern("computed")
        let computedSymbols = globalSymbols.filter { sym in
            ctx.sema?.symbols.symbol(sym)?.name == computedName
        }
        XCTAssertTrue(computedSymbols.isEmpty,
                      "Getter-only computed property should NOT have a KIRGlobal, found: \(computedSymbols)")

        let backedName = interner.intern("backed")
        let backedSymbols = globalSymbols.filter { sym in
            ctx.sema?.symbols.symbol(sym)?.name == backedName
        }
        XCTAssertFalse(backedSymbols.isEmpty,
                       "Var property with backing field should have a KIRGlobal")

        let sema = try XCTUnwrap(ctx.sema, "Sema module not available")
        let computedPropertySymbol = try XCTUnwrap(
            sema.symbols.allSymbols().first(where: { symbol in
                symbol.kind == .property && symbol.name == computedName
            }),
            "computed property symbol not found in sema"
        )

        let expectedGetterSymbol = SymbolID(rawValue: -12000 - computedPropertySymbol.id.rawValue)
        let getterSymbols = module.arena.declarations.compactMap { decl -> SymbolID? in
            guard case let .function(kirFunc) = decl,
                  interner.resolve(kirFunc.name) == "get"
            else {
                return nil
            }
            return kirFunc.symbol
        }
        XCTAssertTrue(getterSymbols.contains(expectedGetterSymbol),
                      "Getter accessor symbol for computed property should be emitted. expected=\(expectedGetterSymbol), actual=\(getterSymbols)")
    }

    func testGetterOnlyComputedPropertyOverrideEmitsAccessors() throws {
        let source = """
        package test

        open class Base {
            open val label: String get() = "base"
        }

        class Derived : Base() {
            override val label: String get() = "derived"
        }
        """
        let ctx = makeContextFromSource(source)
        try runToLowering(ctx)

        guard let module = ctx.kir else {
            XCTFail("KIR module not available")
            return
        }

        let interner = ctx.interner

        let getName = interner.intern("get")
        let getterFunctions = module.arena.declarations.compactMap { decl -> KIRFunction? in
            guard case let .function(kirFunc) = decl,
                  kirFunc.name == getName
            else {
                return nil
            }
            return kirFunc
        }

        XCTAssertGreaterThanOrEqual(
            getterFunctions.count, 2,
            "Both base and override should emit getter accessors, found: \(getterFunctions.count)"
        )

        let labelName = interner.intern("label")
        var globalSymbols: [SymbolID] = []
        for decl in module.arena.declarations {
            if case let .global(global) = decl {
                globalSymbols.append(global.symbol)
            }
        }
        let labelGlobals = globalSymbols.filter { sym in
            ctx.sema?.symbols.symbol(sym)?.name == labelName
        }
        XCTAssertTrue(labelGlobals.isEmpty,
                      "Getter-only computed property override should NOT have a KIRGlobal, found: \(labelGlobals)")
    }

    func testCustomGetterSetterPropertyEmitsAccessorsAndBackingField() throws {
        let source = """
        package test

        class Counter {
            var count: Int = 0
                get() = field
                set(value) { field = value }

            val label: String get() = "Count"
        }
        """
        let ctx = makeContextFromSource(source)
        try runToLowering(ctx)

        guard let module = ctx.kir else {
            XCTFail("KIR module not available")
            return
        }

        let interner = ctx.interner

        var globalSymbols: [SymbolID] = []
        for decl in module.arena.declarations {
            if case let .global(global) = decl {
                globalSymbols.append(global.symbol)
            }
        }

        let countName = interner.intern("count")
        let countGlobals = globalSymbols.filter { sym in
            ctx.sema?.symbols.symbol(sym)?.name == countName
        }
        XCTAssertFalse(countGlobals.isEmpty,
                       "Var property with custom getter/setter should have a KIRGlobal")

        let labelName = interner.intern("label")
        let labelGlobals = globalSymbols.filter { sym in
            ctx.sema?.symbols.symbol(sym)?.name == labelName
        }
        XCTAssertTrue(labelGlobals.isEmpty,
                      "Getter-only computed property should NOT have a KIRGlobal, found: \(labelGlobals)")

        let getName = interner.intern("get")
        let getterFunctions = module.arena.declarations.compactMap { decl -> KIRFunction? in
            guard case let .function(kirFunc) = decl,
                  kirFunc.name == getName
            else {
                return nil
            }
            return kirFunc
        }
        XCTAssertGreaterThanOrEqual(
            getterFunctions.count, 1,
            "Should have at least 1 getter accessor (for label)"
        )
    }

    func testTopLevelGetterOnlyComputedPropertyEmitsNoGlobal() throws {
        let source = """
        package test

        var stored: Int = 42
        val computed: Int get() = stored

        fun readComputed(): Int {
            return computed
        }
        """
        let ctx = makeContextFromSource(source)
        try runToLowering(ctx)

        guard let module = ctx.kir else {
            XCTFail("KIR module not available")
            return
        }

        let interner = ctx.interner

        var globalSymbols: [SymbolID] = []
        for decl in module.arena.declarations {
            if case let .global(global) = decl {
                globalSymbols.append(global.symbol)
            }
        }

        // Top-level "computed" should NOT have a KIRGlobal.
        let computedName = interner.intern("computed")
        let computedGlobals = globalSymbols.filter { sym in
            ctx.sema?.symbols.symbol(sym)?.name == computedName
        }
        XCTAssertTrue(
            computedGlobals.isEmpty,
            "Top-level getter-only computed property should NOT have a KIRGlobal"
        )

        // Top-level "stored" SHOULD have a KIRGlobal.
        let storedName = interner.intern("stored")
        let storedGlobals = globalSymbols.filter { sym in
            ctx.sema?.symbols.symbol(sym)?.name == storedName
        }
        XCTAssertFalse(storedGlobals.isEmpty,
                       "Top-level stored property should have a KIRGlobal")

        // Verify that readComputed() was lowered so that the read of
        // "computed" became a getter accessor call (not loadGlobal).
        let sema = try XCTUnwrap(ctx.sema)
        let computedPropSym = try XCTUnwrap(
            sema.symbols.allSymbols().first(where: {
                $0.kind == .property && $0.name == computedName
            }),
            "computed property symbol not found"
        )
        let getterSym = SyntheticSymbolScheme
            .propertyGetterAccessorSymbol(for: computedPropSym.id)

        // Find readComputed and check its body for a getter call.
        let readName = interner.intern("readComputed")
        let readerFn = module.arena.declarations.compactMap { decl -> KIRFunction? in
            guard case let .function(kirFunc) = decl,
                  kirFunc.name == readName else { return nil }
            return kirFunc
        }.first
        let reader = try XCTUnwrap(readerFn, "readComputed not found")

        let hasGetterCall = reader.body.contains { inst in
            if case let .call(symbol, _, _, _, _, _, _) = inst {
                return symbol == getterSym
            }
            return false
        }
        XCTAssertTrue(
            hasGetterCall,
            "Read of top-level computed property should lower to getter call"
        )

        // Verify no loadGlobal remains for the computed symbol.
        let hasLoadGlobal = reader.body.contains { inst in
            if case let .loadGlobal(_, sym) = inst {
                return sym == computedPropSym.id
            }
            return false
        }
        XCTAssertFalse(
            hasLoadGlobal,
            "loadGlobal for computed property should be rewritten"
        )
    }
}
