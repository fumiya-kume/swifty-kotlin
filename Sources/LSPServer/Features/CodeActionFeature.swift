import CompilerCore

/// Builds LSP quick-fixes from compiler diagnostics with source-backed edits.
public enum CodeActionFeature {
    public static func codeActions(
        for analysis: Analyzer.Analysis,
        params: CodeActionParams
    ) -> [LSPCodeAction] {
        guard
            analysis.uri == params.textDocument.uri,
            let fileID = analysis.fileID
        else {
            return []
        }
        let sourceManager = analysis.context.sourceManager
        guard let requestRange = validatedRange(
            params.range,
            fileID: fileID,
            sourceManager: sourceManager
        ) else {
            return []
        }

        let currentDiagnostics = analysis.diagnostics.compactMap { diagnostic -> (Diagnostic, LSPDiagnostic)? in
            guard let primaryRange = diagnostic.primaryRange,
                  primaryRange.start.file == fileID,
                  primaryRange.end.file == fileID
            else {
                return nil
            }
            let lspDiagnostic = LSPDiagnostic(
                range: LSPConvert.range(primaryRange, sourceManager),
                severity: severity(for: diagnostic.severity).rawValue,
                code: diagnostic.code,
                source: "kswiftk",
                message: diagnostic.message
            )
            return (diagnostic, lspDiagnostic)
        }

        return currentDiagnostics.flatMap { diagnostic, lspDiagnostic in
            guard rangesOverlap(lspDiagnostic.range, requestRange),
                  matchesContext(lspDiagnostic, params.context.diagnostics),
                  let actions = sourceBackedActions(for: diagnostic, analysis: analysis)
            else {
                return [LSPCodeAction]()
            }

            return actions.compactMap { action in
                guard kindIsAllowed(action.kind, by: params.context.only) else {
                    return nil
                }
                let edits = action.edits.compactMap { edit -> LSPTextEdit? in
                    guard edit.range.start.file == fileID, edit.range.end.file == fileID else {
                        return nil
                    }
                    return LSPTextEdit(
                        range: LSPConvert.range(edit.range, sourceManager),
                        newText: edit.newText
                    )
                }
                guard !edits.isEmpty else { return nil }
                let workspaceEdit = WorkspaceEdit(changes: [params.textDocument.uri: edits])
                return LSPCodeAction(
                    title: action.title,
                    kind: action.kind,
                    diagnostics: [lspDiagnostic],
                    edit: workspaceEdit
                )
            }
        }
    }

    private static func sourceBackedActions(
        for diagnostic: Diagnostic,
        analysis: Analyzer.Analysis
    ) -> [DiagnosticCodeAction]? {
        let explicit = diagnostic.codeActions.filter { !$0.edits.isEmpty }
        if !explicit.isEmpty {
            return explicit
        }

        switch diagnostic.code {
        case "KSWIFTK-SEMA-OVERRIDE":
            guard let editRange = declarationModifierInsertionRange(
                for: diagnostic,
                analysis: analysis
            ) else {
                return nil
            }
            return [DiagnosticCodeAction(
                title: "Add 'override' keyword",
                edits: [DiagnosticTextEdit(range: editRange, newText: "override ")]
            )]

        case "KSWIFTK-SEMA-0080":
            guard let editRange = constModifierRemovalRange(
                for: diagnostic,
                analysis: analysis
            ) else {
                return nil
            }
            return [DiagnosticCodeAction(
                title: "Remove 'const' modifier",
                edits: [DiagnosticTextEdit(range: editRange, newText: "")]
            )]

        default:
            return nil
        }
    }

    private static func declarationModifierInsertionRange(
        for diagnostic: Diagnostic,
        analysis: Analyzer.Analysis
    ) -> SourceRange? {
        guard let diagnosticRange = diagnostic.primaryRange,
              let tokens = tokens(for: diagnosticRange.start.file, in: analysis)
        else {
            return nil
        }

        for token in tokens where token.range.start.file == diagnosticRange.start.file {
            guard diagnosticRange.contains(token.range) else { continue }
            switch token.kind {
            case .keyword(.fun), .keyword(.val), .keyword(.var):
                return SourceRange(start: token.range.start, end: token.range.start)
            default:
                continue
            }
        }
        return nil
    }

    private static func constModifierRemovalRange(
        for diagnostic: Diagnostic,
        analysis: Analyzer.Analysis
    ) -> SourceRange? {
        guard let diagnosticRange = diagnostic.primaryRange,
              let tokens = tokens(for: diagnosticRange.start.file, in: analysis)
        else {
            return nil
        }

        for index in tokens.indices {
            let token = tokens[index]
            guard token.range.start.file == diagnosticRange.start.file,
                  diagnosticRange.contains(token.range),
                  token.kind == .keyword(.const)
            else {
                continue
            }
            guard let nextIndex = tokens.index(index, offsetBy: 1, limitedBy: tokens.index(before: tokens.endIndex)) else {
                return nil
            }
            let next = tokens[nextIndex]
            guard next.kind == .keyword(.var), next.range.start.file == diagnosticRange.start.file else {
                return nil
            }
            let gap = SourceRange(start: token.range.end, end: next.range.start)
            let gapText = analysis.context.sourceManager.slice(gap)
            let end = gapText.unicodeScalars.allSatisfy(Self.isHorizontalWhitespace)
                ? next.range.start
                : token.range.end
            return SourceRange(start: token.range.start, end: end)
        }
        return nil
    }

    private static func tokens(for fileID: FileID, in analysis: Analyzer.Analysis) -> [Token]? {
        analysis.context.tokensByFile.first(where: { $0.0 == fileID })?.1
    }

    private static func validatedRange(
        _ range: LSPRange,
        fileID: FileID,
        sourceManager: SourceManager
    ) -> LSPRange? {
        guard isNonNegative(range.start), isNonNegative(range.end), isOrdered(range) else {
            return nil
        }
        guard positionIsWithinDocument(range.start, fileID: fileID, sourceManager: sourceManager),
              positionIsWithinDocument(range.end, fileID: fileID, sourceManager: sourceManager),
              let startOffset = sourceManager.offset(
                  ofLine: range.start.line,
                  utf16Character: range.start.character,
                  in: fileID
              ),
              let endOffset = sourceManager.offset(
                  ofLine: range.end.line,
                  utf16Character: range.end.character,
                  in: fileID
              ),
              startOffset <= endOffset
        else {
            return nil
        }
        return range
    }

    private static func positionIsWithinDocument(
        _ position: LSPPosition,
        fileID: FileID,
        sourceManager: SourceManager
    ) -> Bool {
        let endOffset = sourceManager.contents(of: fileID).count
        let end = sourceManager.lspPosition(of: SourceLocation(file: fileID, offset: endOffset))
        if position.line > end.line { return false }
        if position.line == end.line, position.character > end.character { return false }
        return true
    }

    private static func isNonNegative(_ position: LSPPosition) -> Bool {
        position.line >= 0 && position.character >= 0
    }

    private static func isOrdered(_ range: LSPRange) -> Bool {
        if range.start.line != range.end.line {
            return range.start.line < range.end.line
        }
        return range.start.character <= range.end.character
    }

    private static func rangesOverlap(_ lhs: LSPRange, _ rhs: LSPRange) -> Bool {
        !isBefore(lhs.end, rhs.start) && !isBefore(rhs.end, lhs.start)
    }

    private static func isBefore(_ lhs: LSPPosition, _ rhs: LSPPosition) -> Bool {
        lhs.line < rhs.line || (lhs.line == rhs.line && lhs.character < rhs.character)
    }

    private static func matchesContext(_ diagnostic: LSPDiagnostic, _ context: [LSPDiagnostic]) -> Bool {
        guard !context.isEmpty else { return true }
        return context.contains { candidate in
            candidate.code == diagnostic.code && candidate.range == diagnostic.range
        }
    }

    private static func kindIsAllowed(_ kind: String, by only: [String]?) -> Bool {
        guard let only, !only.isEmpty else { return true }
        return only.contains { requested in
            kind == requested || kind.hasPrefix(requested + ".")
        }
    }

    private static func severity(for severity: DiagnosticSeverity) -> LSPDiagnosticSeverity {
        switch severity {
        case .error: .error
        case .warning: .warning
        case .note: .information
        case .info: .hint
        }
    }

    private static func isHorizontalWhitespace(_ scalar: Unicode.Scalar) -> Bool {
        scalar == " " || scalar == "\t"
    }
}
