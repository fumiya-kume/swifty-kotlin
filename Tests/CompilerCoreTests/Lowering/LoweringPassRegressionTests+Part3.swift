import Foundation
import XCTest
@testable import CompilerCore


extension LoweringPassRegressionTests {
    func testCoroutineLoweringSpillsAndReloadsLiveValuesAcrossSuspension() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()

        let suspendSym = SymbolID(rawValue: 1900)
        let liveValue = arena.appendExpr(.temporary(0))
        let callResult = arena.appendExpr(.temporary(1))
        let summedResult = arena.appendExpr(.temporary(2))

        let suspendFn = KIRFunction(
            symbol: suspendSym,
            name: interner.intern("suspendTarget"),
            params: [],
            returnType: types.make(.primitive(.int, .nonNull)),
            body: [
                .constValue(result: liveValue, value: .intLiteral(41)),
                .call(symbol: suspendSym, callee: interner.intern("suspendTarget"), arguments: [], result: callResult, canThrow: false, thrownResult: nil),
                .binary(op: .add, lhs: liveValue, rhs: callResult, result: summedResult),
                .returnValue(summedResult)
            ],
            isSuspend: true,
            isInline: false
        )

        let suspendID = arena.appendDecl(.function(suspendFn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [suspendID])], arena: arena)
        let options = CompilerOptions(
            moduleName: "CoroutineSpill",
            inputs: [],
            outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path,
            emit: .kirDump,
            target: defaultTargetTriple()
        )
        let ctx = CompilationContext(
            options: options,
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: interner
        )
        ctx.kir = module

        try LoweringPhase().run(ctx)

        let loweredSuspend = try findKIRFunction(named: "kk_suspend_suspendTarget", in: module, interner: interner)

        let loweredCalls = extractCallees(from: loweredSuspend.body, interner: interner)
        XCTAssertTrue(loweredCalls.contains("kk_coroutine_state_set_spill"))
        XCTAssertTrue(loweredCalls.contains("kk_coroutine_state_get_spill"))
        XCTAssertTrue(loweredCalls.contains("kk_coroutine_state_set_completion"))
        XCTAssertTrue(loweredCalls.contains("kk_coroutine_state_get_completion"))

        let setSpillCount = loweredCalls.filter { $0 == "kk_coroutine_state_set_spill" }.count
        let getSpillCount = loweredCalls.filter { $0 == "kk_coroutine_state_get_spill" }.count
        XCTAssertEqual(setSpillCount, 1)
        XCTAssertEqual(getSpillCount, 1)

        let throwFlags = extractThrowFlags(from: loweredSuspend.body, interner: interner)
        XCTAssertEqual(throwFlags["kk_suspend_suspendTarget"]?.allSatisfy({ $0 == true }), true)
        XCTAssertEqual(throwFlags["kk_coroutine_state_set_spill"]?.allSatisfy({ $0 == false }), true)
        XCTAssertEqual(throwFlags["kk_coroutine_state_get_spill"]?.allSatisfy({ $0 == false }), true)
        XCTAssertEqual(throwFlags["kk_coroutine_state_set_completion"]?.allSatisfy({ $0 == false }), true)
        XCTAssertEqual(throwFlags["kk_coroutine_state_get_completion"]?.allSatisfy({ $0 == false }), true)
    }

    func testCoroutineLoweringSynthesizesContinuationNominalTypeLayoutAndSignature() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let symbols = SymbolTable()
        let bindings = BindingTable()
        let diagnostics = DiagnosticEngine()

        let packageName = interner.intern("pkg")
        let suspendName = interner.intern("suspendTarget")
        let parameterName = interner.intern("value")
        let range = makeRange()
        let intType = types.make(.primitive(.int, .nonNull))

        let suspendSymbol = symbols.define(
            kind: .function,
            name: suspendName,
            fqName: [packageName, suspendName],
            declSite: range,
            visibility: .public,
            flags: [.suspendFunction]
        )
        let parameterSymbol = symbols.define(
            kind: .valueParameter,
            name: parameterName,
            fqName: [packageName, suspendName, parameterName],
            declSite: range,
            visibility: .private
        )
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [intType],
                returnType: intType,
                isSuspend: true,
                valueParameterSymbols: [parameterSymbol]
            ),
            for: suspendSymbol
        )

        let liveValue = arena.appendExpr(.temporary(0), type: intType)
        let callResult = arena.appendExpr(.temporary(1), type: intType)
        let sumResult = arena.appendExpr(.temporary(2), type: intType)

        let suspendFunction = KIRFunction(
            symbol: suspendSymbol,
            name: suspendName,
            params: [KIRParameter(symbol: parameterSymbol, type: intType)],
            returnType: intType,
            body: [
                .constValue(result: liveValue, value: .symbolRef(parameterSymbol)),
                .call(
                    symbol: suspendSymbol,
                    callee: suspendName,
                    arguments: [liveValue],
                    result: callResult,
                    canThrow: false,
                    thrownResult: nil
                ),
                .binary(op: .add, lhs: liveValue, rhs: callResult, result: sumResult),
                .returnValue(sumResult)
            ],
            isSuspend: true,
            isInline: false
        )

        let suspendID = arena.appendDecl(.function(suspendFunction))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [suspendID])], arena: arena)

        let ctx = CompilationContext(
            options: CompilerOptions(
                moduleName: "CoroutineContinuationType",
                inputs: [],
                outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path,
                emit: .kirDump,
                target: defaultTargetTriple()
            ),
            sourceManager: SourceManager(),
            diagnostics: diagnostics,
            interner: interner
        )
        ctx.kir = module
        ctx.sema = SemaModule(
            symbols: symbols,
            types: types,
            bindings: bindings,
            diagnostics: diagnostics
        )

        try LoweringPhase().run(ctx)

        let sema = try XCTUnwrap(ctx.sema)
        let continuationTypeSymbol = try XCTUnwrap(sema.symbols.allSymbols().first(where: { symbol in
            symbol.kind == .class &&
                symbol.flags.contains(.synthetic) &&
                interner.resolve(symbol.name).contains("kk_suspend_suspendTarget$Cont")
        }))

        let continuationFields = sema.symbols.allSymbols().filter { symbol in
            symbol.kind == .field &&
                symbol.fqName.count == continuationTypeSymbol.fqName.count + 1 &&
                zip(continuationTypeSymbol.fqName, symbol.fqName).allSatisfy { $0 == $1 }
        }
        let fieldNames = Set(continuationFields.map { interner.resolve($0.name) })
        XCTAssertTrue(fieldNames.contains("$label"))
        XCTAssertTrue(fieldNames.contains("$completion"))
        XCTAssertTrue(fieldNames.contains("$spill0"))

        let layout = try XCTUnwrap(sema.symbols.nominalLayout(for: continuationTypeSymbol.id))
        XCTAssertGreaterThanOrEqual(layout.instanceFieldCount, 3)
        let labelField = try XCTUnwrap(continuationFields.first(where: { interner.resolve($0.name) == "$label" }))
        let completionField = try XCTUnwrap(continuationFields.first(where: { interner.resolve($0.name) == "$completion" }))
        let spillField = try XCTUnwrap(continuationFields.first(where: { interner.resolve($0.name) == "$spill0" }))
        let labelOffset = try XCTUnwrap(layout.fieldOffsets[labelField.id])
        let completionOffset = try XCTUnwrap(layout.fieldOffsets[completionField.id])
        let spillOffset = try XCTUnwrap(layout.fieldOffsets[spillField.id])
        XCTAssertLessThan(labelOffset, completionOffset)
        XCTAssertLessThan(completionOffset, spillOffset)

        let loweredSuspendSymbol = try XCTUnwrap(sema.symbols.allSymbols().first(where: { symbol in
            symbol.kind == .function && interner.resolve(symbol.name).hasPrefix("kk_suspend_suspendTarget")
        }))
        let loweredSignature = try XCTUnwrap(sema.symbols.functionSignature(for: loweredSuspendSymbol.id))
        let continuationParameterType = try XCTUnwrap(loweredSignature.parameterTypes.last)
        guard case .classType(let classType) = types.kind(of: continuationParameterType) else {
            XCTFail("Expected lowered continuation parameter type to be class type.")
            return
        }
        XCTAssertEqual(classType.classSymbol, continuationTypeSymbol.id)

        let nominalSymbols = module.arena.declarations.compactMap { decl -> SymbolID? in
            guard case .nominalType(let nominal) = decl else {
                return nil
            }
            return nominal.symbol
        }
        XCTAssertTrue(nominalSymbols.contains(continuationTypeSymbol.id))
    }

    func testSuspendExceptionPropagationKeepsThrowingChannelAcrossSuspendChain() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()

        let mainSymbol = SymbolID(rawValue: 2100)
        let topSymbol = SymbolID(rawValue: 2101)
        let leafSymbol = SymbolID(rawValue: 2102)

        let mainResult = arena.appendExpr(.temporary(0))
        let topResult = arena.appendExpr(.temporary(1))
        let leafResult = arena.appendExpr(.temporary(2))

        let mainFunction = KIRFunction(
            symbol: mainSymbol,
            name: interner.intern("main"),
            params: [],
            returnType: types.unitType,
            body: [
                .call(symbol: topSymbol, callee: interner.intern("top"), arguments: [], result: mainResult, canThrow: false, thrownResult: nil),
                .returnValue(mainResult)
            ],
            isSuspend: false,
            isInline: false
        )
        let topFunction = KIRFunction(
            symbol: topSymbol,
            name: interner.intern("top"),
            params: [],
            returnType: types.unitType,
            body: [
                .call(symbol: leafSymbol, callee: interner.intern("leaf"), arguments: [], result: topResult, canThrow: false, thrownResult: nil),
                .returnValue(topResult)
            ],
            isSuspend: true,
            isInline: false
        )
        let leafFunction = KIRFunction(
            symbol: leafSymbol,
            name: interner.intern("leaf"),
            params: [],
            returnType: types.unitType,
            body: [
                .call(symbol: nil, callee: interner.intern("external_throwing"), arguments: [], result: leafResult, canThrow: false, thrownResult: nil),
                .returnValue(leafResult)
            ],
            isSuspend: true,
            isInline: false
        )

        let mainID = arena.appendDecl(.function(mainFunction))
        _ = arena.appendDecl(.function(topFunction))
        _ = arena.appendDecl(.function(leafFunction))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainID])], arena: arena)

        let ctx = CompilationContext(
            options: CompilerOptions(
                moduleName: "CoroutineThrowFlags",
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

        let loweredMain = try findKIRFunction(named: "main", in: module, interner: interner)
        let loweredTop = try findKIRFunction(named: "kk_suspend_top", in: module, interner: interner)
        let loweredLeaf = try findKIRFunction(named: "kk_suspend_leaf", in: module, interner: interner)

        let mainThrowFlags = extractThrowFlags(from: loweredMain.body, interner: interner)
        XCTAssertEqual(mainThrowFlags["kk_suspend_top"]?.allSatisfy({ $0 == true }), true)

        let topThrowFlags = extractThrowFlags(from: loweredTop.body, interner: interner)
        XCTAssertEqual(topThrowFlags["kk_suspend_leaf"]?.allSatisfy({ $0 == true }), true)
        XCTAssertEqual(topThrowFlags["kk_coroutine_state_set_label"]?.allSatisfy({ $0 == false }), true)
        XCTAssertEqual(topThrowFlags["kk_coroutine_state_set_completion"]?.allSatisfy({ $0 == false }), true)

        let leafThrowFlags = extractThrowFlags(from: loweredLeaf.body, interner: interner)
        XCTAssertEqual(leafThrowFlags["external_throwing"]?.allSatisfy({ $0 == true }), true)
    }

}
