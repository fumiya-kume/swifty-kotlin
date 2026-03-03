@testable import CompilerCore
import Foundation
import XCTest

/// Tests for delegate property setter rewriting and lowering pass recording.
final class DelegatePropertySetterKIRTests: XCTestCase {
    // MARK: - Setter Rewrite: Observable

    func testObservableSetterRewritesToSetValueCall() throws {
        let source = """
        import kotlin.properties.Delegates
        var name: String by Delegates.observable("initial") { prop, old, new ->
            println("changed")
        }
        fun main() {
            name = "updated"
            println(name)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let diagnosticMessages = ctx.diagnostics.diagnostics.map(\.message)
            XCTAssertFalse(ctx.diagnostics.hasError,
                           "observable setter should compile without errors: \(diagnosticMessages)")

            let module = try XCTUnwrap(ctx.kir)
            let mainBody = try findKIRFunctionBody(
                named: "main", in: module, interner: ctx.interner
            )
            let callees = extractCallees(from: mainBody, interner: ctx.interner)

            XCTAssertTrue(
                callees.contains("kk_observable_set_value"),
                "Should emit kk_observable_set_value, got: \(callees)"
            )
        }
    }

    // MARK: - Setter Rewrite: Vetoable

    func testVetoableSetterRewritesToSetValueCall() throws {
        let source = """
        import kotlin.properties.Delegates
        var count: Int by Delegates.vetoable(0) { prop, old, new ->
            new >= 0
        }
        fun main() {
            count = 5
            println(count)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let diagnosticMessages = ctx.diagnostics.diagnostics.map(\.message)
            XCTAssertFalse(ctx.diagnostics.hasError,
                           "vetoable setter should compile without errors: \(diagnosticMessages)")

            let module = try XCTUnwrap(ctx.kir)
            let mainBody = try findKIRFunctionBody(
                named: "main", in: module, interner: ctx.interner
            )
            let callees = extractCallees(from: mainBody, interner: ctx.interner)

            XCTAssertTrue(
                callees.contains("kk_vetoable_set_value"),
                "Should emit kk_vetoable_set_value, got: \(callees)"
            )
        }
    }

    // MARK: - StdlibDelegateLowering Pass Is Recorded

    func testStdlibDelegateLoweringPassIsRecordedInModule() throws {
        let source = """
        val x by lazy { 42 }
        fun main() = println(x)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try XCTUnwrap(ctx.kir)
            XCTAssertTrue(
                module.executedLowerings.contains("StdlibDelegateLowering"),
                "Should be recorded: \(module.executedLowerings)"
            )
        }
    }
}
