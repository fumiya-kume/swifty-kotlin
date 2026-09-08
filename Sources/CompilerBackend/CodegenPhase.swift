import Foundation

import CompilerCore

public final class CodegenPhase: CompilerPhase {
    public static let name = "Codegen"

    public init() {}

    public func run(_ ctx: CompilationContext) throws {
        guard let kir = ctx.kir else {
            throw CompilerPipelineError.invalidInput("KIR not available for codegen.")
        }
        let fileFacadeNamesByFileID = CodegenSymbolSupport.fileFacadeNames(from: ctx.ast)
        let backend = try makeBackend(ctx: ctx)
        // REFL-004: Build runtime reflection metadata records from sema state.
        let reflectionRecords = buildReflectionMetadataRecords(ctx: ctx, fileFacadeNamesByFileID: fileFacadeNamesByFileID)

        do {
            switch ctx.options.emit {
            case .llvmIR:
                let path = outputPath(base: ctx.options.outputPath, defaultExtension: "ll")
                try backend.emitLLVMIR(
                    module: kir,
                    outputIRPath: path,
                    interner: ctx.interner,
                    typeSystem: ctx.sema?.types,
                    symbols: ctx.sema?.symbols,
                    sourceManager: ctx.sourceManager,
                    fileFacadeNamesByFileID: fileFacadeNamesByFileID,
                    reflectionMetadataRecords: reflectionRecords,
                    reflectionMetadataSymbolPrefix: ctx.options.moduleName
                )
                ctx.storeGeneratedLLVMIRPath(path)

            case .object:
                let path = outputPath(base: ctx.options.outputPath, defaultExtension: "o")
                try backend.emitObject(
                    module: kir,
                    outputObjectPath: path,
                    interner: ctx.interner,
                    typeSystem: ctx.sema?.types,
                    symbols: ctx.sema?.symbols,
                    sourceManager: ctx.sourceManager,
                    fileFacadeNamesByFileID: fileFacadeNamesByFileID,
                    reflectionMetadataRecords: reflectionRecords,
                    reflectionMetadataSymbolPrefix: ctx.options.moduleName
                )
                ctx.storeGeneratedObjectPath(path)

            case .executable:
                let path = executableObjectPath(base: ctx.options.outputPath)
                try backend.emitObject(
                    module: kir,
                    outputObjectPath: path,
                    interner: ctx.interner,
                    typeSystem: ctx.sema?.types,
                    symbols: ctx.sema?.symbols,
                    sourceManager: ctx.sourceManager,
                    fileFacadeNamesByFileID: fileFacadeNamesByFileID,
                    reflectionMetadataRecords: reflectionRecords,
                    reflectionMetadataSymbolPrefix: ctx.options.moduleName
                )
                ctx.storeGeneratedObjectPath(path)

            case .library:
                try emitLibrary(
                    module: kir,
                    backend: backend,
                    ctx: ctx,
                    reflectionMetadataRecords: reflectionRecords,
                    reflectionMetadataSymbolPrefix: ctx.options.moduleName
                )

            case .kirDump:
                return
            }
        } catch {
            if !ctx.diagnostics.hasError {
                ctx.diagnostics.error(
                    "KSWIFTK-PIPELINE-0004",
                    "Codegen phase could not emit requested output: \(error)",
                    range: nil
                )
            }
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
        ctx: CompilationContext,
        reflectionMetadataRecords: [MetadataRecord] = [],
        reflectionMetadataSymbolPrefix: String? = nil
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
        // Bundled stdlib functions appear in every source-backed compilation unit. Use
        // linkonce_odr there so the linker can deduplicate them. A stdlib artifact is the
        // provider of those symbols, however; keeping its definitions externally visible
        // prevents an O2 global-DCE pass from removing entry points that only consumers call.
        let bundledFileIDs = Set(ctx.sourceManager.fileIDs()
            .filter { ctx.sourceManager.origin(of: $0)?.isBundledStdlib == true }
            .map(\.rawValue))
        let bundledSymbolIDs: Set<SymbolID> = ctx.sema.map { sema in
            Set(sema.symbols.allSymbols()
                .filter { sym in
                    guard let declSite = sym.declSite else { return false }
                    return bundledFileIDs.contains(declSite.start.file.rawValue)
                }
                .map(\.id))
        } ?? []
        try backend.emitObject(
            module: module,
            outputObjectPath: objectPath,
            interner: ctx.interner,
            typeSystem: ctx.sema?.types,
            symbols: ctx.sema?.symbols,
            sourceManager: ctx.sourceManager,
            fileFacadeNamesByFileID: CodegenSymbolSupport.fileFacadeNames(from: ctx.ast),
            reflectionMetadataRecords: reflectionMetadataRecords,
            reflectionMetadataSymbolPrefix: reflectionMetadataSymbolPrefix,
            linkOnceODRSymbols: ctx.options.stdlibOnly ? [] : bundledSymbolIDs
        )
        ctx.storeGeneratedObjectPath(objectPath)

        try emitInlineKIRArtifacts(module: module, outputDir: inlineDir, ctx: ctx)

        let manifestPath = outputDir + "/manifest.json"
        let metadataPath = outputDir + "/metadata.bin"

        let targetString = "\(ctx.options.target.arch)-\(ctx.options.target.vendor)-\(ctx.options.target.os)"
        var manifestDict: [String: Any] = [
            "formatVersion": 1,
            "moduleName": ctx.options.moduleName,
            "kotlinLanguageVersion": "2.3.10",
            "compilerVersion": "0.1.0",
            "target": targetString,
            "objects": ["objects/\(ctx.options.moduleName)_0.o"],
            "metadata": "metadata.bin",
            "inlineKIRDir": "inline-kir"
        ]
        if ctx.options.stdlibOnly {
            manifestDict["libraryKind"] = "stdlib"
            manifestDict["stdlibManifestHash"] = BundledStdlib.manifestHash()
        }
        let manifestData = try JSONSerialization.data(withJSONObject: manifestDict, options: [.sortedKeys, .prettyPrinted])
        var manifestString = String(data: manifestData, encoding: .utf8) ?? ""
        manifestString = manifestString.replacingOccurrences(of: "\" : \"", with: "\": \"")
        try manifestString.write(to: URL(fileURLWithPath: manifestPath), atomically: true, encoding: .utf8)

        let metadata = makeMetadata(ctx: ctx, module: module)
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
        let facadeNames = CodegenSymbolSupport.fileFacadeNames(from: ctx.ast)
        var functionLinkNamesBySymbol: [SymbolID: String] = [:]
        for decl in module.arena.declarations {
            guard case let .function(function) = decl else { continue }
            functionLinkNamesBySymbol[function.symbol] = CodegenSymbolSupport.cFunctionSymbol(
                for: function,
                interner: ctx.interner,
                symbols: sema.symbols,
                fileFacadeNamesByFileID: facadeNames
            )
        }
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
            let fileName = MetadataEncoder.inlineKIRFileName(for: mangled)
            let filePath = outputDir + "/\(fileName)"
            let parameterSymbols = Set(function.params.map(\.symbol))
            let bodyLines = function.body.map { instruction in
                serializeInlineInstruction(
                    instruction,
                    interner: ctx.interner,
                    functionLinkNames: functionLinkNamesBySymbol,
                    parameterSymbols: parameterSymbols,
                    symbols: sema.symbols
                )
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

    private func serializeInlineInstruction(
        _ instruction: KIRInstruction,
        interner: StringInterner,
        functionLinkNames: [SymbolID: String],
        parameterSymbols: Set<SymbolID>,
        symbols: SymbolTable?
    ) -> String {
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
            return "const result=\(result.rawValue) value=\(serializeInlineExprKind(value, interner: interner, functionLinkNames: functionLinkNames, parameterSymbols: parameterSymbols, symbols: symbols))"
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
        case let .call(symbol, callee, arguments, result, canThrow, thrownResult, isSuperCall, qualifiedSuperType):
            let args = arguments.map { String($0.rawValue) }.joined(separator: ",")
            let symbolValue = symbol.map { String($0.rawValue) } ?? "_"
            let resultValue = result.map { String($0.rawValue) } ?? "_"
            let thrownResultValue = thrownResult.map { String($0.rawValue) } ?? "_"
            let qualifiedSuperValue = qualifiedSuperType.map { String($0.rawValue) } ?? "_"
            let calleeName = base64Encode(interner.resolve(callee))
            let linkName = symbol.flatMap { functionLinkNames[$0] ?? symbols?.externalLinkName(for: $0) } ?? ""
            let linkField = linkName.isEmpty ? "" : " linkB64=\(base64Encode(linkName))"
            let symbolFQName = symbol.flatMap {
                inlineSymbolFQName($0, interner: interner, symbols: symbols)
            }
            let symbolFQNameField = symbolFQName.map {
                " symbolFQNameB64=\(base64Encode($0))"
            } ?? ""
            return "call symbol=\(symbolValue) calleeB64=\(calleeName) args=[\(args)]"
                + " result=\(resultValue) canThrow=\(canThrow ? 1 : 0)"
                + " thrownResult=\(thrownResultValue) isSuperCall=\(isSuperCall ? 1 : 0)"
                + " qualifiedSuperType=\(qualifiedSuperValue)" + linkField + symbolFQNameField
        case let .virtualCall(symbol, callee, receiver, arguments, result, canThrow, thrownResult, dispatch):
            let args = arguments.map { String($0.rawValue) }.joined(separator: ",")
            let symbolValue = symbol.map { String($0.rawValue) } ?? "_"
            let resultValue = result.map { String($0.rawValue) } ?? "_"
            let thrownResultValue = thrownResult.map { String($0.rawValue) } ?? "_"
            let calleeName = base64Encode(interner.resolve(callee))
            let linkName = symbol.flatMap { functionLinkNames[$0] ?? symbols?.externalLinkName(for: $0) } ?? ""
            let linkField = linkName.isEmpty ? "" : " linkB64=\(base64Encode(linkName))"
            let symbolFQName = symbol.flatMap {
                inlineSymbolFQName($0, interner: interner, symbols: symbols)
            }
            let symbolFQNameField = symbolFQName.map {
                " symbolFQNameB64=\(base64Encode($0))"
            } ?? ""
            let dispatchStr = switch dispatch {
            case let .vtable(slot):
                "vtable:\(slot)"
            case let .itable(interfaceSlot, methodSlot):
                "itable:\(interfaceSlot):\(methodSlot)"
            case let .itableDynamic(interfaceTypeID, methodSlot):
                "itableDynamic:\(interfaceTypeID):\(methodSlot)"
            }
            return "virtualCall symbol=\(symbolValue) calleeB64=\(calleeName)"
                + " receiver=\(receiver.rawValue) args=[\(args)]"
                + " result=\(resultValue) canThrow=\(canThrow ? 1 : 0)"
                + " thrownResult=\(thrownResultValue) dispatch=\(dispatchStr)"
                + linkField + symbolFQNameField
        case let .jumpIfNotNull(value, target):
            return "jumpIfNotNull value=\(value.rawValue) target=\(target)"
        case let .copy(from, to):
            return "copy from=\(from.rawValue) to=\(to.rawValue)"
        case let .storeGlobal(value, symbol):
            let symbolFQName = inlineSymbolFQName(symbol, interner: interner, symbols: symbols)
            let symbolFQNameField = symbolFQName.map {
                " symbolFQNameB64=\(base64Encode($0))"
            } ?? ""
            return "storeGlobal value=\(value.rawValue) symbol=\(symbol.rawValue)" + symbolFQNameField
        case let .loadGlobal(result, symbol):
            let symbolFQName = inlineSymbolFQName(symbol, interner: interner, symbols: symbols)
            let symbolFQNameField = symbolFQName.map {
                " symbolFQNameB64=\(base64Encode($0))"
            } ?? ""
            return "loadGlobal result=\(result.rawValue) symbol=\(symbol.rawValue)" + symbolFQNameField
        case let .rethrow(value):
            return "rethrow value=\(value.rawValue)"
        case let .nonLocalReturn(value):
            if let value {
                return "nonLocalReturn value=\(value.rawValue)"
            } else {
                return "nonLocalReturnUnit"
            }
        case .beginFinallyGuard:
            return "beginFinallyGuard"
        case .endFinallyGuard:
            return "endFinallyGuard"
        }
    }

    private func serializeInlineExprKind(
        _ value: KIRExprKind,
        interner: StringInterner,
        functionLinkNames: [SymbolID: String],
        parameterSymbols: Set<SymbolID>,
        symbols: SymbolTable?
    ) -> String {
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
            if parameterSymbols.contains(symbol) {
                "symbol:\(symbol.rawValue)"
            } else if let linkName = functionLinkNames[symbol] ?? symbols?.externalLinkName(for: symbol), !linkName.isEmpty {
                "externB64:\(base64Encode(linkName))"
            } else if let fQName = inlineSymbolFQName(symbol, interner: interner, symbols: symbols) {
                "symbolFQNameB64:\(base64Encode(fQName))"
            } else {
                "symbol:\(symbol.rawValue)"
            }
        case let .externSymbolAddress(name):
            "externB64:\(base64Encode(interner.resolve(name)))"
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

    private func inlineSymbolFQName(
        _ symbol: SymbolID,
        interner: StringInterner,
        symbols: SymbolTable?
    ) -> String? {
        // Imported inline KIR is consumed by a different symbol table, so raw
        // positive IDs are not stable across library boundaries.
        guard let semanticSymbol = symbols?.symbol(symbol),
              !semanticSymbol.fqName.isEmpty
        else {
            return nil
        }
        return semanticSymbol.fqName.map { interner.resolve($0) }.joined(separator: ".")
    }

    private func libraryOutputPath(base: String) -> String {
        if base.hasSuffix(".kklib") {
            return base
        }
        return base + ".kklib"
    }

    private func makeMetadata(ctx: CompilationContext, module: KIRModule) -> String {
        guard let sema = ctx.sema else {
            return "symbols=0\n"
        }
        let facadeNames = CodegenSymbolSupport.fileFacadeNames(from: ctx.ast)
        var functionLinkNamesBySymbol: [SymbolID: String] = [:]
        var inlineFunctionSymbols: Set<SymbolID> = []
        for decl in module.arena.declarations {
            guard case let .function(function) = decl else {
                continue
            }
            functionLinkNamesBySymbol[function.symbol] = CodegenSymbolSupport.cFunctionSymbol(
                for: function,
                interner: ctx.interner,
                symbols: ctx.sema?.symbols,
                fileFacadeNamesByFileID: facadeNames
            )
            if function.isInline {
                inlineFunctionSymbols.insert(function.symbol)
            }
        }
        let bundledFileIDs = Set(ctx.sourceManager.fileIDs()
            .filter { ctx.sourceManager.origin(of: $0)?.isBundledStdlib == true }
            .map(\.rawValue))

        let excludeSourceFileIDs: Set<Int32>
        let includeSynthetic: Bool
        if ctx.options.stdlibOnly || ctx.options.stdlibLibraryPath != nil {
            excludeSourceFileIDs = []
            includeSynthetic = false
        } else {
            excludeSourceFileIDs = bundledFileIDs
            includeSynthetic = bundledFileIDs.isEmpty
        }

        let runtimeCallbackRawReturnSymbolIDs = NativeEmitter.collectRuntimeCallbackRawStringReturnSymbols(
            module: module,
            interner: ctx.interner,
            typeSystem: ctx.sema?.types,
            symbols: ctx.sema?.symbols
        )
        var objectInitializerLinkNames: [SymbolID: String] = [:]
        var companionInitializerLinkNames: [SymbolID: String] = [:]
        var enumStaticInitLinkNames: [SymbolID: String] = [:]
        for decl in module.arena.declarations {
            guard case let .function(function) = decl,
                  let linkName = functionLinkNamesBySymbol[function.symbol]
            else {
                continue
            }
            let functionName = ctx.interner.resolve(function.name)
            if let ownerID = Self.objectInitializerOwnerSymbolID(from: functionName) {
                objectInitializerLinkNames[SymbolID(rawValue: ownerID)] = linkName
            } else if let ownerID = Self.companionInitializerOwnerSymbolID(from: functionName) {
                companionInitializerLinkNames[SymbolID(rawValue: ownerID)] = linkName
            } else if let ownerID = Self.enumStaticInitOwnerSymbolID(
                from: functionName,
                symbol: function.symbol,
                sema: sema
            ) {
                enumStaticInitLinkNames[ownerID] = linkName
            }
        }

        let encoder = MetadataEncoder()
        let records = encoder.buildRecords(
            symbols: sema.symbols,
            types: sema.types,
            moduleName: ctx.options.moduleName,
            interner: ctx.interner,
            functionLinkNames: functionLinkNamesBySymbol,
            inlineFunctionSymbols: inlineFunctionSymbols,
            includeNonPublic: ctx.options.stdlibOnly,
            includeSynthetic: includeSynthetic,
            includeSyntheticNominalAnchors: ctx.options.stdlibOnly,
            excludeSourceFileIDs: excludeSourceFileIDs,
            runtimeCallbackRawReturnSymbolIDs: runtimeCallbackRawReturnSymbolIDs,
            objectInitializerLinkNames: objectInitializerLinkNames,
            companionInitializerLinkNames: companionInitializerLinkNames,
            enumStaticInitLinkNames: enumStaticInitLinkNames
        )
        return encoder.serialize(records)
    }

    // MARK: - REFL-004: Runtime Reflection Metadata

    /// Builds MetadataRecords for all declared symbols (classes, interfaces,
    /// objects, enum classes, annotation classes, and functions) from the
    /// semantic analysis state. These records are embedded as
    /// runtime-accessible binary metadata in the compiled output.
    private func buildReflectionMetadataRecords(
        ctx: CompilationContext,
        fileFacadeNamesByFileID: [Int32: String]
    ) -> [MetadataRecord] {
        guard let sema = ctx.sema else {
            return []
        }
        let (functionLinkNamesBySymbol, inlineFunctionSymbols): ([SymbolID: String], Set<SymbolID>) = {
            guard let kir = ctx.kir else { return ([:], []) }
            var linkNames: [SymbolID: String] = [:]
            var inlineSymbols: Set<SymbolID> = []
            for decl in kir.arena.declarations {
                guard case let .function(function) = decl else {
                    continue
                }
                linkNames[function.symbol] = CodegenSymbolSupport.cFunctionSymbol(
                    for: function,
                    interner: ctx.interner,
                    symbols: ctx.sema?.symbols,
                    fileFacadeNamesByFileID: fileFacadeNamesByFileID
                )
                if function.isInline {
                    inlineSymbols.insert(function.symbol)
                }
            }
            return (linkNames, inlineSymbols)
        }()
        let encoder = MetadataEncoder()
        return encoder.buildRecords(
            symbols: sema.symbols,
            types: sema.types,
            moduleName: ctx.options.moduleName,
            interner: ctx.interner,
            functionLinkNames: functionLinkNamesBySymbol,
            inlineFunctionSymbols: inlineFunctionSymbols,
            includeNonPublic: ctx.options.includeNonPublicReflectionMetadata
        )
    }

    /// Parses the owner symbol ID embedded in a synthetic top-level object
    /// initializer name (`__object_init_<objectID>_<initID>`).
    private static func objectInitializerOwnerSymbolID(from name: String) -> Int32? {
        let prefix = "__object_init_"
        guard name.hasPrefix(prefix) else { return nil }
        let suffix = String(name.dropFirst(prefix.count))
        let parts = suffix.split(separator: "_").map(String.init)
        guard let first = parts.first else { return nil }
        return Int32(first)
    }

    /// Parses the owner class symbol ID embedded in a synthetic companion
    /// object initializer name (`__companion_init_<ownerID>_<companionID>_<initID>`).
    private static func companionInitializerOwnerSymbolID(from name: String) -> Int32? {
        let prefix = "__companion_init_"
        guard name.hasPrefix(prefix) else { return nil }
        let suffix = String(name.dropFirst(prefix.count))
        let parts = suffix.split(separator: "_").map(String.init)
        guard parts.count >= 2, let ownerID = parts.first else { return nil }
        return Int32(ownerID)
    }
    /// Returns the owner enum class symbol for a synthetic enum static
    /// initializer (`__enum_static_init_<ClassName>`) by looking up the
    /// function's parent FQ name in `sema.symbols`.
    private static func enumStaticInitOwnerSymbolID(
        from name: String,
        symbol: SymbolID,
        sema: SemaModule
    ) -> SymbolID? {
        let prefix = "__enum_static_init_"
        guard name.hasPrefix(prefix) else { return nil }
        guard let functionSymbol = sema.symbols.symbol(symbol),
              functionSymbol.fqName.count >= 2
        else {
            return nil
        }
        let ownerFQName = Array(functionSymbol.fqName.dropLast())
        guard let ownerSymbol = sema.symbols.lookup(fqName: ownerFQName),
              sema.symbols.symbol(ownerSymbol)?.kind == .enumClass
        else {
            return nil
        }
        return ownerSymbol
    }
}
