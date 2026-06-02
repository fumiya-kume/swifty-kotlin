import CompilerCore

/// Converts compiler diagnostics into LSP diagnostics for `publishDiagnostics`.
public enum DiagnosticsFeature {
    /// Builds the LSP diagnostics belonging to the analyzed document.
    ///
    /// Diagnostics that carry a primary range in a different file are skipped;
    /// range-less diagnostics are anchored at the start of the document so they
    /// are still surfaced to the user.
    public static func lspDiagnostics(for analysis: Analyzer.Analysis) -> [LSPDiagnostic] {
        let sourceManager = analysis.context.sourceManager
        var result: [LSPDiagnostic] = []

        for diagnostic in analysis.diagnostics {
            let lspRange: LSPRange
            if let range = diagnostic.primaryRange {
                if let fileID = analysis.fileID, range.start.file != fileID {
                    continue
                }
                lspRange = LSPConvert.range(range, sourceManager)
            } else {
                let origin = LSPPosition(line: 0, character: 0)
                lspRange = LSPRange(start: origin, end: origin)
            }

            result.append(LSPDiagnostic(
                range: lspRange,
                severity: severity(for: diagnostic.severity).rawValue,
                code: diagnostic.code,
                source: "kswiftk",
                message: diagnostic.message
            ))
        }

        return result
    }

    private static func severity(for severity: DiagnosticSeverity) -> LSPDiagnosticSeverity {
        switch severity {
        case .error: .error
        case .warning: .warning
        case .note: .information
        case .info: .hint
        }
    }
}
