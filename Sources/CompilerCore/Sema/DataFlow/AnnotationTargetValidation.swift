import Foundation

extension DataFlowSemaPhase {
    func validateAnnotationTargets(
        ast: ASTModule,
        symbols: SymbolTable,
        bindings: BindingTable,
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) {
        let filesByID = Dictionary(uniqueKeysWithValues: ast.sortedFiles.map { ($0.fileID.rawValue, $0) })

        for file in ast.sortedFiles {
            validateFileAnnotationTargets(
                file: file,
                symbols: symbols,
                diagnostics: diagnostics,
                interner: interner,
                filesByID: filesByID
            )

            for declID in file.topLevelDecls {
                validateAnnotationTargets(
                    declID: declID,
                    file: file,
                    ast: ast,
                    symbols: symbols,
                    bindings: bindings,
                    diagnostics: diagnostics,
                    interner: interner,
                    filesByID: filesByID
                )
            }
        }
    }

    private func validateFileAnnotationTargets(
        file: ASTFile,
        symbols: SymbolTable,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        filesByID: [Int32: ASTFile]
    ) {
        guard !file.annotations.isEmpty else {
            return
        }

        for annotation in file.annotations {
            validateAnnotationTarget(
                annotation: annotation,
                site: .file,
                ownerRange: file.range,
                decl: nil,
                file: file,
                propertySymbol: nil,
                symbols: symbols,
                diagnostics: diagnostics,
                interner: interner,
                filesByID: filesByID
            )
        }
    }

    private func validateAnnotationTargets(
        declID: DeclID,
        file: ASTFile,
        ast: ASTModule,
        symbols: SymbolTable,
        bindings: BindingTable,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        filesByID: [Int32: ASTFile]
    ) {
        guard let decl = ast.arena.decl(declID),
              let symbolID = bindings.declSymbols[declID],
              let ownerSymbol = symbols.symbol(symbolID)
        else {
            return
        }

        for annotation in declarationAnnotations(for: decl) {
            guard let site = annotationUsageSite(for: annotation, on: decl, ownerSymbol: ownerSymbol) else {
                continue
            }
            validateAnnotationTarget(
                annotation: annotation,
                site: site,
                ownerRange: ownerRange(for: decl),
                decl: decl,
                file: file,
                propertySymbol: ownerSymbol.kind == .property ? symbolID : nil,
                symbols: symbols,
                diagnostics: diagnostics,
                interner: interner,
                filesByID: filesByID
            )
        }

if case let .funDecl(funDecl) = decl,
           let signature = symbols.functionSignature(for: symbolID)
        {
            validateValueParameterAnnotationTargets(
                valueParams: funDecl.valueParams,
                valueParameterSymbols: signature.valueParameterSymbols,
                file: file,
                symbols: symbols,
                diagnostics: diagnostics,
                interner: interner,
                filesByID: filesByID
            )
        }

        validateTypeAnnotationTargets(
            in: decl,
            file: file,
            ast: ast,
            symbols: symbols,
            diagnostics: diagnostics,
            interner: interner,
            filesByID: filesByID
        )

        switch decl {
        case let .classDecl(classDecl):
            validateMemberAnnotationTargets(
                declIDs: classDecl.memberFunctions + classDecl.memberProperties + classDecl.nestedClasses + classDecl.nestedObjects,
                file: file,
                ast: ast,
                symbols: symbols,
                bindings: bindings,
                diagnostics: diagnostics,
                interner: interner,
                filesByID: filesByID
            )
            if let companion = classDecl.companionObject {
                validateAnnotationTargets(
                    declID: companion,
                    file: file,
                    ast: ast,
                    symbols: symbols,
                    bindings: bindings,
                    diagnostics: diagnostics,
                    interner: interner,
                    filesByID: filesByID
                )
            }
        case let .interfaceDecl(interfaceDecl):
            validateMemberAnnotationTargets(
                declIDs: interfaceDecl.memberFunctions + interfaceDecl.memberProperties + interfaceDecl.nestedClasses + interfaceDecl.nestedObjects,
                file: file,
                ast: ast,
                symbols: symbols,
                bindings: bindings,
                diagnostics: diagnostics,
                interner: interner,
                filesByID: filesByID
            )
            if let companion = interfaceDecl.companionObject {
                validateAnnotationTargets(
                    declID: companion,
                    file: file,
                    ast: ast,
                    symbols: symbols,
                    bindings: bindings,
                    diagnostics: diagnostics,
                    interner: interner,
                    filesByID: filesByID
                )
            }
        case let .objectDecl(objectDecl):
            validateMemberAnnotationTargets(
                declIDs: objectDecl.memberFunctions + objectDecl.memberProperties + objectDecl.nestedClasses + objectDecl.nestedObjects,
                file: file,
                ast: ast,
                symbols: symbols,
                bindings: bindings,
                diagnostics: diagnostics,
                interner: interner,
                filesByID: filesByID
            )
        case .funDecl, .propertyDecl, .typeAliasDecl, .enumEntryDecl:
            break
        }
    }

    private func validateMemberAnnotationTargets(
        declIDs: [DeclID],
        file: ASTFile,
        ast: ASTModule,
        symbols: SymbolTable,
        bindings: BindingTable,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        filesByID: [Int32: ASTFile]
    ) {
        for declID in declIDs {
            validateAnnotationTargets(
                declID: declID,
                file: file,
                ast: ast,
                symbols: symbols,
                bindings: bindings,
                diagnostics: diagnostics,
                interner: interner,
                filesByID: filesByID
            )
        }
    }

    private func validateAnnotationTarget(
        annotation: AnnotationNode,
        site: AnnotationUsageSite,
        ownerRange: SourceRange?,
        decl: Decl?,
        file: ASTFile,
        propertySymbol: SymbolID?,
        symbols: SymbolTable,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        filesByID: [Int32: ASTFile]
    ) {
        guard let annotationSymbolID = resolveAnnotationSymbol(
            named: annotation.name,
            in: file,
            symbols: symbols,
            interner: interner
        ), let annotationSymbol = symbols.symbol(annotationSymbolID),
              annotationSymbol.kind == .annotationClass
        else {
            return
        }

        guard let allowedTargets = annotationTargets(
            for: annotationSymbolID,
            symbols: symbols,
            filesByID: filesByID,
            interner: interner
        ) else {
            return
        }

        guard annotationTarget(
            site: site,
            allowedTargets: allowedTargets,
            decl: decl,
            propertySymbol: propertySymbol,
            symbols: symbols
        ) else {
            diagnostics.error(
                "KSWIFTK-SEMA-ANNOTATION-TARGET",
                annotationTargetMessage(
                    annotationName: annotation.name,
                    site: site
                ),
                range: ownerRange
            )
            return
        }
    }

    private func annotationUsageSite(
        for annotation: AnnotationNode,
        on decl: Decl,
        ownerSymbol: SemanticSymbol
    ) -> AnnotationUsageSite? {
        let useSiteTarget = annotation.useSiteTarget?.lowercased()
        switch decl {
        case .classDecl, .interfaceDecl, .objectDecl:
            guard useSiteTarget == nil else {
                return nil
            }
            return .classLike(ownerSymbol.kind)
        case .funDecl:
            guard useSiteTarget == nil else {
                return nil
            }
            return .function
        case .propertyDecl:
            switch useSiteTarget {
            case nil:
                return .property(explicitUseSiteTarget: false)
            case "property":
                return .property(explicitUseSiteTarget: true)
            case "field":
                return .field
            case "delegate":
                return .delegate
            case "get":
                return .getter
            case "set":
                return .setter
            default:
                return nil
            }
        case .typeAliasDecl, .enumEntryDecl:
            return nil
        }
    }

    private func annotationTargets(
        for annotationSymbol: SymbolID,
        symbols: SymbolTable,
        filesByID: [Int32: ASTFile],
        interner: StringInterner
    ) -> Set<String>? {
        guard let symbol = symbols.symbol(annotationSymbol),
              symbol.kind == .annotationClass
        else {
            return nil
        }

        var sawTargetMeta = false
        var allowedTargets: Set<String> = []
        for meta in symbols.annotations(for: annotationSymbol) {
            guard isTargetMetaAnnotation(
                meta,
                for: annotationSymbol,
                symbols: symbols,
                filesByID: filesByID,
                interner: interner
            ) else {
                continue
            }
            sawTargetMeta = true
            allowedTargets.formUnion(parseAnnotationTargets(from: meta.arguments))
        }

        return sawTargetMeta ? allowedTargets : nil
    }

    private func isTargetMetaAnnotation(
        _ annotation: MetadataAnnotationRecord,
        for annotationSymbol: SymbolID,
        symbols: SymbolTable,
        filesByID: [Int32: ASTFile],
        interner: StringInterner
    ) -> Bool {
        let builtInTargetFQName: [InternedString] = [
            "kotlin",
            "annotation",
            "Target",
        ].map { interner.intern($0) }
        if annotation.annotationFQName == KnownCompilerAnnotation.target.qualifiedName {
            return true
        }

        guard let sourceFileID = symbols.sourceFileID(for: annotationSymbol),
              let sourceFile = filesByID[sourceFileID.rawValue]
        else {
            return false
        }

        guard let resolvedSymbolID = resolveAnnotationSymbol(
            named: annotation.annotationFQName,
            in: sourceFile,
            symbols: symbols,
            interner: interner
        ), let resolvedSymbol = symbols.symbol(resolvedSymbolID)
        else {
            return false
        }

        return resolvedSymbol.fqName == builtInTargetFQName
    }

    private func resolveAnnotationSymbol(
        named rawName: String,
        in file: ASTFile,
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID? {
        let parts = rawName.split(separator: ".").map(String.init)

        if parts.count > 1 {
            let fqName = parts.map { interner.intern($0) }
            if let symbol = symbols.lookup(fqName: fqName),
               symbols.symbol(symbol)?.kind == .annotationClass
            {
                return symbol
            }
        }

        let shortName = interner.intern(parts.last ?? rawName)
        let samePackageFQName = file.packageFQName + [shortName]
        if let symbol = symbols.lookup(fqName: samePackageFQName),
           symbols.symbol(symbol)?.kind == .annotationClass
        {
            return symbol
        }

        for importDecl in file.imports {
            if let alias = importDecl.alias, alias == shortName {
                if let symbol = symbols.lookup(fqName: importDecl.path),
                   symbols.symbol(symbol)?.kind == .annotationClass
                {
                    return symbol
                }
            }

            if importDecl.path.last == shortName {
                if let symbol = symbols.lookup(fqName: importDecl.path),
                   symbols.symbol(symbol)?.kind == .annotationClass
                {
                    return symbol
                }
            }

            if let packageSymbol = symbols.lookup(fqName: importDecl.path),
               symbols.symbol(packageSymbol)?.kind == .package
            {
                if let child = symbols.children(ofFQName: importDecl.path).compactMap({ symbols.symbol($0) }).first(where: { $0.kind == .annotationClass && $0.name == shortName }) {
                    return child.id
                }
            }
        }

        return symbols.lookupByShortName(shortName).first(where: { symbols.symbol($0)?.kind == .annotationClass })
    }

    private func parseAnnotationTargets(from arguments: [String]) -> Set<String> {
        let knownTargets: Set<String> = [
            "CLASS",
            "ANNOTATION_CLASS",
            "TYPE_PARAMETER",
            "PROPERTY",
            "FIELD",
            "LOCAL_VARIABLE",
            "VALUE_PARAMETER",
            "CONSTRUCTOR",
            "FUNCTION",
            "PROPERTY_GETTER",
            "PROPERTY_SETTER",
            "TYPE",
            "EXPRESSION",
            "FILE",
            "TYPEALIAS",
        ]

        var parsed: Set<String> = []
        for argument in arguments {
            let value = annotationArgumentValue(argument)
            let tokens = value.split { character in
                !(character.isLetter || character.isNumber || character == "_")
            }
            for token in tokens {
                let candidate = String(token).uppercased()
                if knownTargets.contains(candidate) {
                    parsed.insert(candidate)
                }
            }
        }
        return parsed
    }

    private func annotationArgumentValue(_ argument: String) -> String {
        let trimmed = argument.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let equalIndex = trimmed.firstIndex(of: "=") else {
            return trimmed
        }
        return trimmed[trimmed.index(after: equalIndex)...].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func annotationTarget(
        site: AnnotationUsageSite,
        allowedTargets: Set<String>,
        decl: Decl?,
        propertySymbol: SymbolID?,
        symbols: SymbolTable
    ) -> Bool {
        switch site {
        case let .classLike(kind):
            if allowedTargets.contains("CLASS") {
                return true
            }
            return kind == .annotationClass && allowedTargets.contains("ANNOTATION_CLASS")
        case .function:
            return allowedTargets.contains("FUNCTION")
        case .valueParameter:
            return allowedTargets.contains("VALUE_PARAMETER")
        case let .property(explicitUseSiteTarget):
            if allowedTargets.contains("PROPERTY") {
                return true
            }
            guard !explicitUseSiteTarget,
                  let propertyDecl = decl.flatMap(propertyDecl(from:)),
                  propertyAllowsFieldTarget(propertyDecl)
            else {
                return false
            }
            return allowedTargets.contains("FIELD")
        case .getter:
            return allowedTargets.contains("PROPERTY_GETTER")
        case .setter:
            return allowedTargets.contains("PROPERTY_SETTER")
        case .field:
            guard let propertyDecl = decl.flatMap(propertyDecl(from:)),
                  propertyAllowsFieldTarget(propertyDecl)
            else {
                return false
            }
            return allowedTargets.contains("FIELD")
        case .delegate:
            guard let propertySymbol,
                  symbols.delegateStorageSymbol(for: propertySymbol) != nil
            else {
                return false
            }
            return allowedTargets.contains("FIELD")
        case .file:
            return allowedTargets.contains("FILE")
        case .type:
            return allowedTargets.contains("TYPE")
        }
    }

    private func annotationTargetMessage(
        annotationName: String,
        site: AnnotationUsageSite
    ) -> String {
        let targetDescription = annotationTargetDescription(for: site)
        return "Annotation '\(annotationName)' is not applicable to \(targetDescription)."
    }

    private func annotationTargetDescription(
        for site: AnnotationUsageSite
    ) -> String {
        switch site {
        case .classLike(let kind):
            switch kind {
            case .annotationClass:
                return "an annotation class declaration"
            case .enumClass:
                return "an enum class declaration"
            case .interface:
                return "an interface declaration"
            case .object:
                return "an object declaration"
            default:
                return "a class declaration"
            }
        case .function:
            return "a function"
        case .valueParameter:
            return "a value parameter"
        case .property:
            return "a property"
        case .getter:
            return "a property getter"
        case .setter:
            return "a property setter"
        case .field:
            return "a backing field"
        case .delegate:
            return "a delegate storage field"
        case .file:
            return "the file"
        case .type:
            return "a type usage"
        }
    }

    private func propertyDecl(from decl: Decl?) -> PropertyDecl? {
        guard case let .propertyDecl(propertyDecl)? = decl else {
            return nil
        }
        return propertyDecl
    }

    private func propertyAllowsFieldTarget(_ propertyDecl: PropertyDecl) -> Bool {
        if propertyDecl.receiverType != nil {
            return false
        }
        if propertyDecl.explicitBackingField != nil {
            return true
        }
        if propertyDecl.delegateExpression != nil {
            return false
        }
        if propertyDecl.modifiers.contains(.abstract) {
            return false
        }
        let isGetterOnlyComputed = propertyDecl.getter != nil
            && propertyDecl.setter == nil
            && propertyDecl.initializer == nil
            && !propertyDecl.isSynthesizedPrimaryConstructorProperty
        if isGetterOnlyComputed {
            return false
        }
        return propertyDecl.initializer != nil
            || propertyDecl.getter != nil
            || propertyDecl.setter != nil
            || propertyDecl.isSynthesizedPrimaryConstructorProperty
    }

    private func ownerRange(for decl: Decl) -> SourceRange {
        switch decl {
        case let .classDecl(classDecl):
            classDecl.range
        case let .interfaceDecl(interfaceDecl):
            interfaceDecl.range
        case let .objectDecl(objectDecl):
            objectDecl.range
        case let .funDecl(funDecl):
            funDecl.range
        case let .propertyDecl(propertyDecl):
            propertyDecl.range
        case let .typeAliasDecl(typeAliasDecl):
            typeAliasDecl.range
        case let .enumEntryDecl(entry):
            entry.range
        }
    }

    private func validateValueParameterAnnotationTargets(
        valueParams: [ValueParamDecl],
        valueParameterSymbols: [SymbolID],
        file: ASTFile,
        symbols: SymbolTable,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        filesByID: [Int32: ASTFile]
    ) {
        for (valueParam, symbolID) in zip(valueParams, valueParameterSymbols) {
            for annotation in valueParam.annotations {
                guard annotation.useSiteTarget == nil else {
                    continue
                }
                validateAnnotationTarget(
                    annotation: annotation,
                    site: .valueParameter,
                    ownerRange: symbols.symbol(symbolID)?.declSite,
                    decl: nil,
                    file: file,
                    propertySymbol: nil,
                    symbols: symbols,
                    diagnostics: diagnostics,
                    interner: interner,
                    filesByID: filesByID
                )
            }
        }
    }

    private enum AnnotationUsageSite {
        case classLike(SymbolKind)
        case function
        case valueParameter
        case property(explicitUseSiteTarget: Bool)
        case getter
        case setter
        case field
        case delegate
        case file
        case type
    }
}

private extension DataFlowSemaPhase {
    func validateTypeAnnotationTargets(
        in decl: Decl,
        file: ASTFile,
        ast: ASTModule,
        symbols: SymbolTable,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        filesByID: [Int32: ASTFile]
    ) {
        switch decl {
        case let .classDecl(classDecl):
            for superType in classDecl.superTypeEntries {
                validateTypeAnnotationTargets(
                    typeRefID: superType.typeRef,
                    ownerRange: classDecl.range,
                    file: file,
                    ast: ast,
                    symbols: symbols,
                    diagnostics: diagnostics,
                    interner: interner,
                    filesByID: filesByID
                )
            }
            for param in classDecl.primaryConstructorParams {
                if let type = param.type {
                    validateTypeAnnotationTargets(typeRefID: type, ownerRange: classDecl.range, file: file, ast: ast, symbols: symbols, diagnostics: diagnostics, interner: interner, filesByID: filesByID)
                }
            }
        case let .interfaceDecl(interfaceDecl):
            for superType in interfaceDecl.superTypes {
                validateTypeAnnotationTargets(typeRefID: superType, ownerRange: interfaceDecl.range, file: file, ast: ast, symbols: symbols, diagnostics: diagnostics, interner: interner, filesByID: filesByID)
            }
        case let .funDecl(funDecl):
            if let receiverType = funDecl.receiverType {
                validateTypeAnnotationTargets(typeRefID: receiverType, ownerRange: funDecl.range, file: file, ast: ast, symbols: symbols, diagnostics: diagnostics, interner: interner, filesByID: filesByID)
            }
            for param in funDecl.valueParams {
                if let type = param.type {
                    validateTypeAnnotationTargets(typeRefID: type, ownerRange: funDecl.range, file: file, ast: ast, symbols: symbols, diagnostics: diagnostics, interner: interner, filesByID: filesByID)
                }
            }
            if let returnType = funDecl.returnType {
                validateTypeAnnotationTargets(typeRefID: returnType, ownerRange: funDecl.range, file: file, ast: ast, symbols: symbols, diagnostics: diagnostics, interner: interner, filesByID: filesByID)
            }
        case let .propertyDecl(propertyDecl):
            if let receiverType = propertyDecl.receiverType {
                validateTypeAnnotationTargets(typeRefID: receiverType, ownerRange: propertyDecl.range, file: file, ast: ast, symbols: symbols, diagnostics: diagnostics, interner: interner, filesByID: filesByID)
            }
            if let type = propertyDecl.type {
                validateTypeAnnotationTargets(typeRefID: type, ownerRange: propertyDecl.range, file: file, ast: ast, symbols: symbols, diagnostics: diagnostics, interner: interner, filesByID: filesByID)
            }
            if let fieldType = propertyDecl.explicitBackingField?.type {
                validateTypeAnnotationTargets(typeRefID: fieldType, ownerRange: propertyDecl.range, file: file, ast: ast, symbols: symbols, diagnostics: diagnostics, interner: interner, filesByID: filesByID)
            }
        case let .typeAliasDecl(typeAliasDecl):
            if let underlyingType = typeAliasDecl.underlyingType {
                validateTypeAnnotationTargets(typeRefID: underlyingType, ownerRange: typeAliasDecl.range, file: file, ast: ast, symbols: symbols, diagnostics: diagnostics, interner: interner, filesByID: filesByID)
            }
        case .objectDecl, .enumEntryDecl:
            break
        }
    }

    func validateTypeAnnotationTargets(
        typeRefID: TypeRefID,
        ownerRange: SourceRange?,
        file: ASTFile,
        ast: ASTModule,
        symbols: SymbolTable,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        filesByID: [Int32: ASTFile]
    ) {
        guard let typeRef = ast.arena.typeRef(typeRefID) else {
            return
        }

        switch typeRef {
        case let .named(_, args, _):
            for arg in args {
                switch arg {
                case let .invariant(inner), let .out(inner), let .in(inner):
                    validateTypeAnnotationTargets(typeRefID: inner, ownerRange: ownerRange, file: file, ast: ast, symbols: symbols, diagnostics: diagnostics, interner: interner, filesByID: filesByID)
                case .star:
                    break
                }
            }
        case let .functionType(contextReceivers, receiver, params, returnType, isSuspend, nullable):
            if let receiver {
                validateTypeAnnotationTargets(typeRefID: receiver, ownerRange: ownerRange, file: file, ast: ast, symbols: symbols, diagnostics: diagnostics, interner: interner, filesByID: filesByID)
            }
            for param in params {
                validateTypeAnnotationTargets(typeRefID: param, ownerRange: ownerRange, file: file, ast: ast, symbols: symbols, diagnostics: diagnostics, interner: interner, filesByID: filesByID)
            }
            validateTypeAnnotationTargets(typeRefID: returnType, ownerRange: ownerRange, file: file, ast: ast, symbols: symbols, diagnostics: diagnostics, interner: interner, filesByID: filesByID)
        case let .intersection(parts):
            for part in parts {
                validateTypeAnnotationTargets(typeRefID: part, ownerRange: ownerRange, file: file, ast: ast, symbols: symbols, diagnostics: diagnostics, interner: interner, filesByID: filesByID)
            }
        case let .annotated(base, annotations):
            for annotation in annotations {
                validateAnnotationTarget(
                    annotation: annotation,
                    site: .type,
                    ownerRange: ownerRange,
                    decl: nil,
                    file: file,
                    propertySymbol: nil,
                    symbols: symbols,
                    diagnostics: diagnostics,
                    interner: interner,
                    filesByID: filesByID
                )
            }
            validateTypeAnnotationTargets(typeRefID: base, ownerRange: ownerRange, file: file, ast: ast, symbols: symbols, diagnostics: diagnostics, interner: interner, filesByID: filesByID)
        }
    }
}
