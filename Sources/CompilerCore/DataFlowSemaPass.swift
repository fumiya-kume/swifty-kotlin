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

        for file in ast.sortedFiles {
            let packageSymbol = definePackageSymbol(for: file, symbols: symbols, interner: ctx.interner)
            let packageScope = PackageScope(parent: rootScope, symbols: symbols)
            packageScope.insert(packageSymbol)
            fileScopes[file.fileID.rawValue] = FileScope(parent: packageScope, symbols: symbols)
        }

        loadImportedLibrarySymbols(
            options: ctx.options,
            symbols: symbols,
            types: types,
            diagnostics: ctx.diagnostics,
            interner: ctx.interner
        )

        // Pass A: collect declaration headers and signatures.
        for file in ast.sortedFiles {
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
                    diagnostics: ctx.diagnostics,
                    interner: ctx.interner
                )
            }
        }
        bindInheritanceEdges(
            ast: ast,
            symbols: symbols,
            bindings: bindings
        )
        synthesizeNominalLayouts(symbols: symbols)

        // Pass B: lightweight body checks.
        for file in ast.sortedFiles {
            for declID in file.topLevelDecls {
                analyzeBody(
                    declID: declID,
                    ast: ast,
                    symbols: symbols,
                    types: types,
                    bindings: bindings,
                    diagnostics: ctx.diagnostics,
                    interner: ctx.interner
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
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) {
        guard let decl = ast.arena.decl(declID) else { return }
        let package = file.packageFQName
        let anyType = types.anyType
        let unitType = types.unitType

        let declaration: (kind: SymbolKind, name: InternedString, range: SourceRange?, visibility: Visibility, flags: SymbolFlags)?
        switch decl {
        case .classDecl(let classDecl):
            declaration = (
                kind: classSymbolKind(for: classDecl),
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
            var propertyFlags = flags(from: propertyDecl.modifiers)
            if propertyDecl.isVar {
                propertyFlags.insert(.mutable)
            }
            declaration = (
                kind: .property,
                name: propertyDecl.name,
                range: propertyDecl.range,
                visibility: visibility(from: propertyDecl.modifiers),
                flags: propertyFlags
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
        let existingSymbols = symbols.lookupAll(fqName: fqName).compactMap { symbols.symbol($0) }
        if hasDeclarationConflict(newKind: declaration.kind, existing: existingSymbols) {
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
        case .classDecl(let classDecl):
            let classType = types.make(.classType(ClassType(classSymbol: symbol, args: [], nullability: .nonNull)))
            if declaration.kind == .enumClass {
                for entry in classDecl.enumEntries {
                    let entryFQName = fqName + [entry.name]
                    let existingEntrySymbols = symbols.lookupAll(fqName: entryFQName).compactMap { symbols.symbol($0) }
                    if hasDeclarationConflict(newKind: .field, existing: existingEntrySymbols) {
                        diagnostics.error(
                            "KSWIFTK-SEMA-0001",
                            "Duplicate declaration in the same package scope.",
                            range: entry.range
                        )
                    }
                    let entrySymbol = symbols.define(
                        kind: .field,
                        name: entry.name,
                        fqName: entryFQName,
                        declSite: entry.range,
                        visibility: .public,
                        flags: []
                    )
                    symbols.setPropertyType(classType, for: entrySymbol)
                    scope.insert(entrySymbol)
                }
            }

        case .objectDecl:
            _ = types.make(.classType(ClassType(classSymbol: symbol, args: [], nullability: .nonNull)))

        case .funDecl(let funDecl):
            var paramTypes: [TypeID] = []
            var paramSymbols: [SymbolID] = []
            var paramHasDefaultValues: [Bool] = []
            var paramIsVararg: [Bool] = []
            var typeParameterSymbols: [SymbolID] = []
            var localTypeParameters: [InternedString: SymbolID] = [:]
            let localNamespaceFQName = fqName + [interner.intern("$\(symbol.rawValue)")]
            for typeParam in funDecl.typeParams {
                let typeParamFQName = localNamespaceFQName + [typeParam.name]
                let typeParamSymbol = symbols.define(
                    kind: .typeParameter,
                    name: typeParam.name,
                    fqName: typeParamFQName,
                    declSite: funDecl.range,
                    visibility: .private,
                    flags: []
                )
                typeParameterSymbols.append(typeParamSymbol)
                localTypeParameters[typeParam.name] = typeParamSymbol
            }
            let receiverType = resolveTypeRef(
                funDecl.receiverType,
                ast: ast,
                symbols: symbols,
                types: types,
                interner: interner,
                localTypeParameters: localTypeParameters
            )
            for valueParam in funDecl.valueParams {
                let paramFQName = localNamespaceFQName + [valueParam.name]
                let paramSymbol = symbols.define(
                    kind: .valueParameter,
                    name: valueParam.name,
                    fqName: paramFQName,
                    declSite: funDecl.range,
                    visibility: .private,
                    flags: []
                )
                let resolvedType = resolveTypeRef(
                    valueParam.type,
                    ast: ast,
                    symbols: symbols,
                    types: types,
                    interner: interner,
                    localTypeParameters: localTypeParameters
                ) ?? anyType
                paramTypes.append(resolvedType)
                paramSymbols.append(paramSymbol)
                paramHasDefaultValues.append(valueParam.hasDefaultValue)
                paramIsVararg.append(valueParam.isVararg)
            }
            let returnType: TypeID
            if let explicit = resolveTypeRef(
                funDecl.returnType,
                ast: ast,
                symbols: symbols,
                types: types,
                interner: interner,
                localTypeParameters: localTypeParameters
            ) {
                returnType = explicit
            } else {
                switch funDecl.body {
                case .unit:
                    returnType = unitType
                case .block, .expr:
                    returnType = anyType
                }
            }
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: paramTypes,
                    returnType: returnType,
                    isSuspend: funDecl.isSuspend,
                    valueParameterSymbols: paramSymbols,
                    valueParameterHasDefaultValues: paramHasDefaultValues,
                    valueParameterIsVararg: paramIsVararg,
                    typeParameterSymbols: typeParameterSymbols
                ),
                for: symbol
            )

        case .propertyDecl(let propertyDecl):
            let resolvedType = resolveTypeRef(
                propertyDecl.type,
                ast: ast,
                symbols: symbols,
                types: types,
                interner: interner
            ) ?? types.nullableAnyType
            symbols.setPropertyType(resolvedType, for: symbol)

        case .typeAliasDecl, .enumEntry:
            break
        }
    }

    private func bindInheritanceEdges(
        ast: ASTModule,
        symbols: SymbolTable,
        bindings: BindingTable
    ) {
        for file in ast.sortedFiles {
            for declID in file.topLevelDecls {
                guard let symbol = bindings.declSymbols[declID],
                      let decl = ast.arena.decl(declID) else {
                    continue
                }
                let superTypeRefs: [TypeRefID]
                switch decl {
                case .classDecl(let classDecl):
                    superTypeRefs = classDecl.superTypes
                case .objectDecl(let objectDecl):
                    superTypeRefs = objectDecl.superTypes
                default:
                    continue
                }

                var superSymbols: [SymbolID] = []
                for superTypeRef in superTypeRefs {
                    if let superSymbol = resolveNominalSymbolFromTypeRef(
                        superTypeRef,
                        currentPackage: file.packageFQName,
                        ast: ast,
                        symbols: symbols
                    ) {
                        superSymbols.append(superSymbol)
                    }
                }
                let uniqueSuperSymbols = Array(Set(superSymbols)).sorted(by: { $0.rawValue < $1.rawValue })
                symbols.setDirectSupertypes(uniqueSuperSymbols, for: symbol)
            }
        }
    }

    private func resolveNominalSymbolFromTypeRef(
        _ typeRefID: TypeRefID,
        currentPackage: [InternedString],
        ast: ASTModule,
        symbols: SymbolTable
    ) -> SymbolID? {
        guard let typeRef = ast.arena.typeRef(typeRefID) else {
            return nil
        }
        let path: [InternedString]
        switch typeRef {
        case .named(let refPath, _):
            path = refPath
        }
        guard !path.isEmpty else {
            return nil
        }

        var candidatePaths: [[InternedString]] = [path]
        if path.count == 1 && !currentPackage.isEmpty {
            candidatePaths.append(currentPackage + path)
        }

        for candidatePath in candidatePaths {
            if let symbol = symbols.lookupAll(fqName: candidatePath)
                .compactMap({ symbols.symbol($0) })
                .first(where: { isNominalTypeSymbol($0.kind) })?.id {
                return symbol
            }
        }
        return nil
    }

    private func synthesizeNominalLayouts(symbols: SymbolTable) {
        let nominalIDs = symbols.allSymbols()
            .filter { isNominalLayoutTargetSymbol($0.kind) }
            .map(\.id)
            .sorted(by: { $0.rawValue < $1.rawValue })
        guard !nominalIDs.isEmpty else {
            return
        }

        var topoOrder: [SymbolID] = []
        var visited: Set<SymbolID> = []

        func visit(_ symbolID: SymbolID) {
            guard visited.insert(symbolID).inserted else {
                return
            }
            let superNominals = symbols.directSupertypes(for: symbolID)
                .filter { superID in
                    guard let superSymbol = symbols.symbol(superID) else {
                        return false
                    }
                    return isNominalLayoutTargetSymbol(superSymbol.kind)
                }
                .sorted(by: { $0.rawValue < $1.rawValue })
            for superNominal in superNominals {
                visit(superNominal)
            }
            topoOrder.append(symbolID)
        }

        for nominalID in nominalIDs {
            visit(nominalID)
        }

        for nominalID in topoOrder {
            guard let nominalSymbol = symbols.symbol(nominalID) else {
                continue
            }

            let directSuperNominals = symbols.directSupertypes(for: nominalID)
                .compactMap { symbols.symbol($0) }
                .filter { isNominalLayoutTargetSymbol($0.kind) }
                .sorted(by: { $0.id.rawValue < $1.id.rawValue })

            let superClass = directSuperNominals.first(where: { $0.kind != .interface })?.id
            let layoutHint = symbols.nominalLayoutHint(for: nominalID)

            let inheritedVtable = superClass.flatMap { symbols.nominalLayout(for: $0)?.vtableSlots } ?? [:]
            let inheritedVtableSize = superClass.flatMap { symbols.nominalLayout(for: $0)?.vtableSize } ?? 0
            var vtableSlots = inheritedVtable
            var vtableSlotByKey: [MethodDispatchKey: Int] = [:]
            for methodID in inheritedVtable.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
                guard let methodSymbol = symbols.symbol(methodID),
                      let slot = inheritedVtable[methodID] else {
                    continue
                }
                vtableSlotByKey[methodDispatchKey(for: methodSymbol, symbols: symbols)] = slot
            }

            var nextVtableSlot = max(inheritedVtableSize, (vtableSlots.values.max() ?? -1) + 1)
            let ownMethods = symbols.allSymbols()
                .filter { symbol in
                    symbol.kind == .function &&
                    isDirectMemberSymbol(symbol, of: nominalSymbol)
                }
                .sorted(by: { $0.id.rawValue < $1.id.rawValue })
            for method in ownMethods {
                let key = methodDispatchKey(for: method, symbols: symbols)
                if let inheritedSlot = vtableSlotByKey[key] {
                    vtableSlots[method.id] = inheritedSlot
                    continue
                }
                vtableSlots[method.id] = nextVtableSlot
                vtableSlotByKey[key] = nextVtableSlot
                nextVtableSlot += 1
            }
            let declaredVtableSize = layoutHint?.declaredVtableSize ?? 0
            let vtableSize = max(nextVtableSlot, declaredVtableSize)

            let inheritedItable = superClass.flatMap { symbols.nominalLayout(for: $0)?.itableSlots } ?? [:]
            let inheritedItableSize = superClass.flatMap { symbols.nominalLayout(for: $0)?.itableSize } ?? 0
            var itableSlots = inheritedItable
            var nextItableSlot = max(inheritedItableSize, (itableSlots.values.max() ?? -1) + 1)
            let interfaces = collectInterfaceSupertypes(of: nominalID, symbols: symbols)
            for interfaceID in interfaces where itableSlots[interfaceID] == nil {
                itableSlots[interfaceID] = nextItableSlot
                nextItableSlot += 1
            }
            let declaredItableSize = layoutHint?.declaredItableSize ?? 0
            let itableSize = max(nextItableSlot, declaredItableSize)

            let ownFieldCount = symbols.allSymbols().filter { symbol in
                (symbol.kind == .field || symbol.kind == .property) &&
                isDirectMemberSymbol(symbol, of: nominalSymbol)
            }.count
            let inheritedFieldCount = superClass.flatMap { symbols.nominalLayout(for: $0)?.instanceFieldCount } ?? 0
            let declaredFieldCount = layoutHint?.declaredFieldCount ?? 0
            let instanceFieldCount = max(inheritedFieldCount + ownFieldCount, declaredFieldCount)

            let objectHeaderWords = 3
            let declaredSizeWords = layoutHint?.declaredInstanceSizeWords ?? 0
            let instanceSizeWords = max(objectHeaderWords + instanceFieldCount, declaredSizeWords)
            symbols.setNominalLayout(
                NominalLayout(
                    objectHeaderWords: objectHeaderWords,
                    instanceFieldCount: instanceFieldCount,
                    instanceSizeWords: instanceSizeWords,
                    vtableSlots: vtableSlots,
                    itableSlots: itableSlots,
                    vtableSize: vtableSize,
                    itableSize: itableSize,
                    superClass: superClass
                ),
                for: nominalID
            )
        }
    }

    private func isDirectMemberSymbol(_ member: SemanticSymbol, of owner: SemanticSymbol) -> Bool {
        guard member.fqName.count == owner.fqName.count + 1 else {
            return false
        }
        return zip(owner.fqName, member.fqName).allSatisfy { $0 == $1 }
    }

    private func collectInterfaceSupertypes(of symbol: SymbolID, symbols: SymbolTable) -> [SymbolID] {
        var stack: [SymbolID] = symbols.directSupertypes(for: symbol)
        var visited: Set<SymbolID> = []
        var interfaces: [SymbolID] = []

        while let current = stack.popLast() {
            guard visited.insert(current).inserted else {
                continue
            }
            guard let currentSymbol = symbols.symbol(current) else {
                continue
            }

            if currentSymbol.kind == .interface {
                interfaces.append(current)
            }
            let next = symbols.directSupertypes(for: current)
                .sorted(by: { $0.rawValue < $1.rawValue })
            for candidate in next {
                stack.append(candidate)
            }
        }

        return interfaces.sorted(by: { $0.rawValue < $1.rawValue })
    }

    private struct MethodDispatchKey: Hashable {
        let name: InternedString
        let arity: Int
        let isSuspend: Bool
    }

    private func methodDispatchKey(for method: SemanticSymbol, symbols: SymbolTable) -> MethodDispatchKey {
        let signature = symbols.functionSignature(for: method.id)
        return MethodDispatchKey(
            name: method.name,
            arity: signature?.parameterTypes.count ?? 0,
            isSuspend: signature?.isSuspend ?? false
        )
    }

    private func classSymbolKind(for classDecl: ClassDecl) -> SymbolKind {
        if classDecl.modifiers.contains(.annotationClass) {
            return .annotationClass
        }
        if classDecl.modifiers.contains(.enumModifier) {
            return .enumClass
        }
        return .class
    }

    private func resolveTypeRef(
        _ typeRefID: TypeRefID?,
        ast: ASTModule,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        localTypeParameters: [InternedString: SymbolID] = [:]
    ) -> TypeID? {
        guard let typeRefID, let typeRef = ast.arena.typeRef(typeRefID) else {
            return nil
        }

        let nullability: Nullability
        let path: [InternedString]
        switch typeRef {
        case .named(let refPath, let nullable):
            path = refPath
            nullability = nullable ? .nullable : .nonNull
        }

        guard let shortName = path.last else {
            return nil
        }

        if path.count == 1, let typeParamSymbol = localTypeParameters[shortName] {
            return types.make(.typeParam(TypeParamType(symbol: typeParamSymbol, nullability: nullability)))
        }

        switch interner.resolve(shortName) {
        case "Int":
            return types.make(.primitive(.int, nullability))
        case "Boolean":
            return types.make(.primitive(.boolean, nullability))
        case "String":
            return types.make(.primitive(.string, nullability))
        case "Any":
            return nullability == .nullable ? types.nullableAnyType : types.anyType
        case "Unit":
            return nullability == .nullable ? types.nullableAnyType : types.unitType
        case "Nothing":
            return types.nothingType
        default:
            break
        }

        if let symbol = symbols.lookupAll(fqName: path)
            .compactMap({ symbols.symbol($0) })
            .first(where: { isNominalTypeSymbol($0.kind) })?.id {
            return types.make(.classType(ClassType(classSymbol: symbol, args: [], nullability: nullability)))
        }
        return nullability == .nullable ? types.nullableAnyType : types.anyType
    }

    private func hasDeclarationConflict(newKind: SymbolKind, existing: [SemanticSymbol]) -> Bool {
        guard !existing.isEmpty else {
            return false
        }
        if isOverloadableSymbol(newKind) {
            return existing.contains(where: { !isOverloadableSymbol($0.kind) })
        }
        return true
    }

    private func isOverloadableSymbol(_ kind: SymbolKind) -> Bool {
        kind == .function || kind == .constructor
    }

    private func isNominalTypeSymbol(_ kind: SymbolKind) -> Bool {
        switch kind {
        case .class, .interface, .object, .enumClass, .annotationClass, .typeAlias:
            return true
        default:
            return false
        }
    }

    private func isNominalLayoutTargetSymbol(_ kind: SymbolKind) -> Bool {
        switch kind {
        case .class, .interface, .object, .enumClass, .annotationClass:
            return true
        default:
            return false
        }
    }

    private func analyzeBody(
        declID: DeclID,
        ast: ASTModule,
        symbols: SymbolTable,
        types: TypeSystem,
        bindings: BindingTable,
        diagnostics: DiagnosticEngine,
        interner: StringInterner
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

        case .propertyDecl(let propertyDecl):
            if let symbol = bindings.declSymbols[declID] {
                let expr = ExprID(rawValue: declID.rawValue)
                bindings.bindIdentifier(expr, symbol: symbol)
                let boundType = resolveTypeRef(
                    propertyDecl.type,
                    ast: ast,
                    symbols: symbols,
                    types: types,
                    interner: interner
                ) ?? types.anyType
                bindings.bindExprType(expr, type: boundType)
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
        if modifiers.contains(.sealed) {
            value.insert(.sealedType)
        }
        if modifiers.contains(.data) {
            value.insert(.dataType)
        }
        return value
    }

    private struct ImportedLibrarySymbolRecord {
        let kind: SymbolKind
        let fqName: [InternedString]
        let arity: Int
        let isSuspend: Bool
        let declaredFieldCount: Int?
        let declaredInstanceSizeWords: Int?
        let declaredVtableSize: Int?
        let declaredItableSize: Int?
        let superFQName: [InternedString]?
    }

    private func loadImportedLibrarySymbols(
        options: CompilerOptions,
        symbols: SymbolTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) {
        let libraryDirs = discoverLibraryDirectories(searchPaths: options.searchPaths)
        var pendingSupertypeEdges: [(subtype: SymbolID, superFQName: [InternedString])] = []
        for libraryDir in libraryDirs {
            let metadataPath = resolveMetadataPath(libraryDir: libraryDir)
            guard let records = parseLibraryMetadata(
                path: metadataPath,
                diagnostics: diagnostics,
                interner: interner
            ) else {
                continue
            }
            for record in records {
                guard !record.fqName.isEmpty else {
                    continue
                }
                let name = record.fqName.last ?? interner.intern("_")
                var flags: SymbolFlags = [.synthetic]
                if record.isSuspend && record.kind == .function {
                    flags.insert(.suspendFunction)
                }
                let symbol = symbols.define(
                    kind: record.kind,
                    name: name,
                    fqName: record.fqName,
                    declSite: nil,
                    visibility: .public,
                    flags: flags
                )
                if isNominalLayoutTargetSymbol(record.kind) {
                    let hasLayoutHint =
                        record.declaredFieldCount != nil ||
                        record.declaredInstanceSizeWords != nil ||
                        record.declaredVtableSize != nil ||
                        record.declaredItableSize != nil
                    if hasLayoutHint {
                        symbols.setNominalLayoutHint(
                            NominalLayoutHint(
                                declaredFieldCount: record.declaredFieldCount,
                                declaredInstanceSizeWords: record.declaredInstanceSizeWords,
                                declaredVtableSize: record.declaredVtableSize,
                                declaredItableSize: record.declaredItableSize
                            ),
                            for: symbol
                        )
                    }
                    if let superFQName = record.superFQName, !superFQName.isEmpty {
                        pendingSupertypeEdges.append((subtype: symbol, superFQName: superFQName))
                    }
                }
                if record.kind == .function {
                    let parameterTypes = Array(repeating: types.anyType, count: max(0, record.arity))
                    symbols.setFunctionSignature(
                        FunctionSignature(
                            parameterTypes: parameterTypes,
                            returnType: types.anyType,
                            isSuspend: record.isSuspend
                        ),
                        for: symbol
                    )
                } else if record.kind == .property || record.kind == .field {
                    symbols.setPropertyType(types.anyType, for: symbol)
                }
            }
        }

        for edge in pendingSupertypeEdges {
            guard let superSymbol = symbols.lookupAll(fqName: edge.superFQName)
                .compactMap({ symbols.symbol($0) })
                .first(where: { isNominalLayoutTargetSymbol($0.kind) })?.id else {
                continue
            }
            var supertypes = symbols.directSupertypes(for: edge.subtype)
            if !supertypes.contains(superSymbol) {
                supertypes.append(superSymbol)
                supertypes.sort(by: { $0.rawValue < $1.rawValue })
                symbols.setDirectSupertypes(supertypes, for: edge.subtype)
            }
        }
    }

    private func discoverLibraryDirectories(searchPaths: [String]) -> [String] {
        let fm = FileManager.default
        var found: Set<String> = []
        for rawPath in searchPaths {
            let path = URL(fileURLWithPath: rawPath).path
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
                continue
            }
            if path.hasSuffix(".kklib") {
                found.insert(path)
                continue
            }
            guard let entries = try? fm.contentsOfDirectory(atPath: path) else {
                continue
            }
            for entry in entries where entry.hasSuffix(".kklib") {
                found.insert(URL(fileURLWithPath: path).appendingPathComponent(entry).path)
            }
        }
        return found.sorted()
    }

    private func resolveMetadataPath(libraryDir: String) -> String {
        let manifestPath = URL(fileURLWithPath: libraryDir).appendingPathComponent("manifest.json").path
        if let manifestData = try? Data(contentsOf: URL(fileURLWithPath: manifestPath)),
           let object = try? JSONSerialization.jsonObject(with: manifestData) as? [String: Any],
           let metadataRelativePath = object["metadata"] as? String, !metadataRelativePath.isEmpty {
            return URL(fileURLWithPath: libraryDir).appendingPathComponent(metadataRelativePath).path
        }
        return URL(fileURLWithPath: libraryDir).appendingPathComponent("metadata.bin").path
    }

    private func parseLibraryMetadata(
        path: String,
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) -> [ImportedLibrarySymbolRecord]? {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            diagnostics.warning(
                "KSWIFTK-LIB-0001",
                "Unable to read library metadata: \(path)",
                range: nil
            )
            return nil
        }

        var records: [ImportedLibrarySymbolRecord] = []
        for rawLine in content.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("symbols=") {
                continue
            }
            let parts = line.split(separator: " ").map(String.init)
            guard let kindToken = parts.first,
                  let kind = symbolKindFromMetadata(kindToken) else {
                continue
            }
            if kind == .package {
                continue
            }

            var fqName: [InternedString] = []
            var arity = 0
            var isSuspend = false
            var declaredFieldCount: Int? = nil
            var declaredInstanceSizeWords: Int? = nil
            var declaredVtableSize: Int? = nil
            var declaredItableSize: Int? = nil
            var superFQName: [InternedString]? = nil

            for part in parts.dropFirst() {
                guard let separatorIndex = part.firstIndex(of: "=") else {
                    continue
                }
                let key = String(part[..<separatorIndex])
                let value = String(part[part.index(after: separatorIndex)...])
                switch key {
                case "fq":
                    fqName = value
                        .split(separator: ".")
                        .map { interner.intern(String($0)) }
                case "arity":
                    arity = Int(value) ?? 0
                case "suspend":
                    isSuspend = value == "1" || value == "true"
                case "fields":
                    declaredFieldCount = Int(value)
                case "layoutWords":
                    declaredInstanceSizeWords = Int(value)
                case "vtable":
                    declaredVtableSize = Int(value)
                case "itable":
                    declaredItableSize = Int(value)
                case "superFq":
                    let parsed = value
                        .split(separator: ".")
                        .map { interner.intern(String($0)) }
                    superFQName = parsed.isEmpty ? nil : parsed
                default:
                    continue
                }
            }

            guard !fqName.isEmpty else {
                continue
            }
            records.append(ImportedLibrarySymbolRecord(
                kind: kind,
                fqName: fqName,
                arity: arity,
                isSuspend: isSuspend,
                declaredFieldCount: declaredFieldCount,
                declaredInstanceSizeWords: declaredInstanceSizeWords,
                declaredVtableSize: declaredVtableSize,
                declaredItableSize: declaredItableSize,
                superFQName: superFQName
            ))
        }

        return records
    }

    private func symbolKindFromMetadata(_ token: String) -> SymbolKind? {
        switch token {
        case "package":
            return .package
        case "class":
            return .class
        case "interface":
            return .interface
        case "object":
            return .object
        case "enumClass":
            return .enumClass
        case "annotationClass":
            return .annotationClass
        case "typeAlias":
            return .typeAlias
        case "function":
            return .function
        case "constructor":
            return .constructor
        case "property":
            return .property
        case "field":
            return .field
        case "typeParameter":
            return .typeParameter
        case "valueParameter":
            return .valueParameter
        case "local":
            return .local
        case "label":
            return .label
        default:
            return nil
        }
    }
}
