import Foundation

extension DataFlowSemaPhase {
    func validateAnnotationOptInRequirements(
        ast: ASTModule,
        symbols: SymbolTable,
        bindings: BindingTable,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        options: CompilerOptions
    ) {
        for file in ast.sortedFiles {
            var activeMarkers = compilerOptionOptInMarkers(
                file: file,
                symbols: symbols,
                interner: interner,
                options: options
            )
            collectAnnotationOptInMarkers(
                from: file.annotations,
                file: file,
                symbols: symbols,
                interner: interner,
                into: &activeMarkers
            )

            for annotation in file.annotations {
                validateAnnotationOptInRequirement(
                    annotation: annotation,
                    activeMarkers: activeMarkers,
                    file: file,
                    ownerRange: file.range,
                    symbols: symbols,
                    diagnostics: diagnostics,
                    interner: interner
                )
            }

            for declID in file.topLevelDecls {
                validateAnnotationOptInRequirements(
                    declID: declID,
                    file: file,
                    ast: ast,
                    symbols: symbols,
                    bindings: bindings,
                    diagnostics: diagnostics,
                    interner: interner,
                    inheritedMarkers: activeMarkers
                )
            }
        }
    }

    private func validateAnnotationOptInRequirements(
        declID: DeclID,
        file: ASTFile,
        ast: ASTModule,
        symbols: SymbolTable,
        bindings: BindingTable,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        inheritedMarkers: Set<SymbolID>
    ) {
        guard let decl = ast.arena.decl(declID) else {
            return
        }

        var activeMarkers = inheritedMarkers
        let annotations = declarationAnnotations(for: decl)
        collectAnnotationOptInMarkers(
            from: annotations,
            file: file,
            symbols: symbols,
            interner: interner,
            into: &activeMarkers
        )

        for annotation in annotations {
            validateAnnotationOptInRequirement(
                annotation: annotation,
                activeMarkers: activeMarkers,
                file: file,
                ownerRange: annotationOptInOwnerRange(for: decl),
                symbols: symbols,
                diagnostics: diagnostics,
                interner: interner
            )
        }

        validateValueParameterAnnotationOptInRequirements(
            in: decl,
            file: file,
            ast: ast,
            symbols: symbols,
            diagnostics: diagnostics,
            interner: interner,
            activeMarkers: activeMarkers
        )

        for childDeclID in annotationOptInNestedDeclarationIDs(in: decl) {
            validateAnnotationOptInRequirements(
                declID: childDeclID,
                file: file,
                ast: ast,
                symbols: symbols,
                bindings: bindings,
                diagnostics: diagnostics,
                interner: interner,
                inheritedMarkers: activeMarkers
            )
        }
    }

    private func validateValueParameterAnnotationOptInRequirements(
        in decl: Decl,
        file: ASTFile,
        ast _: ASTModule,
        symbols: SymbolTable,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        activeMarkers: Set<SymbolID>
    ) {
        let groups: [([ValueParamDecl], SourceRange?)] = switch decl {
        case let .classDecl(classDecl):
            [(classDecl.primaryConstructorParams, classDecl.range)]
                + classDecl.secondaryConstructors.map { ($0.valueParams, $0.range) }
        case let .funDecl(funDecl):
            [(funDecl.valueParams, funDecl.range)]
        default:
            []
        }

        for (parameters, ownerRange) in groups {
            for parameter in parameters {
                var parameterMarkers = activeMarkers
                collectAnnotationOptInMarkers(
                    from: parameter.annotations,
                    file: file,
                    symbols: symbols,
                    interner: interner,
                    into: &parameterMarkers
                )
                for annotation in parameter.annotations {
                    validateAnnotationOptInRequirement(
                        annotation: annotation,
                        activeMarkers: parameterMarkers,
                        file: file,
                        ownerRange: ownerRange,
                        symbols: symbols,
                        diagnostics: diagnostics,
                        interner: interner
                    )
                }
            }
        }
    }

    private func validateAnnotationOptInRequirement(
        annotation: AnnotationNode,
        activeMarkers: Set<SymbolID>,
        file: ASTFile,
        ownerRange: SourceRange?,
        symbols: SymbolTable,
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) {
        guard let annotationSymbol = resolveAnnotationOptInSymbol(
            named: annotation.name,
            file: file,
            symbols: symbols,
            interner: interner
        ), !isOptInMarkerAnnotation(
            annotationSymbol,
            symbols: symbols
        ) else {
            return
        }

        let requirements = annotationOptInRequirements(
            forAnnotationSymbol: annotationSymbol,
            file: file,
            symbols: symbols,
            interner: interner
        )
        for requirement in requirements where !activeMarkers.contains(requirement.markerSymbol) {
            let message = "'\(requirement.markerName)' requires opt-in. " +
                "Annotate the usage with '@\(requirement.markerName)' or '@OptIn(\(requirement.markerName)::class)', " +
                "or pass '-opt-in=\(requirement.markerName)'."
            switch requirement.level {
            case .warning:
                diagnostics.warning("KSWIFTK-SEMA-OPT-IN", message, range: ownerRange)
            case .error:
                diagnostics.error("KSWIFTK-SEMA-OPT-IN", message, range: ownerRange)
            }
        }
    }

    private struct AnnotationOptInRequirement {
        let markerSymbol: SymbolID
        let markerName: String
        let level: AnnotationOptInLevel
    }

    private enum AnnotationOptInLevel {
        case warning
        case error
    }

    private func annotationOptInRequirements(
        forAnnotationSymbol annotationSymbol: SymbolID,
        file: ASTFile,
        symbols: SymbolTable,
        interner: StringInterner
    ) -> [AnnotationOptInRequirement] {
        var requirements: [AnnotationOptInRequirement] = []
        var seenMarkers: Set<SymbolID> = []

        for meta in symbols.annotations(for: annotationSymbol) {
            guard let markerSymbol = resolveAnnotationOptInSymbol(
                named: meta.annotationFQName,
                file: file,
                symbols: symbols,
                interner: interner
            ), seenMarkers.insert(markerSymbol).inserted,
                let requirement = annotationOptInRequirement(
                    forMarkerAnnotation: markerSymbol,
                    symbols: symbols,
                    interner: interner
                )
            else {
                continue
            }
            requirements.append(requirement)
        }

        return requirements
    }

    private func annotationOptInRequirement(
        forMarkerAnnotation markerSymbol: SymbolID,
        symbols: SymbolTable,
        interner: StringInterner
    ) -> AnnotationOptInRequirement? {
        for metaAnnotation in symbols.annotations(for: markerSymbol)
            where KnownCompilerAnnotation.requiresOptIn.matches(metaAnnotation.annotationFQName)
        {
            return AnnotationOptInRequirement(
                markerSymbol: markerSymbol,
                markerName: renderAnnotationOptInSymbolName(markerSymbol, symbols: symbols, interner: interner),
                level: parseAnnotationOptInLevel(metaAnnotation.arguments)
            )
        }
        return nil
    }

    private func isOptInMarkerAnnotation(
        _ annotationSymbol: SymbolID,
        symbols: SymbolTable
    ) -> Bool {
        symbols.annotations(for: annotationSymbol).contains {
            KnownCompilerAnnotation.requiresOptIn.matches($0.annotationFQName)
        }
    }

    private func compilerOptionOptInMarkers(
        file: ASTFile,
        symbols: SymbolTable,
        interner: StringInterner,
        options: CompilerOptions
    ) -> Set<SymbolID> {
        var markers: Set<SymbolID> = []
        for markerName in options.optInAnnotationNames {
            if let markerSymbol = resolveAnnotationOptInSymbol(
                named: markerName,
                file: file,
                symbols: symbols,
                interner: interner
            ) {
                markers.insert(markerSymbol)
            }
        }
        return markers
    }

    private func collectAnnotationOptInMarkers(
        from annotations: [AnnotationNode],
        file: ASTFile,
        symbols: SymbolTable,
        interner: StringInterner,
        into markers: inout Set<SymbolID>
    ) {
        for annotation in annotations {
            if KnownCompilerAnnotation.optIn.matches(annotation.name) {
                for markerName in parseAnnotationOptInMarkerNames(annotation.arguments) {
                    if let markerSymbol = resolveAnnotationOptInSymbol(
                        named: markerName,
                        file: file,
                        symbols: symbols,
                        interner: interner
                    ) {
                        markers.insert(markerSymbol)
                    }
                }
                continue
            }

            if let annotationSymbol = resolveAnnotationOptInSymbol(
                named: annotation.name,
                file: file,
                symbols: symbols,
                interner: interner
            ), isOptInMarkerAnnotation(annotationSymbol, symbols: symbols) {
                markers.insert(annotationSymbol)
            }
        }
    }

    private func parseAnnotationOptInMarkerNames(_ arguments: [String]) -> [String] {
        var names: [String] = []
        var seen: Set<String> = []
        let pattern = #"[A-Za-z_][A-Za-z0-9_\.]*\s*::\s*class"#

        for argument in arguments {
            let value = annotationOptInArgumentValue(argument)
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                continue
            }
            let nsValue = value as NSString
            let matches = regex.matches(in: value, range: NSRange(location: 0, length: nsValue.length))
            for match in matches {
                let rawMatch = nsValue.substring(with: match.range)
                let markerName = rawMatch
                    .replacingOccurrences(of: "::class", with: "")
                    .replacingOccurrences(of: ":: class", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "[]()"))
                guard !markerName.isEmpty, seen.insert(markerName).inserted else {
                    continue
                }
                names.append(markerName)
            }

            if matches.isEmpty,
               let markerName = normalizeAnnotationOptInMarkerName(value),
               seen.insert(markerName).inserted
            {
                names.append(markerName)
            }
        }

        return names
    }

    private func parseAnnotationOptInLevel(_ arguments: [String]) -> AnnotationOptInLevel {
        for argument in arguments {
            let value = annotationOptInArgumentValue(argument)
            let normalized = value
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
                .replacingOccurrences(of: " ", with: "")
                .split(separator: ".")
                .last
                .map(String.init)?
                .uppercased() ?? ""
            if normalized == "WARNING" {
                return .warning
            }
            if normalized == "ERROR" {
                return .error
            }
        }
        return .error
    }

    private func normalizeAnnotationOptInMarkerName(_ raw: String) -> String? {
        let trimmed = annotationOptInArgumentValue(raw)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]()"))
        guard !trimmed.isEmpty else {
            return nil
        }
        for suffix in ["::class", ".class", ":class", "class"] where trimmed.count > suffix.count && trimmed.hasSuffix(suffix) {
            return String(trimmed.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private func annotationOptInArgumentValue(_ argument: String) -> String {
        let trimmed = argument.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let equalIndex = trimmed.firstIndex(of: "=") else {
            return trimmed
        }
        return String(trimmed[trimmed.index(after: equalIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func resolveAnnotationOptInSymbol(
        named rawName: String,
        file: ASTFile,
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

            if let packageSymbol = symbols.lookup(fqName: importDecl.path),
               symbols.symbol(packageSymbol)?.kind == .package
            {
                let children = symbols.children(ofFQName: importDecl.path)
                if let child = children.first(where: {
                    symbols.symbol($0)?.kind == .annotationClass
                        && symbols.symbol($0)?.name == shortName
                }) {
                    return child
                }
            }
        }

        return symbols.lookupByShortName(shortName).first {
            symbols.symbol($0)?.kind == .annotationClass
        }
    }

    private func renderAnnotationOptInSymbolName(
        _ symbolID: SymbolID,
        symbols: SymbolTable,
        interner: StringInterner
    ) -> String {
        guard let symbol = symbols.symbol(symbolID) else {
            return "<unknown>"
        }
        return symbol.fqName.map { interner.resolve($0) }.joined(separator: ".")
    }

    private func annotationOptInOwnerRange(for decl: Decl) -> SourceRange? {
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
        case let .enumEntryDecl(enumEntryDecl):
            enumEntryDecl.range
        }
    }

    private func annotationOptInNestedDeclarationIDs(in decl: Decl) -> [DeclID] {
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
}
