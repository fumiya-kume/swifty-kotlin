@testable import CompilerCore
import Foundation
import XCTest

// Tests for virtual dispatch (vtable/itable) lowering, codegen, and backend emission (P5-25).

extension VirtualDispatchTests {
    func testABILoweringUnboxesReturnForVirtualCall() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let symbols = SymbolTable()

        let intType = types.make(.primitive(.int, .nonNull))
        let anyNullableType = types.make(.any(.nullable))

        let callerSym = SymbolID(rawValue: 4100)
        let targetSym = SymbolID(rawValue: 4101)

        let targetName = interner.intern("virtualGetValue")

        // The target function returns Any? but the result expression has type Int
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [],
                returnType: anyNullableType,
                valueParameterSymbols: []
            ),
            for: targetSym
        )

        let receiverExpr = arena.appendExpr(.temporary(0), type: types.anyType)
        let resultExpr = arena.appendExpr(.temporary(1), type: intType)

        let callerFn = KIRFunction(
            symbol: callerSym,
            name: interner.intern("main"),
            params: [],
            returnType: types.unitType,
            body: [
                .virtualCall(
                    symbol: targetSym,
                    callee: targetName,
                    receiver: receiverExpr,
                    arguments: [],
                    result: resultExpr,
                    canThrow: false,
                    thrownResult: nil,
                    dispatch: .vtable(slot: 0)
                ),
                .returnUnit,
            ],
            isSuspend: false,
            isInline: false
        )

        let callerID = arena.appendDecl(.function(callerFn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [callerID])], arena: arena)

        let sema = SemaModule(symbols: symbols, types: types, bindings: BindingTable(), diagnostics: DiagnosticEngine())
        let ctx = CompilationContext(
            options: CompilerOptions(
                moduleName: "ABIUnboxVirtual",
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
        ctx.sema = sema

        try LoweringPhase().run(ctx)

        let lowered = try findKIRFunction(named: "main", in: module, interner: interner)
        let callees = lowered.body.compactMap { instruction -> String? in
            switch instruction {
            case let .call(_, callee, _, _, _, _, _):
                return interner.resolve(callee)
            default:
                return nil
            }
        }
        XCTAssertTrue(callees.contains("kk_unbox_int"), "Expected kk_unbox_int call for Any? -> Int unboxing after virtualCall, got: \(callees)")
    }

    // MARK: - 4. virtualCall preserved through lowering (not converted to .call)

    func testVirtualCallSurvivesLoweringPhase() throws {
        let fixture = makeVtableFixture()
        let sema = SemaModule(
            symbols: fixture.symbols,
            types: fixture.types,
            bindings: BindingTable(),
            diagnostics: DiagnosticEngine()
        )
        let ctx = CompilationContext(
            options: CompilerOptions(
                moduleName: "VCallSurvival",
                inputs: [],
                outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path,
                emit: .kirDump,
                target: defaultTargetTriple()
            ),
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: fixture.interner
        )
        ctx.kir = fixture.module
        ctx.sema = sema

        try LoweringPhase().run(ctx)

        let lowered = try findKIRFunction(named: "callSpeak", in: fixture.module, interner: fixture.interner)
        let hasVirtualCall = lowered.body.contains { instruction in
            if case .virtualCall = instruction { return true }
            return false
        }
        XCTAssertTrue(hasVirtualCall, "virtualCall should survive all lowering passes and not be downgraded to .call")
    }

    // MARK: - 5. virtualCall dispatch kind preservation

    func testVirtualCallPreservesVtableDispatchKind() throws {
        let fixture = makeVtableFixture()
        let sema = SemaModule(
            symbols: fixture.symbols,
            types: fixture.types,
            bindings: BindingTable(),
            diagnostics: DiagnosticEngine()
        )
        let ctx = CompilationContext(
            options: CompilerOptions(
                moduleName: "VtableKind",
                inputs: [],
                outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path,
                emit: .kirDump,
                target: defaultTargetTriple()
            ),
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: fixture.interner
        )
        ctx.kir = fixture.module
        ctx.sema = sema

        try LoweringPhase().run(ctx)

        let lowered = try findKIRFunction(named: "callSpeak", in: fixture.module, interner: fixture.interner)
        let vcInstruction = lowered.body.first { instruction in
            if case .virtualCall = instruction { return true }
            return false
        }
        guard case let .virtualCall(_, _, _, _, _, _, _, dispatch) = vcInstruction else {
            XCTFail("Expected virtualCall instruction after lowering")
            return
        }
        XCTAssertEqual(dispatch, .vtable(slot: 0), "Dispatch kind should be preserved as vtable(slot: 0)")
    }

    func testVirtualCallPreservesItableDispatchKind() throws {
        let fixture = makeItableFixture()
        let sema = SemaModule(
            symbols: fixture.symbols,
            types: fixture.types,
            bindings: BindingTable(),
            diagnostics: DiagnosticEngine()
        )
        let ctx = CompilationContext(
            options: CompilerOptions(
                moduleName: "ItableKind",
                inputs: [],
                outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path,
                emit: .kirDump,
                target: defaultTargetTriple()
            ),
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: fixture.interner
        )
        ctx.kir = fixture.module
        ctx.sema = sema

        try LoweringPhase().run(ctx)

        let lowered = try findKIRFunction(named: "callDraw", in: fixture.module, interner: fixture.interner)
        let vcInstruction = lowered.body.first { instruction in
            if case .virtualCall = instruction { return true }
            return false
        }
        guard case let .virtualCall(_, _, _, _, _, _, _, dispatch) = vcInstruction else {
            XCTFail("Expected virtualCall instruction after lowering")
            return
        }
        XCTAssertEqual(dispatch, .itable(interfaceSlot: 0, methodSlot: 0), "Dispatch kind should be preserved as itable(interfaceSlot: 0, methodSlot: 0)")
    }

    // MARK: - 6. Receiver is NOT duplicated in virtualCall arguments after lowering

    func testVirtualCallReceiverNotInArgumentsAfterLowering() throws {
        let fixture = makeVtableFixture()
        let sema = SemaModule(
            symbols: fixture.symbols,
            types: fixture.types,
            bindings: BindingTable(),
            diagnostics: DiagnosticEngine()
        )
        let ctx = CompilationContext(
            options: CompilerOptions(
                moduleName: "ReceiverDedup",
                inputs: [],
                outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path,
                emit: .kirDump,
                target: defaultTargetTriple()
            ),
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: fixture.interner
        )
        ctx.kir = fixture.module
        ctx.sema = sema

        try LoweringPhase().run(ctx)

        let lowered = try findKIRFunction(named: "callSpeak", in: fixture.module, interner: fixture.interner)
        let vcInstruction = lowered.body.first { instruction in
            if case .virtualCall = instruction { return true }
            return false
        }
        guard case let .virtualCall(_, _, receiver, arguments, _, _, _, _) = vcInstruction else {
            XCTFail("Expected virtualCall instruction after lowering")
            return
        }
        // The speak method has no value parameters, so arguments should be empty.
        // The receiver should be separate.
        XCTAssertEqual(arguments.count, 0, "virtualCall arguments should not contain the receiver (speak has 0 value params)")
        // Verify receiver is a valid expression
        XCTAssertNotEqual(receiver.rawValue, -1, "Receiver should be a valid expression ID")
    }

    // MARK: - 7. KIR dump contains vtable/itable dispatch info

    func testKIRDumpContainsVtableLookupDispatchInfo() {
        let fixture = makeVtableFixture()
        let dump = fixture.module.dump(interner: fixture.interner, symbols: fixture.symbols)
        XCTAssertTrue(dump.contains("virtualCall"), "KIR dump should contain virtualCall instruction")
        XCTAssertTrue(dump.contains("dispatch=vtable[0]"), "KIR dump should contain dispatch=vtable[0]")
        XCTAssertTrue(dump.contains("receiver="), "KIR dump should contain receiver field")
    }

    func testKIRDumpContainsItableLookupDispatchInfo() {
        let fixture = makeItableFixture()
        let dump = fixture.module.dump(interner: fixture.interner, symbols: fixture.symbols)
        XCTAssertTrue(dump.contains("virtualCall"), "KIR dump should contain virtualCall instruction")
        XCTAssertTrue(dump.contains("dispatch=itable[0:0]"), "KIR dump should contain dispatch=itable[0:0]")
    }

    // MARK: - 8. Receiver serialization via KIR dump

    func testVirtualCallReceiverAppearsInKIRDump() {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let symbols = SymbolTable()

        let anyType = types.anyType

        let callerSym = SymbolID(rawValue: 5000)
        let methodSym = SymbolID(rawValue: 5001)

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: anyType,
                parameterTypes: [anyType],
                returnType: types.unitType,
                valueParameterSymbols: [SymbolID(rawValue: 5002)]
            ),
            for: methodSym
        )

        let receiverExpr = arena.appendExpr(.temporary(0), type: anyType)
        let argExpr = arena.appendExpr(.temporary(1), type: anyType)
        let resultExpr = arena.appendExpr(.temporary(2), type: types.unitType)

        let callerFn = KIRFunction(
            symbol: callerSym,
            name: interner.intern("callWithArg"),
            params: [
                KIRParameter(symbol: SymbolID(rawValue: 5003), type: anyType),
                KIRParameter(symbol: SymbolID(rawValue: 5004), type: anyType),
            ],
            returnType: types.unitType,
            body: [
                .virtualCall(
                    symbol: methodSym,
                    callee: interner.intern("methodWithArg"),
                    receiver: receiverExpr,
                    arguments: [argExpr],
                    result: resultExpr,
                    canThrow: false,
                    thrownResult: nil,
                    dispatch: .vtable(slot: 0)
                ),
                .returnUnit,
            ],
            isSuspend: false,
            isInline: false
        )

        let callerID = arena.appendDecl(.function(callerFn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [callerID])], arena: arena)

        // Verify via KIR dump that the receiver is separate from arguments
        let dump = module.dump(interner: interner, symbols: symbols)
        XCTAssertTrue(dump.contains("virtualCall"), "Dump should contain virtualCall")
        // The receiver and arguments should be separate fields in the dump
        XCTAssertTrue(dump.contains("receiver="), "Dump should have receiver= field")
        XCTAssertTrue(dump.contains("dispatch=vtable[0]"), "Dump should have dispatch info")
    }

    // MARK: - 9. LLVM backend via emitObject: virtualCall compiles without error

    func testLlvmCapiBackendCompilesVirtualCallWithoutError() throws {
        guard llvmCapiBindingsAvailable() else {
            throw XCTSkip("LLVM C API bindings are unavailable in this environment.")
        }
        let fixture = makeVtableFixture()
        let sema = SemaModule(
            symbols: fixture.symbols,
            types: fixture.types,
            bindings: BindingTable(),
            diagnostics: DiagnosticEngine()
        )
        let ctx = CompilationContext(
            options: CompilerOptions(
                moduleName: "CBackendVtable",
                inputs: [],
                outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".o").path,
                emit: .kirDump,
                target: defaultTargetTriple()
            ),
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: fixture.interner
        )
        ctx.kir = fixture.module
        ctx.sema = sema

        try LoweringPhase().run(ctx)

        let backend = LLVMCAPIBackend(
            target: defaultTargetTriple(),
            optLevel: .O0,
            debugInfo: false,
            diagnostics: DiagnosticEngine(),
            isStrictMode: true
        )
        let runtime = RuntimeLinkInfo(libraryPaths: [], libraries: [], extraObjects: [])
        let irPath = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ll").path
        try backend.emitLLVMIR(module: fixture.module, runtime: runtime, outputIRPath: irPath, interner: fixture.interner)
        let ir = try String(contentsOfFile: irPath, encoding: .utf8)
        XCTAssertTrue(ir.contains("kk_vtable_lookup") || ir.contains("kk_fn_"), "IR should contain vtable dispatch or emitted functions")
    }

    // MARK: - 10. Codegen serialization of virtualCall

    func testCodegenSerializesVirtualCallWithVtableDispatch() {
        let fixture = makeVtableFixture()

        let dump = fixture.module.dump(interner: fixture.interner, symbols: fixture.symbols)

        XCTAssertTrue(dump.contains("virtualCall"), "KIR dump should contain virtualCall instruction, got:\n\(dump)")
        XCTAssertTrue(dump.contains("dispatch=vtable[0]"), "KIR dump should contain dispatch=vtable[0], got:\n\(dump)")
    }

    func testCodegenSerializesVirtualCallWithItableDispatch() {
        let fixture = makeItableFixture()

        let dump = fixture.module.dump(interner: fixture.interner, symbols: fixture.symbols)

        XCTAssertTrue(dump.contains("virtualCall"), "KIR dump should contain virtualCall instruction, got:\n\(dump)")
        XCTAssertTrue(dump.contains("dispatch=itable[0:0]"), "KIR dump should contain dispatch=itable[0:0], got:\n\(dump)")
    }
}
