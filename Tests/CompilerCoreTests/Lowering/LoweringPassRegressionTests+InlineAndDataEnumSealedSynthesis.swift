@testable import CompilerCore
import Foundation
import XCTest

extension LoweringPassRegressionTests {
    func testInlineLoweringExpandsInlineBodyAndRewritesResultUse() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()

        let callerSym = SymbolID(rawValue: 300)
        let inlineSym = SymbolID(rawValue: 301)
        let inlineParamSym = SymbolID(rawValue: 302)

        let inlineArg = arena.appendExpr(.temporary(0))
        let inlineOne = arena.appendExpr(.temporary(1))
        let inlineSum = arena.appendExpr(.temporary(2))
        let callerArg = arena.appendExpr(.temporary(3))
        let callerResult = arena.appendExpr(.temporary(4))

        let inlineFn = KIRFunction(
            symbol: inlineSym,
            name: interner.intern("plusOne"),
            params: [KIRParameter(symbol: inlineParamSym, type: types.make(.primitive(.int, .nonNull)))],
            returnType: types.make(.primitive(.int, .nonNull)),
            body: [
                .constValue(result: inlineArg, value: .symbolRef(inlineParamSym)),
                .constValue(result: inlineOne, value: .intLiteral(1)),
                .call(symbol: nil, callee: interner.intern("kk_op_add"), arguments: [inlineArg, inlineOne], result: inlineSum, canThrow: false, thrownResult: nil),
                .returnValue(inlineSum),
            ],
            isSuspend: false,
            isInline: true
        )
        let callerFn = KIRFunction(
            symbol: callerSym,
            name: interner.intern("main"),
            params: [],
            returnType: types.make(.primitive(.int, .nonNull)),
            body: [
                .constValue(result: callerArg, value: .intLiteral(41)),
                .call(symbol: inlineSym, callee: interner.intern("plusOne"), arguments: [callerArg], result: callerResult, canThrow: false, thrownResult: nil),
                .returnValue(callerResult),
            ],
            isSuspend: false,
            isInline: false
        )

        let callerID = arena.appendDecl(.function(callerFn))
        _ = arena.appendDecl(.function(inlineFn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [callerID])], arena: arena)

        let ctx = CompilationContext(
            options: CompilerOptions(
                moduleName: "InlineLowering",
                inputs: [],
                outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path,
                emit: .kirDump,
                target: defaultTargetTriple()
            ),
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: interner
        )
        ctx.kir = module
        try LoweringPhase().run(ctx)

        guard case let .function(loweredCaller)? = module.arena.decl(callerID) else {
            XCTFail("expected lowered caller function")
            return
        }

        let calleeNames = extractCallees(from: loweredCaller.body, interner: interner)
        XCTAssertFalse(calleeNames.contains("plusOne"))
        XCTAssertTrue(calleeNames.contains("kk_op_add"))

        let returnValues = loweredCaller.body.compactMap { instruction -> KIRExprID? in
            guard case let .returnValue(expr) = instruction else { return nil }
            return expr
        }
        XCTAssertEqual(returnValues.count, 1)
        XCTAssertNotEqual(returnValues.first, callerResult)
    }

    func testDataEnumSealedSynthesisAddsSyntheticHelpers() throws {
        let interner = StringInterner()
        let diagnostics = DiagnosticEngine()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let bindings = BindingTable()
        let sema = SemaModule(symbols: symbols, types: types, bindings: bindings, diagnostics: diagnostics)

        let packageName = interner.intern("demo")
        let packagePath = [packageName]

        let colorName = interner.intern("Color")
        let colorSymbol = symbols.define(
            kind: .enumClass,
            name: colorName,
            fqName: packagePath + [colorName],
            declSite: nil,
            visibility: .public
        )
        _ = symbols.define(
            kind: .field,
            name: interner.intern("RED"),
            fqName: packagePath + [colorName, interner.intern("RED")],
            declSite: nil,
            visibility: .public
        )
        _ = symbols.define(
            kind: .field,
            name: interner.intern("BLUE"),
            fqName: packagePath + [colorName, interner.intern("BLUE")],
            declSite: nil,
            visibility: .public
        )

        let baseName = interner.intern("Base")
        let baseSymbol = symbols.define(
            kind: .class,
            name: baseName,
            fqName: packagePath + [baseName],
            declSite: nil,
            visibility: .public,
            flags: [.sealedType]
        )
        let childName = interner.intern("Child")
        let childSymbol = symbols.define(
            kind: .class,
            name: childName,
            fqName: packagePath + [childName],
            declSite: nil,
            visibility: .public
        )
        symbols.setDirectSupertypes([baseSymbol], for: childSymbol)

        let pointName = interner.intern("Point")
        let pointSymbol = symbols.define(
            kind: .class,
            name: pointName,
            fqName: packagePath + [pointName],
            declSite: nil,
            visibility: .public,
            flags: [.dataType]
        )

        let arena = KIRArena()
        let colorDecl = arena.appendDecl(.nominalType(KIRNominalType(symbol: colorSymbol)))
        let baseDecl = arena.appendDecl(.nominalType(KIRNominalType(symbol: baseSymbol)))
        let pointDecl = arena.appendDecl(.nominalType(KIRNominalType(symbol: pointSymbol)))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [colorDecl, baseDecl, pointDecl])], arena: arena)

        let ctx = CompilationContext(
            options: CompilerOptions(
                moduleName: "Synthesis",
                inputs: [],
                outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path,
                emit: .kirDump,
                target: defaultTargetTriple()
            ),
            sourceManager: SourceManager(),
            diagnostics: diagnostics,
            interner: interner
        )
        ctx.sema = sema
        ctx.kir = module

        try LoweringPhase().run(ctx)

        let functionNames = module.arena.declarations.compactMap { decl -> String? in
            guard case let .function(function) = decl else {
                return nil
            }
            return interner.resolve(function.name)
        }
        XCTAssertTrue(functionNames.contains("Color$enumValuesCount"))
        XCTAssertTrue(functionNames.contains("Base$sealedSubtypeCount"))
        XCTAssertTrue(functionNames.contains("Point$copy"))

        let copyFunction = try findKIRFunction(named: "Point$copy", in: module, interner: interner)
        XCTAssertEqual(copyFunction.params.count, 1)
    }

    func testDataEnumSealedSynthesisAddsOrdinalNameValuesValueOf() throws {
        let interner = StringInterner()
        let diagnostics = DiagnosticEngine()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let bindings = BindingTable()
        let sema = SemaModule(symbols: symbols, types: types, bindings: bindings, diagnostics: diagnostics)

        let packageName = interner.intern("demo")
        let packagePath = [packageName]

        let colorName = interner.intern("Color")
        let colorSymbol = symbols.define(
            kind: .enumClass,
            name: colorName,
            fqName: packagePath + [colorName],
            declSite: nil,
            visibility: .public
        )
        _ = symbols.define(
            kind: .field,
            name: interner.intern("RED"),
            fqName: packagePath + [colorName, interner.intern("RED")],
            declSite: nil,
            visibility: .public
        )
        _ = symbols.define(
            kind: .field,
            name: interner.intern("GREEN"),
            fqName: packagePath + [colorName, interner.intern("GREEN")],
            declSite: nil,
            visibility: .public
        )
        _ = symbols.define(
            kind: .field,
            name: interner.intern("BLUE"),
            fqName: packagePath + [colorName, interner.intern("BLUE")],
            declSite: nil,
            visibility: .public
        )

        let arena = KIRArena()
        let colorDecl = arena.appendDecl(.nominalType(KIRNominalType(symbol: colorSymbol)))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [colorDecl])], arena: arena)

        let ctx = CompilationContext(
            options: CompilerOptions(
                moduleName: "EnumSynthesis",
                inputs: [],
                outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path,
                emit: .kirDump,
                target: defaultTargetTriple()
            ),
            sourceManager: SourceManager(),
            diagnostics: diagnostics,
            interner: interner
        )
        ctx.sema = sema
        ctx.kir = module

        try LoweringPhase().run(ctx)

        let functionNames = module.arena.declarations.compactMap { decl -> String? in
            guard case let .function(function) = decl else {
                return nil
            }
            return interner.resolve(function.name)
        }

        // Verify count helper still exists
        XCTAssertTrue(functionNames.contains("Color$enumValuesCount"), "Missing Color$enumValuesCount, got: \(functionNames)")

        // Verify per-entry ordinal helpers
        XCTAssertTrue(functionNames.contains("RED$enumOrdinal"), "Missing RED$enumOrdinal, got: \(functionNames)")
        XCTAssertTrue(functionNames.contains("GREEN$enumOrdinal"), "Missing GREEN$enumOrdinal, got: \(functionNames)")
        XCTAssertTrue(functionNames.contains("BLUE$enumOrdinal"), "Missing BLUE$enumOrdinal, got: \(functionNames)")

        // Verify per-entry name helpers
        XCTAssertTrue(functionNames.contains("RED$enumName"), "Missing RED$enumName, got: \(functionNames)")
        XCTAssertTrue(functionNames.contains("GREEN$enumName"), "Missing GREEN$enumName, got: \(functionNames)")
        XCTAssertTrue(functionNames.contains("BLUE$enumName"), "Missing BLUE$enumName, got: \(functionNames)")

        // Verify values() and valueOf() companion functions
        XCTAssertTrue(functionNames.contains("values"), "Missing values, got: \(functionNames)")
        XCTAssertTrue(functionNames.contains("valueOf"), "Missing valueOf, got: \(functionNames)")

        // Verify ordinal values are correct (0-based)
        let redOrdinal = try findKIRFunction(named: "RED$enumOrdinal", in: module, interner: interner)
        let greenOrdinal = try findKIRFunction(named: "GREEN$enumOrdinal", in: module, interner: interner)
        let blueOrdinal = try findKIRFunction(named: "BLUE$enumOrdinal", in: module, interner: interner)

        // Each ordinal function should have a constValue instruction with the correct ordinal
        let redConst = redOrdinal.body.compactMap { inst -> Int64? in
            guard case let .constValue(_, value) = inst, case let .intLiteral(v) = value else { return nil }
            return v
        }
        XCTAssertTrue(redConst.contains(0), "RED ordinal should be 0, got consts: \(redConst)")

        let greenConst = greenOrdinal.body.compactMap { inst -> Int64? in
            guard case let .constValue(_, value) = inst, case let .intLiteral(v) = value else { return nil }
            return v
        }
        XCTAssertTrue(greenConst.contains(1), "GREEN ordinal should be 1, got consts: \(greenConst)")

        let blueConst = blueOrdinal.body.compactMap { inst -> Int64? in
            guard case let .constValue(_, value) = inst, case let .intLiteral(v) = value else { return nil }
            return v
        }
        XCTAssertTrue(blueConst.contains(2), "BLUE ordinal should be 2, got consts: \(blueConst)")

        // Verify name functions return correct string literals
        let redName = try findKIRFunction(named: "RED$enumName", in: module, interner: interner)
        let redNameConsts = redName.body.compactMap { inst -> InternedString? in
            guard case let .constValue(_, value) = inst, case let .stringLiteral(s) = value else { return nil }
            return s
        }
        XCTAssertTrue(redNameConsts.contains(interner.intern("RED")), "RED name function should return \"RED\"")

        // Verify valueOf has receiver + name parameter (companion member)
        let valueOfFn = try findKIRFunction(named: "valueOf", in: module, interner: interner)
        XCTAssertEqual(valueOfFn.params.count, 2, "valueOf should have receiver + 1 name parameter")

        // Verify valueOf body contains string comparison calls
        let valueOfCallees = extractCallees(from: valueOfFn.body, interner: interner)
        XCTAssertTrue(valueOfCallees.contains("kk_string_equals"), "valueOf should call kk_string_equals")
        XCTAssertTrue(valueOfCallees.contains("kk_enum_valueOf_throw"), "valueOf should call kk_enum_valueOf_throw for no-match case")
    }

    func testEnumStaticInitSynthesizesGlobalsAndInitFunction() throws {
        let interner = StringInterner()
        let diagnostics = DiagnosticEngine()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let bindings = BindingTable()
        let sema = SemaModule(symbols: symbols, types: types, bindings: bindings, diagnostics: diagnostics)

        let packageName = interner.intern("demo")
        let packagePath = [packageName]

        let colorName = interner.intern("Color")
        let colorSymbol = symbols.define(
            kind: .enumClass,
            name: colorName,
            fqName: packagePath + [colorName],
            declSite: nil,
            visibility: .public
        )
        let redSymbol = symbols.define(
            kind: .field,
            name: interner.intern("RED"),
            fqName: packagePath + [colorName, interner.intern("RED")],
            declSite: nil,
            visibility: .public
        )
        let greenSymbol = symbols.define(
            kind: .field,
            name: interner.intern("GREEN"),
            fqName: packagePath + [colorName, interner.intern("GREEN")],
            declSite: nil,
            visibility: .public
        )
        let blueSymbol = symbols.define(
            kind: .field,
            name: interner.intern("BLUE"),
            fqName: packagePath + [colorName, interner.intern("BLUE")],
            declSite: nil,
            visibility: .public
        )

        let arena = KIRArena()
        let colorDecl = arena.appendDecl(.nominalType(KIRNominalType(symbol: colorSymbol)))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [colorDecl])], arena: arena)

        let ctx = CompilationContext(
            options: CompilerOptions(
                moduleName: "EnumStaticInit",
                inputs: [],
                outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path,
                emit: .kirDump,
                target: defaultTargetTriple()
            ),
            sourceManager: SourceManager(),
            diagnostics: diagnostics,
            interner: interner
        )
        ctx.sema = sema
        ctx.kir = module

        try LoweringPhase().run(ctx)

        // Verify __enum_static_init_Color function was synthesized
        let functionNames = module.arena.declarations.compactMap { decl -> String? in
            guard case let .function(function) = decl else {
                return nil
            }
            return interner.resolve(function.name)
        }
        XCTAssertTrue(
            functionNames.contains("__enum_static_init_Color"),
            "Missing __enum_static_init_Color, got: \(functionNames)"
        )

        // Verify KIRGlobal declarations exist for each entry
        let globalSymbols = Set(module.arena.declarations.compactMap { decl -> SymbolID? in
            guard case let .global(global) = decl else {
                return nil
            }
            return global.symbol
        })
        XCTAssertTrue(globalSymbols.contains(redSymbol), "Missing KIRGlobal for RED")
        XCTAssertTrue(globalSymbols.contains(greenSymbol), "Missing KIRGlobal for GREEN")
        XCTAssertTrue(globalSymbols.contains(blueSymbol), "Missing KIRGlobal for BLUE")

        // Verify the static init body stores ordinals (0, 1, 2) into the expected entry globals.
        let staticInitFn = try findKIRFunction(named: "__enum_static_init_Color", in: module, interner: interner)

        var ordinalStores: [(ordinal: Int64, target: SymbolID)] = []

        for instruction in staticInitFn.body {
            switch instruction {
            case let .copy(from, to):
                guard case let .intLiteral(ordinal)? = module.arena.expr(from),
                      case let .symbolRef(target)? = module.arena.expr(to)
                else {
                    XCTFail("Static init copy should connect an ordinal literal to an entry global")
                    continue
                }
                ordinalStores.append((ordinal, target))
            case let .call(_, _, arguments, result, _, _, _):
                guard arguments.count == 1,
                      let result,
                      case let .intLiteral(ordinal)? = module.arena.expr(arguments[0]),
                      case let .symbolRef(target)? = module.arena.expr(result)
                else {
                    continue
                }
                ordinalStores.append((ordinal, target))
            default:
                break
            }
        }
        XCTAssertEqual(ordinalStores.count, 3, "Static init should emit one ordinal store per enum entry")
        XCTAssertEqual(ordinalStores.map(\.ordinal), [0, 1, 2], "Static init should store sequential ordinals")
        XCTAssertEqual(
            ordinalStores.map(\.target),
            [redSymbol, greenSymbol, blueSymbol],
            "Static init should store ordinals into RED, GREEN, BLUE globals in order"
        )

        // Verify the function ends with returnUnit.
        guard let lastInstruction = staticInitFn.body.last else {
            return XCTFail("Static init should not be empty")
        }
        guard case .returnUnit = lastInstruction else {
            return XCTFail("Static init should end with returnUnit, got \(lastInstruction)")
        }
    }

    func testEnumStaticInitSkipsWhenNoEntries() throws {
        let interner = StringInterner()
        let diagnostics = DiagnosticEngine()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let bindings = BindingTable()
        let sema = SemaModule(symbols: symbols, types: types, bindings: bindings, diagnostics: diagnostics)

        let packageName = interner.intern("demo")
        let packagePath = [packageName]

        // Enum with no entries
        let emptyName = interner.intern("Empty")
        let emptySymbol = symbols.define(
            kind: .enumClass,
            name: emptyName,
            fqName: packagePath + [emptyName],
            declSite: nil,
            visibility: .public
        )

        let arena = KIRArena()
        let emptyDecl = arena.appendDecl(.nominalType(KIRNominalType(symbol: emptySymbol)))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [emptyDecl])], arena: arena)

        let ctx = CompilationContext(
            options: CompilerOptions(
                moduleName: "EnumStaticInitEmpty",
                inputs: [],
                outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path,
                emit: .kirDump,
                target: defaultTargetTriple()
            ),
            sourceManager: SourceManager(),
            diagnostics: diagnostics,
            interner: interner
        )
        ctx.sema = sema
        ctx.kir = module

        try LoweringPhase().run(ctx)

        // Verify no __enum_static_init function was generated for empty enum
        let functionNames = module.arena.declarations.compactMap { decl -> String? in
            guard case let .function(function) = decl else {
                return nil
            }
            return interner.resolve(function.name)
        }
        XCTAssertFalse(
            functionNames.contains("__enum_static_init_Empty"),
            "Should not synthesize static init for empty enum"
        )
    }

    func testEnumStaticInitDoesNotDuplicateExistingGlobals() throws {
        let interner = StringInterner()
        let diagnostics = DiagnosticEngine()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let bindings = BindingTable()
        let sema = SemaModule(symbols: symbols, types: types, bindings: bindings, diagnostics: diagnostics)

        let packageName = interner.intern("demo")
        let packagePath = [packageName]

        let statusName = interner.intern("Status")
        let statusSymbol = symbols.define(
            kind: .enumClass,
            name: statusName,
            fqName: packagePath + [statusName],
            declSite: nil,
            visibility: .public
        )
        let okSymbol = symbols.define(
            kind: .field,
            name: interner.intern("OK"),
            fqName: packagePath + [statusName, interner.intern("OK")],
            declSite: nil,
            visibility: .public
        )

        let arena = KIRArena()
        // Pre-create the KIRGlobal as BuildKIR would for enumEntryDecl
        _ = arena.appendDecl(.global(KIRGlobal(symbol: okSymbol, type: sema.types.anyType)))
        let statusDecl = arena.appendDecl(.nominalType(KIRNominalType(symbol: statusSymbol)))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [statusDecl])], arena: arena)

        let ctx = CompilationContext(
            options: CompilerOptions(
                moduleName: "EnumStaticInitNoDup",
                inputs: [],
                outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path,
                emit: .kirDump,
                target: defaultTargetTriple()
            ),
            sourceManager: SourceManager(),
            diagnostics: diagnostics,
            interner: interner
        )
        ctx.sema = sema
        ctx.kir = module

        try LoweringPhase().run(ctx)

        // Count how many KIRGlobal declarations reference the OK symbol
        let okGlobalCount = module.arena.declarations.filter { decl in
            guard case let .global(global) = decl else { return false }
            return global.symbol == okSymbol
        }.count
        XCTAssertEqual(okGlobalCount, 1, "Should not duplicate KIRGlobal for pre-existing entry")
    }
}
