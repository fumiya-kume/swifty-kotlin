// swiftlint:disable file_length type_body_length
@testable import CompilerCore
import XCTest

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
        let srcMgr = SourceManager()
        XCTAssertEqual(engine.render(srcMgr), "")
    }

    func testRenderFormatsWithoutRange() {
        let engine = DiagnosticEngine()
        engine.error("E-001", "something bad", range: nil)
        let srcMgr = SourceManager()
        let rendered = engine.render(srcMgr)
        XCTAssertTrue(rendered.contains("error E-001: something bad"))
    }

    func testRenderFormatsWithRange() {
        let srcMgr = SourceManager()
        let fileID = srcMgr.addFile(path: "test.kt", contents: Data("line1\nline2\n".utf8))
        let range = SourceRange(
            start: SourceLocation(file: fileID, offset: 6),
            end: SourceLocation(file: fileID, offset: 11)
        )
        let engine = DiagnosticEngine()
        engine.error("E-002", "bad line2", range: range)
        let rendered = engine.render(srcMgr)
        XCTAssertTrue(rendered.contains("test.kt:2:1:"))
        XCTAssertTrue(rendered.contains("error E-002: bad line2"))
    }

    func testRenderSortsByFileThenLineColumn() {
        let srcMgr = SourceManager()
        let fileA = srcMgr.addFile(path: "a.kt", contents: Data("abc\ndef\n".utf8))
        let fileB = srcMgr.addFile(path: "b.kt", contents: Data("xyz\n".utf8))

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

        let rendered = engine.render(srcMgr)
        let lines = rendered.split(separator: "\n")
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines[0].contains("E-A0"))
        XCTAssertTrue(lines[1].contains("E-A1"))
        XCTAssertTrue(lines[2].contains("E-B"))
    }

    func testRenderSortsSeveritiesWithinSameLocation() {
        let srcMgr = SourceManager()
        let fileID = srcMgr.addFile(path: "same.kt", contents: Data("x\n".utf8))
        let range = SourceRange(
            start: SourceLocation(file: fileID, offset: 0),
            end: SourceLocation(file: fileID, offset: 1)
        )

        let engine = DiagnosticEngine()
        engine.warning("W-1", "warn", range: range)
        engine.error("E-1", "err", range: range)

        let rendered = engine.render(srcMgr)
        let lines = rendered.split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        // Errors (rank 0) come before warnings (rank 1)
        XCTAssertTrue(lines[0].contains("error"))
        XCTAssertTrue(lines[1].contains("warning"))
    }

    func testRenderRangelessDiagnosticsComeLast() {
        let srcMgr = SourceManager()
        let fileID = srcMgr.addFile(path: "f.kt", contents: Data("a\n".utf8))

        let engine = DiagnosticEngine()
        engine.error("E-NORANGE", "no range", range: nil)
        engine.error("E-RANGE", "has range", range: SourceRange(
            start: SourceLocation(file: fileID, offset: 0),
            end: SourceLocation(file: fileID, offset: 1)
        ))

        let rendered = engine.render(srcMgr)
        let lines = rendered.split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[0].contains("E-RANGE"))
        XCTAssertTrue(lines[1].contains("E-NORANGE"))
    }

    func testRenderSeverityLabels() {
        let srcMgr = SourceManager()
        let engine = DiagnosticEngine()
        engine.error("E", "e", range: nil)
        engine.warning("W", "w", range: nil)
        engine.note("N", "n", range: nil)
        engine.info("I", "i", range: nil)

        let rendered = engine.render(srcMgr)
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
        let diag = Diagnostic(
            severity: .error,
            code: "E",
            message: "m",
            primaryRange: range1,
            secondaryRanges: [range2]
        )
        XCTAssertEqual(diag.secondaryRanges.count, 1)
        XCTAssertEqual(diag.secondaryRanges[0], range2)
    }

    // MARK: - JSON Rendering

    func testRenderJSONEmptyDiagnostics() {
        let engine = DiagnosticEngine()
        let srcMgr = SourceManager()
        let json = engine.renderJSON(srcMgr)
        XCTAssertTrue(json.contains("\"version\": 1"))
        XCTAssertTrue(json.contains("\"diagnostics\": ["))
    }

    func testRenderJSONSingleErrorWithRange() {
        let srcMgr = SourceManager()
        let fileID = srcMgr.addFile(path: "test.kt", contents: Data("line1\nline2\n".utf8))
        let range = SourceRange(
            start: SourceLocation(file: fileID, offset: 6),
            end: SourceLocation(file: fileID, offset: 11)
        )
        let engine = DiagnosticEngine()
        engine.error("KSWIFTK-SEMA-0014", "Type mismatch", range: range)
        let json = engine.renderJSON(srcMgr)

        XCTAssertTrue(json.contains("\"version\": 1"))
        XCTAssertTrue(json.contains("\"file\": \"test.kt\""))
        XCTAssertTrue(json.contains("\"severity\": 1"))
        XCTAssertTrue(json.contains("\"severityLabel\": \"error\""))
        XCTAssertTrue(json.contains("\"code\": \"KSWIFTK-SEMA-0014\""))
        XCTAssertTrue(json.contains("\"source\": \"kswiftk\""))
        XCTAssertTrue(json.contains("\"message\": \"Type mismatch\""))
        // LSP uses 0-based lines: line1 is 0, line2 is 1
        XCTAssertTrue(json.contains("\"line\": 1"))
    }

    func testRenderJSONWarningHasSeverityTwo() {
        let engine = DiagnosticEngine()
        engine.warning("KSWIFTK-SEMA-0001", "unused var", range: nil)
        let srcMgr = SourceManager()
        let json = engine.renderJSON(srcMgr)
        XCTAssertTrue(json.contains("\"severity\": 2"))
        XCTAssertTrue(json.contains("\"severityLabel\": \"warning\""))
    }

    func testRenderJSONNoteHasSeverityThree() {
        let engine = DiagnosticEngine()
        engine.note("KSWIFTK-SEMA-0002", "see also", range: nil)
        let srcMgr = SourceManager()
        let json = engine.renderJSON(srcMgr)
        XCTAssertTrue(json.contains("\"severity\": 3"))
        XCTAssertTrue(json.contains("\"severityLabel\": \"note\""))
    }

    func testRenderJSONInfoHasSeverityFour() {
        let engine = DiagnosticEngine()
        engine.info("KSWIFTK-SEMA-0003", "hint", range: nil)
        let srcMgr = SourceManager()
        let json = engine.renderJSON(srcMgr)
        XCTAssertTrue(json.contains("\"severity\": 4"))
        XCTAssertTrue(json.contains("\"severityLabel\": \"info\""))
    }

    func testRenderJSONCodeActionsFromRegistry() {
        let engine = DiagnosticEngine()
        // KSWIFTK-SEMA-0014 has a registry codeAction: "Add explicit type cast"
        engine.error("KSWIFTK-SEMA-0014", "Type mismatch", range: nil)
        let srcMgr = SourceManager()
        let json = engine.renderJSON(srcMgr)
        XCTAssertTrue(json.contains("\"codeActions\""))
        XCTAssertTrue(json.contains("\"title\": \"Add explicit type cast\""))
        XCTAssertTrue(json.contains("\"kind\": \"quickfix\""))
    }

    func testRenderJSONExplicitCodeActionOverridesRegistry() {
        let engine = DiagnosticEngine()
        let action = DiagnosticCodeAction(title: "Custom fix", kind: "quickfix")
        engine.error("KSWIFTK-SEMA-0014", "Type mismatch", range: nil, codeActions: [action])
        let srcMgr = SourceManager()
        let json = engine.renderJSON(srcMgr)
        XCTAssertTrue(json.contains("\"title\": \"Custom fix\""))
        // Should NOT contain the registry default when explicit actions are provided.
        XCTAssertFalse(json.contains("\"title\": \"Add explicit type cast\""))
    }

    func testRenderJSONMultipleDiagnosticsSorted() {
        let srcMgr = SourceManager()
        let fileID = srcMgr.addFile(path: "multi.kt", contents: Data("aaa\nbbb\nccc\n".utf8))
        let engine = DiagnosticEngine()
        // Emit in reverse order to verify sorting.
        engine.error("E-2", "second", range: SourceRange(
            start: SourceLocation(file: fileID, offset: 4),
            end: SourceLocation(file: fileID, offset: 7)
        ))
        engine.error("E-1", "first", range: SourceRange(
            start: SourceLocation(file: fileID, offset: 0),
            end: SourceLocation(file: fileID, offset: 3)
        ))
        let json = engine.renderJSON(srcMgr)
        // E-1 should appear before E-2 in the output.
        guard let idx1 = json.range(of: "E-1")?.lowerBound,
              let idx2 = json.range(of: "E-2")?.lowerBound
        else {
            XCTFail("Both diagnostics should appear in JSON")
            return
        }
        XCTAssertTrue(idx1 < idx2)
    }

    func testRenderJSONEscapesSpecialCharacters() {
        let engine = DiagnosticEngine()
        engine.error("E-ESC", "msg with \"quotes\" and \\backslash", range: nil)
        let srcMgr = SourceManager()
        let json = engine.renderJSON(srcMgr)
        XCTAssertTrue(json.contains("\\\"quotes\\\""))
        XCTAssertTrue(json.contains("\\\\backslash"))
    }

    func testRenderJSONSchemaVersionStability() {
        // Golden schema test: verify the top-level structure is stable.
        let srcMgr = SourceManager()
        let fileID = srcMgr.addFile(path: "schema.kt", contents: Data("val x = 1\n".utf8))
        let engine = DiagnosticEngine()
        engine.error(
            "KSWIFTK-SEMA-0022",
            "Unresolved reference: foo",
            range: SourceRange(
                start: SourceLocation(file: fileID, offset: 0),
                end: SourceLocation(file: fileID, offset: 3)
            )
        )

        let json = engine.renderJSON(srcMgr)

        // Verify all required LSP schema fields are present.
        let requiredFields = [
            "\"version\"", "\"diagnostics\"", "\"file\"",
            "\"range\"", "\"start\"", "\"end\"",
            "\"line\"", "\"character\"",
            "\"severity\"", "\"severityLabel\"",
            "\"code\"", "\"source\"", "\"message\"",
            "\"codeActions\"" // swiftlint:disable:this trailing_comma
        ]
        for field in requiredFields {
            XCTAssertTrue(json.contains(field), "JSON should contain field: \(field)")
        }
    }

    // MARK: - DiagnosticRegistry

    func testDiagnosticRegistryLookupKnownCode() {
        let descriptor = DiagnosticRegistry.lookup("KSWIFTK-SEMA-0014")
        XCTAssertNotNil(descriptor)
        XCTAssertEqual(descriptor?.code, "KSWIFTK-SEMA-0014")
        XCTAssertEqual(descriptor?.pass, "SEMA")
    }

    func testDiagnosticRegistryLookupUnknownCode() {
        let descriptor = DiagnosticRegistry.lookup("KSWIFTK-DOES-NOT-EXIST")
        XCTAssertNil(descriptor)
    }

    func testDiagnosticRegistryAllDescriptorsHaveKSWIFTKPrefix() {
        for descriptor in DiagnosticRegistry.allDescriptors {
            XCTAssertTrue(
                descriptor.code.hasPrefix("KSWIFTK-"),
                "Descriptor code \(descriptor.code) should start with KSWIFTK-"
            )
        }
    }

    func testDiagnosticRegistryHasMinimumTenCodeActions() {
        let withActions = DiagnosticRegistry.allDescriptors.filter { !$0.codeActions.isEmpty }
        XCTAssertGreaterThanOrEqual(
            withActions.count, 10,
            "Registry should have at least 10 diagnostics with codeActions"
        )
    }

    // MARK: - DiagnosticsFormat

    func testDiagnosticsFormatRawValues() {
        XCTAssertEqual(DiagnosticsFormat(rawValue: "text"), .text)
        XCTAssertEqual(DiagnosticsFormat(rawValue: "json"), .json)
        XCTAssertNil(DiagnosticsFormat(rawValue: "xml"))
    }

    // MARK: - codeActions on Diagnostic

    func testDiagnosticCodeActionsDefaultToEmpty() {
        let diag = Diagnostic(severity: .error, code: "E", message: "m", primaryRange: nil, secondaryRanges: [])
        XCTAssertTrue(diag.codeActions.isEmpty)
    }

    func testDiagnosticCodeActionsCanBeProvided() {
        let action = DiagnosticCodeAction(title: "Fix it", kind: "quickfix")
        let diag = Diagnostic(
            severity: .error, code: "E", message: "m",
            primaryRange: nil, secondaryRanges: [],
            codeActions: [action]
        )
        XCTAssertEqual(diag.codeActions.count, 1)
        XCTAssertEqual(diag.codeActions[0].title, "Fix it")
    }
}

// swiftlint:enable file_length type_body_length
