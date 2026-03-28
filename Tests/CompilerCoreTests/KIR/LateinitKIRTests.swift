@testable import CompilerCore
import Foundation
import XCTest

final class LateinitKIRTests: XCTestCase {
    func testLateinitReadEmitsGetOrThrowCall() throws {
        let source = """
        class Box {
            lateinit var name: String
            fun read(): String = name
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            XCTAssertFalse(ctx.diagnostics.hasError,
                           "lateinit read should compile without errors: \(ctx.diagnostics.diagnostics.map(\.message))")

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "read", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            XCTAssertTrue(callees.contains("kk_lateinit_get_or_throw"),
                          "Expected kk_lateinit_get_or_throw in read body, got: \(callees)")
        }
    }

    func testLateinitIsInitializedEmitsRuntimeCheck() throws {
        let source = """
        class Box {
            lateinit var name: String
            fun ready(): Boolean = ::name.isInitialized
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            XCTAssertFalse(ctx.diagnostics.hasError,
                           "lateinit isInitialized should compile without errors: \(ctx.diagnostics.diagnostics.map(\.message))")

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "ready", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            XCTAssertTrue(callees.contains("kk_lateinit_is_initialized"),
                          "Expected kk_lateinit_is_initialized in ready body, got: \(callees)")
        }
    }
}
