public enum DiagnosticSeverity {
    case error
    case warning
    case note
    case info
}

import Foundation

public struct Diagnostic: Equatable {
    public let severity: DiagnosticSeverity
    public let code: String
    public let message: String
    public let primaryRange: SourceRange?
    public let secondaryRanges: [SourceRange]
}

public final class DiagnosticEngine {
    public private(set) var diagnostics: [Diagnostic] = []

    public init() {}

    public func emit(_ d: Diagnostic) {
        diagnostics.append(d)
    }

    public func error(_ code: String, _ message: String, range: SourceRange?) {
        emit(Diagnostic(
            severity: .error,
            code: code,
            message: message,
            primaryRange: range,
            secondaryRanges: []
        ))
    }

    public func warning(_ code: String, _ message: String, range: SourceRange?) {
        emit(Diagnostic(
            severity: .warning,
            code: code,
            message: message,
            primaryRange: range,
            secondaryRanges: []
        ))
    }

    public func note(_ code: String, _ message: String, range: SourceRange?) {
        emit(Diagnostic(
            severity: .note,
            code: code,
            message: message,
            primaryRange: range,
            secondaryRanges: []
        ))
    }

    public func info(_ code: String, _ message: String, range: SourceRange?) {
        emit(Diagnostic(
            severity: .info,
            code: code,
            message: message,
            primaryRange: range,
            secondaryRanges: []
        ))
    }

    public var hasError: Bool {
        diagnostics.contains(where: { $0.severity == .error })
    }

    public func render(_ sourceManager: SourceManager) -> String {
        let ordered = diagnostics.sorted { lhs, rhs in
            let lhsKey = renderSortKey(for: lhs, sourceManager: sourceManager)
            let rhsKey = renderSortKey(for: rhs, sourceManager: sourceManager)

            if lhsKey.path != rhsKey.path { return lhsKey.path < rhsKey.path }
            if lhsKey.line != rhsKey.line { return lhsKey.line < rhsKey.line }
            if lhsKey.column != rhsKey.column { return lhsKey.column < rhsKey.column }
            if lhsKey.offset != rhsKey.offset { return lhsKey.offset < rhsKey.offset }
            if lhsKey.severityRank != rhsKey.severityRank { return lhsKey.severityRank < rhsKey.severityRank }
            return lhsKey.code < rhsKey.code
        }
        return ordered.map { formatDiagnostic($0, sourceManager: sourceManager) }.joined(separator: "\n")
    }

    public func printDiagnostics(to stderr: Bool = true, from sourceManager: SourceManager) {
        let output = render(sourceManager)
        if output.isEmpty { return }
        if stderr {
            let handle = FileHandle.standardError
            handle.write(output.data(using: .utf8) ?? Data())
            handle.write(Data([0x0A]))
        } else {
            print(output)
        }
    }

    private func formatDiagnostic(_ diagnostic: Diagnostic, sourceManager: SourceManager) -> String {
        let severityLabel = label(for: diagnostic.severity)
        if let range = diagnostic.primaryRange {
            let position = sourceManager.lineColumn(of: range.start)
            let path = sourceManager.path(of: range.start.file)
            return "\(path):\(position.line):\(position.column): \(severityLabel) \(diagnostic.code): \(diagnostic.message)"
        }
        return "\(severityLabel) \(diagnostic.code): \(diagnostic.message)"
    }

    private func label(for severity: DiagnosticSeverity) -> String {
        switch severity {
        case .error:
            return "error"
        case .warning:
            return "warning"
        case .note:
            return "note"
        case .info:
            return "info"
        }
    }

    private func renderSortKey(for diagnostic: Diagnostic, sourceManager: SourceManager) -> (
        path: String,
        line: Int,
        column: Int,
        offset: Int,
        severityRank: Int,
        code: String
    ) {
        guard let range = diagnostic.primaryRange else {
            return (
                path: "\u{10FFFF}",
                line: Int.max,
                column: Int.max,
                offset: Int.max,
                severityRank: severityRank(for: diagnostic.severity),
                code: diagnostic.code
            )
        }
        let position = sourceManager.lineColumn(of: range.start)
        return (
            path: sourceManager.path(of: range.start.file),
            line: position.line,
            column: position.column,
            offset: range.start.offset,
            severityRank: severityRank(for: diagnostic.severity),
            code: diagnostic.code
        )
    }

    private func severityRank(for severity: DiagnosticSeverity) -> Int {
        switch severity {
        case .error:
            return 0
        case .warning:
            return 1
        case .note:
            return 2
        case .info:
            return 3
        }
    }
}
