#if canImport(Testing)
@testable import CompilerBackend
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct LLVMOptimizationPipelineTests {
    @Test(arguments: [1, 2, 3])
    func optimizedIREliminatesTemporaryStackSlots(optimization: Int) throws {
        let level = try #require(OptimizationLevel(rawValue: optimization))
        let source = """
        fun answer(): Int {
            var result = 20
            result = result + 22
            return result
        }
        """
        let unoptimized = try compileIR(source, level: .O0)
        let optimized = try compileIR(source, level: level)
        let hasUnoptimizedStackSlots = unoptimized.contains("alloca ")
        let hasOptimizedStackSlots = optimized.contains("alloca ")
        #expect(hasUnoptimizedStackSlots, "The probe must exercise stack-slot promotion.")
        #expect(!hasOptimizedStackSlots, "The new pass manager must eliminate temporary stack slots.")
        // ABI lowering may retain an unbox call at the return boundary. LLVM
        // must still fold the arithmetic feeding that boundary to 42.
        let foldsArithmetic = optimized.contains("ret i64 42")
            || optimized.contains("@kk_unbox_int(i64 42)")
        #expect(foldsArithmetic)
        let hasDataLayout = optimized.contains("target datalayout =")
        #expect(hasDataLayout)
    }

    @Test
    func optimizedIRRetainsFinalizedDebugMetadata() throws {
        let ir = try compileIR("fun answer(): Int = 42", level: .O2, debugInfo: true)
        #expect(ir.contains("!DICompileUnit("))
        #expect(ir.contains("isOptimized: true"))
        #expect(ir.contains("!DISubprogram("))
    }

    @Test
    func invalidIRIsRejectedBeforeRunningOptimization() throws {
        let bindings = try #require(LLVMCAPIBindings.loadUsable())
        let context = try #require(bindings.createContext())
        defer { bindings.disposeContext(context) }
        let module = try #require(bindings.createModule(name: "InvalidIR", context: context))
        defer { bindings.disposeModule(module) }
        let integerType = try #require(bindings.int64Type(context: context))
        let functionType = try #require(bindings.functionType(returnType: integerType, parameters: [], isVarArg: false))
        let function = try #require(bindings.addFunction(module: module, name: "missingTerminator", functionType: functionType))
        _ = try #require(bindings.appendBasicBlock(context: context, function: function, name: "entry"))
        try CodegenCriticalSection.withLinuxLLVMProcessLock(target: defaultTargetTriple()) {
            let triple = try #require(bindings.defaultTargetTriple())
            let machine = try #require(bindings.createTargetMachine(triple: triple, optLevel: .O2))
            defer { bindings.disposeTargetMachine(machine) }
            bindings.setTarget(module, triple: triple)
            #expect(bindings.applyTargetMachine(machine, to: module))
            let message = try #require(bindings.optimizeModule(module, targetMachine: machine, optLevel: .O2))
            #expect(message.contains("Invalid LLVM IR before optimization"))
            #expect(message.contains("terminator"))
            // Debug emission retains the existing O0 path.
            #expect(bindings.optimizeModule(module, targetMachine: machine, optLevel: .O0) == nil)
        }
    }

    @Test
    func invalidPipelineReportsLLVMErrorAndSubsequentOptimizationSucceeds() throws {
        let bindings = try #require(LLVMCAPIBindings.loadUsable())
        let context = try #require(bindings.createContext())
        defer { bindings.disposeContext(context) }
        let module = try #require(bindings.createModule(name: "PassErrors", context: context))
        defer { bindings.disposeModule(module) }
        try CodegenCriticalSection.withLinuxLLVMProcessLock(target: defaultTargetTriple()) {
            let triple = try #require(bindings.defaultTargetTriple())
            let machine = try #require(bindings.createTargetMachine(triple: triple, optLevel: .O2))
            defer { bindings.disposeTargetMachine(machine) }
            bindings.setTarget(module, triple: triple)
            #expect(bindings.applyTargetMachine(machine, to: module))

            let message = try #require(bindings.runPassPipeline(
                "kswiftk-invalid-pass", module: module, targetMachine: machine
            ))
            #expect(message.contains("kswiftk-invalid-pass"))
            #expect(bindings.optimizeModule(module, targetMachine: machine, optLevel: .O2) == nil)
        }
    }

    private func compileIR(_ source: String, level: OptimizationLevel, debugInfo: Bool = false) throws -> String {
        var ir = ""
        try withTemporaryFile(contents: source) { path in
            let outputPath = FileManager.default.temporaryDirectory
                .appendingPathComponent("optimization-\(UUID().uuidString).ll").path
            defer { try? FileManager.default.removeItem(atPath: outputPath) }
            let options = CompilerOptions(
                moduleName: "OptimizationProbe", inputs: [path], outputPath: outputPath,
                emit: .llvmIR, target: defaultTargetTriple(), optLevel: level,
                debugInfo: debugInfo, includeStdlib: false
            )
            let context = CompilationContext(
                options: options, sourceManager: SourceManager(),
                diagnostics: DiagnosticEngine(), interner: StringInterner()
            )
            try runToKIR(context)
            try LoweringPhase().run(context)
            try CodegenPhase().run(context)
            let generatedPath = try #require(context.generatedLLVMIRPath)
            ir = try String(contentsOfFile: generatedPath, encoding: .utf8)
        }
        return ir
    }
}
#endif
