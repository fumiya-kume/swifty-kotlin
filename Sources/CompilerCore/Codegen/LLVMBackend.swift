import Foundation

public final class LLVMBackend {
    private let target: TargetTriple
    private let optLevel: OptimizationLevel
    private let debugInfo: Bool
    private let diagnostics: DiagnosticEngine
    private let bindings: LLVMCAPIBindings

    public init(
        target: TargetTriple,
        optLevel: OptimizationLevel,
        debugInfo: Bool,
        diagnostics: DiagnosticEngine
    ) throws {
        self.target = target
        self.optLevel = optLevel
        self.debugInfo = debugInfo
        self.diagnostics = diagnostics

        guard let bindings = LLVMCAPIBindings.loadUsable() else {
            diagnostics.error(
                "KSWIFTK-BACKEND-1007",
                "LLVM backend is unavailable because the LLVM C API bindings could not be loaded.",
                range: nil
            )
            throw LLVMBackendError.bindingsUnavailable
        }
        self.bindings = bindings
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
        do {
            try nativeEmit(bindings)
        } catch {
            let reason = describe(error: error)
            diagnostics.error(
                "KSWIFTK-BACKEND-1006",
                "LLVM backend failed to emit \(context): \(reason)",
                range: nil
            )
            throw LLVMBackendError.nativeEmissionFailed(reason)
        }
    }

    private func describe(error: Error) -> String {
        if let backendError = error as? LLVMBackendError {
            switch backendError {
            case .bindingsUnavailable:
                return "backend unavailable"
            case let .nativeEmissionFailed(reason):
                return reason
            }
        }
        return String(describing: error)
    }
}

enum LLVMBackendError: Error {
    case bindingsUnavailable
    case nativeEmissionFailed(String)
}
