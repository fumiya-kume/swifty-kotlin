import Foundation

public final class CodegenPhase: CompilerPhase {
    public static let name = "Codegen"

    public init() {}

    public func run(_ ctx: CompilationContext) throws {
        guard let kir = ctx.kir else {
            throw CompilerPipelineError.invalidInput("KIR not available for codegen.")
        }
        let fileFacadeNamesByFileID = CodegenSymbolSupport.fileFacadeNames(from: ctx.ast)

        if ctx.options.emit == .kirDump {
            let path = outputPath(base: ctx.options.outputPath, defaultExtension: "kir")
            let dump = kir.dump(interner: ctx.interner, symbols: ctx.sema?.symbols)
            do {
                try dump.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
                return
            } catch {
                throw CompilerPipelineError.outputUnavailable
            }
        }

        let runtime = RuntimeLinkInfo(
            libraryPaths: ctx.options.libraryPaths,
            libraries: ctx.options.linkLibraries,
            extraObjects: []
        )
        let backend = try makeBackend(ctx: ctx)

        do {
            switch ctx.options.emit {
            case .llvmIR:
                let path = outputPath(base: ctx.options.outputPath, defaultExtension: "ll")
                try backend.emitLLVMIR(
                    module: kir,
                    runtime: runtime,
                    outputIRPath: path,
                    interner: ctx.interner,
                    sourceManager: ctx.sourceManager,
                    fileFacadeNamesByFileID: fileFacadeNamesByFileID
                )
                ctx.generatedLLVMIRPath = path

            case .object:
                let path = outputPath(base: ctx.options.outputPath, defaultExtension: "o")
                try backend.emitObject(
                    module: kir,
                    runtime: runtime,
                    outputObjectPath: path,
                    interner: ctx.interner,
                    sourceManager: ctx.sourceManager,
                    fileFacadeNamesByFileID: fileFacadeNamesByFileID
                )
                ctx.generatedObjectPath = path

            case .executable:
                let path = executableObjectPath(base: ctx.options.outputPath)
                try backend.emitObject(
                    module: kir,
                    runtime: runtime,
                    outputObjectPath: path,
                    interner: ctx.interner,
                    sourceManager: ctx.sourceManager,
                    fileFacadeNamesByFileID: fileFacadeNamesByFileID
                )
                ctx.generatedObjectPath = path

            case .library:
                try emitLibrary(module: kir, backend: backend, runtime: runtime, ctx: ctx)

            case .kirDump:
                break
            }
        } catch {
            throw CompilerPipelineError.outputUnavailable
        }
    }

    private func outputPath(base: String, defaultExtension: String) -> String {
        let fileURL = URL(fileURLWithPath: base)
        if fileURL.pathExtension.isEmpty {
            return fileURL.appendingPathExtension(defaultExtension).path
        }
        return base
    }

    private func executableObjectPath(base: String) -> String {
        // Keep the linker output path and the intermediate object path distinct,
        // even when the user passes an executable filename with an extension.
        let fileURL = URL(fileURLWithPath: base)
        if fileURL.pathExtension == "o" {
            return fileURL
                .deletingPathExtension()
                .appendingPathExtension("executable")
                .appendingPathExtension("o")
                .path
        }
        return fileURL.appendingPathExtension("o").path
    }

    private func emitLibrary(
        module: KIRModule,
        backend: LLVMBackend,
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
        try backend.emitObject(
            module: module,
            runtime: runtime,
            outputObjectPath: objectPath,
            interner: ctx.interner,
            sourceManager: ctx.sourceManager,
            fileFacadeNamesByFileID: CodegenSymbolSupport.fileFacadeNames(from: ctx.ast)
        )
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

    private func makeBackend(ctx: CompilationContext) throws -> LLVMBackend {
        try LLVMBackend(
            target: ctx.options.target,
            optLevel: ctx.options.optLevel,
            debugInfo: ctx.options.debugInfo,
            diagnostics: ctx.diagnostics
        )
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
            return "call symbol=\(symbolValue) calleeB64=\(calleeName) args=[\(args)]"
                + " result=\(resultValue) canThrow=\(canThrow ? 1 : 0)"
                + " thrownResult=\(thrownResultValue) isSuperCall=\(isSuperCall ? 1 : 0)"
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
            return "virtualCall symbol=\(symbolValue) calleeB64=\(calleeName)"
                + " receiver=\(receiver.rawValue) args=[\(args)]"
                + " result=\(resultValue) canThrow=\(canThrow ? 1 : 0)"
                + " thrownResult=\(thrownResultValue) dispatch=\(dispatchStr)"
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
        case let .uintLiteral(uintValue):
            "uint:\(uintValue)"
        case let .ulongLiteral(ulongValue):
            "ulong:\(ulongValue)"
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
            let facadeNames = CodegenSymbolSupport.fileFacadeNames(from: ctx.ast)
            return kir.arena.declarations.reduce(into: [:]) { partial, decl in
                guard case let .function(function) = decl else {
                    return
                }
                partial[function.symbol] = CodegenSymbolSupport.cFunctionSymbol(
                    for: function,
                    interner: ctx.interner,
                    fileFacadeNamesByFileID: facadeNames
                )
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
