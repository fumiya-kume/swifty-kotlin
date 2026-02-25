import Foundation

public struct RuntimeLinkInfo {
    public let libraryPaths: [String]
    public let libraries: [String]
    public let extraObjects: [String]

    public init(libraryPaths: [String], libraries: [String], extraObjects: [String]) {
        self.libraryPaths = libraryPaths
        self.libraries = libraries
        self.extraObjects = extraObjects
    }
}

public final class LLVMBackend {
    let target: TargetTriple
    let optLevel: OptimizationLevel
    let debugInfo: Bool
    let diagnostics: DiagnosticEngine

    /// Optional phase timer for recording subprocess wall-clock durations.
    var phaseTimer: PhaseTimer?

    /// Process-wide cache for the pre-compiled runtime stub object.
    /// Key: target triple string, Value: path to the cached .o file.
    private static var runtimeStubCache: [String: String] = [:]
    private static let runtimeStubLock = NSLock()

    public init(
        target: TargetTriple,
        optLevel: OptimizationLevel,
        debugInfo: Bool,
        diagnostics: DiagnosticEngine
    ) {
        self.target = target
        self.optLevel = optLevel
        self.debugInfo = debugInfo
        self.diagnostics = diagnostics
    }

    @available(*, deprecated, message: "Use init(target:optLevel:debugInfo:diagnostics:) instead.")
    public convenience init(
        target: TargetTriple,
        optLevel: OptimizationLevel,
        emitsDebugInfo: Bool,
        diagnostics: DiagnosticEngine
    ) {
        self.init(
            target: target,
            optLevel: optLevel,
            debugInfo: emitsDebugInfo,
            diagnostics: diagnostics
        )
    }

    public func emitObject(
        module: KIRModule,
        runtime: RuntimeLinkInfo,
        outputObjectPath: String,
        interner: StringInterner,
        sourceManager: SourceManager? = nil
    ) throws {
        try compileWithClang(
            module: module, interner: interner,
            extraArgs: ["-c"],
            outputPath: outputObjectPath,
            errorCode: "KSWIFTK-BACKEND-0001",
            errorContext: "object output"
        )
    }

    /// Returns the path to the cached runtime stub `.o` if available,
    /// for use by the link phase as an additional link input.
    public func runtimeStubPath() -> String? {
        return cachedRuntimeStubPath()
    }

    public func emitLLVMIR(
        module: KIRModule,
        runtime: RuntimeLinkInfo,
        outputIRPath: String,
        interner: StringInterner,
        sourceManager: SourceManager? = nil
    ) throws {
        try compileWithClang(
            module: module, interner: interner,
            extraArgs: ["-S", "-emit-llvm"],
            outputPath: outputIRPath,
            errorCode: "KSWIFTK-BACKEND-0002",
            errorContext: "LLVM IR output"
        )
    }

    /// Returns the path to a pre-compiled runtime stub `.o` for the current
    /// target triple, compiling it on first access and caching the result for
    /// subsequent compilations within the same process.
    func cachedRuntimeStubPath() -> String? {
        let triple = targetTripleString()
        let source = cRuntimePreamble().joined(separator: "\n")
        let cacheKey = Self.stableFNV1a64Hex(triple + "_" + Self.stableFNV1a64Hex(source))

        Self.runtimeStubLock.lock()
        defer { Self.runtimeStubLock.unlock() }

        if let cached = Self.runtimeStubCache[triple],
           FileManager.default.fileExists(atPath: cached) {
            return cached
        }

        let stubDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kswiftk_rt_stubs")
        try? FileManager.default.createDirectory(at: stubDir, withIntermediateDirectories: true)

        let stubSource = stubDir.appendingPathComponent("kk_runtime_\(cacheKey).c")
        let stubObject = stubDir.appendingPathComponent("kk_runtime_\(cacheKey).o")

        if FileManager.default.fileExists(atPath: stubObject.path) {
            Self.runtimeStubCache[triple] = stubObject.path
            return stubObject.path
        }
        do {
            try source.write(to: stubSource, atomically: true, encoding: .utf8)
            let clangPath = CommandRunner.resolveExecutable("clang", fallback: "/usr/bin/clang")
            var args = ["-x", "c", "-std=c11", "-c", stubSource.path, "-o", stubObject.path]
            args.append(contentsOf: clangTargetArgs())
            _ = try CommandRunner.run(
                executable: clangPath,
                arguments: args,
                phaseTimer: phaseTimer,
                subPhaseName: "Codegen/clang-stub"
            )
            Self.runtimeStubCache[triple] = stubObject.path
            return stubObject.path
        } catch {
            return nil
        }
    }

    private func compileWithClang(
        module: KIRModule,
        interner: StringInterner,
        extraArgs: [String],
        outputPath: String,
        errorCode: String,
        errorContext: String
    ) throws {
        let isIRDump = extraArgs.contains("-S") || extraArgs.contains("-emit-llvm")
        let runtimeStub = isIRDump ? nil : cachedRuntimeStubPath()
        let source = emitCModule(module: module, interner: interner, useExternRuntime: runtimeStub != nil)
        let sourceURL = deterministicTempSourceURL(outputPath: outputPath)
        defer {
            try? FileManager.default.removeItem(at: sourceURL)
        }

        do {
            try source.write(to: sourceURL, atomically: false, encoding: .utf8)
            var args = ["-x", "c", "-std=c11"] + extraArgs
            if debugInfo {
                args.append("-g")
            }
            args.append(contentsOf: [sourceURL.path])
            args.append(contentsOf: ["-o", outputPath])
            args.append(contentsOf: clangTargetArgs())
            let clangPath = CommandRunner.resolveExecutable("clang", fallback: "/usr/bin/clang")
            _ = try CommandRunner.run(
                executable: clangPath,
                arguments: args,
                phaseTimer: phaseTimer,
                subPhaseName: "Codegen/clang"
            )
        } catch let error as CommandRunnerError {
            reportBackendError(
                code: errorCode,
                message: "clang failed while emitting \(errorContext): \(outputPath)",
                error: error
            )
            throw error
        } catch {
            diagnostics.error(
                errorCode,
                "Failed to emit \(errorContext): \(outputPath)",
                range: nil
            )
            throw error
        }
    }

    private func deterministicTempSourceURL(outputPath: String) -> URL {
        let key = Self.stableFNV1a64Hex(outputPath)
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("kswiftk_codegen_\(key)")
            .appendingPathExtension("c")
    }

    static func stableFNV1a64Hex(_ value: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(hash, radix: 16)
    }

    static let builtinOps: [String: String] = [
        "kk_op_add": "+",
        "kk_op_sub": "-",
        "kk_op_mul": "*",
        "kk_op_div": "/",
        "kk_op_mod": "%",
        "kk_op_eq": "==",
        "kk_op_ne": "!=",
        "kk_op_lt": "<",
        "kk_op_le": "<=",
        "kk_op_gt": ">",
        "kk_op_ge": ">=",
        "kk_op_and": "&&",
        "kk_op_or": "||",
        // Bitwise/shift (P5-103)
        "kk_bitwise_and": "&",
        "kk_bitwise_or": "|",
        "kk_bitwise_xor": "^",
        "kk_op_shl": "<<",
        "kk_op_shr": ">>",
    ]

    /// Unary builtin ops: function name → C prefix operator (P5-103)
    static let unaryBuiltinOps: [String: String] = [
        "kk_op_inv": "~",
    ]

    static let floatBuiltinOps: Set<String> = [
        "kk_op_fadd", "kk_op_fsub", "kk_op_fmul", "kk_op_fdiv", "kk_op_fmod",
        "kk_op_feq", "kk_op_fne", "kk_op_flt", "kk_op_fle", "kk_op_fgt", "kk_op_fge"
    ]

    static let doubleBuiltinOps: Set<String> = [
        "kk_op_dadd", "kk_op_dsub", "kk_op_dmul", "kk_op_ddiv", "kk_op_dmod",
        "kk_op_deq", "kk_op_dne", "kk_op_dlt", "kk_op_dle", "kk_op_dgt", "kk_op_dge"
    ]

    public static func cFunctionSymbol(for function: KIRFunction, interner: StringInterner) -> String {
        let rawName = interner.resolve(function.name)
        let safeName = sanitizeForCSymbol(rawName)
        let suffix = abs(function.symbol.rawValue)
        return "kk_fn_\(safeName)_\(suffix)"
    }

    private func targetTripleString() -> String {
        if let osVersion = target.osVersion, !osVersion.isEmpty {
            return "\(target.arch)-\(target.vendor)-\(target.os)\(osVersion)"
        }
        return "\(target.arch)-\(target.vendor)-\(target.os)"
    }

    private func emitCModule(module: KIRModule, interner: StringInterner, useExternRuntime: Bool = false) -> String {
        let functions: [KIRFunction] = module.arena.declarations.compactMap { decl in
            guard case .function(let function) = decl else {
                return nil
            }
            return function
        }
        let globals: [KIRGlobal] = module.arena.declarations.compactMap { decl in
            guard case .global(let global) = decl else {
                return nil
            }
            return global
        }.sorted(by: { lhs, rhs in
            lhs.symbol.rawValue < rhs.symbol.rawValue
        })
        let globalValueSymbols: [SymbolID: String] = globals.reduce(into: [:]) { partial, global in
            partial[global.symbol] = globalSlotSymbol(for: global.symbol)
        }
        let functionSymbols: [SymbolID: String] = functions.reduce(into: [:]) { acc, function in
            acc[function.symbol] = Self.cFunctionSymbol(for: function, interner: interner)
        }
        let frameMapPlans: [SymbolID: FrameMapPlan] = functions.reduce(into: [:]) { plans, function in
            plans[function.symbol] = buildFrameMapPlan(function: function)
        }
        let externalCallees = collectExternalCallees(module: module, interner: interner, functionSymbols: functionSymbols)

        var lines: [String]
        if useExternRuntime {
            lines = cRuntimeExternDeclarations()
        } else {
            lines = cRuntimePreamble()
        }

        for global in globals {
            lines.append("static intptr_t \(globalSlotSymbol(for: global.symbol)) = 0;")
        }
        if !globals.isEmpty {
            lines.append("static void kk_register_module_globals(void) __attribute__((constructor));")
            lines.append("static void kk_unregister_module_globals(void) __attribute__((destructor));")
            lines.append("static void kk_register_module_globals(void) {")
            for global in globals {
                let slotSymbol = globalSlotSymbol(for: global.symbol)
                lines.append("  kk_register_global_root((void**)&\(slotSymbol));")
            }
            lines.append("}")
            lines.append("static void kk_unregister_module_globals(void) {")
            for global in globals {
                let slotSymbol = globalSlotSymbol(for: global.symbol)
                lines.append("  kk_unregister_global_root((void**)&\(slotSymbol));")
            }
            lines.append("}")
        }
        if !globals.isEmpty {
            lines.append("")
        }

        for callee in externalCallees {
            lines.append("extern intptr_t \(callee)();")
        }
        if !externalCallees.isEmpty {
            lines.append("")
        }

        for function in functions {
            let framePlan = frameMapPlans[function.symbol] ?? .empty
            let frameMapSymbol = frameMapDescriptorSymbol(for: function)
            if framePlan.rootCount > 0 {
                let offsetsSymbol = frameMapOffsetsSymbol(for: function)
                let offsetsText = framePlan.rootOffsets.map(String.init).joined(separator: ", ")
                lines.append("static const int32_t \(offsetsSymbol)[] = { \(offsetsText) };")
                lines.append("static const KKFrameMapDescriptor \(frameMapSymbol) = { \(framePlan.rootCount)u, \(offsetsSymbol) };")
            } else {
                lines.append("static const KKFrameMapDescriptor \(frameMapSymbol) = { 0u, NULL };")
            }
        }
        lines.append("")

        if !functions.isEmpty {
            lines.append("static void kk_register_module_frame_maps(void) __attribute__((constructor));")
            lines.append("static void kk_unregister_module_frame_maps(void) __attribute__((destructor));")
            lines.append("static void kk_register_module_frame_maps(void) {")
            for function in functions {
                let functionID = max(0, Int(function.symbol.rawValue))
                let frameMapSymbol = frameMapDescriptorSymbol(for: function)
                lines.append("  kk_register_frame_map(\(functionID)u, &\(frameMapSymbol));")
            }
            lines.append("}")
            lines.append("static void kk_unregister_module_frame_maps(void) {")
            for function in functions {
                let functionID = max(0, Int(function.symbol.rawValue))
                lines.append("  kk_register_frame_map(\(functionID)u, NULL);")
            }
            lines.append("}")
            lines.append("")
        }

        for function in functions {
            lines.append(functionPrototype(function: function, interner: interner) + ";")
        }
        lines.append("")
        lines.append("static int32_t kk_module_function_count(void) { return \(module.functionCount); }")
        lines.append("")

        for function in functions {
            lines.append(functionPrototype(function: function, interner: interner) + " {")
            lines.append(contentsOf: emitFunctionBody(
                function: function,
                frameMapPlan: frameMapPlans[function.symbol] ?? .empty,
                interner: interner,
                arena: module.arena,
                functionSymbols: functionSymbols,
                globalValueSymbols: globalValueSymbols
            ))
            lines.append("}")
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    private func functionPrototype(function: KIRFunction, interner: StringInterner) -> String {
        let symbol = Self.cFunctionSymbol(for: function, interner: interner)
        var parameters = function.params.enumerated().map { index, _ in
            "intptr_t p\(index)"
        }
        parameters.append("intptr_t* outThrown")
        return "intptr_t \(symbol)(\(parameters.joined(separator: ", ")))"
    }

    private func collectExternalCallees(
        module: KIRModule,
        interner: StringInterner,
        functionSymbols: [SymbolID: String]
    ) -> [String] {
        var callees: Set<String> = []
        let ignored: Set<String> = [
            "println",
            "kk_println_any",
            "kk_string_concat",
            "kk_string_compareTo",
            "kk_any_to_string",
            "kk_string_from_utf8",

            "kk_coroutine_suspended",
            "kk_coroutine_continuation_new",
            "kk_coroutine_state_enter",
            "kk_coroutine_state_set_label",
            "kk_coroutine_state_exit",
            "kk_coroutine_state_set_spill",
            "kk_coroutine_state_get_spill",
            "kk_coroutine_state_set_completion",
            "kk_coroutine_state_get_completion",
            "kk_register_global_root",
            "kk_unregister_global_root",
            "kk_register_coroutine_root",
            "kk_unregister_coroutine_root",
            "kk_kxmini_run_blocking",
            "kk_kxmini_launch",
            "kk_kxmini_async",
            "kk_kxmini_async_await",
            "kk_kxmini_delay",
            "kk_array_new",
            "kk_array_get",
            "kk_array_set",
            "kk_vararg_spread_concat",
            "kk_println_long",
            "kk_println_float",
            "kk_println_double",
            "kk_println_char",
            "kk_box_long",
            "kk_box_float",
            "kk_box_double",
            "kk_box_char",
            "kk_unbox_long",
            "kk_unbox_float",
            "kk_unbox_double",
            "kk_unbox_char",
            "kk_int_to_float_bits",
            "kk_int_to_double_bits",
            "kk_float_to_double_bits",
            "delay",
            "kk_op_notnull",
            "kk_op_elvis",
            "kk_lazy_create",
            "kk_lazy_get_value",
            "kk_observable_create",
            "kk_observable_get_value",
            "kk_observable_set_value",
            "kk_vetoable_create",
            "kk_vetoable_get_value",
            "kk_vetoable_set_value",
            // Bitwise/shift (P5-103)
            "kk_bitwise_and",
            "kk_bitwise_or",
            "kk_bitwise_xor",
            "kk_op_inv",
            "kk_op_shl",
            "kk_op_shr",
            "kk_op_ushr"
        ]

        for decl in module.arena.declarations {
            guard case .function(let function) = decl else {
                continue
            }
            for instruction in function.body {
                let calleeInfo: (symbol: SymbolID?, callee: InternedString)?
                switch instruction {
                case .call(let symbol, let callee, _, _, _, _, _):
                    calleeInfo = (symbol, callee)
                case .virtualCall(let symbol, let callee, _, _, _, _, _, _):
                    calleeInfo = (symbol, callee)
                default:
                    calleeInfo = nil
                }
                guard let calleeInfo else {
                    continue
                }
                if let symbol = calleeInfo.symbol, functionSymbols[symbol] != nil {
                    continue
                }

                let calleeName = interner.resolve(calleeInfo.callee)
                guard !calleeName.isEmpty else {
                    continue
                }
                if LLVMBackend.builtinOps[calleeName] != nil {
                    continue
                }
                if LLVMBackend.unaryBuiltinOps[calleeName] != nil || calleeName == "kk_op_ushr" {
                    continue
                }
                if LLVMBackend.floatBuiltinOps.contains(calleeName) || LLVMBackend.doubleBuiltinOps.contains(calleeName) {
                    continue
                }
                if ignored.contains(calleeName) {
                    continue
                }
                callees.insert(calleeName)
            }
        }

        return callees.sorted()
    }

    private func clangTargetArgs() -> [String] {
        var triple = "\(target.arch)-\(target.vendor)-\(target.os)"
        if let version = target.osVersion, !version.isEmpty {
            triple += version
        }
        return ["-target", triple]
    }

    private func reportBackendError(code: String, message: String, error: CommandRunnerError) {
        switch error {
        case .launchFailed(let reason):
            diagnostics.error(code, "\(message). \(reason)", range: nil)
        case .nonZeroExit(let result):
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if stderr.isEmpty {
                diagnostics.error(code, "\(message). exit=\(result.exitCode)", range: nil)
            } else {
                diagnostics.error(code, "\(message). \(stderr)", range: nil)
            }
        }
    }
}
