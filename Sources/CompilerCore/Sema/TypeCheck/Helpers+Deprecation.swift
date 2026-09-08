import Foundation

// ANNO-001: @Deprecated annotation checking helpers.

private struct KotlinCompilerVersion: Comparable {
    let major: Int
    let minor: Int
    let patch: Int

    static func < (lhs: KotlinCompilerVersion, rhs: KotlinCompilerVersion) -> Bool {
        if lhs.major != rhs.major {
            return lhs.major < rhs.major
        }
        if lhs.minor != rhs.minor {
            return lhs.minor < rhs.minor
        }
        return lhs.patch < rhs.patch
    }

    init?(rawValue: String) {
        let components = rawValue.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 2 || components.count == 3,
              let major = Int(components[0]),
              let minor = Int(components[1]) else {
            return nil
        }
        let patch = components.count == 3 ? Int(components[2]) : 0
        guard let patch, major >= 0, minor >= 0, patch >= 0 else {
            return nil
        }
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }
}

// Keep this in sync with the Kotlin target used by the bundled stdlib
// artifact (currently 2.3.10).
private let kotlinCompilerTargetVersion = KotlinCompilerVersion(major: 2, minor: 3, patch: 10)

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

    private struct DeprecatedSinceKotlinArguments {
        let warningSince: KotlinCompilerVersion?
        let errorSince: KotlinCompilerVersion?
        let hiddenSince: KotlinCompilerVersion?
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
        guard let deprecatedAnnotation = annotations.first(where: {
            KnownCompilerAnnotation.deprecated.matches($0.annotationFQName)
        }) else {
            return
        }

        let symbolName = if let sym = sema.symbols.symbol(symbolID) {
            sym.fqName.map { interner.resolve($0) }.joined(separator: ".")
        } else {
            "<unknown>"
        }
        let parsed = parseDeprecatedArguments(deprecatedAnnotation.arguments)
        let sinceArguments = annotations.first(where: {
            KnownCompilerAnnotation.deprecatedSinceKotlin.matches($0.annotationFQName)
        }).map { parseDeprecatedSinceKotlinArguments($0.arguments) }

        // An explicit @Deprecated(level = ERROR) remains authoritative.  The
        // SinceKotlin metadata only refines the default warning level used by
        // the stdlib as the target compiler version advances.
        let severity: DeprecatedSeverity = if parsed.level == .error {
            .error
        } else if let sinceArguments {
            deprecatedSeverity(for: sinceArguments)
        } else {
            .warning
        }
        guard severity != .none else {
            return
        }

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

        if severity == .error {
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

    func checkBuiltinDeprecation(
        calleeName: InternedString,
        receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner,
        range: SourceRange?,
        diagnostics: DiagnosticEngine
    ) {
        let callee = interner.resolve(calleeName)
        guard callee == "toChar" else {
            return
        }

        let receiver = sema.types.makeNonNullable(receiverType)
        let deprecatedReceiverTypes: Set<TypeID> = [
            sema.types.intType,
            sema.types.longType,
            sema.types.uintType,
            sema.types.ulongType,
            sema.types.ubyteType,
            sema.types.ushortType,
        ]
        guard deprecatedReceiverTypes.contains(receiver) else {
            return
        }

        let toCharFQName: [InternedString] = [interner.intern("kotlin"), calleeName]
        guard let symbolID = sema.symbols.lookupAll(fqName: toCharFQName).first(where: { candidate in
            guard let signature = sema.symbols.functionSignature(for: candidate) else {
                return false
            }
            return signature.receiverType == receiver
        }) else {
            return
        }

        checkDeprecation(
            for: symbolID,
            sema: sema,
            interner: interner,
            range: range,
            diagnostics: diagnostics
        )
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

    private enum DeprecatedSeverity {
        case none
        case warning
        case error
    }

    private func parseDeprecatedSinceKotlinArguments(_ arguments: [String]) -> DeprecatedSinceKotlinArguments {
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

        func parseVersion(_ raw: String?) -> KotlinCompilerVersion? {
            guard let raw else {
                return nil
            }
            let normalized = normalizeAnnotationStringLiteral(raw)
            guard !normalized.isEmpty else {
                return nil
            }
            return KotlinCompilerVersion(rawValue: normalized)
        }

        func positional(_ index: Int) -> String? {
            positionalArgs.indices.contains(index) ? positionalArgs[index] : nil
        }

        return DeprecatedSinceKotlinArguments(
            warningSince: parseVersion(namedArgs["warningsince"] ?? positional(0)),
            errorSince: parseVersion(namedArgs["errorsince"] ?? positional(1)),
            hiddenSince: parseVersion(namedArgs["hiddensince"] ?? positional(2))
        )
    }

    private func deprecatedSeverity(for arguments: DeprecatedSinceKotlinArguments) -> DeprecatedSeverity {
        if let errorSince = arguments.errorSince, kotlinCompilerTargetVersion >= errorSince {
            return .error
        }
        if let warningSince = arguments.warningSince, kotlinCompilerTargetVersion >= warningSince {
            return .warning
        }
        // A SinceKotlin annotation keeps the declaration available without a
        // deprecation diagnostic until its first visible threshold is reached.
        // Lookup hiding based on hiddenSince is outside this helper and remains
        // unsupported, so hiddenSince-only metadata keeps the historical warning.
        if arguments.warningSince != nil || arguments.errorSince != nil {
            return .none
        }
        return .warning
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
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // Annotation arguments are rebuilt from raw tokens. Determine whether
        // the value is a string literal (regular or raw, with optional
        // multi-dollar prefix) and extract its content. Raw strings must not
        // be escape-decoded; regular strings are decoded like any other
        // Kotlin string literal.
        if let extraction = extractKotlinStringLiteralContent(value) {
            return extraction.isRaw ? extraction.content : decodeKotlinStringEscapes(extraction.content)
        }

        return decodeKotlinStringEscapes(value)
    }
}
