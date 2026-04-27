import Foundation

extension DataFlowSemaPhase {
    func validateExperimentalTypeInferenceOptIn(
        ast: ASTModule,
        symbols: SymbolTable,
        bindings: BindingTable,
        diagnostics: DiagnosticEngine
    ) {
        for file in ast.sortedFiles {
            for declID in file.topLevelDecls {
                validateExperimentalTypeInferenceOptIn(
                    declID: declID,
                    ast: ast,
                    symbols: symbols,
                    bindings: bindings,
                    diagnostics: diagnostics
                )
            }
        }
    }

    private func validateExperimentalTypeInferenceOptIn(
        declID: DeclID,
        ast: ASTModule,
        symbols: SymbolTable,
        bindings: BindingTable,
        diagnostics: DiagnosticEngine
    ) {
        guard let decl = ast.arena.decl(declID) else {
            return
        }

        if let symbol = bindings.declSymbols[declID] {
            validateExperimentalTypeInferenceOptIn(
                decl: decl,
                symbol: symbol,
                symbols: symbols,
                diagnostics: diagnostics
            )
        }

        for childDeclID in nestedDeclarationIDs(in: decl) {
            validateExperimentalTypeInferenceOptIn(
                declID: childDeclID,
                ast: ast,
                symbols: symbols,
                bindings: bindings,
                diagnostics: diagnostics
            )
        }
    }

    private func validateExperimentalTypeInferenceOptIn(
        decl: Decl,
        symbol: SymbolID,
        symbols: SymbolTable,
        diagnostics: DiagnosticEngine
    ) {
        let annotations = symbols.annotations(for: symbol)
        guard annotations.contains(where: {
            KnownCompilerAnnotation.overloadResolutionByLambdaReturnType.matches($0.annotationFQName)
        }) else {
            return
        }

        guard !annotations.contains(where: isExperimentalTypeInferenceOptInAnnotation) else {
            return
        }

        diagnostics.error(
            "KSWIFTK-SEMA-OPTIN",
            "Declaration annotated with '@OverloadResolutionByLambdaReturnType' must also be annotated with '@OptIn(kotlin.experimental.ExperimentalTypeInference::class)'.",
            range: declarationRange(for: decl)
        )
    }

    private func nestedDeclarationIDs(in decl: Decl) -> [DeclID] {
        switch decl {
        case let .classDecl(classDecl):
            classDecl.memberFunctions
                + classDecl.memberProperties
                + classDecl.nestedClasses
                + classDecl.nestedObjects
        case let .interfaceDecl(interfaceDecl):
            interfaceDecl.memberFunctions
                + interfaceDecl.memberProperties
                + interfaceDecl.nestedClasses
                + interfaceDecl.nestedObjects
        case let .objectDecl(objectDecl):
            objectDecl.memberFunctions
                + objectDecl.memberProperties
                + objectDecl.nestedClasses
                + objectDecl.nestedObjects
        default:
            []
        }
    }

    private func declarationRange(for decl: Decl) -> SourceRange? {
        switch decl {
        case let .classDecl(classDecl):
            classDecl.range
        case let .interfaceDecl(interfaceDecl):
            interfaceDecl.range
        case let .funDecl(funDecl):
            funDecl.range
        case let .propertyDecl(propertyDecl):
            propertyDecl.range
        case let .typeAliasDecl(typeAliasDecl):
            typeAliasDecl.range
        case let .objectDecl(objectDecl):
            objectDecl.range
        case let .enumEntryDecl(enumEntryDecl):
            enumEntryDecl.range
        }
    }

    private func isExperimentalTypeInferenceOptInAnnotation(
        _ annotation: MetadataAnnotationRecord
    ) -> Bool {
        if KnownCompilerAnnotation.experimentalTypeInference.matches(annotation.annotationFQName) {
            return true
        }
        guard KnownCompilerAnnotation.optIn.matches(annotation.annotationFQName) else {
            return false
        }

        return annotation.arguments.contains { argument in
            argument.contains(KnownCompilerAnnotation.experimentalTypeInference.simpleName)
                || argument.contains(KnownCompilerAnnotation.experimentalTypeInference.qualifiedName)
        }
    }

    func validateExperimentalVersionOverloadingOptIn(
        ast: ASTModule,
        symbols: SymbolTable,
        bindings: BindingTable,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        options: CompilerOptions
    ) {
        for file in ast.sortedFiles {
            for declID in file.topLevelDecls {
                validateExperimentalVersionOverloadingOptIn(
                    declID: declID,
                    file: file,
                    ast: ast,
                    symbols: symbols,
                    bindings: bindings,
                    diagnostics: diagnostics,
                    interner: interner,
                    options: options
                )
            }
        }
    }

    private func validateExperimentalVersionOverloadingOptIn(
        declID: DeclID,
        file: ASTFile,
        ast: ASTModule,
        symbols: SymbolTable,
        bindings: BindingTable,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        options: CompilerOptions
    ) {
        guard let decl = ast.arena.decl(declID) else {
            return
        }

        if let symbol = bindings.declSymbols[declID] {
            validateExperimentalVersionOverloadingOptIn(
                decl: decl,
                symbol: symbol,
                file: file,
                symbols: symbols,
                diagnostics: diagnostics,
                interner: interner,
                options: options
            )
        }

        for childDeclID in nestedDeclarationIDs(in: decl) {
            validateExperimentalVersionOverloadingOptIn(
                declID: childDeclID,
                file: file,
                ast: ast,
                symbols: symbols,
                bindings: bindings,
                diagnostics: diagnostics,
                interner: interner,
                options: options
            )
        }
    }

    private func validateExperimentalVersionOverloadingOptIn(
        decl: Decl,
        symbol: SymbolID,
        file: ASTFile,
        symbols: SymbolTable,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        options: CompilerOptions
    ) {
        let annotations = symbols.annotations(for: symbol)
        guard annotations.contains(where: {
            annotationCarriesExperimentalVersionOverloading(
                $0,
                file: file,
                symbols: symbols,
                interner: interner
            )
        }) else {
            return
        }

        guard !isExperimentalVersionOverloadingOptedIn(
            declarationAnnotations: annotations,
            fileAnnotations: file.annotations,
            file: file,
            symbols: symbols,
            interner: interner,
            options: options
        ) else {
            return
        }

        diagnostics.error(
            "KSWIFTK-SEMA-OPT-IN",
            "Annotation usage requires opt-in to '\(KnownCompilerAnnotation.experimentalVersionOverloading.qualifiedName)'. Annotate the declaration with '@OptIn(ExperimentalVersionOverloading::class)' or pass '-opt-in=kotlin.ExperimentalVersionOverloading'.",
            range: declarationRange(for: decl)
        )
    }

    private func annotationCarriesExperimentalVersionOverloading(
        _ annotation: MetadataAnnotationRecord,
        file: ASTFile,
        symbols: SymbolTable,
        interner: StringInterner
    ) -> Bool {
        guard let annotationSymbol = resolveAnnotationClassSymbol(
            named: annotation.annotationFQName,
            in: file,
            symbols: symbols,
            interner: interner
        ) else {
            return false
        }

        return symbols.annotations(for: annotationSymbol).contains {
            KnownCompilerAnnotation.experimentalVersionOverloading.matches($0.annotationFQName)
        }
    }

    private func isExperimentalVersionOverloadingOptedIn(
        declarationAnnotations: [MetadataAnnotationRecord],
        fileAnnotations: [AnnotationNode],
        file: ASTFile,
        symbols: SymbolTable,
        interner: StringInterner,
        options: CompilerOptions
    ) -> Bool {
        let optionMarkers = options.optInMarkerNames
        if optionMarkers.contains(where: {
            optInMarkerNameMatchesExperimentalVersionOverloading(
                $0,
                file: file,
                symbols: symbols,
                interner: interner
            )
        }) {
            return true
        }

        if declarationAnnotations.contains(where: {
            optInAnnotationAcceptsExperimentalVersionOverloading(
                annotationName: $0.annotationFQName,
                arguments: $0.arguments,
                file: file,
                symbols: symbols,
                interner: interner
            )
        }) {
            return true
        }

        return fileAnnotations.contains(where: {
            optInAnnotationAcceptsExperimentalVersionOverloading(
                annotationName: $0.name,
                arguments: $0.arguments,
                file: file,
                symbols: symbols,
                interner: interner
            )
        })
    }

    private func optInAnnotationAcceptsExperimentalVersionOverloading(
        annotationName: String,
        arguments: [String],
        file: ASTFile,
        symbols: SymbolTable,
        interner: StringInterner
    ) -> Bool {
        guard KnownCompilerAnnotation.optIn.matches(annotationName) else {
            return false
        }

        return parseOptInMarkerNames(arguments).contains {
            optInMarkerNameMatchesExperimentalVersionOverloading(
                $0,
                file: file,
                symbols: symbols,
                interner: interner
            )
        }
    }

    private func optInMarkerNameMatchesExperimentalVersionOverloading(
        _ markerName: String,
        file: ASTFile,
        symbols: SymbolTable,
        interner: StringInterner
    ) -> Bool {
        if KnownCompilerAnnotation.experimentalVersionOverloading.matches(markerName) {
            return true
        }

        guard let symbol = resolveAnnotationClassSymbol(
            named: markerName,
            in: file,
            symbols: symbols,
            interner: interner
        ), let symbolInfo = symbols.symbol(symbol)
        else {
            return false
        }

        let expectedFQName = KnownCompilerAnnotation.experimentalVersionOverloading.qualifiedName
            .split(separator: ".")
            .map { interner.intern(String($0)) }
        return symbolInfo.fqName == expectedFQName
    }

    private func parseOptInMarkerNames(_ arguments: [String]) -> [String] {
        var names: [String] = []
        var seen: Set<String> = []
        let pattern = #"([A-Za-z_][A-Za-z0-9_\.]*)\s*::\s*class"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return names
        }

        for argument in arguments {
            let value = optInArgumentValue(argument)
            let nsValue = value as NSString
            let matches = regex.matches(
                in: value,
                range: NSRange(location: 0, length: nsValue.length)
            )
            for match in matches {
                guard match.numberOfRanges > 1 else {
                    continue
                }
                let trimmed = nsValue.substring(with: match.range(at: 1))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "[]()"))
                if !trimmed.isEmpty, seen.insert(trimmed).inserted {
                    names.append(trimmed)
                }
            }
        }

        return names
    }

    private func optInArgumentValue(_ argument: String) -> String {
        let trimmed = argument.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let equalIndex = trimmed.firstIndex(of: "=") else {
            return trimmed
        }
        return String(trimmed[trimmed.index(after: equalIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func resolveAnnotationClassSymbol(
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
            if let alias = importDecl.alias, alias == shortName,
               let symbol = symbols.lookup(fqName: importDecl.path),
               symbols.symbol(symbol)?.kind == .annotationClass
            {
                return symbol
            }

            if importDecl.path.last == shortName,
               let symbol = symbols.lookup(fqName: importDecl.path),
               symbols.symbol(symbol)?.kind == .annotationClass
            {
                return symbol
            }
        }

        return symbols.lookupByShortName(shortName).first {
            symbols.symbol($0)?.kind == .annotationClass
        }
    }
}
