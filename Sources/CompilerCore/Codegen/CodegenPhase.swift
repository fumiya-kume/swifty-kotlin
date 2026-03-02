import Foundation

public final class CodegenPhase: CompilerPhase {
    public static let name = "Codegen"

    private enum BackendKind {
        case syntheticC
        case llvmCAPI
    }

    private struct BackendSelection {
        let kind: BackendKind
        let isStrictMode: Bool
    }

    public init() {}

    public func run(_ ctx: CompilationContext) throws {
        guard let kir = ctx.kir else {
            throw CompilerPipelineError.invalidInput("KIR not available for codegen.")
        }

        let runtime = RuntimeLinkInfo(
            libraryPaths: ctx.options.libraryPaths,
            libraries: ctx.options.linkLibraries,
            extraObjects: []
        )
        let backend = makeBackend(ctx: ctx)

        do {
            switch ctx.options.emit {
            case .kirDump:
                let path = outputPath(base: ctx.options.outputPath, defaultExtension: "kir")
                let dump = kir.dump(interner: ctx.interner, symbols: ctx.sema?.symbols)
                try dump.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)

            case .llvmIR:
                let path = outputPath(base: ctx.options.outputPath, defaultExtension: "ll")
                try backend.emitLLVMIR(module: kir, runtime: runtime, outputIRPath: path, interner: ctx.interner, sourceManager: ctx.sourceManager)
                ctx.generatedLLVMIRPath = path

            case .object, .executable:
                let path = outputPath(base: ctx.options.outputPath, defaultExtension: "o")
                try backend.emitObject(module: kir, runtime: runtime, outputObjectPath: path, interner: ctx.interner, sourceManager: ctx.sourceManager)
                ctx.generatedObjectPath = path
                ctx.runtimeStubObjectPath = runtimeStubObjectPath(backend: backend, ctx: ctx)

            case .library:
                try emitLibrary(module: kir, backend: backend, runtime: runtime, ctx: ctx)
            }
        } catch {
            throw CompilerPipelineError.outputUnavailable
        }
    }

    /// Returns the path to a pre-compiled runtime stub `.o` that provides
    /// weak definitions for all runtime helper functions.  Both the synthetic-C
    /// backend (`LLVMBackend`) and the native LLVM-C-API backend
    /// (`LLVMCAPIBackend`) emit code that references these helpers as external
    /// symbols, so the stub must be linked regardless of which backend produced
    /// the user-code object file.
    private func runtimeStubObjectPath(backend: any CodegenBackend, ctx: CompilationContext) -> String? {
        if let llvmBackend = backend as? LLVMBackend {
            return llvmBackend.runtimeStubPath()
        }
        // For non-synthetic backends (e.g. LLVMCAPIBackend) we still need the
        // runtime stub at link time.  Create a lightweight LLVMBackend solely
        // to compile / retrieve the cached stub object.
        let stubProvider = LLVMBackend(
            target: ctx.options.target,
            optLevel: ctx.options.optLevel,
            debugInfo: ctx.options.debugInfo,
            diagnostics: ctx.diagnostics
        )
        stubProvider.phaseTimer = ctx.phaseTimer
        return stubProvider.runtimeStubPath()
    }

    private func outputPath(base: String, defaultExtension: String) -> String {
        let fileURL = URL(fileURLWithPath: base)
        if fileURL.pathExtension.isEmpty {
            return fileURL.appendingPathExtension(defaultExtension).path
        }
        return base
    }

    private func emitLibrary(
        module: KIRModule,
        backend: any CodegenBackend,
        runtime: RuntimeLinkInfo,
        ctx: CompilationContext
    ) throws {
        let fm = FileManager.default
        let outputDir = libraryOutputPath(base: ctx.options.outputPath)
        let objectsDir = outputDir + "/objects"
        let inlineDir = outputDir + "/inline-kir"

        if fm.fileExists(atPath: outputDir) {
            try fm.removeItem(atPath: outputDir)
        }
        try fm.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
        try fm.createDirectory(atPath: objectsDir, withIntermediateDirectories: true)
        try fm.createDirectory(atPath: inlineDir, withIntermediateDirectories: true)

        let objectPath = objectsDir + "/\(ctx.options.moduleName)_0.o"
        try backend.emitObject(module: module, runtime: runtime, outputObjectPath: objectPath, interner: ctx.interner, sourceManager: ctx.sourceManager)
        ctx.generatedObjectPath = objectPath

        try emitInlineKIRArtifacts(module: module, outputDir: inlineDir, ctx: ctx)

        let manifestPath = outputDir + "/manifest.json"
        let metadataPath = outputDir + "/metadata.bin"

        let targetString = "\(ctx.options.target.arch)-\(ctx.options.target.vendor)-\(ctx.options.target.os)"
        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "\(ctx.options.moduleName)",
          "kotlinLanguageVersion": "2.3.10",
          "compilerVersion": "0.1.0",
          "target": "\(targetString)",
          "objects": ["objects/\(ctx.options.moduleName)_0.o"],
          "metadata": "metadata.bin",
          "inlineKIRDir": "inline-kir"
        }
        """
        try manifest.write(to: URL(fileURLWithPath: manifestPath), atomically: true, encoding: .utf8)

        let metadata = makeMetadata(ctx: ctx)
        try metadata.write(to: URL(fileURLWithPath: metadataPath), atomically: true, encoding: .utf8)
    }

    private func makeBackend(ctx: CompilationContext) -> any CodegenBackend {
        let selection = selectedBackend(irFlags: ctx.options.irFlags, target: ctx.options.target,
                                        diagnostics: ctx.diagnostics)
        switch selection.kind {
        case .syntheticC:
            let backend = LLVMBackend(
                target: ctx.options.target,
                optLevel: ctx.options.optLevel,
                debugInfo: ctx.options.debugInfo,
                diagnostics: ctx.diagnostics
            )
            backend.phaseTimer = ctx.phaseTimer
            return backend
        case .llvmCAPI:
            return LLVMCAPIBackend(
                target: ctx.options.target,
                optLevel: ctx.options.optLevel,
                debugInfo: ctx.options.debugInfo,
                diagnostics: ctx.diagnostics,
                isStrictMode: selection.isStrictMode
            )
        }
    }

    private func selectedBackend(
        irFlags: [String], target: TargetTriple, diagnostics: DiagnosticEngine
    ) -> BackendSelection {
        var requestedBackend: String?
        var isStrictMode = false

        for flag in irFlags {
            if flag == "backend-strict" {
                isStrictMode = true
                continue
            }
            if flag.hasPrefix("backend-strict=") {
                let value = String(flag.dropFirst("backend-strict=".count))
                isStrictMode = parseStrictModeFlag(value) ?? isStrictMode
                continue
            }
            guard flag.hasPrefix("backend=") else {
                continue
            }
            requestedBackend = String(flag.dropFirst("backend=".count))
        }

        guard let requestedBackend else {
            return llvmCapiBackendUsableForDefaultSelection(target: target)
                ? BackendSelection(kind: .llvmCAPI, isStrictMode: isStrictMode)
                : BackendSelection(kind: .syntheticC, isStrictMode: false)
        }

        switch requestedBackend {
        case "synthetic-c", "synthetic":
            return BackendSelection(kind: .syntheticC, isStrictMode: false)
        case "llvm-c-api", "llvm-capi":
            return BackendSelection(kind: .llvmCAPI, isStrictMode: isStrictMode)
        default:
            diagnostics.warning("KSWIFTK-BACKEND-1002",
                                "Unknown backend '\(requestedBackend)'; falling back to synthetic C backend.",
                                range: nil)
            return BackendSelection(kind: .syntheticC, isStrictMode: false)
        }
    }

    private func parseStrictModeFlag(_ value: String) -> Bool? {
        switch value.lowercased() {
        case "1", "true", "yes", "on":
            true
        case "0", "false", "no", "off":
            false
        default:
            nil
        }
    }

    private func emitInlineKIRArtifacts(
        module: KIRModule,
        outputDir: String,
        ctx: CompilationContext
    ) throws {
        guard let sema = ctx.sema else {
            return
        }
        let mangler = NameMangler()
        for decl in module.arena.declarations {
            guard case let .function(function) = decl, function.isInline else {
                continue
            }
            guard let symbol = sema.symbols.symbol(function.symbol) else {
                continue
            }
            let mangled = mangler.mangle(
                moduleName: ctx.options.moduleName,
                symbol: symbol,
                symbols: sema.symbols,
                types: sema.types,
                nameResolver: { ctx.interner.resolve($0) }
            )
            let filePath = outputDir + "/\(mangled).kirbin"
            let bodyLines = function.body.map { instruction in
                serializeInlineInstruction(instruction, interner: ctx.interner)
            }.joined(separator: "\n")
            let paramSymbols = function.params.map { String($0.symbol.rawValue) }.joined(separator: ",")
            let content = """
            version=2
            nameB64=\(base64Encode(ctx.interner.resolve(function.name)))
            params=\(function.params.count)
            paramSymbols=\(paramSymbols)
            suspend=\(function.isSuspend)
            body:
            \(bodyLines)
            """
            try content.write(to: URL(fileURLWithPath: filePath), atomically: true, encoding: .utf8)
        }
    }

    private func serializeInlineInstruction(_ instruction: KIRInstruction, interner: StringInterner) -> String {
        switch instruction {
        case .nop:
            return "nop"
        case .beginBlock:
            return "beginBlock"
        case .endBlock:
            return "endBlock"
        case let .label(id):
            return "label id=\(id)"
        case let .jump(target):
            return "jump target=\(target)"
        case let .jumpIfEqual(lhs, rhs, target):
            return "jumpIfEqual lhs=\(lhs.rawValue) rhs=\(rhs.rawValue) target=\(target)"
        case let .constValue(result, value):
            return "const result=\(result.rawValue) value=\(serializeInlineExprKind(value, interner: interner))"
        case let .binary(op, lhs, rhs, result):
            return "binary op=\(op) lhs=\(lhs.rawValue) rhs=\(rhs.rawValue) result=\(result.rawValue)"
        case .returnUnit:
            return "returnUnit"
        case let .returnValue(value):
            return "returnValue value=\(value.rawValue)"
        case let .returnIfEqual(lhs, rhs):
            return "returnIfEqual lhs=\(lhs.rawValue) rhs=\(rhs.rawValue)"
        case let .unary(op, operand, result):
            return "unary op=\(op) operand=\(operand.rawValue) result=\(result.rawValue)"
        case let .nullAssert(operand, result):
            return "nullAssert operand=\(operand.rawValue) result=\(result.rawValue)"
        case let .call(symbol, callee, arguments, result, canThrow, thrownResult, isSuperCall):
            let args = arguments.map { String($0.rawValue) }.joined(separator: ",")
            let symbolValue = symbol.map { String($0.rawValue) } ?? "_"
            let resultValue = result.map { String($0.rawValue) } ?? "_"
            let thrownResultValue = thrownResult.map { String($0.rawValue) } ?? "_"
            let calleeName = base64Encode(interner.resolve(callee))
            return "call symbol=\(symbolValue) calleeB64=\(calleeName) args=[\(args)] result=\(resultValue) canThrow=\(canThrow ? 1 : 0) thrownResult=\(thrownResultValue) isSuperCall=\(isSuperCall ? 1 : 0)"
        case let .virtualCall(symbol, callee, receiver, arguments, result, canThrow, thrownResult, dispatch):
            let args = arguments.map { String($0.rawValue) }.joined(separator: ",")
            let symbolValue = symbol.map { String($0.rawValue) } ?? "_"
            let resultValue = result.map { String($0.rawValue) } ?? "_"
            let thrownResultValue = thrownResult.map { String($0.rawValue) } ?? "_"
            let calleeName = base64Encode(interner.resolve(callee))
            let dispatchStr = switch dispatch {
            case let .vtable(slot):
                "vtable:\(slot)"
            case let .itable(interfaceSlot, methodSlot):
                "itable:\(interfaceSlot):\(methodSlot)"
            }
            return "virtualCall symbol=\(symbolValue) calleeB64=\(calleeName) receiver=\(receiver.rawValue) args=[\(args)] result=\(resultValue) canThrow=\(canThrow ? 1 : 0) thrownResult=\(thrownResultValue) dispatch=\(dispatchStr)"
        case let .jumpIfNotNull(value, target):
            return "jumpIfNotNull value=\(value.rawValue) target=\(target)"
        case let .copy(from, to):
            return "copy from=\(from.rawValue) to=\(to.rawValue)"
        case let .storeGlobal(value, symbol):
            return "storeGlobal value=\(value.rawValue) symbol=\(symbol.rawValue)"
        case let .loadGlobal(result, symbol):
            return "loadGlobal result=\(result.rawValue) symbol=\(symbol.rawValue)"
        case let .rethrow(value):
            return "rethrow value=\(value.rawValue)"
        }
    }

    private func serializeInlineExprKind(_ value: KIRExprKind, interner: StringInterner) -> String {
        switch value {
        case let .intLiteral(intValue):
            "int:\(intValue)"
        case let .longLiteral(longValue):
            "long:\(longValue)"
        case let .floatLiteral(floatValue):
            "float:\(floatValue)"
        case let .doubleLiteral(doubleValue):
            "double:\(doubleValue)"
        case let .charLiteral(charValue):
            "char:\(charValue)"
        case let .boolLiteral(boolValue):
            "bool:\(boolValue ? 1 : 0)"
        case let .stringLiteral(text):
            "stringB64:\(base64Encode(interner.resolve(text)))"
        case let .symbolRef(symbol):
            "symbol:\(symbol.rawValue)"
        case let .temporary(raw):
            "temp:\(raw)"
        case .null:
            "null"
        case .unit:
            "unit"
        }
    }

    private func base64Encode(_ value: String) -> String {
        Data(value.utf8).base64EncodedString()
    }

    private func libraryOutputPath(base: String) -> String {
        if base.hasSuffix(".kklib") {
            return base
        }
        return base + ".kklib"
    }

    private func makeMetadata(ctx: CompilationContext) -> String {
        guard let sema = ctx.sema else {
            return "symbols=0\n"
        }
        let functionLinkNamesBySymbol: [SymbolID: String] = {
            guard let kir = ctx.kir else { return [:] }
            return kir.arena.declarations.reduce(into: [:]) { partial, decl in
                guard case let .function(function) = decl else {
                    return
                }
                partial[function.symbol] = LLVMBackend.cFunctionSymbol(for: function, interner: ctx.interner)
            }
        }()
        let encoder = MetadataEncoder()
        let records = encoder.buildRecords(
            symbols: sema.symbols,
            types: sema.types,
            moduleName: ctx.options.moduleName,
            interner: ctx.interner,
            functionLinkNames: functionLinkNamesBySymbol
        )
        return encoder.serialize(records)
    }
}
