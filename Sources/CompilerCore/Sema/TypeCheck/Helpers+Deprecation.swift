import Foundation

// ANNO-001: @Deprecated annotation checking helpers.

extension TypeCheckHelpers {
    private enum DeprecatedLevel {
        case warning
        case error
    }

    private struct DeprecatedArguments {
        let message: String
        let level: DeprecatedLevel
        let replaceWith: String?
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
            var deprecationMessage = parsed.message.isEmpty
                ? "'\(symbolName)' is deprecated."
                : "'\(symbolName)' is deprecated. \(parsed.message)"
            let codeActions: [DiagnosticCodeAction]
            if let replaceWith = parsed.replaceWith, !replaceWith.isEmpty {
                deprecationMessage += " Replace with: \(replaceWith)"
                codeActions = [DiagnosticCodeAction(title: "Replace with '\(replaceWith)'")]
            } else {
                codeActions = []
            }

            if parsed.level == .error {
                diagnostics.error(
                    "KSWIFTK-SEMA-DEPRECATED",
                    deprecationMessage,
                    range: range,
                    codeActions: codeActions
                )
            } else {
                diagnostics.warning(
                    "KSWIFTK-SEMA-DEPRECATED",
                    deprecationMessage,
                    range: range,
                    codeActions: codeActions
                )
            }
            return // Only emit one deprecation diagnostic per symbol reference.
        }
    }

    private func parseDeprecatedArguments(_ arguments: [String]) -> DeprecatedArguments {
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
        let replaceWithCandidate = namedArgs["replacewith"]
            ?? positionalArgs.first(where: { isReplaceWithExpression($0) })
        let replaceWith = parseReplaceWithExpression(replaceWithCandidate)

        return DeprecatedArguments(message: message, level: level, replaceWith: replaceWith)
    }

    private func splitNamedArgument(_ argument: String) -> (String, String)? {
        guard let equalIndex = firstTopLevelIndex(of: "=", in: argument) else {
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

    private func isReplaceWithExpression(_ raw: String) -> Bool {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.hasPrefix(KnownCompilerAnnotation.replaceWith.simpleName + "(")
            || normalized.hasPrefix(KnownCompilerAnnotation.replaceWith.qualifiedName + "(")
    }

    private func parseReplaceWithExpression(_ raw: String?) -> String? {
        guard let raw else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isReplaceWithExpression(trimmed),
              let lParen = trimmed.firstIndex(of: "("),
              let rParen = trimmed.lastIndex(of: ")"),
              lParen < rParen
        else {
            return nil
        }

        let innerStart = trimmed.index(after: lParen)
        let inner = String(trimmed[innerStart..<rParen])
        let arguments = splitAnnotationArguments(inner)
        var namedArgs: [String: String] = [:]
        var positionalArgs: [String] = []
        for argument in arguments {
            if let (name, value) = splitNamedArgument(argument) {
                namedArgs[name.lowercased()] = value
            } else {
                positionalArgs.append(argument)
            }
        }

        let expressionCandidate = namedArgs["expression"] ?? positionalArgs.first
        let expression = expressionCandidate.map(normalizeAnnotationStringLiteral) ?? ""
        return expression.isEmpty ? nil : expression
    }

    private func splitAnnotationArguments(_ raw: String) -> [String] {
        var arguments: [String] = []
        var current = ""
        var parenDepth = 0
        var bracketDepth = 0
        var braceDepth = 0
        var inString = false
        var stringDelimiter: Character?
        var previousWasEscape = false

        for character in raw {
            current.append(character)
            if inString {
                if character == "\\" && !previousWasEscape {
                    previousWasEscape = true
                    continue
                }
                if character == stringDelimiter && !previousWasEscape {
                    inString = false
                    stringDelimiter = nil
                }
                previousWasEscape = false
                continue
            }

            switch character {
            case "\"", "'":
                inString = true
                stringDelimiter = character
                previousWasEscape = false
            case "(":
                parenDepth += 1
            case ")":
                parenDepth = max(0, parenDepth - 1)
            case "[":
                bracketDepth += 1
            case "]":
                bracketDepth = max(0, bracketDepth - 1)
            case "{":
                braceDepth += 1
            case "}":
                braceDepth = max(0, braceDepth - 1)
            case "," where parenDepth == 0 && bracketDepth == 0 && braceDepth == 0:
                current.removeLast()
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    arguments.append(trimmed)
                }
                current = ""
            default:
                break
            }
        }

        let trailing = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trailing.isEmpty {
            arguments.append(trailing)
        }
        return arguments
    }

    private func firstTopLevelIndex(of character: Character, in raw: String) -> String.Index? {
        var parenDepth = 0
        var bracketDepth = 0
        var braceDepth = 0
        var inString = false
        var stringDelimiter: Character?
        var previousWasEscape = false

        for index in raw.indices {
            let current = raw[index]
            if inString {
                if current == "\\" && !previousWasEscape {
                    previousWasEscape = true
                    continue
                }
                if current == stringDelimiter && !previousWasEscape {
                    inString = false
                    stringDelimiter = nil
                }
                previousWasEscape = false
                continue
            }

            switch current {
            case "\"", "'":
                inString = true
                stringDelimiter = current
                previousWasEscape = false
            case "(":
                parenDepth += 1
            case ")":
                parenDepth = max(0, parenDepth - 1)
            case "[":
                bracketDepth += 1
            case "]":
                bracketDepth = max(0, bracketDepth - 1)
            case "{":
                braceDepth += 1
            case "}":
                braceDepth = max(0, braceDepth - 1)
            default:
                break
            }

            if current == character,
               parenDepth == 0,
               bracketDepth == 0,
               braceDepth == 0
            {
                return index
            }
        }
        return nil
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
