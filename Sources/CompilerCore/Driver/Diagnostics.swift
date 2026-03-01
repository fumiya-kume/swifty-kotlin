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

public final class DiagnosticEngine: @unchecked Sendable {
    private let lock = NSLock()
    private var _diagnostics: [Diagnostic] = []

    public var diagnostics: [Diagnostic] {
        lock.lock()
        defer { lock.unlock() }
        return _diagnostics
    }

    public init() {}

    public func emit(_ diagnostic: Diagnostic) {
        lock.lock()
        defer { lock.unlock() }
        _diagnostics.append(diagnostic)
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
        lock.lock()
        defer { lock.unlock() }
        return _diagnostics.contains(where: { $0.severity == .error })
    }

    /// Sort the diagnostics array in-place by source location for deterministic
    /// ordering after parallel phases where lock-acquisition order is arbitrary.
    public func sortBySourceLocation() {
        lock.lock()
        defer { lock.unlock() }
        _diagnostics.sort(by: diagnosticsOrder(lhs:rhs:))
    }

    public func render(_ sourceManager: SourceManager) -> String {
        lock.lock()
        let ordered = _diagnostics.sorted(by: diagnosticsOrder(lhs:rhs:))
        lock.unlock()
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
            "error"
        case .warning:
            "warning"
        case .note:
            "note"
        case .info:
            "info"
        }
    }

    private func diagnosticsOrder(lhs: Diagnostic, rhs: Diagnostic) -> Bool {
        guard let lhsRange = lhs.primaryRange else {
            guard rhs.primaryRange != nil else {
                return tieBreak(lhs: lhs, rhs: rhs)
            }
            return false
        }
        guard let rhsRange = rhs.primaryRange else {
            return true
        }
        if lhsRange.start.file.rawValue != rhsRange.start.file.rawValue {
            return lhsRange.start.file.rawValue < rhsRange.start.file.rawValue
        }
        if lhsRange.start.offset != rhsRange.start.offset {
            return lhsRange.start.offset < rhsRange.start.offset
        }
        return tieBreak(lhs: lhs, rhs: rhs)
    }

    private func tieBreak(lhs: Diagnostic, rhs: Diagnostic) -> Bool {
        let lhsSeverity = severityRank(for: lhs.severity)
        let rhsSeverity = severityRank(for: rhs.severity)
        if lhsSeverity != rhsSeverity { return lhsSeverity < rhsSeverity }
        if lhs.code != rhs.code { return lhs.code < rhs.code }
        return lhs.message < rhs.message
    }

    private func severityRank(for severity: DiagnosticSeverity) -> Int {
        switch severity {
        case .error:
            0
        case .warning:
            1
        case .note:
            2
        case .info:
            3
        }
    }
}
