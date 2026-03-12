import Foundation

// ANNO-001: @Deprecated annotation checking helpers.

extension TypeCheckHelpers {
    private enum DeprecatedLevel {
        case warning
        case error
    }

    /// Checks whether `symbol` has a `@Deprecated` annotation and emits an appropriate
    /// diagnostic at `range` (the call/reference site).
    ///
    /// - `@Deprecated("msg")` or `@Deprecated("msg", level = WARNING)` -> warning
    /// - `@Deprecated("msg", level = ERROR)` -> error
    func checkDeprecation(
        for symbolID: SymbolID,
        sema: SemaModule,
        interner: StringInterner,
        range: SourceRange?,
        diagnostics: DiagnosticEngine
    ) {
        let annotations = sema.symbols.annotations(for: symbolID)
        for ann in annotations
            where KnownCompilerAnnotation.deprecated.matches(ann.annotationFQName)
        {
            let symbolName = if let sym = sema.symbols.symbol(symbolID) {
                sym.fqName.map { interner.resolve($0) }.joined(separator: ".")
            } else {
                "<unknown>"
            }
            let parsed = parseDeprecatedArguments(ann.arguments)
            let deprecationMessage = parsed.message.isEmpty
                ? "'\(symbolName)' is deprecated."
                : "'\(symbolName)' is deprecated. \(parsed.message)"

            if parsed.level == .error {
                diagnostics.error(
                    "KSWIFTK-SEMA-DEPRECATED",
                    deprecationMessage,
                    range: range
                )
            } else {
                diagnostics.warning(
                    "KSWIFTK-SEMA-DEPRECATED",
                    deprecationMessage,
                    range: range
                )
            }
            return // Only emit one deprecation diagnostic per symbol reference.
        }
    }

    private func parseDeprecatedArguments(_ arguments: [String]) -> (message: String, level: DeprecatedLevel) {
        var namedArgs: [String: String] = [:]
        var positionalArgs: [String] = []

        for raw in arguments {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }
            if let (name, value) = splitNamedArgument(trimmed) {
                namedArgs[name.lowercased()] = value
            } else {
                positionalArgs.append(trimmed)
            }
        }

        let messageCandidate = namedArgs["message"] ?? positionalArgs.first
        let message = messageCandidate.map(normalizeAnnotationStringLiteral) ?? ""

        let levelCandidate = namedArgs["level"] ?? positionalArgs.first(where: { parseDeprecatedLevel($0) != nil })
        let level = parseDeprecatedLevel(levelCandidate) ?? .warning

        return (message, level)
    }

    private func splitNamedArgument(_ argument: String) -> (String, String)? {
        guard let equalIndex = argument.firstIndex(of: "=") else {
            return nil
        }
        let name = argument[..<equalIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        let value = argument[argument.index(after: equalIndex)...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !value.isEmpty else {
            return nil
        }
        return (name, value)
    }

    private func parseDeprecatedLevel(_ raw: String?) -> DeprecatedLevel? {
        guard var raw else {
            return nil
        }
        raw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        raw = normalizeAnnotationStringLiteral(raw)
        let normalized = raw.replacingOccurrences(of: " ", with: "")
        let levelName = normalized.split(separator: ".").last.map(String.init)?.uppercased() ?? normalized.uppercased()
        return switch levelName {
        case "ERROR":
            .error
        case "WARNING", "HIDDEN":
            .warning
        default:
            nil
        }
    }

    private func normalizeAnnotationStringLiteral(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasPrefix("\"") || value.hasPrefix("'") {
            value.removeFirst()
        }
        while value.hasSuffix("\"") || value.hasSuffix("'") {
            value.removeLast()
        }
        return value
    }
}
