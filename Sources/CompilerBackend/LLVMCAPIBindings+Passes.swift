import CompilerCore

extension LLVMCAPIBindings {
    /// O0 deliberately leaves the module unchanged, including debug allocas.
    func optimizeModule(
        _ module: LLVMModuleRef,
        targetMachine: LLVMTargetMachineRef,
        optLevel: OptimizationLevel
    ) -> String? {
        guard optLevel != .O0 else { return nil }
        guard let verifyModuleFn else {
            return "LLVM optimization requires LLVMVerifyModule."
        }
        var verificationMessage: UnsafeMutablePointer<CChar>?
        // ReturnStatusAction reports invalid input without aborting the compiler.
        let invalid = verifyModuleFn(module, 2, &verificationMessage)
        defer {
            if let verificationMessage { disposeMessageFn(verificationMessage) }
        }
        if invalid != 0 {
            let message = verificationMessage.map { String(cString: $0) } ?? "unknown verifier error"
            return "Invalid LLVM IR before optimization: \(message)"
        }
        return runPassPipeline(
            "default<O\(llvmOptLevel(optLevel))>",
            module: module,
            targetMachine: targetMachine
        )
    }

    func runPassPipeline(
        _ pipeline: String,
        module: LLVMModuleRef,
        targetMachine: LLVMTargetMachineRef
    ) -> String? {
        guard let runPassesFn,
              let createPassBuilderOptionsFn,
              let disposePassBuilderOptionsFn,
              let getErrorMessageFn,
              let disposeErrorMessageFn
        else {
            return "LLVM optimization requires the new pass manager C API (LLVMRunPasses)."
        }
        guard let options = createPassBuilderOptionsFn() else {
            return "LLVMCreatePassBuilderOptions returned null."
        }
        defer { disposePassBuilderOptionsFn(options) }

        let error = pipeline.withCString {
            runPassesFn(module, $0, targetMachine, options)
        }
        guard let error else { return nil }
        // LLVMGetErrorMessage consumes the error. Its string uses a different
        // disposer from LLVMDisposeMessage and must be released exactly once.
        guard let message = getErrorMessageFn(error) else {
            return "LLVM optimization pipeline '\(pipeline)' failed."
        }
        defer { disposeErrorMessageFn(message) }
        return "LLVM optimization pipeline '\(pipeline)' failed: \(String(cString: message))"
    }
}
