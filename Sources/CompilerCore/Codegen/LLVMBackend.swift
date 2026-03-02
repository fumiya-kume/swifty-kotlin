import Foundation

public final class LLVMBackend {
    let target: TargetTriple
    let optLevel: OptimizationLevel
    let debugInfo: Bool
    let diagnostics: DiagnosticEngine

    /// Optional phase timer for recording subprocess wall-clock durations.
    var phaseTimer: PhaseTimer?

    /// Process-wide cache for the pre-compiled runtime stub object.
    /// Protected by a lock for Swift 6 concurrency compliance in synchronous APIs.
    private static let stubCache = RuntimeStubCache()

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

    public func emitObject(
        module: KIRModule,
        runtime _: RuntimeLinkInfo,
        outputObjectPath: String,
        interner: StringInterner,
        sourceManager _: SourceManager? = nil
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
        cachedRuntimeStubPath()
    }

    public func emitLLVMIR(
        module: KIRModule,
        runtime _: RuntimeLinkInfo,
        outputIRPath: String,
        interner: StringInterner,
        sourceManager _: SourceManager? = nil
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
        let stubDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kswiftk_rt_stubs")
        let context = StubCompilationContext(
            source: source,
            cacheKey: cacheKey,
            clangTargetArgs: clangTargetArgs(),
            stubDir: stubDir
        )

        return Self.stubCache.getOrInsert(triple: triple, context: context)
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
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100_0000_01B3
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
        "kk_op_not": "!",
        "kk_op_uplus": "+",
        "kk_op_uminus": "-",
        "kk_op_inv": "~",
    ]

    static let floatBuiltinOps: Set<String> = [
        "kk_op_fadd", "kk_op_fsub", "kk_op_fmul", "kk_op_fdiv", "kk_op_fmod",
        "kk_op_feq", "kk_op_fne", "kk_op_flt", "kk_op_fle", "kk_op_fgt", "kk_op_fge",
    ]

    static let doubleBuiltinOps: Set<String> = [
        "kk_op_dadd", "kk_op_dsub", "kk_op_dmul", "kk_op_ddiv", "kk_op_dmod",
        "kk_op_deq", "kk_op_dne", "kk_op_dlt", "kk_op_dle", "kk_op_dgt", "kk_op_dge",
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
            guard case let .function(function) = decl else {
                return nil
            }
            return function
        }
        let globals: [KIRGlobal] = module.arena.declarations.compactMap { decl in
            guard case let .global(global) = decl else {
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

        var lines: [String] = if useExternRuntime {
            cRuntimeExternDeclarations()
        } else {
            cRuntimePreamble()
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
        var parameters = function.params.indices.map { index in
            "intptr_t p\(index)"
        }
        parameters.append("intptr_t* outThrown")
        return "intptr_t \(symbol)(\(parameters.joined(separator: ", ")))"
    }

}
