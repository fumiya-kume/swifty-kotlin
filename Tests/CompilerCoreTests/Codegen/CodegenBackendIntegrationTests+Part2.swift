import Foundation
import XCTest
@testable import CompilerCore


extension CodegenBackendIntegrationTests {
    func testLLVMBackendEmitsCoroutineRootLifecycleHooks() throws {
        let interner = StringInterner()
        let types = TypeSystem()
        let arena = KIRArena()

        let mainSymbol = SymbolID(rawValue: 990)
        let functionIDValue = arena.appendExpr(.intLiteral(7))
        let returnSeed = arena.appendExpr(.intLiteral(0))
        let continuation = arena.appendExpr(.temporary(1))
        let exited = arena.appendExpr(.temporary(2))

        let main = KIRFunction(
            symbol: mainSymbol,
            name: interner.intern("main"),
            params: [],
            returnType: types.anyType,
            body: [
                .constValue(result: functionIDValue, value: .intLiteral(7)),
                .constValue(result: returnSeed, value: .intLiteral(0)),
                .call(
                    symbol: nil,
                    callee: interner.intern("kk_coroutine_continuation_new"),
                    arguments: [functionIDValue],
                    result: continuation,
                    canThrow: false,
                    thrownResult: nil
                ),
                .call(
                    symbol: nil,
                    callee: interner.intern("kk_coroutine_state_exit"),
                    arguments: [continuation, returnSeed],
                    result: exited,
                    canThrow: false,
                    thrownResult: nil
                ),
                .returnValue(exited)
            ],
            isSuspend: false,
            isInline: false
        )

        let mainID = arena.appendDecl(.function(main))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainID])], arena: arena)

        let backend = LLVMBackend(
            target: defaultTargetTriple(),
            optLevel: .O0,
            debugInfo: false,
            diagnostics: DiagnosticEngine()
        )
        let runtime = RuntimeLinkInfo(libraryPaths: [], libraries: [], extraObjects: [])
        let irPath = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ll").path

        try backend.emitLLVMIR(module: module, runtime: runtime, outputIRPath: irPath, interner: interner)
        let ir = try String(contentsOfFile: irPath, encoding: .utf8)
        XCTAssertTrue(ir.contains("call void @kk_register_coroutine_root"))
        XCTAssertTrue(ir.contains("call void @kk_unregister_coroutine_root"))
    }

    func testLLVMBackendSupportsExternalThrowChannelCalls() throws {
        let interner = StringInterner()
        let types = TypeSystem()
        let arena = KIRArena()

        let mainSymbol = SymbolID(rawValue: 910)
        let callResult = arena.appendExpr(.temporary(0))

        let main = KIRFunction(
            symbol: mainSymbol,
            name: interner.intern("main"),
            params: [],
            returnType: types.anyType,
            body: [
                .call(symbol: nil, callee: interner.intern("external_throwing"), arguments: [], result: callResult, canThrow: true, thrownResult: nil),
                .returnValue(callResult)
            ],
            isSuspend: false,
            isInline: false
        )
        let mainID = arena.appendDecl(.function(main))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainID])], arena: arena)

        let backend = LLVMBackend(
            target: defaultTargetTriple(),
            optLevel: .O0,
            debugInfo: false,
            diagnostics: DiagnosticEngine()
        )

        let runtime = RuntimeLinkInfo(libraryPaths: [], libraries: [], extraObjects: [])
        let objectPath = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".o").path
        try backend.emitObject(module: module, runtime: runtime, outputObjectPath: objectPath, interner: interner)
        XCTAssertTrue(FileManager.default.fileExists(atPath: objectPath))
    }

    // MARK: - Private Helpers

    func runCodegenPipeline(inputPath: String, moduleName: String, emit: EmitMode, outputPath: String) throws -> CompilationContext {
        let ctx = makeCompilationContext(
            inputs: [inputPath],
            moduleName: moduleName,
            emit: emit,
            outputPath: outputPath
        )
        try runToKIR(ctx)
        try LoweringPhase().run(ctx)
        try CodegenPhase().run(ctx)
        return ctx
    }

    func assertDeterministicCodegenOutput(source: String, emit: EmitMode) throws {
        try withTemporaryFile(contents: source) { path in
            let fm = FileManager.default
            let workDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try fm.createDirectory(at: workDir, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: workDir) }

            let artifactBase1 = workDir.appendingPathComponent("deterministic_1").path
            let artifactBase2 = workDir.appendingPathComponent("deterministic_2").path
            var first = try readCodegenArtifact(inputPath: path, emit: emit, outputPath: artifactBase1)
            var second = try readCodegenArtifact(inputPath: path, emit: emit, outputPath: artifactBase2)
            if emit == .llvmIR {
                first = stripPathDependentLines(first)
                second = stripPathDependentLines(second)
            }
            if emit == .object {
                first = stripPathDependentBytes(first, outputPath: artifactBase1)
                second = stripPathDependentBytes(second, outputPath: artifactBase2)
            }
            XCTAssertEqual(first, second)
        }
    }

    func stripPathDependentBytes(_ data: Data, outputPath: String) -> Data {
        var result = data

        // 1. Synthetic C backend: strip the hash in "kswiftk_codegen_<hash>.c" paths
        //    embedded by clang in the object file's string table.
        let prefix = "kswiftk_codegen_"
        if let prefixData = prefix.data(using: .utf8) {
            var searchStart = result.startIndex
            while let range = result.range(of: prefixData, in: searchStart..<result.endIndex) {
                let hashStart = range.upperBound
                var hashEnd = hashStart
                while hashEnd < result.endIndex {
                    let byte = result[hashEnd]
                    if byte == 0x2E || byte == 0x00 { break }
                    hashEnd = result.index(after: hashEnd)
                }
                for i in hashStart..<hashEnd { result[i] = 0x30 }
                searchStart = hashEnd
            }
        }

        // 2. LLVM C API backend: LLVM embeds the output path itself in the object file
        //    (e.g. the basename "deterministic_1" in Mach-O STABS / ELF debug sections).
        //    Replace every occurrence of the output path with a fixed placeholder so that
        //    two compilations with different paths produce identical bytes.
        let outputBasename = (outputPath as NSString).lastPathComponent
        let placeholder = "deterministic_X"
        if outputBasename != placeholder,
           let pathData = outputBasename.data(using: .utf8),
           let fixedData = placeholder.data(using: .utf8) {
            var searchStart = result.startIndex
            while let range = result.range(of: pathData, in: searchStart..<result.endIndex) {
                result.replaceSubrange(range, with: fixedData)
                searchStart = result.index(range.lowerBound, offsetBy: fixedData.count)
            }
        }

        return result
    }

    func stripPathDependentLines(_ data: Data) -> Data {
        guard let text = String(data: data, encoding: .utf8) else { return data }
        let filtered = text.components(separatedBy: "\n").filter { line in
            !line.hasPrefix("source_filename = ") && !line.hasPrefix("; ModuleID = ")
        }
        return Data(filtered.joined(separator: "\n").utf8)
    }

    func readCodegenArtifact(inputPath: String, emit: EmitMode, outputPath: String) throws -> Data {
        let ctx = try runCodegenPipeline(
            inputPath: inputPath,
            moduleName: "Determinism",
            emit: emit,
            outputPath: outputPath
        )

        let artifactPath: String
        switch emit {
        case .kirDump:
            artifactPath = outputPath + ".kir"
        case .llvmIR:
            artifactPath = try XCTUnwrap(ctx.generatedLLVMIRPath)
        case .object:
            artifactPath = try XCTUnwrap(ctx.generatedObjectPath)
        default:
            XCTFail("unsupported emit for determinism test: \(emit)")
            artifactPath = outputPath
        }
        return try Data(contentsOf: URL(fileURLWithPath: artifactPath))
    }

    func makeComplexKIRModule(interner: StringInterner) -> KIRModule {
        let arena = KIRArena()

        let mainSym = SymbolID(rawValue: 1)
        let calleeSym = SymbolID(rawValue: 2)

        let e0 = arena.appendExpr(.intLiteral(10))
        let e1 = arena.appendExpr(.intLiteral(3))
        let e2 = arena.appendExpr(.boolLiteral(true))
        let e3 = arena.appendExpr(.stringLiteral(interner.intern("hello\\n\"world\"")))
        let e4 = arena.appendExpr(.symbolRef(calleeSym))
        let e5 = arena.appendExpr(.temporary(5))
        let e6 = arena.appendExpr(.temporary(6))
        let e7 = arena.appendExpr(.temporary(7))
        let e8 = arena.appendExpr(.temporary(8))
        let e9 = arena.appendExpr(.unit)
        let eFalse = arena.appendExpr(.boolLiteral(false))

        let callee = KIRFunction(
            symbol: calleeSym,
            name: interner.intern("callee"),
            params: [],
            returnType: TypeSystem().unitType,
            body: [.returnUnit],
            isSuspend: false,
            isInline: false
        )

        let main = KIRFunction(
            symbol: mainSym,
            name: interner.intern("1-main"),
            params: [],
            returnType: TypeSystem().unitType,
            body: [
                .nop,
                .beginBlock,
                .constValue(result: e0, value: .intLiteral(10)),
                .constValue(result: e1, value: .intLiteral(3)),
                .constValue(result: e2, value: .boolLiteral(true)),
                .constValue(result: e3, value: .stringLiteral(interner.intern("hello\\n\"world\""))),
                .constValue(result: e4, value: .symbolRef(calleeSym)),
                .constValue(result: e5, value: .temporary(99)),
                .constValue(result: e9, value: .unit),
                .binary(op: .add, lhs: e0, rhs: e1, result: e5),
                .binary(op: .subtract, lhs: e0, rhs: e1, result: e6),
                .binary(op: .multiply, lhs: e0, rhs: e1, result: e7),
                .binary(op: .divide, lhs: e0, rhs: e1, result: e8),
                .binary(op: .equal, lhs: e0, rhs: e1, result: e5),
                .call(symbol: nil, callee: interner.intern("println"), arguments: [e3], result: e5, canThrow: false, thrownResult: nil),
                .call(symbol: nil, callee: interner.intern("kk_println_any"), arguments: [e3], result: nil, canThrow: false, thrownResult: nil),
                .call(symbol: nil, callee: interner.intern("kk_op_add"), arguments: [e0, e1], result: e5, canThrow: false, thrownResult: nil),
                .call(symbol: nil, callee: interner.intern("kk_op_sub"), arguments: [e0, e1], result: e6, canThrow: false, thrownResult: nil),
                .call(symbol: nil, callee: interner.intern("kk_op_mul"), arguments: [e0, e1], result: e7, canThrow: false, thrownResult: nil),
                .call(symbol: nil, callee: interner.intern("kk_op_div"), arguments: [e0, e1], result: e8, canThrow: false, thrownResult: nil),
                .call(symbol: nil, callee: interner.intern("kk_op_eq"), arguments: [e0, e1], result: e5, canThrow: false, thrownResult: nil),
                .constValue(result: eFalse, value: .boolLiteral(false)),
                .jumpIfEqual(lhs: e2, rhs: eFalse, target: 800),
                .copy(from: e0, to: e5),
                .jump(801),
                .label(800),
                .copy(from: e1, to: e5),
                .label(801),
                .call(symbol: calleeSym, callee: interner.intern("ignored"), arguments: [], result: e5, canThrow: false, thrownResult: nil),
                .returnValue(e5),
                .endBlock
            ],
            isSuspend: false,
            isInline: false
        )

        let mainID = arena.appendDecl(.function(main))
        _ = arena.appendDecl(.global(KIRGlobal(symbol: mainSym, type: TypeSystem().anyType)))
        _ = arena.appendDecl(.nominalType(KIRNominalType(symbol: mainSym)))
        _ = arena.appendDecl(.function(callee))

        return KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainID])], arena: arena)
    }

}
