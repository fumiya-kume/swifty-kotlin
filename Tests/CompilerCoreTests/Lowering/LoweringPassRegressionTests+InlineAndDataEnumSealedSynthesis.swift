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

        // Verify toString body uses kk_string_concat and kk_any_to_string
        let toStringFn = try findKIRFunction(named: "toString", in: module, interner: interner)
        let toStringCallees = extractCallees(from: toStringFn.body, interner: interner)
        XCTAssertTrue(toStringCallees.contains("kk_string_concat"), "toString should use kk_string_concat")
        XCTAssertTrue(toStringCallees.contains("kk_any_to_string"), "toString should use kk_any_to_string")
        // Should call property getters for x and y
        XCTAssertTrue(toStringCallees.contains("x$get"), "toString should call x$get")
        XCTAssertTrue(toStringCallees.contains("y$get"), "toString should call y$get")
        XCTAssertFalse(toStringCallees.contains("z$get"), "toString should ignore non-constructor properties")

        // Verify toString body contains the class name prefix "Point("
        let toStringStringLiterals = toStringFn.body.compactMap { inst -> String? in
            guard case let .constValue(_, value) = inst, case let .stringLiteral(s) = value else { return nil }
            return interner.resolve(s)
        }
        XCTAssertTrue(toStringStringLiterals.contains("Point("), "toString should contain 'Point(' prefix")
        XCTAssertTrue(toStringStringLiterals.contains("x="), "toString should contain 'x=' label")
        XCTAssertTrue(toStringStringLiterals.contains(", y="), "toString should contain ', y=' label")
        XCTAssertTrue(toStringStringLiterals.contains(")"), "toString should contain ')' suffix")

        // Verify equals body uses kk_op_eq for property comparison
        let equalsFn = try findKIRFunction(named: "equals", in: module, interner: interner)
        let equalsCallees = extractCallees(from: equalsFn.body, interner: interner)
        XCTAssertTrue(equalsCallees.contains("kk_op_is"), "equals should type-check other before reading properties")
        XCTAssertTrue(equalsCallees.contains("kk_op_safe_cast"), "equals should materialize a narrowed other receiver before getter calls")
        XCTAssertTrue(equalsCallees.contains("kk_op_eq"), "equals should use kk_op_eq for comparison")
        XCTAssertTrue(equalsCallees.contains("x$get"), "equals should call x$get")
        XCTAssertTrue(equalsCallees.contains("y$get"), "equals should call y$get")
        XCTAssertFalse(equalsCallees.contains("z$get"), "equals should ignore non-constructor properties")
        // Should have receiver + other parameter
        XCTAssertEqual(equalsFn.params.count, 2, "equals should have receiver + other parameter")

        let xGetterCalls = equalsFn.body.compactMap { instruction -> KIRInstruction? in
            guard case let .call(_, callee, _, _, _, _, _) = instruction,
                  interner.resolve(callee) == "x$get"
            else {
                return nil
            }
            return instruction
        }
        XCTAssertEqual(xGetterCalls.count, 2, "equals should compare both receiver and narrowed other")
    }
}
