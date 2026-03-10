import Foundation

public final class LLVMBackend {
    let target: TargetTriple
    private let optLevel: OptimizationLevel
    private let debugInfo: Bool
    let diagnostics: DiagnosticEngine
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
        sourceManager: SourceManager? = nil,
        fileFacadeNamesByFileID: [Int32: String] = [:]
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
                    sourceManager: sourceManager,
                    fileFacadeNamesByFileID: fileFacadeNamesByFileID
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
        sourceManager: SourceManager? = nil,
        fileFacadeNamesByFileID: [Int32: String] = [:]
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
                    sourceManager: sourceManager,
                    fileFacadeNamesByFileID: fileFacadeNamesByFileID
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

    static let builtinOps: [String: String] = [
        "kk_op_add": "+", "kk_op_sub": "-", "kk_op_mul": "*", "kk_op_div": "/", "kk_op_mod": "%",
        "kk_op_eq": "==", "kk_op_ne": "!=", "kk_op_lt": "<", "kk_op_le": "<=", "kk_op_gt": ">", "kk_op_ge": ">=",
        "kk_op_and": "&&", "kk_op_or": "||",
    ]
    static let unsignedBuiltinOps: Set<String> = [
        "kk_op_uadd", "kk_op_usub", "kk_op_umul", "kk_op_udiv", "kk_op_umod",
    ]
    static let unaryBuiltinOps: [String: String] = [
        "kk_op_not": "!", "kk_op_inv": "~", "kk_op_pos": "+", "kk_op_neg": "-",
    ]
    static let floatBuiltinOps: Set<String> = [
        "kk_op_fadd", "kk_op_fsub", "kk_op_fmul", "kk_op_fdiv", "kk_op_fmod",
        "kk_op_feq", "kk_op_fne", "kk_op_flt", "kk_op_fle", "kk_op_fgt", "kk_op_fge",
    ]
    static let doubleBuiltinOps: Set<String> = [
        "kk_op_dadd", "kk_op_dsub", "kk_op_dmul", "kk_op_ddiv", "kk_op_dmod",
        "kk_op_deq", "kk_op_dne", "kk_op_dlt", "kk_op_dle", "kk_op_dgt", "kk_op_dge",
    ]
}

enum LLVMBackendError: Error {
    case bindingsUnavailable
    case nativeEmissionFailed(String)
}
