import XCTest
@testable import CompilerCore

final class DiagnosticEngineTests: XCTestCase {

    // MARK: - Emit and Severity Helpers

    func testEmitAppendsDiagnostic() {
        let engine = DiagnosticEngine()
        let diag = Diagnostic(
            severity: .error,
            code: "E001",
            message: "test error",
            primaryRange: nil,
            secondaryRanges: []
        )
        engine.emit(diag)
        XCTAssertEqual(engine.diagnostics.count, 1)
        XCTAssertEqual(engine.diagnostics[0].code, "E001")
    }

    func testErrorHelperEmitsErrorSeverity() {
        let engine = DiagnosticEngine()
        engine.error("E-ERR", "an error", range: nil)
        XCTAssertEqual(engine.diagnostics.count, 1)
        XCTAssertEqual(engine.diagnostics[0].severity, .error)
        XCTAssertEqual(engine.diagnostics[0].code, "E-ERR")
        XCTAssertEqual(engine.diagnostics[0].message, "an error")
        XCTAssertNil(engine.diagnostics[0].primaryRange)
    }

    func testWarningHelperEmitsWarningSeverity() {
        let engine = DiagnosticEngine()
        engine.warning("W-WARN", "a warning", range: nil)
        XCTAssertEqual(engine.diagnostics.count, 1)
        XCTAssertEqual(engine.diagnostics[0].severity, .warning)
    }

    func testNoteHelperEmitsNoteSeverity() {
        let engine = DiagnosticEngine()
        engine.note("N-NOTE", "a note", range: nil)
        XCTAssertEqual(engine.diagnostics.count, 1)
        XCTAssertEqual(engine.diagnostics[0].severity, .note)
    }

    func testInfoHelperEmitsInfoSeverity() {
        let engine = DiagnosticEngine()
        engine.info("I-INFO", "info msg", range: nil)
        XCTAssertEqual(engine.diagnostics.count, 1)
        XCTAssertEqual(engine.diagnostics[0].severity, .info)
    }

    func testEmitWithRange() {
        let engine = DiagnosticEngine()
        let range = makeRange(start: 5, end: 10)
        engine.error("E-RANGE", "has range", range: range)
        XCTAssertEqual(engine.diagnostics[0].primaryRange, range)
    }

    // MARK: - hasError

    func testHasErrorReturnsFalseWhenEmpty() {
        let engine = DiagnosticEngine()
        XCTAssertFalse(engine.hasError)
    }

    func testHasErrorReturnsTrueAfterError() {
        let engine = DiagnosticEngine()
        engine.error("E", "err", range: nil)
        XCTAssertTrue(engine.hasError)
    }

    func testHasErrorReturnsFalseForWarningOnly() {
        let engine = DiagnosticEngine()
        engine.warning("W", "warn", range: nil)
        XCTAssertFalse(engine.hasError)
    }

    func testHasErrorReturnsFalseForNoteOnly() {
        let engine = DiagnosticEngine()
        engine.note("N", "note", range: nil)
        XCTAssertFalse(engine.hasError)
    }

    func testHasErrorReturnsFalseForInfoOnly() {
        let engine = DiagnosticEngine()
        engine.info("I", "info", range: nil)
        XCTAssertFalse(engine.hasError)
    }

    // MARK: - Render

    func testRenderReturnsEmptyStringWhenNoDiagnostics() {
        let engine = DiagnosticEngine()
        let sm = SourceManager()
        XCTAssertEqual(engine.render(sm), "")
    }

    func testRenderFormatsWithoutRange() {
        let engine = DiagnosticEngine()
        engine.error("E-001", "something bad", range: nil)
        let sm = SourceManager()
        let rendered = engine.render(sm)
        XCTAssertTrue(rendered.contains("error E-001: something bad"))
    }

    func testRenderFormatsWithRange() {
        let sm = SourceManager()
        let fileID = sm.addFile(path: "test.kt", contents: Data("line1\nline2\n".utf8))
        let range = SourceRange(
            start: SourceLocation(file: fileID, offset: 6),
            end: SourceLocation(file: fileID, offset: 11)
        )
        let engine = DiagnosticEngine()
        engine.error("E-002", "bad line2", range: range)
        let rendered = engine.render(sm)
        XCTAssertTrue(rendered.contains("test.kt:2:1:"))
        XCTAssertTrue(rendered.contains("error E-002: bad line2"))
    }

    func testRenderSortsByFileThenLineColumn() {
        let sm = SourceManager()
        let fileA = sm.addFile(path: "a.kt", contents: Data("abc\ndef\n".utf8))
        let fileB = sm.addFile(path: "b.kt", contents: Data("xyz\n".utf8))

        let engine = DiagnosticEngine()
        engine.error("E-B", "in b", range: SourceRange(
            start: SourceLocation(file: fileB, offset: 0),
            end: SourceLocation(file: fileB, offset: 3)
        ))
        engine.error("E-A1", "in a line 2", range: SourceRange(
            start: SourceLocation(file: fileA, offset: 4),
            end: SourceLocation(file: fileA, offset: 7)
        ))
        engine.error("E-A0", "in a line 1", range: SourceRange(
            start: SourceLocation(file: fileA, offset: 0),
            end: SourceLocation(file: fileA, offset: 3)
        ))

        let rendered = engine.render(sm)
        let lines = rendered.split(separator: "\n")
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines[0].contains("E-A0"))
        XCTAssertTrue(lines[1].contains("E-A1"))
        XCTAssertTrue(lines[2].contains("E-B"))
    }

    func testRenderSortsSeveritiesWithinSameLocation() {
        let sm = SourceManager()
        let fileID = sm.addFile(path: "same.kt", contents: Data("x\n".utf8))
        let range = SourceRange(
            start: SourceLocation(file: fileID, offset: 0),
            end: SourceLocation(file: fileID, offset: 1)
        )

        let engine = DiagnosticEngine()
        engine.warning("W-1", "warn", range: range)
        engine.error("E-1", "err", range: range)

        let rendered = engine.render(sm)
        let lines = rendered.split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        // Errors (rank 0) come before warnings (rank 1)
        XCTAssertTrue(lines[0].contains("error"))
        XCTAssertTrue(lines[1].contains("warning"))
    }

    func testRenderRangelessDiagnosticsComeLast() {
        let sm = SourceManager()
        let fileID = sm.addFile(path: "f.kt", contents: Data("a\n".utf8))

        let engine = DiagnosticEngine()
        engine.error("E-NORANGE", "no range", range: nil)
        engine.error("E-RANGE", "has range", range: SourceRange(
            start: SourceLocation(file: fileID, offset: 0),
            end: SourceLocation(file: fileID, offset: 1)
        ))

        let rendered = engine.render(sm)
        let lines = rendered.split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[0].contains("E-RANGE"))
        XCTAssertTrue(lines[1].contains("E-NORANGE"))
    }

    func testRenderSeverityLabels() {
        let sm = SourceManager()
        let engine = DiagnosticEngine()
        engine.error("E", "e", range: nil)
        engine.warning("W", "w", range: nil)
        engine.note("N", "n", range: nil)
        engine.info("I", "i", range: nil)

        let rendered = engine.render(sm)
        XCTAssertTrue(rendered.contains("error E:"))
        XCTAssertTrue(rendered.contains("warning W:"))
        XCTAssertTrue(rendered.contains("note N:"))
        XCTAssertTrue(rendered.contains("info I:"))
    }

    // MARK: - Multiple Diagnostics

    func testMultipleDiagnosticsAccumulateInOrder() {
        let engine = DiagnosticEngine()
        engine.error("E1", "first", range: nil)
        engine.warning("W1", "second", range: nil)
        engine.note("N1", "third", range: nil)
        XCTAssertEqual(engine.diagnostics.count, 3)
        XCTAssertEqual(engine.diagnostics[0].code, "E1")
        XCTAssertEqual(engine.diagnostics[1].code, "W1")
        XCTAssertEqual(engine.diagnostics[2].code, "N1")
    }

    // MARK: - Diagnostic Equality

    func testDiagnosticEquality() {
        let d1 = Diagnostic(severity: .error, code: "E", message: "m", primaryRange: nil, secondaryRanges: [])
        let d2 = Diagnostic(severity: .error, code: "E", message: "m", primaryRange: nil, secondaryRanges: [])
        let d3 = Diagnostic(severity: .warning, code: "E", message: "m", primaryRange: nil, secondaryRanges: [])
        XCTAssertEqual(d1, d2)
        XCTAssertNotEqual(d1, d3)
    }

    func testDiagnosticWithSecondaryRanges() {
        let range1 = makeRange(start: 0, end: 5)
        let range2 = makeRange(start: 10, end: 15)
        let d = Diagnostic(
            severity: .error,
            code: "E",
            message: "m",
            primaryRange: range1,
            secondaryRanges: [range2]
        )
        XCTAssertEqual(d.secondaryRanges.count, 1)
        XCTAssertEqual(d.secondaryRanges[0], range2)
    }
}
