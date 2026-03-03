import Foundation

public enum DiagnosticSeverity: Sendable {
    case error
    case warning
    case note
    case info
}

public struct Diagnostic: Equatable {
    public let severity: DiagnosticSeverity
    public let code: String
    public let message: String
    public let primaryRange: SourceRange?
    public let secondaryRanges: [SourceRange]
    public let codeActions: [DiagnosticCodeAction]

    public init(
        severity: DiagnosticSeverity,
        code: String,
        message: String,
        primaryRange: SourceRange?,
        secondaryRanges: [SourceRange],
        codeActions: [DiagnosticCodeAction] = []
    ) {
        self.severity = severity
        self.code = code
        self.message = message
        self.primaryRange = primaryRange
        self.secondaryRanges = secondaryRanges
        self.codeActions = codeActions
    }
}

// swiftlint:disable:next type_body_length
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

    public func error(
        _ code: String, _ message: String, range: SourceRange?, codeActions: [DiagnosticCodeAction] = []
    ) {
        emit(Diagnostic(
            severity: .error,
            code: code,
            message: message,
            primaryRange: range,
            secondaryRanges: [],
            codeActions: codeActions
        ))
    }

    public func warning(
        _ code: String, _ message: String, range: SourceRange?, codeActions: [DiagnosticCodeAction] = []
    ) {
        emit(Diagnostic(
            severity: .warning,
            code: code,
            message: message,
            primaryRange: range,
            secondaryRanges: [],
            codeActions: codeActions
        ))
    }

    public func note(
        _ code: String, _ message: String, range: SourceRange?, codeActions: [DiagnosticCodeAction] = []
    ) {
        emit(Diagnostic(
            severity: .note,
            code: code,
            message: message,
            primaryRange: range,
            secondaryRanges: [],
            codeActions: codeActions
        ))
    }

    public func info(
        _ code: String, _ message: String, range: SourceRange?, codeActions: [DiagnosticCodeAction] = []
    ) {
        emit(Diagnostic(
            severity: .info,
            code: code,
            message: message,
            primaryRange: range,
            secondaryRanges: [],
            codeActions: codeActions
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
        _diagnostics.sort { diagnosticsOrder(lhs: $0, rhs: $1) }
    }

    public func render(_ sourceManager: SourceManager) -> String {
        lock.lock()
        let ordered = _diagnostics.sorted { diagnosticsOrder(lhs: $0, rhs: $1) }
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

    public func printDiagnostics(
        format: DiagnosticsFormat,
        to stderr: Bool = true,
        from sourceManager: SourceManager
    ) {
        switch format {
        case .json:
            printDiagnosticsJSON(to: stderr, from: sourceManager)
        case .text:
            printDiagnostics(to: stderr, from: sourceManager)
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

    // MARK: - JSON diagnostic output (LSP-compatible)

    /// LSP severity codes: 1 = Error, 2 = Warning, 3 = Information, 4 = Hint.
    private func lspSeverity(for severity: DiagnosticSeverity) -> Int {
        switch severity {
        case .error:
            1
        case .warning:
            2
        case .note:
            3
        case .info:
            4
        }
    }

    /// Renders all diagnostics as a JSON string conforming to the LSP-compatible
    /// schema consumed by language servers and editor integrations.
    ///
    /// Schema version 1:
    /// ```
    /// { "version": 1,
    ///   "diagnostics": [ { "file", "range", "severity", "severityLabel",
    ///                        "code", "source", "message", "codeActions" } ] }
    /// ```
    public func renderJSON(_ sourceManager: SourceManager) -> String {
        let diagnosticsSnapshot: [Diagnostic] = {
            lock.lock()
            defer { lock.unlock() }
            return _diagnostics
        }()
        let ordered = diagnosticsSnapshot.sorted { diagnosticsOrder(lhs: $0, rhs: $1) }

        var entries: [String] = []
        for diag in ordered {
            entries.append(renderDiagnosticJSON(diag, sourceManager: sourceManager))
        }

        let joined = entries.joined(separator: ",\n    ")
        return """
        {
          "version": 1,
          "diagnostics": [
            \(joined)
          ]
        }
        """
    }

    /// Prints diagnostics in JSON format to the given output.
    public func printDiagnosticsJSON(to stderr: Bool = true, from sourceManager: SourceManager) {
        let output = renderJSON(sourceManager)
        if stderr {
            let handle = FileHandle.standardError
            handle.write(output.data(using: .utf8) ?? Data())
            handle.write(Data([0x0A]))
        } else {
            print(output)
        }
    }

    private func renderDiagnosticJSON(_ diagnostic: Diagnostic, sourceManager: SourceManager) -> String {
        let sevLabel = label(for: diagnostic.severity)
        let sevCode = lspSeverity(for: diagnostic.severity)

        var filePath = ""
        var startLine = 0
        var startChar = 0
        var endLine = 0
        var endChar = 0

        if let range = diagnostic.primaryRange {
            filePath = sourceManager.path(of: range.start.file)
            let startLC = sourceManager.lineColumn(of: range.start)
            let endLC = sourceManager.lineColumn(of: range.end)
            // LSP uses 0-based line/character.
            startLine = startLC.line - 1
            startChar = startLC.column - 1
            endLine = endLC.line - 1
            endChar = endLC.column - 1
        }

        // Merge code actions: explicit ones on the diagnostic first, then
        // fall back to registry defaults.
        var actions = diagnostic.codeActions
        if actions.isEmpty, let descriptor = DiagnosticRegistry.lookup(diagnostic.code) {
            actions = descriptor.codeActions
        }

        let actionsJSON = actions.map { action in
            "{ \"title\": \(escapeJSON(action.title)), \"kind\": \(escapeJSON(action.kind)) }"
        }.joined(separator: ", ")

        return """
        {
              "file": \(escapeJSON(filePath)),
              "range": {
                "start": { "line": \(startLine), "character": \(startChar) },
                "end": { "line": \(endLine), "character": \(endChar) }
              },
              "severity": \(sevCode),
              "severityLabel": \(escapeJSON(sevLabel)),
              "code": \(escapeJSON(diagnostic.code)),
              "source": "kswiftk",
              "message": \(escapeJSON(diagnostic.message)),
              "codeActions": [\(actionsJSON)]
            }
        """
    }

    private func escapeJSON(_ value: String) -> String {
        var result = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"":
                result += "\\\""
            case "\\":
                result += "\\\\"
            case "\u{8}":
                result += "\\b"
            case "\u{C}":
                result += "\\f"
            case "\n":
                result += "\\n"
            case "\r":
                result += "\\r"
            case "\t":
                result += "\\t"
            case let scalar where scalar.value < 0x20:
                result += String(format: "\\u%04X", scalar.value)
            default:
                result += String(scalar)
            }
        }
        result += "\""
        return result
    }
}
