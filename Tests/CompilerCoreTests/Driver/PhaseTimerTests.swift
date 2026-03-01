@testable import CompilerCore
import XCTest

final class PhaseTimerTests: XCTestCase {
    // MARK: - PhaseRecord

    func testPhaseRecordDurationNanos() {
        let record = PhaseTimer.PhaseRecord(
            name: "Lex",
            startTime: 1000,
            endTime: 5000
        )
        XCTAssertEqual(record.durationNanos, 4000)
    }

    func testPhaseRecordDurationMs() {
        let record = PhaseTimer.PhaseRecord(
            name: "Lex",
            startTime: 0,
            endTime: 2_000_000
        )
        XCTAssertEqual(record.durationMs, 2.0, accuracy: 0.001)
    }

    func testPhaseRecordSubRecords() {
        let sub = PhaseTimer.PhaseRecord(name: "clang", startTime: 100, endTime: 200)
        let record = PhaseTimer.PhaseRecord(
            name: "Link",
            startTime: 0,
            endTime: 1000,
            subRecords: [sub]
        )
        XCTAssertEqual(record.subRecords.count, 1)
        XCTAssertEqual(record.subRecords[0].name, "clang")
    }

    // MARK: - Recording phases

    func testBeginEndPhaseRecordsEntry() {
        let timer = PhaseTimer()
        timer.beginPhase("TestPhase")
        timer.endPhase()
        XCTAssertEqual(timer.phaseRecords.count, 1)
        XCTAssertEqual(timer.phaseRecords[0].name, "TestPhase")
    }

    func testEndPhaseWithoutBeginIsNoOp() {
        let timer = PhaseTimer()
        timer.endPhase()
        XCTAssertEqual(timer.phaseRecords.count, 0)
    }

    func testMultiplePhasesRecorded() {
        let timer = PhaseTimer()
        timer.beginPhase("Lex")
        timer.endPhase()
        timer.beginPhase("Parse")
        timer.endPhase()
        timer.beginPhase("Sema")
        timer.endPhase()
        XCTAssertEqual(timer.phaseRecords.count, 3)
        XCTAssertEqual(timer.phaseRecords.map(\.name), ["Lex", "Parse", "Sema"])
    }

    func testRecordSubPhase() {
        let timer = PhaseTimer()
        timer.beginPhase("Link")
        timer.recordSubPhase("clang", startTime: 100, endTime: 500)
        timer.recordSubPhase("ld", startTime: 500, endTime: 900)
        timer.endPhase()
        XCTAssertEqual(timer.phaseRecords.count, 1)
        XCTAssertEqual(timer.phaseRecords[0].subRecords.count, 2)
        XCTAssertEqual(timer.phaseRecords[0].subRecords[0].name, "clang")
        XCTAssertEqual(timer.phaseRecords[0].subRecords[1].name, "ld")
    }

    // MARK: - totalNanos / totalMs

    func testTotalNanosAndMs() {
        let timer = PhaseTimer()
        timer.beginPhase("A")
        timer.endPhase()
        timer.beginPhase("B")
        timer.endPhase()
        // totalNanos should be sum of all durations
        XCTAssertTrue(timer.totalNanos > 0)
        XCTAssertTrue(timer.totalMs >= 0)
    }

    func testTotalNanosEmptyIsZero() {
        let timer = PhaseTimer()
        XCTAssertEqual(timer.totalNanos, 0)
        XCTAssertEqual(timer.totalMs, 0)
    }

    // MARK: - exportTSV

    func testExportTSVContainsHeader() {
        let timer = PhaseTimer()
        timer.beginPhase("Lex")
        timer.endPhase()
        let tsv = timer.exportTSV()
        XCTAssertTrue(tsv.hasPrefix("phase\tduration_ms\tpercent"))
        XCTAssertTrue(tsv.contains("Lex"))
        XCTAssertTrue(tsv.contains("TOTAL"))
    }

    func testExportTSVWithSubPhases() {
        let timer = PhaseTimer()
        timer.beginPhase("Link")
        timer.recordSubPhase("clang", startTime: 100, endTime: 200)
        timer.endPhase()
        let tsv = timer.exportTSV()
        XCTAssertTrue(tsv.contains("Link"))
        XCTAssertTrue(tsv.contains("clang"))
    }

    // MARK: - exportJSON

    func testExportJSONContainsPhasesAndTotal() {
        let timer = PhaseTimer()
        timer.beginPhase("Lex")
        timer.endPhase()
        timer.beginPhase("Parse")
        timer.endPhase()
        let json = timer.exportJSON()
        // Should have Lex, Parse, TOTAL = 3 entries
        XCTAssertEqual(json.count, 3)
        XCTAssertEqual(json[0]["phase"] as? String, "Lex")
        XCTAssertEqual(json[1]["phase"] as? String, "Parse")
        XCTAssertEqual(json[2]["phase"] as? String, "TOTAL")
        XCTAssertEqual(json[2]["percent"] as? Double, 100.0)
    }

    func testExportJSONWithSubPhases() {
        let timer = PhaseTimer()
        timer.beginPhase("Link")
        timer.recordSubPhase("clang", startTime: 100, endTime: 500)
        timer.endPhase()
        let json = timer.exportJSON()
        XCTAssertEqual(json.count, 2) // Link + TOTAL
        let linkEntry = json[0]
        XCTAssertNotNil(linkEntry["sub_phases"])
    }

    func testExportJSONEmptyTimer() {
        let timer = PhaseTimer()
        let json = timer.exportJSON()
        // Should contain just the TOTAL entry
        XCTAssertEqual(json.count, 1)
        XCTAssertEqual(json[0]["phase"] as? String, "TOTAL")
    }

    // MARK: - printSummary

    func testPrintSummaryDoesNotCrash() {
        let timer = PhaseTimer()
        timer.beginPhase("Lex")
        timer.endPhase()
        timer.beginPhase("Link")
        timer.recordSubPhase("clang", startTime: 100, endTime: 500)
        timer.endPhase()
        // Just ensure it doesn't crash
        timer.printSummary()
    }
}
