import Foundation

public final class LLVMCAPIBackend: CodegenBackend {
    private let target: TargetTriple
    private let optLevel: OptimizationLevel
    private let debugInfo: Bool
    private let diagnostics: DiagnosticEngine
    private let isStrictMode: Bool
    private let bindings: LLVMCAPIBindings?
    private let hasUsableBindings: Bool

    public init(
        target: TargetTriple,
        optLevel: OptimizationLevel,
        debugInfo: Bool,
        diagnostics: DiagnosticEngine,
        isStrictMode: Bool = false
    ) {
        self.target = target
        self.optLevel = optLevel
        self.debugInfo = debugInfo
        self.diagnostics = diagnostics
        self.isStrictMode = isStrictMode

        let loadedBindings = LLVMCAPIBindings.load()
        self.bindings = loadedBindings
        self.hasUsableBindings = loadedBindings?.smokeTestContextLifecycle() == true
    }

    public func emitObject(
        module: KIRModule,
        runtime: RuntimeLinkInfo,
        outputObjectPath: String,
        interner: StringInterner,
        sourceManager: SourceManager? = nil
    ) throws {
        _ = runtime
        try emitNative(
            context: "object",
            nativeEmit: { bindings in
                let emitter = NativeEmitter(
                    target: target,
                    optLevel: optLevel,
                    debugInfo: debugInfo,
                    bindings: bindings,
                    module: module,
                    interner: interner,
                    sourceManager: sourceManager
                )
                try emitter.emitObject(outputPath: outputObjectPath)
            }
        )
    }

    public func emitLLVMIR(
        module: KIRModule,
        runtime: RuntimeLinkInfo,
        outputIRPath: String,
        interner: StringInterner,
        sourceManager: SourceManager? = nil
    ) throws {
        _ = runtime
        try emitNative(
            context: "LLVM IR",
            nativeEmit: { bindings in
                let emitter = NativeEmitter(
                    target: target,
                    optLevel: optLevel,
                    debugInfo: debugInfo,
                    bindings: bindings,
                    module: module,
                    interner: interner,
                    sourceManager: sourceManager
                )
                try emitter.emitLLVMIR(outputPath: outputIRPath)
            }
        )
    }

    private func emitNative(
        context: String,
        nativeEmit: (LLVMCAPIBindings) throws -> Void
    ) throws {
        guard let bindings, hasUsableBindings else {
            if isStrictMode {
                diagnostics.error(
                    "KSWIFTK-BACKEND-1003",
                    "LLVM C API backend is requested in strict mode, but LLVM C API bindings are unavailable.",
                    range: nil
                )
                throw LLVMCAPIBackendError.bindingsUnavailable
            }
            diagnostics.error(
                "KSWIFTK-BACKEND-1007",
                "LLVM C API backend is requested, but LLVM C API bindings are unavailable and fallback backend is disabled.",
                range: nil
            )
            throw LLVMCAPIBackendError.bindingsUnavailable
        }

        do {
            try nativeEmit(bindings)
        } catch {
            let reason = describe(error: error)
            if isStrictMode {
                diagnostics.error(
                    "KSWIFTK-BACKEND-1004",
                    "LLVM C API backend failed to emit \(context) in strict mode: \(reason)",
                    range: nil
                )
                throw LLVMCAPIBackendError.nativeEmissionFailed(reason)
            }
            diagnostics.error(
                "KSWIFTK-BACKEND-1006",
                "LLVM C API backend failed to emit \(context): \(reason)",
                range: nil
            )
            throw LLVMCAPIBackendError.nativeEmissionFailed(reason)
        }
    }

    private func describe(error: Error) -> String {
        if let backendError = error as? LLVMCAPIBackendError {
            switch backendError {
            case .bindingsUnavailable:
                return "backend unavailable"
            case .nativeEmissionFailed(let reason):
                return reason
            }
        }
        return String(describing: error)
    }
}

enum LLVMCAPIBackendError: Error {
    case bindingsUnavailable
    case nativeEmissionFailed(String)
}
