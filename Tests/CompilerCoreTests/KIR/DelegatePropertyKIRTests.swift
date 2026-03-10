@testable import CompilerCore
import Foundation
import XCTest

/// Tests for P5-79: property delegation (`by`) full desugaring.
/// Covers KIR lowering, StdlibDelegateLoweringPass, and end-to-end compilation
/// of lazy, observable, vetoable, and custom delegate properties.
final class DelegatePropertyKIRTests: XCTestCase {
    // MARK: - KIR Lowering: Lazy Delegate

    func testLazyDelegateEmitsCreateAndGetValueInKIR() throws {
        let source = """
        val x by lazy { 42 }
        fun main() = println(x)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            XCTAssertFalse(ctx.diagnostics.hasError,
                           "lazy delegate should compile without errors: \(ctx.diagnostics.diagnostics.map(\.message))")

            let module = try XCTUnwrap(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: mainBody, interner: ctx.interner)

            XCTAssertTrue(callees.contains("kk_lazy_create"),
                          "Expected kk_lazy_create in main body, got: \(callees)")
            XCTAssertTrue(callees.contains("kk_lazy_get_value"),
                          "Expected kk_lazy_get_value in main body, got: \(callees)")
        }
    }

    func testLazyDelegateGetValueCallIsNonThrowing() throws {
        let source = """
        val x by lazy { 42 }
        fun main() = println(x)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let throwFlags = extractThrowFlags(from: mainBody, interner: ctx.interner)

            XCTAssertEqual(throwFlags["kk_lazy_create"]?.allSatisfy { $0 == false }, true,
                           "kk_lazy_create should be non-throwing")
            XCTAssertEqual(throwFlags["kk_lazy_get_value"]?.allSatisfy { $0 == false }, true,
                           "kk_lazy_get_value should be non-throwing")
        }
    }

    // MARK: - KIR Lowering: Observable Delegate

    func testObservableDelegateEmitsCreateAndGetValueInKIR() throws {
        let source = """
        import kotlin.properties.Delegates
        var name: String by Delegates.observable("initial") { prop, old, new ->
            println("changed")
        }
        fun main() = println(name)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            XCTAssertFalse(ctx.diagnostics.hasError,
                           "observable delegate should compile without errors: \(ctx.diagnostics.diagnostics.map(\.message))")

            let module = try XCTUnwrap(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: mainBody, interner: ctx.interner)

            XCTAssertTrue(callees.contains("kk_observable_create"),
                          "Expected kk_observable_create in main body, got: \(callees)")
            XCTAssertTrue(callees.contains("kk_observable_get_value"),
                          "Expected kk_observable_get_value in main body, got: \(callees)")
        }
    }

    // MARK: - KIR Lowering: Vetoable Delegate

    func testVetoableDelegateEmitsCreateAndGetValueInKIR() throws {
        let source = """
        import kotlin.properties.Delegates
        var count: Int by Delegates.vetoable(0) { prop, old, new ->
            new >= 0
        }
        fun main() = println(count)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            XCTAssertFalse(ctx.diagnostics.hasError,
                           "vetoable delegate should compile without errors: \(ctx.diagnostics.diagnostics.map(\.message))")

            let module = try XCTUnwrap(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: mainBody, interner: ctx.interner)

            XCTAssertTrue(callees.contains("kk_vetoable_create"),
                          "Expected kk_vetoable_create in main body, got: \(callees)")
            XCTAssertTrue(callees.contains("kk_vetoable_get_value"),
                          "Expected kk_vetoable_get_value in main body, got: \(callees)")
        }
    }

    // MARK: - KIR Lowering: Custom Delegate

    func testCustomDelegateEmitsCreateAndGetValueInKIR() throws {
        let source = """
        val x by myCustomDelegate()
        fun main() = println(x)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            // Custom delegates may produce diagnostics for unresolved symbols,
            // but the KIR lowering path should still emit custom delegate calls.
            let module = try XCTUnwrap(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: mainBody, interner: ctx.interner)

            XCTAssertTrue(callees.contains("myCustomDelegate"),
                          "Expected delegate constructor/factory call in main body, got: \(callees)")
            XCTAssertTrue(callees.contains("get"),
                          "Expected synthesized property getter call in main body, got: \(callees)")
        }
    }

    func testCustomDelegateGetValueCallIsNonThrowing() throws {
        let source = """
        val x by myCustomDelegate()
        fun main() = println(x)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let throwFlags = extractThrowFlags(from: mainBody, interner: ctx.interner)

            XCTAssertEqual(throwFlags["myCustomDelegate"]?.allSatisfy { $0 == false }, true,
                           "delegate constructor/factory should be non-throwing")
            XCTAssertEqual(throwFlags["get"]?.allSatisfy { $0 == false }, true,
                           "synthesized property getter should be non-throwing")
        }
    }

    // MARK: - StdlibDelegateLoweringPass: Lazy Rewrite

    func testStdlibDelegateLoweringRewritesLazyAccessToGetValue() throws {
        let source = """
        val x by lazy { 42 }
        fun main() = println(x)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: mainBody, interner: ctx.interner)

            // After lowering, kk_lazy_get_value should still be present.
            XCTAssertTrue(callees.contains("kk_lazy_get_value"),
                          "Expected kk_lazy_get_value after lowering, got: \(callees)")
            // Raw kk_property_access should NOT remain for delegate fields.
            XCTAssertFalse(callees.contains("kk_property_access"),
                           "kk_property_access should be rewritten after StdlibDelegateLowering")
        }
    }

    // MARK: - StdlibDelegateLoweringPass: Custom Rewrite

    func testStdlibDelegateLoweringRewritesCustomAccessToGetValue() throws {
        let source = """
        val x by unknownDelegate()
        fun main() = println(x)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: mainBody, interner: ctx.interner)

            // After lowering, custom delegate access should stay on the synthesized accessor path.
            XCTAssertTrue(callees.contains("get"),
                          "Expected synthesized property getter after lowering, got: \(callees)")
            XCTAssertFalse(callees.contains("kk_property_access"),
                           "kk_property_access should be rewritten after PropertyLowering")
        }
    }

    // MARK: - Sema: Delegate Type Checking

    func testSemaDelegatePropertyWithLazyCompilesWithoutErrors() throws {
        let source = """
        val x: Int by lazy { 42 }
        fun main() = println(x)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runSema(ctx)

            XCTAssertFalse(ctx.diagnostics.hasError,
                           "val by lazy should pass sema without errors: \(ctx.diagnostics.diagnostics.map(\.message))")
        }
    }

    func testSemaDelegatePropertyWithObservableCompilesWithoutErrors() throws {
        let source = """
        import kotlin.properties.Delegates
        var name: String by Delegates.observable("initial") { prop, old, new ->
            println("changed")
        }
        fun main() = println(name)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runSema(ctx)

            XCTAssertFalse(ctx.diagnostics.hasError,
                           "var by Delegates.observable should pass sema without errors: \(ctx.diagnostics.diagnostics.map(\.message))")
        }
    }

    func testSemaDelegatePropertyWithVetoableCompilesWithoutErrors() throws {
        let source = """
        import kotlin.properties.Delegates
        var count: Int by Delegates.vetoable(0) { prop, old, new ->
            new >= 0
        }
        fun main() = println(count)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runSema(ctx)

            XCTAssertFalse(ctx.diagnostics.hasError,
                           "var by Delegates.vetoable should pass sema without errors: \(ctx.diagnostics.diagnostics.map(\.message))")
        }
    }

    // MARK: - Delegate Kind Detection

    func testDetectDelegateKindLazyProducesLazyCreate() throws {
        let source = """
        val x by lazy { 42 }
        fun main() = println(x)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: mainBody, interner: ctx.interner)

            // Lazy detection should produce kk_lazy_create, NOT kk_custom_delegate_create.
            XCTAssertTrue(callees.contains("kk_lazy_create"),
                          "lazy delegate should be detected as lazy kind, got: \(callees)")
            XCTAssertFalse(callees.contains("kk_custom_delegate_create"),
                           "lazy delegate should NOT produce custom delegate create, got: \(callees)")
        }
    }

    func testDetectDelegateKindUnknownProducesCustomCreate() throws {
        let source = """
        val x by someUnknownDelegate()
        fun main() = println(x)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: mainBody, interner: ctx.interner)

            // Unknown delegate should stay on the custom delegate path via its own constructor/factory.
            XCTAssertTrue(callees.contains("someUnknownDelegate"),
                          "unknown delegate should be detected as custom kind, got: \(callees)")
            XCTAssertFalse(callees.contains("kk_lazy_create"),
                           "unknown delegate should NOT produce lazy create, got: \(callees)")
        }
    }

    // MARK: - End-to-End: Lazy Delegate Compilation

    func testLazyDelegateEndToEndCompilesToExecutable() throws {
        let source = """
        val x by lazy { 42 }
        fun main() {
            println(x)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputPath = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            defer { try? FileManager.default.removeItem(atPath: outputPath) }
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "LazyDelegateExec",
                emit: .executable,
                outputPath: outputPath
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            XCTAssertTrue(FileManager.default.fileExists(atPath: outputPath),
                          "Executable should be produced for lazy delegate program")
        }
    }

    // MARK: - Multiple Delegate Properties

    func testMultipleLazyDelegatePropertiesCompileAndLower() throws {
        let source = """
        val a by lazy { 1 }
        val b by lazy { 2 }
        fun main(): Any? = println(a)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            XCTAssertFalse(ctx.diagnostics.hasError,
                           "Multiple lazy delegates should compile without errors: \(ctx.diagnostics.diagnostics.map(\.message))")

            let module = try XCTUnwrap(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: mainBody, interner: ctx.interner)

            // Should have at least 2 kk_lazy_create calls (one per property).
            let createCount = callees.filter { $0 == "kk_lazy_create" }.count
            XCTAssertGreaterThanOrEqual(createCount, 2,
                                        "Expected at least 2 kk_lazy_create calls for 2 lazy properties, got \(createCount)")
        }
    }

    // MARK: - Delegate Property With Explicit Type Annotation

    func testDelegatePropertyWithExplicitTypeAnnotation() throws {
        let source = """
        val x: Int by lazy { 42 }
        fun main() = println(x)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            XCTAssertFalse(ctx.diagnostics.hasError,
                           "Delegate with explicit type annotation should compile: \(ctx.diagnostics.diagnostics.map(\.message))")

            let module = try XCTUnwrap(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: mainBody, interner: ctx.interner)

            XCTAssertTrue(callees.contains("kk_lazy_create"),
                          "Explicit type annotation should still use lazy create")
            XCTAssertTrue(callees.contains("kk_lazy_get_value"),
                          "Explicit type annotation should still use lazy get_value")
        }
    }
}
