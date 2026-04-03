@testable import Runtime
import XCTest

final class RuntimeKAPTTests: IsolatedRuntimeXCTestCase {
    func testOptionManagementStoresAndListsKeys() {
        let session = kk_kapt_session_create(0)

        _ = kk_kapt_session_add_option(session, makeRuntimeString("kapt.kotlin.generated"), makeRuntimeString("/tmp/gen"))
        _ = kk_kapt_session_add_option(session, makeRuntimeString("mode"), makeRuntimeString("strict"))

        XCTAssertEqual(extractString(from: UnsafeMutableRawPointer(bitPattern: kk_kapt_session_get_option(session, makeRuntimeString("mode")))), "strict")

        let keys = decodeStringList(kk_kapt_session_get_option_keys(session))
        XCTAssertEqual(keys, ["kapt.kotlin.generated", "mode"])
    }

    func testRoundProcessingCarriesGeneratedFilesIntoNextRound() {
        let session = kk_kapt_session_create(0)
        _ = kk_kapt_session_register_annotation(session, makeRuntimeString("src/A.kt"), makeRuntimeString("demo.Generate"))

        let firstRound = kk_kapt_session_begin_round(session)
        XCTAssertEqual(kk_kapt_round_get_number(firstRound), 1)
        XCTAssertEqual(kk_kapt_round_is_processing_over(firstRound), 0)
        XCTAssertEqual(decodeStringList(kk_kapt_round_get_annotations(firstRound)), ["demo.Generate"])
        XCTAssertEqual(decodeStringList(kk_kapt_round_get_sources(firstRound)), ["src/A.kt"])

        _ = kk_kapt_session_emit_generated_file(session, makeRuntimeString("build/generated/GenA.kt"), makeRuntimeString("src/A.kt"))
        XCTAssertEqual(kk_kapt_session_finish_round(session), 1)

        let secondRound = kk_kapt_session_begin_round(session)
        XCTAssertEqual(kk_kapt_round_get_number(secondRound), 2)
        XCTAssertEqual(decodeStringList(kk_kapt_round_get_sources(secondRound)), ["build/generated/GenA.kt", "src/A.kt"])
        XCTAssertEqual(
            decodeStringList(kk_kapt_round_get_incoming_generated_files(secondRound)),
            ["build/generated/GenA.kt|src/A.kt"]
        )
        XCTAssertEqual(kk_kapt_session_finish_round(session), 0)
    }

    func testIncrementalProcessingOnlyTargetsDirtyAndGeneratedSources() {
        let session = kk_kapt_session_create(1)
        _ = kk_kapt_session_register_annotation(session, makeRuntimeString("src/A.kt"), makeRuntimeString("demo.Generate"))
        _ = kk_kapt_session_register_annotation(session, makeRuntimeString("src/B.kt"), makeRuntimeString("demo.Generate"))
        _ = kk_kapt_session_mark_dirty(session, makeRuntimeString("src/B.kt"))

        XCTAssertEqual(kk_kapt_session_should_process(session, makeRuntimeString("src/A.kt")), 0)
        XCTAssertEqual(kk_kapt_session_should_process(session, makeRuntimeString("src/B.kt")), 1)

        let round = kk_kapt_session_begin_round(session)
        XCTAssertEqual(decodeStringList(kk_kapt_round_get_sources(round)), ["src/B.kt"])

        _ = kk_kapt_session_emit_generated_file(session, makeRuntimeString("build/generated/BGen.kt"), makeRuntimeString("src/B.kt"))
        XCTAssertEqual(kk_kapt_session_finish_round(session), 1)
        XCTAssertEqual(kk_kapt_session_should_process(session, makeRuntimeString("build/generated/BGen.kt")), 1)

        let nextRound = kk_kapt_session_begin_round(session)
        XCTAssertEqual(decodeStringList(kk_kapt_round_get_sources(nextRound)), ["build/generated/BGen.kt", "src/B.kt"])
        XCTAssertEqual(kk_kapt_session_finish_round(session), 0)
        XCTAssertEqual(kk_kapt_session_dirty_source_count(session), 0)
    }

    func testErrorReportingFormatsCompilerDiagnostics() {
        let session = kk_kapt_session_create(0)

        _ = kk_kapt_session_report_error(
            session,
            makeRuntimeString("Missing required option"),
            makeRuntimeString("src/Processor.kt"),
            12,
            4
        )

        XCTAssertEqual(kk_kapt_session_has_errors(session), 1)
        XCTAssertEqual(
            decodeStringList(kk_kapt_session_get_errors(session)),
            ["src/Processor.kt:12:4: error: Missing required option"]
        )
    }

    func testEmptySessionEventuallyReportsProcessingOver() {
        let session = kk_kapt_session_create(0)
        let round = kk_kapt_session_begin_round(session)

        XCTAssertEqual(kk_kapt_round_is_processing_over(round), 1)
        XCTAssertEqual(decodeStringList(kk_kapt_round_get_annotations(round)), [])
        XCTAssertEqual(decodeStringList(kk_kapt_round_get_sources(round)), [])
    }

    private func makeRuntimeString(_ value: String) -> Int {
        let utf8 = Array(value.utf8)
        if utf8.isEmpty {
            var empty: UInt8 = 0
            return withUnsafePointer(to: &empty) { ptr in
                Int(bitPattern: kk_string_from_utf8(ptr, 0))
            }
        }
        return utf8.withUnsafeBufferPointer { buffer in
            Int(bitPattern: kk_string_from_utf8(buffer.baseAddress!, Int32(buffer.count)))
        }
    }

    private func decodeStringList(_ raw: Int) -> [String] {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: raw),
              let list = tryCast(ptr, to: RuntimeListBox.self)
        else {
            return []
        }
        return list.elements.compactMap { element in
            extractString(from: UnsafeMutableRawPointer(bitPattern: element))
        }
    }
}
