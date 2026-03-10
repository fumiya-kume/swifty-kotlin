@testable import CompilerCore
import Foundation
import XCTest

extension LoweringPassRegressionTests {
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

        let ctx = CompilationContext(
            options: CompilerOptions(
                moduleName: "PropNoSym", inputs: [],
                outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path,
                emit: .kirDump, target: defaultTargetTriple()
            ),
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: interner
        )
        ctx.kir = module
        try LoweringPhase().run(ctx)

        guard case let .function(lowered)? = module.arena.decl(fnID) else {
            XCTFail("expected function")
            return
        }

        // The call should remain unchanged (no symbol to derive accessor from).
        let callees = extractCallees(from: lowered.body, interner: interner)
        XCTAssertTrue(callees.contains("get"))
        XCTAssertFalse(callees.contains("kk_property_access"))
    }

    /// Verify that backing field copy is rewritten to a direct setter call.
    func testPropertyLoweringRewritesBackingFieldCopyToDirectSetterCall() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let symbols = SymbolTable()

        // Create a property symbol and its backing field symbol.
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
        let ctx = CompilationContext(
            options: CompilerOptions(
                moduleName: "BFSetter", inputs: [],
                outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path,
                emit: .kirDump, target: defaultTargetTriple()
            ),
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: interner
        )
        ctx.kir = module
        ctx.sema = sema
        try LoweringPhase().run(ctx)

        guard case let .function(lowered)? = module.arena.decl(fnID) else {
            XCTFail("expected function")
            return
        }

        // The copy should be rewritten to a set call with the synthetic setter
        // symbol derived from the property (not the backing field).
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

        // Verify no copy instruction remains for the backing field.
        let hasCopy = lowered.body.contains { instruction in
            if case .copy = instruction { return true }
            return false
        }
        XCTAssertFalse(hasCopy, "Backing field copy should have been rewritten to a setter call")
    }

    /// Verify that a constValue(.symbolRef(propSym)) for a getter-only computed
    /// property (no backing field) is rewritten to a getter call by PropertyLoweringPass.
    func testPropertyLoweringRewritesComputedPropertySymbolRefToGetterCall() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let symbols = SymbolTable()

        // Define a property symbol with NO backing field (getter-only computed).
        let propertySym = symbols.define(
            kind: .property,
            name: interner.intern("computed"),
            fqName: [interner.intern("Foo"), interner.intern("computed")],
            declSite: nil,
            visibility: .public,
            flags: []
        )
        // Deliberately do NOT set a backing field symbol for this property.

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
        let ctx = CompilationContext(
            options: CompilerOptions(
                moduleName: "ComputedProp", inputs: [],
                outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path,
                emit: .kirDump, target: defaultTargetTriple()
            ),
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: interner
        )
        ctx.kir = module
        ctx.sema = sema
        try LoweringPhase().run(ctx)

        guard case let .function(lowered)? = module.arena.decl(fnID) else {
            XCTFail("expected function")
            return
        }

        // The constValue(.symbolRef) should be rewritten to a getter call
        // using the synthetic getter symbol (-12_000 - propSym).
        let expectedGetterSymbol = SymbolID(rawValue: -12000 - propertySym.rawValue)
        let callSymbols = lowered.body.compactMap { instruction -> SymbolID? in
            guard case let .call(sym, _, _, _, _, _, _) = instruction else { return nil }
            return sym
        }
        XCTAssertTrue(callSymbols.contains(expectedGetterSymbol),
                      "Expected getter call for computed property, got: \(callSymbols)")

        // No constValue(.symbolRef) should remain for the computed property.
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

    /// Verify that a `var` property with a backing field is NOT rewritten
    /// (its constValue(.symbolRef) is preserved because it has storage).
    func testPropertyLoweringPreservesBackedPropertySymbolRef() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let symbols = SymbolTable()

        // Define a property with a backing field (var with custom getter/setter).
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

        let fnID = arena.appendDecl(.function(callerFn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [fnID])], arena: arena)

        let sema = SemaModule(symbols: symbols, types: types, bindings: BindingTable(), diagnostics: DiagnosticEngine())
        let ctx = CompilationContext(
            options: CompilerOptions(
                moduleName: "BackedProp", inputs: [],
                outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path,
                emit: .kirDump, target: defaultTargetTriple()
            ),
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: interner
        )
        ctx.kir = module
        ctx.sema = sema
        try LoweringPhase().run(ctx)

        guard case let .function(lowered)? = module.arena.decl(fnID) else {
            XCTFail("expected function")
            return
        }

        // The constValue(.symbolRef) for a backed property should be preserved.
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

    /// Integration test: compile `val computed: String get() = "hello"` through
    /// the full pipeline and verify no KIRGlobal is emitted for the computed property.
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

        // Collect all global symbols.
        var globalSymbols: [SymbolID] = []
        for decl in module.arena.declarations {
            if case let .global(global) = decl {
                globalSymbols.append(global.symbol)
            }
        }

        // The "computed" property should NOT have a KIRGlobal.
        let computedName = interner.intern("computed")
        let computedSymbols = globalSymbols.filter { sym in
            ctx.sema?.symbols.symbol(sym)?.name == computedName
        }
        XCTAssertTrue(computedSymbols.isEmpty,
                      "Getter-only computed property should NOT have a KIRGlobal, found: \(computedSymbols)")

        // The "backed" property SHOULD have a KIRGlobal (it has storage).
        let backedName = interner.intern("backed")
        let backedSymbols = globalSymbols.filter { sym in
            ctx.sema?.symbols.symbol(sym)?.name == backedName
        }
        XCTAssertFalse(backedSymbols.isEmpty,
                       "Var property with backing field should have a KIRGlobal")

        // Verify that accessor functions were generated for the computed property.
        var accessorCallees: [String] = []
        for decl in module.arena.declarations {
            if case let .function(fn) = decl {
                let name = interner.resolve(fn.name)
                if name == "get" || name == "set" {
                    accessorCallees.append(name)
                }
            }
        }
        XCTAssertTrue(accessorCallees.contains("get"),
                      "Getter accessor function should be emitted for computed property")
    }
}
