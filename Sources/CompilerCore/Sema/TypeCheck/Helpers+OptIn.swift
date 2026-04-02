import Foundation

extension TypeCheckHelpers {
    private enum OptInLevel {
        case warning
        case error
    }

    private struct OptInRequirement {
        let markerSymbol: SymbolID
        let markerName: String
        let message: String
        let level: OptInLevel
    }

    func checkOptIn(
        for symbolID: SymbolID,
        ctx: TypeInferenceContext,
        range: SourceRange?,
        diagnostics: DiagnosticEngine
    ) {
        let requirements = requiredOptInRequirements(for: symbolID, ctx: ctx)
        guard !requirements.isEmpty else {
            return
        }
        let optedInMarkers = activeOptInMarkers(in: ctx)
        for requirement in requirements {
            guard !optedInMarkers.contains(requirement.markerSymbol) else {
                continue
            }

            let messageSuffix = requirement.message.isEmpty ? "" : " \(requirement.message)"
            let diagnosticMessage = "'\(requirement.markerName)' requires opt-in. " +
                "Annotate the usage with '@\(requirement.markerName)' or '@OptIn(\(requirement.markerName)::class)'.\(messageSuffix)"

            switch requirement.level {
            case .warning:
                diagnostics.warning(
                    "KSWIFTK-SEMA-OPT-IN",
                    diagnosticMessage,
                    range: range
                )
            case .error:
                diagnostics.error(
                    "KSWIFTK-SEMA-OPT-IN",
                    diagnosticMessage,
                    range: range
                )
            }
        }
    }

    func checkOptInForType(
        _ type: TypeID,
        ctx: TypeInferenceContext,
        range: SourceRange?,
        diagnostics: DiagnosticEngine
    ) {
        var visitedTypes: Set<TypeID> = []
        var visitedSymbols: Set<SymbolID> = []
        checkOptInForType(
            type,
            ctx: ctx,
            range: range,
            diagnostics: diagnostics,
            visitedTypes: &visitedTypes,
            visitedSymbols: &visitedSymbols
        )
    }

    private func checkOptInForType(
        _ type: TypeID,
        ctx: TypeInferenceContext,
        range: SourceRange?,
        diagnostics: DiagnosticEngine,
        visitedTypes: inout Set<TypeID>,
        visitedSymbols: inout Set<SymbolID>
    ) {
        guard visitedTypes.insert(type).inserted else {
            return
        }

        switch ctx.sema.types.kind(of: type) {
        case .unit, .any, .primitive, .typeParam, .nothing, .error:
            return

        case let .classType(classType):
            if visitedSymbols.insert(classType.classSymbol).inserted {
                checkOptIn(
                    for: classType.classSymbol,
                    ctx: ctx,
                    range: range,
                    diagnostics: diagnostics
                )
            }
            for arg in classType.args {
                if let inner = typeArgType(arg) {
                    checkOptInForType(
                        inner,
                        ctx: ctx,
                        range: range,
                        diagnostics: diagnostics,
                        visitedTypes: &visitedTypes,
                        visitedSymbols: &visitedSymbols
                    )
                }
            }

        case let .functionType(functionType):
            if let receiverType = functionType.receiver {
                checkOptInForType(
                    receiverType,
                    ctx: ctx,
                    range: range,
                    diagnostics: diagnostics,
                    visitedTypes: &visitedTypes,
                    visitedSymbols: &visitedSymbols
                )
            }
            for parameterType in functionType.params {
                checkOptInForType(
                    parameterType,
                    ctx: ctx,
                    range: range,
                    diagnostics: diagnostics,
                    visitedTypes: &visitedTypes,
                    visitedSymbols: &visitedSymbols
                )
            }
            checkOptInForType(
                functionType.returnType,
                ctx: ctx,
                range: range,
                diagnostics: diagnostics,
                visitedTypes: &visitedTypes,
                visitedSymbols: &visitedSymbols
            )

        case let .intersection(parts):
            for part in parts {
                checkOptInForType(
                    part,
                    ctx: ctx,
                    range: range,
                    diagnostics: diagnostics,
                    visitedTypes: &visitedTypes,
                    visitedSymbols: &visitedSymbols
                )
            }

        case let .kClassType(kClassType):
            checkOptInForType(
                kClassType.argument,
                ctx: ctx,
                range: range,
                diagnostics: diagnostics,
                visitedTypes: &visitedTypes,
                visitedSymbols: &visitedSymbols
            )
        }
    }

    private func requiredOptInRequirements(
        for symbolID: SymbolID,
        ctx: TypeInferenceContext
    ) -> [OptInRequirement] {
        let annotations = ctx.sema.symbols.annotations(for: symbolID)
        guard !annotations.isEmpty else {
            return []
        }

        let sourceFile = sourceFile(for: symbolID, ctx: ctx)
        var requirements: [OptInRequirement] = []
        var seenMarkers: Set<SymbolID> = []

        for annotation in annotations {
            guard let annotationSymbol = resolveAnnotationClassSymbol(
                named: annotation.annotationFQName,
                file: sourceFile,
                ctx: ctx
            ) else {
                continue
            }
            guard let requirement = optInRequirement(forMarkerAnnotation: annotationSymbol, ctx: ctx),
                  seenMarkers.insert(requirement.markerSymbol).inserted
            else {
                continue
            }
            requirements.append(requirement)
        }

        return requirements
    }

    private func optInRequirement(
        forMarkerAnnotation markerSymbol: SymbolID,
        ctx: TypeInferenceContext
    ) -> OptInRequirement? {
        for metaAnnotation in ctx.sema.symbols.annotations(for: markerSymbol)
            where KnownCompilerAnnotation.requiresOptIn.matches(metaAnnotation.annotationFQName)
        {
            let parsed = parseRequiresOptInArguments(metaAnnotation.arguments)
            let markerName = renderSymbolName(markerSymbol, ctx: ctx)
            return OptInRequirement(
                markerSymbol: markerSymbol,
                markerName: markerName,
                message: parsed.message,
                level: parsed.level
            )
        }
        return nil
    }

    private func activeOptInMarkers(in ctx: TypeInferenceContext) -> Set<SymbolID> {
        var markers: Set<SymbolID> = []

        if let file = currentFile(in: ctx) {
            collectOptInMarkers(
                from: file.annotations,
                file: file,
                ctx: ctx,
                into: &markers
            )
        }

        var symbol = ctx.currentDeclSymbol
        while let current = symbol {
            collectOptInMarkers(
                from: ctx.sema.symbols.annotations(for: current),
                file: sourceFile(for: current, ctx: ctx) ?? currentFile(in: ctx),
                ctx: ctx,
                into: &markers
            )
            symbol = ctx.sema.symbols.parentSymbol(for: current)
        }

        return markers
    }

    private func collectOptInMarkers(
        from annotations: [MetadataAnnotationRecord],
        file: ASTFile?,
        ctx: TypeInferenceContext,
        into markers: inout Set<SymbolID>
    ) {
        for annotation in annotations {
            if KnownCompilerAnnotation.optIn.matches(annotation.annotationFQName) {
                for markerName in parseOptInMarkerNames(annotation.arguments) {
                    if let markerSymbol = resolveAnnotationClassSymbol(
                        named: markerName,
                        file: file,
                        ctx: ctx
                    ) {
                        markers.insert(markerSymbol)
                    }
                }
            }

            // If this annotation is itself a @RequiresOptIn marker, it implicitly
            // grants opt-in for that marker within the annotated declaration's scope.
            if let annotationSymbol = resolveAnnotationClassSymbol(
                named: annotation.annotationFQName,
                file: file,
                ctx: ctx
            ),
               optInRequirement(forMarkerAnnotation: annotationSymbol, ctx: ctx) != nil
            {
                markers.insert(annotationSymbol)
            }
        }
    }

    private func collectOptInMarkers(
        from annotations: [AnnotationNode],
        file: ASTFile,
        ctx: TypeInferenceContext,
        into markers: inout Set<SymbolID>
    ) {
        for annotation in annotations {
            if KnownCompilerAnnotation.optIn.matches(annotation.name) {
                for markerName in parseOptInMarkerNames(annotation.arguments) {
                    if let markerSymbol = resolveAnnotationClassSymbol(
                        named: markerName,
                        file: file,
                        ctx: ctx
                    ) {
                        markers.insert(markerSymbol)
                    }
                }
            }

            // If this annotation is itself a @RequiresOptIn marker, it implicitly
            // grants opt-in for that marker within the annotated declaration's scope.
            if let annotationSymbol = resolveAnnotationClassSymbol(
                named: annotation.name,
                file: file,
                ctx: ctx
            ),
               optInRequirement(forMarkerAnnotation: annotationSymbol, ctx: ctx) != nil
            {
                markers.insert(annotationSymbol)
            }
        }
    }

    private func parseRequiresOptInArguments(
        _ arguments: [String]
    ) -> (message: String, level: OptInLevel) {
        var namedArgs: [String: String] = [:]
        var positionalArgs: [String] = []

        for raw in arguments {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }
            if let (name, value) = splitOptInNamedArgument(trimmed) {
                namedArgs[name.lowercased()] = value
            } else {
                positionalArgs.append(trimmed)
            }
        }

        let message = normalizeOptInStringLiteral(namedArgs["message"] ?? positionalArgs.first ?? "")
        let levelCandidate = namedArgs["level"] ?? positionalArgs.first(where: { parseOptInLevel($0) != nil })
        return (
            message: message,
            level: parseOptInLevel(levelCandidate) ?? .error
        )
    }

    private func parseOptInLevel(_ raw: String?) -> OptInLevel? {
        guard var raw else {
            return nil
        }
        raw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        raw = normalizeOptInStringLiteral(raw)
        let normalized = raw.replacingOccurrences(of: " ", with: "")
        let levelName = normalized.split(separator: ".").last.map(String.init)?.uppercased() ?? normalized.uppercased()
        return switch levelName {
        case "WARNING":
            .warning
        case "ERROR":
            .error
        default:
            nil
        }
    }

    private func parseOptInMarkerNames(_ arguments: [String]) -> [String] {
        var names: [String] = []
        var seen: Set<String> = []
        let pattern = #"[A-Za-z_][A-Za-z0-9_\.]*\s*::\s*class"#

        for argument in arguments {
            let value = optInArgumentValue(argument)
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                continue
            }
            let nsValue = value as NSString
            let matches = regex.matches(
                in: value,
                range: NSRange(location: 0, length: nsValue.length)
            )
            for match in matches {
                let rawMatch = nsValue.substring(with: match.range)
                let trimmed = rawMatch
                    .replacingOccurrences(of: "::class", with: "")
                    .replacingOccurrences(of: ":: class", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "[]()"))
                guard !trimmed.isEmpty, seen.insert(trimmed).inserted else {
                    continue
                }
                names.append(trimmed)
            }

            if matches.isEmpty,
               let normalized = normalizeOptInMarkerName(value),
               seen.insert(normalized).inserted
            {
                names.append(normalized)
            }
        }

        return names
    }

    private func normalizeOptInMarkerName(_ raw: String) -> String? {
        let trimmed = optInArgumentValue(raw)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]()"))
        guard !trimmed.isEmpty else {
            return nil
        }

        let suffixes = ["::class", ".class", ":class", "class"]
        for suffix in suffixes where trimmed.count > suffix.count && trimmed.hasSuffix(suffix) {
            return String(trimmed.dropLast(suffix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return nil
    }

    private func optInArgumentValue(_ argument: String) -> String {
        let trimmed = argument.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let equalIndex = trimmed.firstIndex(of: "=") else {
            return trimmed
        }
        return String(trimmed[trimmed.index(after: equalIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func splitOptInNamedArgument(_ argument: String) -> (String, String)? {
        guard let equalIndex = argument.firstIndex(of: "=") else {
            return nil
        }
        let name = String(argument[..<equalIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        let value = String(argument[argument.index(after: equalIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !value.isEmpty else {
            return nil
        }
        return (name, value)
    }

    private func normalizeOptInStringLiteral(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasPrefix("\"") || value.hasPrefix("'") {
            value.removeFirst()
        }
        while value.hasSuffix("\"") || value.hasSuffix("'") {
            value.removeLast()
        }
        return value
    }

    private func resolveAnnotationClassSymbol(
        named rawName: String,
        file: ASTFile?,
        ctx: TypeInferenceContext
    ) -> SymbolID? {
        let parts = rawName
            .split(separator: ".")
            .map(String.init)
            .filter { !$0.isEmpty }

        if parts.count > 1 {
            let fqName = parts.map { ctx.interner.intern($0) }
            if let symbol = ctx.sema.symbols.lookup(fqName: fqName),
               ctx.sema.symbols.symbol(symbol)?.kind == .annotationClass
            {
                return symbol
            }
        }

        guard let shortPart = parts.last ?? rawName.split(separator: ".").last.map(String.init) else {
            return nil
        }
        let shortName = ctx.interner.intern(shortPart)

        if let file {
            let samePackageFQName = file.packageFQName + [shortName]
            if let symbol = ctx.sema.symbols.lookup(fqName: samePackageFQName),
               ctx.sema.symbols.symbol(symbol)?.kind == .annotationClass
            {
                return symbol
            }

            for importDecl in file.imports {
                if let alias = importDecl.alias, alias == shortName,
                   let symbol = ctx.sema.symbols.lookup(fqName: importDecl.path),
                   ctx.sema.symbols.symbol(symbol)?.kind == .annotationClass
                {
                    return symbol
                }

                if importDecl.path.last == shortName,
                   let symbol = ctx.sema.symbols.lookup(fqName: importDecl.path),
                   ctx.sema.symbols.symbol(symbol)?.kind == .annotationClass
                {
                    return symbol
                }
            }
        }

        return ctx.sema.symbols.lookupByShortName(shortName).first {
            ctx.sema.symbols.symbol($0)?.kind == .annotationClass
        }
    }

    private func currentFile(in ctx: TypeInferenceContext) -> ASTFile? {
        ctx.ast.sortedFiles.first(where: { $0.fileID == ctx.currentFileID })
    }

    private func sourceFile(
        for symbolID: SymbolID,
        ctx: TypeInferenceContext
    ) -> ASTFile? {
        guard let fileID = ctx.sema.symbols.sourceFileID(for: symbolID) else {
            return currentFile(in: ctx)
        }
        return ctx.ast.sortedFiles.first(where: { $0.fileID == fileID })
    }

    private func renderSymbolName(_ symbolID: SymbolID, ctx: TypeInferenceContext) -> String {
        guard let symbol = ctx.sema.symbols.symbol(symbolID) else {
            return "<unknown>"
        }
        return symbol.fqName.map { ctx.interner.resolve($0) }.joined(separator: ".")
    }

    private func typeArgType(_ arg: TypeArg) -> TypeID? {
        switch arg {
        case .invariant(let type), .in(let type), .out(let type):
            type
        case .star:
            nil
        }
    }
}
