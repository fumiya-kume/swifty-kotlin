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
        _ = symbols.define(
            kind: .function,
            name: interner.intern("copy"),
            fqName: packagePath + [pointName, interner.intern("copy")],
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        _ = symbols.define(
            kind: .function,
            name: interner.intern("copy"),
            fqName: packagePath + [pointName, interner.intern("copy")],
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        _ = symbols.define(
            kind: .function,
            name: interner.intern("copy"),
            fqName: packagePath + [pointName, interner.intern("copy")],
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
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
        XCTAssertTrue(functionNames.contains("copy"))

        let copyFunction = try findKIRFunction(named: "copy", in: module, interner: interner)
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
        XCTAssertTrue(valueOfCallees.contains("kk_string_concat"), "valueOf should call kk_string_concat to build 'ClassName.value' for error message")
        XCTAssertTrue(valueOfCallees.contains("kk_enum_valueOf_throw"), "valueOf should call kk_enum_valueOf_throw for no-match case")

        // Verify valueOf body contains the class name prefix string "Color."
        let valueOfStringConsts = valueOfFn.body.compactMap { inst -> InternedString? in
            guard case let .constValue(_, value) = inst, case let .stringLiteral(s) = value else { return nil }
            return s
        }
        XCTAssertTrue(valueOfStringConsts.contains(interner.intern("Color.")),
                       "valueOf should contain 'Color.' prefix for Kotlin-compatible error message")
    }

    // MARK: - DATA-003: hashCode() synthesis for data classes

    func testDataClassHashCodeSynthesisGeneratesHashCodeFunction() throws {
        let interner = StringInterner()
        let diagnostics = DiagnosticEngine()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let bindings = BindingTable()
        let sema = SemaModule(symbols: symbols, types: types, bindings: bindings, diagnostics: diagnostics)

        let packageName = interner.intern("demo")
        let packagePath = [packageName]

        // Define a data class Point with two properties: x and y
        let pointName = interner.intern("Point")
        let pointFQName = packagePath + [pointName]
        let pointSymbol = symbols.define(
            kind: .class,
            name: pointName,
            fqName: pointFQName,
            declSite: nil,
            visibility: .public,
            flags: [.dataType]
        )

        let intType = types.make(.primitive(.int, .nonNull))
        let pointType = types.make(.classType(ClassType(
            classSymbol: pointSymbol,
            args: [],
            nullability: .nonNull
        )))

        // Register constructor properties x and y
        let xName = interner.intern("x")
        let xSymbol = symbols.define(
            kind: .property,
            name: xName,
            fqName: pointFQName + [xName],
            declSite: nil,
            visibility: .public
        )
        symbols.setParentSymbol(pointSymbol, for: xSymbol)
        symbols.setPropertyType(intType, for: xSymbol)

        let yName = interner.intern("y")
        let ySymbol = symbols.define(
            kind: .property,
            name: yName,
            fqName: pointFQName + [yName],
            declSite: nil,
            visibility: .public
        )
        symbols.setParentSymbol(pointSymbol, for: ySymbol)
        symbols.setPropertyType(intType, for: ySymbol)

        // Register synthetic hashCode symbol (as Sema would)
        let hashCodeName = interner.intern("hashCode")
        let hashCodeFQName = pointFQName + [hashCodeName]
        let hashCodeSymbol = symbols.define(
            kind: .function,
            name: hashCodeName,
            fqName: hashCodeFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(pointSymbol, for: hashCodeSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: pointType,
                parameterTypes: [],
                returnType: intType,
                isSuspend: false,
                valueParameterSymbols: [],
                valueParameterHasDefaultValues: [],
                valueParameterIsVararg: [],
                typeParameterSymbols: []
            ),
            for: hashCodeSymbol
        )

        let arena = KIRArena()
        let pointDecl = arena.appendDecl(.nominalType(KIRNominalType(symbol: pointSymbol)))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [pointDecl])], arena: arena)

        let ctx = CompilationContext(
            options: CompilerOptions(
                moduleName: "DataHashCode",
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
        XCTAssertTrue(functionNames.contains("hashCode"), "Missing hashCode, got: \(functionNames)")

        // Verify hashCode function has receiver parameter
        let hashCodeFn = try findKIRFunction(named: "hashCode", in: module, interner: interner)
        XCTAssertEqual(hashCodeFn.params.count, 1, "hashCode should have 1 receiver parameter")

        // Verify body calls kk_any_hashCode for each property
        let callees = extractCallees(from: hashCodeFn.body, interner: interner)
        XCTAssertTrue(callees.contains("kk_any_hashCode"), "hashCode should call kk_any_hashCode")

        // With 2 properties, should use 31 * result + hash pattern
        XCTAssertTrue(callees.contains("kk_op_mul"), "hashCode with 2+ properties should call kk_op_mul")
        XCTAssertTrue(callees.contains("kk_op_add"), "hashCode with 2+ properties should call kk_op_add")

        // Verify the constant 31 is used in the body
        let intConsts = hashCodeFn.body.compactMap { inst -> Int64? in
            guard case let .constValue(_, value) = inst, case let .intLiteral(v) = value else { return nil }
            return v
        }
        XCTAssertTrue(intConsts.contains(31), "hashCode should use constant 31 for hash combining")
    }

    func testDataClassHashCodeWithNoPropertiesReturnsZero() throws {
        let interner = StringInterner()
        let diagnostics = DiagnosticEngine()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let bindings = BindingTable()
        let sema = SemaModule(symbols: symbols, types: types, bindings: bindings, diagnostics: diagnostics)

        let packageName = interner.intern("demo")
        let packagePath = [packageName]

        // Define a data class Empty with no properties
        let emptyName = interner.intern("Empty")
        let emptyFQName = packagePath + [emptyName]
        let emptySymbol = symbols.define(
            kind: .class,
            name: emptyName,
            fqName: emptyFQName,
            declSite: nil,
            visibility: .public,
            flags: [.dataType]
        )

        let intType = types.make(.primitive(.int, .nonNull))
        let emptyType = types.make(.classType(ClassType(
            classSymbol: emptySymbol,
            args: [],
            nullability: .nonNull
        )))

        // Register synthetic hashCode symbol
        let hashCodeName = interner.intern("hashCode")
        let hashCodeFQName = emptyFQName + [hashCodeName]
        let hashCodeSymbol = symbols.define(
            kind: .function,
            name: hashCodeName,
            fqName: hashCodeFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(emptySymbol, for: hashCodeSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: emptyType,
                parameterTypes: [],
                returnType: intType,
                isSuspend: false,
                valueParameterSymbols: [],
                valueParameterHasDefaultValues: [],
                valueParameterIsVararg: [],
                typeParameterSymbols: []
            ),
            for: hashCodeSymbol
        )

        let arena = KIRArena()
        let emptyDecl = arena.appendDecl(.nominalType(KIRNominalType(symbol: emptySymbol)))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [emptyDecl])], arena: arena)

        let ctx = CompilationContext(
            options: CompilerOptions(
                moduleName: "DataHashCodeEmpty",
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

        let hashCodeFn = try findKIRFunction(named: "hashCode", in: module, interner: interner)

        // With no properties, should return 0 directly
        let intConsts = hashCodeFn.body.compactMap { inst -> Int64? in
            guard case let .constValue(_, value) = inst, case let .intLiteral(v) = value else { return nil }
            return v
        }
        XCTAssertTrue(intConsts.contains(0), "hashCode with no properties should return 0")

        // Should NOT use mul/add since there's nothing to combine
        let callees = extractCallees(from: hashCodeFn.body, interner: interner)
        XCTAssertFalse(callees.contains("kk_op_mul"), "hashCode with no properties should not call kk_op_mul")
        XCTAssertFalse(callees.contains("kk_op_add"), "hashCode with no properties should not call kk_op_add")
    }

    func testDataClassHashCodeSinglePropertyNoMulAdd() throws {
        let interner = StringInterner()
        let diagnostics = DiagnosticEngine()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let bindings = BindingTable()
        let sema = SemaModule(symbols: symbols, types: types, bindings: bindings, diagnostics: diagnostics)

        let packageName = interner.intern("demo")
        let packagePath = [packageName]

        let wrapperName = interner.intern("Wrapper")
        let wrapperFQName = packagePath + [wrapperName]
        let wrapperSymbol = symbols.define(
            kind: .class,
            name: wrapperName,
            fqName: wrapperFQName,
            declSite: nil,
            visibility: .public,
            flags: [.dataType]
        )

        let intType = types.make(.primitive(.int, .nonNull))
        let wrapperType = types.make(.classType(ClassType(
            classSymbol: wrapperSymbol,
            args: [],
            nullability: .nonNull
        )))

        // Register a single constructor property
        let valueName = interner.intern("value")
        let valueSymbol = symbols.define(
            kind: .property,
            name: valueName,
            fqName: wrapperFQName + [valueName],
            declSite: nil,
            visibility: .public
        )
        symbols.setParentSymbol(wrapperSymbol, for: valueSymbol)
        symbols.setPropertyType(intType, for: valueSymbol)

        // Register synthetic hashCode symbol
        let hashCodeName = interner.intern("hashCode")
        let hashCodeFQName = wrapperFQName + [hashCodeName]
        let hashCodeSymbol = symbols.define(
            kind: .function,
            name: hashCodeName,
            fqName: hashCodeFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(wrapperSymbol, for: hashCodeSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: wrapperType,
                parameterTypes: [],
                returnType: intType,
                isSuspend: false,
                valueParameterSymbols: [],
                valueParameterHasDefaultValues: [],
                valueParameterIsVararg: [],
                typeParameterSymbols: []
            ),
            for: hashCodeSymbol
        )

        let arena = KIRArena()
        let wrapperDecl = arena.appendDecl(.nominalType(KIRNominalType(symbol: wrapperSymbol)))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [wrapperDecl])], arena: arena)

        let ctx = CompilationContext(
            options: CompilerOptions(
                moduleName: "DataHashCodeSingle",
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

        let hashCodeFn = try findKIRFunction(named: "hashCode", in: module, interner: interner)
        let callees = extractCallees(from: hashCodeFn.body, interner: interner)

        // Single property: result = kk_any_hashCode(receiver, offset), no mul/add needed
        XCTAssertTrue(callees.contains("kk_any_hashCode"), "hashCode should call kk_any_hashCode")
        XCTAssertFalse(callees.contains("kk_op_mul"), "hashCode with single property should not call kk_op_mul")
        XCTAssertFalse(callees.contains("kk_op_add"), "hashCode with single property should not call kk_op_add")
    }

    // MARK: - DATA-004: Data class toString/equals for multi-property classes

    func testDataClassToStringAndEqualsAreSynthesized() throws {
        let interner = StringInterner()
        let diagnostics = DiagnosticEngine()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let bindings = BindingTable()
        let sema = SemaModule(symbols: symbols, types: types, bindings: bindings, diagnostics: diagnostics)

        let packageName = interner.intern("demo")
        let packagePath = [packageName]

        // Define data class Point with primary-constructor properties x and y.
        let pointName = interner.intern("Point")
        let pointFQName = packagePath + [pointName]
        let pointSymbol = symbols.define(
            kind: .class,
            name: pointName,
            fqName: pointFQName,
            declSite: nil,
            visibility: .public,
            flags: [.dataType]
        )

        let constructorSymbol = symbols.define(
            kind: .constructor,
            name: pointName,
            fqName: pointFQName + [pointName],
            declSite: nil,
            visibility: .public
        )
        symbols.setParentSymbol(pointSymbol, for: constructorSymbol)
        let ctorXParamSymbol = symbols.define(
            kind: .valueParameter,
            name: interner.intern("x"),
            fqName: pointFQName + [pointName, interner.intern("x")],
            declSite: nil,
            visibility: .private
        )
        let ctorYParamSymbol = symbols.define(
            kind: .valueParameter,
            name: interner.intern("y"),
            fqName: pointFQName + [pointName, interner.intern("y")],
            declSite: nil,
            visibility: .private
        )

        // Register properties x: Int and y: Int
        let intType = types.make(.primitive(.int, .nonNull))
        let xName = interner.intern("x")
        let xSymbol = symbols.define(
            kind: .property,
            name: xName,
            fqName: pointFQName + [xName],
            declSite: nil,
            visibility: .public
        )
        symbols.setPropertyType(intType, for: xSymbol)
        symbols.setParentSymbol(pointSymbol, for: xSymbol)

        let yName = interner.intern("y")
        let ySymbol = symbols.define(
            kind: .property,
            name: yName,
            fqName: pointFQName + [yName],
            declSite: nil,
            visibility: .public
        )
        symbols.setPropertyType(intType, for: ySymbol)
        symbols.setParentSymbol(pointSymbol, for: ySymbol)

        // Non-constructor member properties should not participate in synthesized data methods.
        let zName = interner.intern("z")
        let zSymbol = symbols.define(
            kind: .property,
            name: zName,
            fqName: pointFQName + [zName],
            declSite: nil,
            visibility: .public
        )
        symbols.setPropertyType(intType, for: zSymbol)
        symbols.setParentSymbol(pointSymbol, for: zSymbol)

        // Register synthetic toString and equals stubs (as Sema would)
        let pointType = types.make(.classType(ClassType(
            classSymbol: pointSymbol,
            args: [],
            nullability: .nonNull
        )))
        let stringType = types.make(.primitive(.string, .nonNull))
        let boolType = types.make(.primitive(.boolean, .nonNull))
        let nullableAnyType = types.nullableAnyType
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: pointType,
                parameterTypes: [intType, intType],
                returnType: pointType,
                isSuspend: false,
                valueParameterSymbols: [ctorXParamSymbol, ctorYParamSymbol],
                valueParameterHasDefaultValues: [false, false],
                valueParameterIsVararg: [false, false],
                typeParameterSymbols: []
            ),
            for: constructorSymbol
        )

        let toStringName = interner.intern("toString")
        let toStringSymbol = symbols.define(
            kind: .function,
            name: toStringName,
            fqName: pointFQName + [toStringName],
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(pointSymbol, for: toStringSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: pointType,
                parameterTypes: [],
                returnType: stringType,
                isSuspend: false,
                valueParameterSymbols: [],
                valueParameterHasDefaultValues: [],
                valueParameterIsVararg: [],
                typeParameterSymbols: []
            ),
            for: toStringSymbol
        )

        let equalsName = interner.intern("equals")
        let equalsSymbol = symbols.define(
            kind: .function,
            name: equalsName,
            fqName: pointFQName + [equalsName],
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(pointSymbol, for: equalsSymbol)
        let otherParamName = interner.intern("other")
        let otherParamSymbol = symbols.define(
            kind: .valueParameter,
            name: otherParamName,
            fqName: pointFQName + [equalsName, otherParamName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: pointType,
                parameterTypes: [nullableAnyType],
                returnType: boolType,
                isSuspend: false,
                valueParameterSymbols: [otherParamSymbol],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [false],
                typeParameterSymbols: []
            ),
            for: equalsSymbol
        )

        let arena = KIRArena()
        let pointDecl = arena.appendDecl(.nominalType(KIRNominalType(symbol: pointSymbol)))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [pointDecl])], arena: arena)

        let ctx = CompilationContext(
            options: CompilerOptions(
                moduleName: "DataClassSynthesis",
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

        // Verify toString and equals are synthesized
        XCTAssertTrue(functionNames.contains("toString"), "Missing toString, got: \(functionNames)")
        XCTAssertTrue(functionNames.contains("equals"), "Missing equals, got: \(functionNames)")

        // Verify toString body uses StringBuilder + kk_any_to_string
        let toStringFn = try findKIRFunction(named: "toString", in: module, interner: interner)
        let toStringCallees = extractCallees(from: toStringFn.body, interner: interner)
        XCTAssertTrue(toStringCallees.contains("kk_string_builder_new_from_string"), "toString should create a StringBuilder from the class prefix")
        XCTAssertTrue(toStringCallees.contains("kk_string_builder_append_obj"), "toString should append labels and values via StringBuilder")
        XCTAssertTrue(toStringCallees.contains("kk_string_builder_toString"), "toString should convert the StringBuilder back to String")
        XCTAssertTrue(toStringCallees.contains("kk_any_to_string"), "toString should use kk_any_to_string")
        XCTAssertFalse(toStringCallees.contains("x$get"), "toString should read constructor-backed fields directly")
        XCTAssertFalse(toStringCallees.contains("y$get"), "toString should read constructor-backed fields directly")
        XCTAssertFalse(toStringCallees.contains("z$get"), "toString should ignore non-constructor properties")

        let toStringStringLiterals = toStringFn.body.compactMap { inst -> String? in
            guard case let .constValue(_, value) = inst, case let .stringLiteral(s) = value else { return nil }
            return interner.resolve(s)
        }
        XCTAssertTrue(toStringStringLiterals.contains("Point("), "toString should contain 'Point(' prefix")
        XCTAssertTrue(toStringStringLiterals.contains("x="), "toString should contain 'x=' label")
        XCTAssertTrue(toStringStringLiterals.contains(", y="), "toString should contain ', y=' label")
        XCTAssertTrue(toStringStringLiterals.contains(")"), "toString should contain ')' suffix")

        let equalsFn = try findKIRFunction(named: "equals", in: module, interner: interner)
        let equalsCallees = extractCallees(from: equalsFn.body, interner: interner)
        XCTAssertTrue(equalsCallees.contains("kk_op_is"), "equals should type-check other before reading properties")
        XCTAssertTrue(equalsCallees.contains("kk_op_safe_cast"), "equals should materialize a narrowed other receiver before getter calls")
        XCTAssertTrue(equalsCallees.contains("kk_op_eq"), "equals should use kk_op_eq for comparison")
        XCTAssertFalse(equalsCallees.contains("x$get"), "equals should compare constructor-backed fields directly")
        XCTAssertFalse(equalsCallees.contains("y$get"), "equals should compare constructor-backed fields directly")
        XCTAssertFalse(equalsCallees.contains("z$get"), "equals should ignore non-constructor properties")
        XCTAssertEqual(equalsFn.params.count, 2, "equals should have receiver + other parameter")

    }

    // MARK: - DATA-001: copy() edge cases

    /// When a data class has no primary constructor, copy() should fall back to
    /// returning self and emit a KSWIFTK-DATA-0001 warning.
    func testDataCopyNoPrimaryCtorEmitsWarningAndReturnsSelf() throws {
        let interner = StringInterner()
        let diagnostics = DiagnosticEngine()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let bindings = BindingTable()
        let sema = SemaModule(symbols: symbols, types: types, bindings: bindings, diagnostics: diagnostics)

        let packageName = interner.intern("test")
        let packagePath = [packageName]

        // Define a data class with NO constructor
        let pointName = interner.intern("Point")
        let pointSymbol = symbols.define(
            kind: .class,
            name: pointName,
            fqName: packagePath + [pointName],
            declSite: nil,
            visibility: .public,
            flags: [.dataType]
        )
        _ = symbols.define(
            kind: .function,
            name: interner.intern("copy"),
            fqName: packagePath + [pointName, interner.intern("copy")],
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )

        let arena = KIRArena()
        let pointDecl = arena.appendDecl(.nominalType(KIRNominalType(symbol: pointSymbol)))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [pointDecl])], arena: arena)

        let ctx = CompilationContext(
            options: CompilerOptions(
                moduleName: "DataCopyNoCtor",
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

        // Verify copy() is synthesized with only self parameter (fallback)
        let copyFunction = try findKIRFunction(named: "copy", in: module, interner: interner)
        XCTAssertEqual(copyFunction.params.count, 1, "copy() without ctor should have only self param")

        // Verify the body returns self (constValue + returnValue)
        let returnInstructions = copyFunction.body.filter {
            if case .returnValue = $0 { return true }
            return false
        }
        XCTAssertEqual(returnInstructions.count, 1, "copy() fallback should have exactly one return")

        // Verify KSWIFTK-DATA-0001 warning was emitted
        let dataWarnings = diagnostics.diagnostics.filter { $0.code == "KSWIFTK-DATA-0001" }
        XCTAssertEqual(dataWarnings.count, 1, "Expected one KSWIFTK-DATA-0001 warning, got \(dataWarnings.count)")
        XCTAssertEqual(dataWarnings.first?.severity, .warning)
        XCTAssertTrue(dataWarnings.first?.message.contains("Point") ?? false)
    }

    /// When a data class has a proper primary constructor, copy() should include
    /// parameters matching the constructor and call it.
    func testDataCopyWithPrimaryCtorIncludesCtorParams() throws {
        let interner = StringInterner()
        let diagnostics = DiagnosticEngine()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let bindings = BindingTable()
        let sema = SemaModule(symbols: symbols, types: types, bindings: bindings, diagnostics: diagnostics)

        let packageName = interner.intern("test")
        let packagePath = [packageName]

        let pointName = interner.intern("Point")
        let pointSymbol = symbols.define(
            kind: .class,
            name: pointName,
            fqName: packagePath + [pointName],
            declSite: nil,
            visibility: .public,
            flags: [.dataType]
        )
        _ = symbols.define(
            kind: .function,
            name: interner.intern("copy"),
            fqName: packagePath + [pointName, interner.intern("copy")],
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )

        // Define a constructor with two Int parameters (x, y)
        let initName = interner.intern("<init>")
        let ctorSymbol = symbols.define(
            kind: .constructor,
            name: initName,
            fqName: packagePath + [pointName, initName],
            declSite: nil,
            visibility: .public
        )

        let intType = types.make(.primitive(.int, .nonNull))
        let xParamName = interner.intern("x")
        let yParamName = interner.intern("y")
        let xParamSymbol = symbols.define(
            kind: .valueParameter,
            name: xParamName,
            fqName: packagePath + [pointName, initName, xParamName],
            declSite: nil,
            visibility: .private
        )
        let yParamSymbol = symbols.define(
            kind: .valueParameter,
            name: yParamName,
            fqName: packagePath + [pointName, initName, yParamName],
            declSite: nil,
            visibility: .private
        )

        let ctorSignature = FunctionSignature(
            parameterTypes: [intType, intType],
            returnType: types.make(.classType(ClassType(classSymbol: pointSymbol, args: [], nullability: .nonNull))),
            isSuspend: false,
            valueParameterSymbols: [xParamSymbol, yParamSymbol],
            valueParameterHasDefaultValues: [false, false],
            valueParameterIsVararg: [false, false]
        )
        symbols.setFunctionSignature(ctorSignature, for: ctorSymbol)

        let arena = KIRArena()
        let pointDecl = arena.appendDecl(.nominalType(KIRNominalType(symbol: pointSymbol)))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [pointDecl])], arena: arena)

        let ctx = CompilationContext(
            options: CompilerOptions(
                moduleName: "DataCopyWithCtor",
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

        // copy() should have self + x + y = 3 params
        let copyFunction = try findKIRFunction(named: "copy", in: module, interner: interner)
        XCTAssertEqual(copyFunction.params.count, 3, "copy() should have self + 2 ctor params")

        // Verify the body calls the constructor
        let callees = extractCallees(from: copyFunction.body, interner: interner)
        XCTAssertTrue(callees.contains("<init>"), "copy() should call <init>")

        // No warnings should be emitted for normal case
        let dataWarnings = diagnostics.diagnostics.filter { $0.code.hasPrefix("KSWIFTK-DATA-") }
        XCTAssertEqual(dataWarnings.count, 0, "No DATA warnings expected for normal data class copy")
    }

    /// When a data class constructor has a signature mismatch between
    /// parameterTypes and valueParameterSymbols, copy() should emit
    /// KSWIFTK-DATA-0002 warning and use the shorter count.
    func testDataCopySignatureMismatchEmitsWarning() throws {
        let interner = StringInterner()
        let diagnostics = DiagnosticEngine()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let bindings = BindingTable()
        let sema = SemaModule(symbols: symbols, types: types, bindings: bindings, diagnostics: diagnostics)

        let packageName = interner.intern("test")
        let packagePath = [packageName]

        let personName = interner.intern("Person")
        let personSymbol = symbols.define(
            kind: .class,
            name: personName,
            fqName: packagePath + [personName],
            declSite: nil,
            visibility: .public,
            flags: [.dataType]
        )
        _ = symbols.define(
            kind: .function,
            name: interner.intern("copy"),
            fqName: packagePath + [personName, interner.intern("copy")],
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )

        let initName = interner.intern("<init>")
        let ctorSymbol = symbols.define(
            kind: .constructor,
            name: initName,
            fqName: packagePath + [personName, initName],
            declSite: nil,
            visibility: .public
        )

        let intType = types.make(.primitive(.int, .nonNull))
        let stringType = types.make(.primitive(.string, .nonNull))
        let nameParamName = interner.intern("name")
        let nameParamSymbol = symbols.define(
            kind: .valueParameter,
            name: nameParamName,
            fqName: packagePath + [personName, initName, nameParamName],
            declSite: nil,
            visibility: .private
        )

        // Mismatch: 1 symbol but 2 types (extra type with no matching symbol)
        let ctorSignature = FunctionSignature(
            parameterTypes: [stringType, intType],
            returnType: types.make(.classType(ClassType(classSymbol: personSymbol, args: [], nullability: .nonNull))),
            isSuspend: false,
            valueParameterSymbols: [nameParamSymbol],
            valueParameterHasDefaultValues: [false],
            valueParameterIsVararg: [false]
        )
        symbols.setFunctionSignature(ctorSignature, for: ctorSymbol)

        let arena = KIRArena()
        let personDecl = arena.appendDecl(.nominalType(KIRNominalType(symbol: personSymbol)))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [personDecl])], arena: arena)

        let ctx = CompilationContext(
            options: CompilerOptions(
                moduleName: "DataCopyMismatch",
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

        // copy() should use min(1, 2) = 1 ctor param, so self + 1 = 2 params
        let copyFunction = try findKIRFunction(named: "copy", in: module, interner: interner)
        XCTAssertEqual(copyFunction.params.count, 2, "copy() with mismatch should have self + min(symbols, types) params")

        // Verify KSWIFTK-DATA-0002 warning was emitted
        let mismatchWarnings = diagnostics.diagnostics.filter { $0.code == "KSWIFTK-DATA-0002" }
        XCTAssertEqual(mismatchWarnings.count, 1, "Expected one KSWIFTK-DATA-0002 warning, got \(mismatchWarnings.count)")
        XCTAssertEqual(mismatchWarnings.first?.severity, .warning)
        XCTAssertTrue(mismatchWarnings.first?.message.contains("Person") ?? false)
    }

    /// When a data class constructor has zero value parameters, copy()
    /// should produce a function with only the self parameter.
    func testDataCopyZeroCtorParams() throws {
        let interner = StringInterner()
        let diagnostics = DiagnosticEngine()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let bindings = BindingTable()
        let sema = SemaModule(symbols: symbols, types: types, bindings: bindings, diagnostics: diagnostics)

        let packageName = interner.intern("test")
        let packagePath = [packageName]

        let emptyName = interner.intern("Empty")
        let emptySymbol = symbols.define(
            kind: .class,
            name: emptyName,
            fqName: packagePath + [emptyName],
            declSite: nil,
            visibility: .public,
            flags: [.dataType]
        )

        let initName = interner.intern("<init>")
        let ctorSymbol = symbols.define(
            kind: .constructor,
            name: initName,
            fqName: packagePath + [emptyName, initName],
            declSite: nil,
            visibility: .public
        )

        // Constructor with zero value params
        let ctorSignature = FunctionSignature(
            parameterTypes: [],
            returnType: types.make(.classType(ClassType(classSymbol: emptySymbol, args: [], nullability: .nonNull))),
            isSuspend: false,
            valueParameterSymbols: [],
            valueParameterHasDefaultValues: [],
            valueParameterIsVararg: []
        )
        symbols.setFunctionSignature(ctorSignature, for: ctorSymbol)
        _ = symbols.define(
            kind: .function,
            name: interner.intern("copy"),
            fqName: packagePath + [emptyName, interner.intern("copy")],
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )

        let arena = KIRArena()
        let emptyDecl = arena.appendDecl(.nominalType(KIRNominalType(symbol: emptySymbol)))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [emptyDecl])], arena: arena)

        let ctx = CompilationContext(
            options: CompilerOptions(
                moduleName: "DataCopyZeroParams",
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

        // copy() with zero ctor params should have only self param
        let copyFunction = try findKIRFunction(named: "copy", in: module, interner: interner)
        XCTAssertEqual(copyFunction.params.count, 1, "copy() with zero ctor params should have only self param")

        // Should still call the constructor
        let callees = extractCallees(from: copyFunction.body, interner: interner)
        XCTAssertTrue(callees.contains("<init>"), "copy() should call <init> even with zero params")

        // No warnings
        let dataWarnings = diagnostics.diagnostics.filter { $0.code.hasPrefix("KSWIFTK-DATA-") }
        XCTAssertEqual(dataWarnings.count, 0, "No DATA warnings expected for zero-param data class copy")
    }

    /// When a data class constructor has a function signature but the symbol
    /// lookup returns no constructor kind, copy() should fall back to self.
    func testDataCopyCtorWithoutConstructorKindFallsBack() throws {
        let interner = StringInterner()
        let diagnostics = DiagnosticEngine()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let bindings = BindingTable()
        let sema = SemaModule(symbols: symbols, types: types, bindings: bindings, diagnostics: diagnostics)

        let packageName = interner.intern("test")
        let packagePath = [packageName]

        let widgetName = interner.intern("Widget")
        let widgetSymbol = symbols.define(
            kind: .class,
            name: widgetName,
            fqName: packagePath + [widgetName],
            declSite: nil,
            visibility: .public,
            flags: [.dataType]
        )
        _ = symbols.define(
            kind: .function,
            name: interner.intern("copy"),
            fqName: packagePath + [widgetName, interner.intern("copy")],
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )

        // Define <init> with kind .function instead of .constructor
        let initName = interner.intern("<init>")
        let wrongKindSymbol = symbols.define(
            kind: .function,
            name: initName,
            fqName: packagePath + [widgetName, initName],
            declSite: nil,
            visibility: .public
        )

        let intType = types.make(.primitive(.int, .nonNull))
        let sig = FunctionSignature(
            parameterTypes: [intType],
            returnType: types.make(.classType(ClassType(classSymbol: widgetSymbol, args: [], nullability: .nonNull))),
            isSuspend: false,
            valueParameterSymbols: [wrongKindSymbol],
            valueParameterHasDefaultValues: [false],
            valueParameterIsVararg: [false]
        )
        symbols.setFunctionSignature(sig, for: wrongKindSymbol)

        let arena = KIRArena()
        let widgetDecl = arena.appendDecl(.nominalType(KIRNominalType(symbol: widgetSymbol)))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [widgetDecl])], arena: arena)

        let ctx = CompilationContext(
            options: CompilerOptions(
                moduleName: "DataCopyWrongKind",
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

        // Should fall back to self-returning copy (only self param)
        let copyFunction = try findKIRFunction(named: "copy", in: module, interner: interner)
        XCTAssertEqual(copyFunction.params.count, 1, "copy() with wrong ctor kind should fall back to self-only")

        // Should emit the no-ctor warning
        let dataWarnings = diagnostics.diagnostics.filter { $0.code == "KSWIFTK-DATA-0001" }
        XCTAssertEqual(dataWarnings.count, 1, "Expected KSWIFTK-DATA-0001 for non-constructor init")
    }
}
