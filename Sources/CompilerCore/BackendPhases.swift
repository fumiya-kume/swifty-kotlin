import Foundation

public final class DataFlowSemaPassPhase: CompilerPhase {
    public static let name = "DataFlowSemaPass"

    public init() {}

    public func run(_ ctx: CompilationContext) throws {
        guard let ast = ctx.ast else {
            throw CompilerPipelineError.invalidInput("No AST available for semantic analysis.")
        }

        let symbols = SymbolTable()
        let types = TypeSystem()
        let bindings = BindingTable()
        let sema = SemaModule(
            symbols: symbols,
            types: types,
            bindings: bindings,
            diagnostics: ctx.diagnostics
        )

        let rootScope = PackageScope(parent: nil, symbols: symbols)
        var fileScopes: [Int32: FileScope] = [:]

        for file in ast.files.sorted(by: { $0.fileID.rawValue < $1.fileID.rawValue }) {
            let packageSymbol = definePackageSymbol(for: file, symbols: symbols, interner: ctx.interner)
            let packageScope = PackageScope(parent: rootScope, symbols: symbols)
            packageScope.insert(packageSymbol)
            fileScopes[file.fileID.rawValue] = FileScope(parent: packageScope, symbols: symbols)
        }

        // Pass A: collect declaration headers and signatures.
        for file in ast.files.sorted(by: { $0.fileID.rawValue < $1.fileID.rawValue }) {
            guard let fileScope = fileScopes[file.fileID.rawValue] else { continue }
            for declID in file.topLevelDecls {
                collectHeader(
                    declID: declID,
                    file: file,
                    ast: ast,
                    symbols: symbols,
                    types: types,
                    bindings: bindings,
                    scope: fileScope,
                    diagnostics: ctx.diagnostics
                )
            }
        }

        // Pass B: lightweight body checks.
        for file in ast.files.sorted(by: { $0.fileID.rawValue < $1.fileID.rawValue }) {
            for declID in file.topLevelDecls {
                analyzeBody(
                    declID: declID,
                    ast: ast,
                    symbols: symbols,
                    types: types,
                    bindings: bindings,
                    diagnostics: ctx.diagnostics
                )
            }
        }

        ctx.sema = sema
    }

    private func definePackageSymbol(for file: ASTFile, symbols: SymbolTable, interner: StringInterner) -> SymbolID {
        let package = file.packageFQName.isEmpty ? [interner.intern("_root_")] : file.packageFQName
        let name = package.last ?? interner.intern("_root_")
        if let existing = symbols.lookup(fqName: package) {
            return existing
        }
        return symbols.define(
            kind: .package,
            name: name,
            fqName: package,
            declSite: nil,
            visibility: .public
        )
    }

    private func collectHeader(
        declID: DeclID,
        file: ASTFile,
        ast: ASTModule,
        symbols: SymbolTable,
        types: TypeSystem,
        bindings: BindingTable,
        scope: Scope,
        diagnostics: DiagnosticEngine
    ) {
        guard let decl = ast.arena.decl(declID) else { return }
        let package = file.packageFQName
        let anyType = types.anyType
        let unitType = types.unitType

        let declaration: (kind: SymbolKind, name: InternedString, range: SourceRange?, visibility: Visibility, flags: SymbolFlags)?
        switch decl {
        case .classDecl(let classDecl):
            declaration = (
                kind: .class,
                name: classDecl.name,
                range: classDecl.range,
                visibility: visibility(from: classDecl.modifiers),
                flags: flags(from: classDecl.modifiers)
            )
        case .objectDecl(let objectDecl):
            declaration = (
                kind: .object,
                name: objectDecl.name,
                range: objectDecl.range,
                visibility: visibility(from: objectDecl.modifiers),
                flags: flags(from: objectDecl.modifiers)
            )
        case .funDecl(let funDecl):
            declaration = (
                kind: .function,
                name: funDecl.name,
                range: funDecl.range,
                visibility: visibility(from: funDecl.modifiers),
                flags: flags(from: funDecl.modifiers)
            )
        case .propertyDecl(let propertyDecl):
            declaration = (
                kind: .property,
                name: propertyDecl.name,
                range: propertyDecl.range,
                visibility: visibility(from: propertyDecl.modifiers),
                flags: flags(from: propertyDecl.modifiers)
            )
        case .typeAliasDecl(let typeAliasDecl):
            declaration = (
                kind: .typeAlias,
                name: typeAliasDecl.name,
                range: typeAliasDecl.range,
                visibility: visibility(from: typeAliasDecl.modifiers),
                flags: flags(from: typeAliasDecl.modifiers)
            )
        case .enumEntry(let entry):
            declaration = (
                kind: .field,
                name: entry.name,
                range: entry.range,
                visibility: .public,
                flags: []
            )
        }

        guard let declaration else { return }
        let fqName = package + [declaration.name]
        if symbols.lookup(fqName: fqName) != nil {
            diagnostics.error(
                "KSWIFTK-SEMA-0001",
                "Duplicate declaration in the same package scope.",
                range: declaration.range
            )
        }
        let symbol = symbols.define(
            kind: declaration.kind,
            name: declaration.name,
            fqName: fqName,
            declSite: declaration.range,
            visibility: declaration.visibility,
            flags: declaration.flags
        )
        scope.insert(symbol)
        bindings.bindDecl(declID, symbol: symbol)

        switch decl {
        case .classDecl:
            _ = types.make(.classType(ClassType(classSymbol: symbol, args: [], nullability: .nonNull)))

        case .objectDecl:
            _ = types.make(.classType(ClassType(classSymbol: symbol, args: [], nullability: .nonNull)))

        case .funDecl(let funDecl):
            var paramTypes: [TypeID] = []
            var paramSymbols: [SymbolID] = []
            for valueParam in funDecl.valueParams {
                let paramFQName = fqName + [valueParam.name]
                let paramSymbol = symbols.define(
                    kind: .valueParameter,
                    name: valueParam.name,
                    fqName: paramFQName,
                    declSite: funDecl.range,
                    visibility: .private,
                    flags: []
                )
                paramTypes.append(anyType)
                paramSymbols.append(paramSymbol)
            }
            let returnType: TypeID
            switch funDecl.body {
            case .unit:
                returnType = unitType
            case .block, .expr:
                returnType = anyType
            }
            symbols.setFunctionSignature(
                FunctionSignature(
                    parameterTypes: paramTypes,
                    returnType: returnType,
                    isSuspend: funDecl.isSuspend,
                    valueParameterSymbols: paramSymbols
                ),
                for: symbol
            )

        case .propertyDecl:
            _ = types.make(.any(.nullable))

        case .typeAliasDecl, .enumEntry:
            break
        }
    }

    private func analyzeBody(
        declID: DeclID,
        ast: ASTModule,
        symbols: SymbolTable,
        types: TypeSystem,
        bindings: BindingTable,
        diagnostics: DiagnosticEngine
    ) {
        guard let decl = ast.arena.decl(declID) else { return }
        switch decl {
        case .funDecl(let funDecl):
            var seenNames: Set<InternedString> = []
            for valueParam in funDecl.valueParams {
                if seenNames.contains(valueParam.name) {
                    diagnostics.error(
                        "KSWIFTK-TYPE-0002",
                        "Duplicate function parameter name.",
                        range: funDecl.range
                    )
                }
                seenNames.insert(valueParam.name)
            }

            if let symbol = bindings.declSymbols[declID],
               let signature = symbols.functionSignature(for: symbol),
               case .expr = funDecl.body {
                // Bind a synthetic expression type for expression-body functions.
                let expr = ExprID(rawValue: declID.rawValue)
                bindings.bindExprType(expr, type: signature.returnType)
            }

        case .propertyDecl:
            if let symbol = bindings.declSymbols[declID] {
                let expr = ExprID(rawValue: declID.rawValue)
                bindings.bindIdentifier(expr, symbol: symbol)
                bindings.bindExprType(expr, type: types.anyType)
            }

        case .classDecl, .objectDecl, .typeAliasDecl, .enumEntry:
            break
        }
    }

    private func visibility(from modifiers: Modifiers) -> Visibility {
        if modifiers.contains(.privateModifier) {
            return .private
        }
        if modifiers.contains(.internalModifier) {
            return .internal
        }
        if modifiers.contains(.protectedModifier) {
            return .protected
        }
        return .public
    }

    private func flags(from modifiers: Modifiers) -> SymbolFlags {
        var value: SymbolFlags = []
        if modifiers.contains(.suspend) {
            value.insert(.suspendFunction)
        }
        if modifiers.contains(.inline) {
            value.insert(.inlineFunction)
        }
        return value
    }
}

public final class TypeCheckSemaPassPhase: CompilerPhase {
    public static let name = "TypeCheckSemaPass"

    public init() {}

    public func run(_ ctx: CompilationContext) throws {
        guard let sema = ctx.sema else {
            throw CompilerPipelineError.invalidInput("Semantic model is unavailable.")
        }

        // Run a minimal consistency check: every declaration should have a symbol binding.
        guard let ast = ctx.ast else {
            throw CompilerPipelineError.invalidInput("AST is unavailable during type check.")
        }
        for decl in ast.arena.decls.indices {
            let declID = DeclID(rawValue: Int32(decl))
            if sema.bindings.declSymbols[declID] == nil {
                ctx.diagnostics.error(
                    "KSWIFTK-TYPE-0003",
                    "Unbound declaration found during type checking.",
                    range: nil
                )
            }
        }
    }
}

public final class SemaPassesPhase: CompilerPhase {
    public static let name = "SemaPasses"

    private let passes: [CompilerPhase] = [
        DataFlowSemaPassPhase(),
        TypeCheckSemaPassPhase()
    ]

    public init() {}

    public func run(_ ctx: CompilationContext) throws {
        guard ctx.ast != nil else {
            throw CompilerPipelineError.invalidInput("AST phase did not run.")
        }
        for phase in passes {
            try phase.run(ctx)
        }
    }
}

public final class BuildKIRPhase: CompilerPhase {
    public static let name = "BuildKIR"

    public init() {}

    public func run(_ ctx: CompilationContext) throws {
        guard let ast = ctx.ast, let sema = ctx.sema else {
            throw CompilerPipelineError.invalidInput("Sema phase did not run.")
        }

        let arena = KIRArena()
        var files: [KIRFile] = []

        for file in ast.files.sorted(by: { $0.fileID.rawValue < $1.fileID.rawValue }) {
            var declIDs: [KIRDeclID] = []
            for declID in file.topLevelDecls {
                guard let decl = ast.arena.decl(declID),
                      let symbol = sema.bindings.declSymbols[declID] else {
                    continue
                }

                switch decl {
                case .classDecl, .objectDecl:
                    let kirID = arena.appendDecl(.nominalType(KIRNominalType(symbol: symbol)))
                    declIDs.append(kirID)

                case .funDecl(let function):
                    let signature = sema.symbols.functionSignature(for: symbol)
                    let params: [KIRParameter]
                    if let signature {
                        params = zip(signature.valueParameterSymbols, signature.parameterTypes).map { pair in
                            KIRParameter(symbol: pair.0, type: pair.1)
                        }
                    } else {
                        params = []
                    }
                    let returnType = signature?.returnType ?? sema.types.unitType
                    let body: [KIRInstruction]
                    switch function.body {
                    case .block:
                        body = [.beginBlock, .endBlock, .returnUnit]
                    case .expr:
                        body = [.returnUnit]
                    case .unit:
                        body = [.returnUnit]
                    }
                    let kirID = arena.appendDecl(
                        .function(
                            KIRFunction(
                                symbol: symbol,
                                name: function.name,
                                params: params,
                                returnType: returnType,
                                body: body,
                                isSuspend: function.isSuspend,
                                isInline: function.isInline
                            )
                        )
                    )
                    declIDs.append(kirID)

                case .propertyDecl:
                    let kirID = arena.appendDecl(.global(KIRGlobal(symbol: symbol, type: sema.types.anyType)))
                    declIDs.append(kirID)

                case .typeAliasDecl:
                    let kirID = arena.appendDecl(.nominalType(KIRNominalType(symbol: symbol)))
                    declIDs.append(kirID)

                case .enumEntry:
                    let kirID = arena.appendDecl(.global(KIRGlobal(symbol: symbol, type: sema.types.anyType)))
                    declIDs.append(kirID)
                }
            }
            files.append(KIRFile(fileID: file.fileID, decls: declIDs))
        }

        let module = KIRModule(files: files, arena: arena)
        if module.functionCount == 0 && !ctx.diagnostics.hasError {
            ctx.diagnostics.warning(
                "KSWIFTK-KIR-0001",
                "No function declarations found.",
                range: nil
            )
        }
        ctx.kir = module
    }
}

private protocol LoweringImpl: KIRPass {}

private final class NormalizeBlocksPass: LoweringImpl {
    static let name = "NormalizeBlocks"
    func run(module: KIRModule, ctx: KIRContext) throws { module.recordLowering(Self.name) }
}

private final class OperatorLoweringPass: LoweringImpl {
    static let name = "OperatorLowering"
    func run(module: KIRModule, ctx: KIRContext) throws { module.recordLowering(Self.name) }
}

private final class ForLoweringPass: LoweringImpl {
    static let name = "ForLowering"
    func run(module: KIRModule, ctx: KIRContext) throws { module.recordLowering(Self.name) }
}

private final class WhenLoweringPass: LoweringImpl {
    static let name = "WhenLowering"
    func run(module: KIRModule, ctx: KIRContext) throws { module.recordLowering(Self.name) }
}

private final class PropertyLoweringPass: LoweringImpl {
    static let name = "PropertyLowering"
    func run(module: KIRModule, ctx: KIRContext) throws { module.recordLowering(Self.name) }
}

private final class DataEnumSealedSynthesisPass: LoweringImpl {
    static let name = "DataEnumSealedSynthesis"
    func run(module: KIRModule, ctx: KIRContext) throws { module.recordLowering(Self.name) }
}

private final class LambdaClosureConversionPass: LoweringImpl {
    static let name = "LambdaClosureConversion"
    func run(module: KIRModule, ctx: KIRContext) throws { module.recordLowering(Self.name) }
}

private final class InlineLoweringPass: LoweringImpl {
    static let name = "InlineLowering"
    func run(module: KIRModule, ctx: KIRContext) throws { module.recordLowering(Self.name) }
}

private final class CoroutineLoweringPass: LoweringImpl {
    static let name = "CoroutineLowering"
    func run(module: KIRModule, ctx: KIRContext) throws { module.recordLowering(Self.name) }
}

private final class ABILoweringPass: LoweringImpl {
    static let name = "ABILowering"
    func run(module: KIRModule, ctx: KIRContext) throws { module.recordLowering(Self.name) }
}

public final class LoweringPhase: CompilerPhase {
    public static let name = "Lowerings"

    private let passes: [any LoweringImpl] = [
        NormalizeBlocksPass(),
        OperatorLoweringPass(),
        ForLoweringPass(),
        WhenLoweringPass(),
        PropertyLoweringPass(),
        DataEnumSealedSynthesisPass(),
        LambdaClosureConversionPass(),
        InlineLoweringPass(),
        CoroutineLoweringPass(),
        ABILoweringPass()
    ]

    public init() {}

    public func run(_ ctx: CompilationContext) throws {
        guard let module = ctx.kir else {
            throw CompilerPipelineError.invalidInput("KIR not available for lowering.")
        }
        let kirCtx = KIRContext(diagnostics: ctx.diagnostics, options: ctx.options)
        for pass in passes {
            try pass.run(module: module, ctx: kirCtx)
        }
    }
}

public final class CodegenPhase: CompilerPhase {
    public static let name = "Codegen"

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
        let backend = LLVMBackend(
            target: ctx.options.target,
            optLevel: ctx.options.optLevel,
            debugInfo: ctx.options.debugInfo,
            diagnostics: ctx.diagnostics
        )

        do {
            switch ctx.options.emit {
            case .kirDump:
                let path = outputPath(base: ctx.options.outputPath, defaultExtension: "kir")
                let dump = kir.dump(interner: ctx.interner, symbols: ctx.sema?.symbols)
                try dump.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)

            case .llvmIR:
                let path = outputPath(base: ctx.options.outputPath, defaultExtension: "ll")
                try backend.emitLLVMIR(module: kir, runtime: runtime, outputIRPath: path)
                ctx.generatedLLVMIRPath = path

            case .object:
                let path = outputPath(base: ctx.options.outputPath, defaultExtension: "o")
                try backend.emitObject(module: kir, runtime: runtime, outputObjectPath: path)
                ctx.generatedObjectPath = path

            case .executable:
                let objectPath = outputPath(base: ctx.options.outputPath, defaultExtension: "o")
                try backend.emitObject(module: kir, runtime: runtime, outputObjectPath: objectPath)
                ctx.generatedObjectPath = objectPath

            case .library:
                try emitLibrary(module: kir, backend: backend, runtime: runtime, ctx: ctx)
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

        try fm.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
        try fm.createDirectory(atPath: objectsDir, withIntermediateDirectories: true)
        try fm.createDirectory(atPath: inlineDir, withIntermediateDirectories: true)

        let objectPath = objectsDir + "/\(ctx.options.moduleName)_0.o"
        try backend.emitObject(module: module, runtime: runtime, outputObjectPath: objectPath)
        ctx.generatedObjectPath = objectPath

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
        let exported = sema.symbols.allSymbols()
            .filter { $0.visibility == Visibility.public }
            .sorted { lhs, rhs in
                if lhs.fqName.count != rhs.fqName.count {
                    return lhs.fqName.count < rhs.fqName.count
                }
                let lhsRaw = lhs.fqName.map { $0.rawValue }
                let rhsRaw = rhs.fqName.map { $0.rawValue }
                if lhsRaw != rhsRaw {
                    return lhsRaw.lexicographicallyPrecedes(rhsRaw)
                }
                return lhs.id.rawValue < rhs.id.rawValue
            }

        var lines: [String] = ["symbols=\(exported.count)"]
        let mangler = NameMangler()
        for symbol in exported {
            let mangled = mangler.mangle(moduleName: ctx.options.moduleName, symbol: symbol, signature: "_")
            lines.append("\(symbol.kind) \(mangled)")
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

public final class LinkPhase: CompilerPhase {
    public static let name = "Link"

    public init() {}

    public func run(_ ctx: CompilationContext) throws {
        if ctx.options.emit != .executable {
            return
        }

        guard let objectPath = ctx.generatedObjectPath,
              FileManager.default.fileExists(atPath: objectPath) else {
            throw CompilerPipelineError.outputUnavailable
        }

        let outputURL = URL(fileURLWithPath: ctx.options.outputPath)
        let functionCount = ctx.kir?.functionCount ?? 0
        let script = """
        #!/bin/sh
        # KSwiftK synthetic executable
        echo "module=\(ctx.options.moduleName) functions=\(functionCount)"
        """

        do {
            try script.write(to: outputURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: NSNumber(value: Int16(0o755))],
                ofItemAtPath: outputURL.path
            )
        } catch {
            throw CompilerPipelineError.outputUnavailable
        }
    }
}
