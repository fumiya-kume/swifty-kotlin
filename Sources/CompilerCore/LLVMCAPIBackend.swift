import Foundation

public final class LLVMCAPIBackend: CodegenBackend {
    private let fallbackBackend: LLVMBackend
    private let diagnostics: DiagnosticEngine
    private let strictMode: Bool
    private let bindings: LLVMCAPIBindings?
    private var didWarnFallback = false

    public init(
        target: TargetTriple,
        optLevel: OptimizationLevel,
        debugInfo: Bool,
        diagnostics: DiagnosticEngine,
        strictMode: Bool = false
    ) {
        self.fallbackBackend = LLVMBackend(
            target: target,
            optLevel: optLevel,
            debugInfo: debugInfo,
            diagnostics: diagnostics
        )
        self.diagnostics = diagnostics
        self.strictMode = strictMode
        self.bindings = LLVMCAPIBindings.load()
    }

    public func emitObject(
        module: KIRModule,
        runtime: RuntimeLinkInfo,
        outputObjectPath: String,
        interner: StringInterner
    ) throws {
        try validateModeOrFallback()
        try fallbackBackend.emitObject(
            module: module,
            runtime: runtime,
            outputObjectPath: outputObjectPath,
            interner: interner
        )
    }

    public func emitLLVMIR(
        module: KIRModule,
        runtime: RuntimeLinkInfo,
        outputIRPath: String,
        interner: StringInterner
    ) throws {
        try validateModeOrFallback()
        try fallbackBackend.emitLLVMIR(
            module: module,
            runtime: runtime,
            outputIRPath: outputIRPath,
            interner: interner
        )
    }

    private func validateModeOrFallback() throws {
        guard !didWarnFallback else {
            return
        }
        didWarnFallback = true

        let hasUsableBindings = bindings?.smokeTestContextLifecycle() == true
        if strictMode {
            if !hasUsableBindings {
                diagnostics.error(
                    "KSWIFTK-BACKEND-1003",
                    "LLVM C API backend is requested in strict mode, but LLVM C API bindings are unavailable.",
                    range: nil
                )
            } else {
                diagnostics.error(
                    "KSWIFTK-BACKEND-1004",
                    "LLVM C API backend is requested in strict mode, but native emission is not implemented yet.",
                    range: nil
                )
            }
            throw LLVMCAPIBackendError.unavailableInStrictMode
        }
        if !hasUsableBindings {
            diagnostics.warning(
                "KSWIFTK-BACKEND-1001",
                "LLVM C API backend is unavailable; falling back to synthetic C backend.",
                range: nil
            )
        } else {
            diagnostics.warning(
                "KSWIFTK-BACKEND-1005",
                "LLVM C API bindings are available, but native emission is not implemented yet; falling back to synthetic C backend.",
                range: nil
            )
        }
    }
}

enum LLVMCAPIBackendError: Error {
    case unavailableInStrictMode
}
