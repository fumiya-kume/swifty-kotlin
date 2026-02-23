import Foundation
import XCTest
@testable import CompilerCore

// MARK: - Helper to extract isSuperCall flags from KIR instructions

private func extractSuperCallFlags(
    from body: [KIRInstruction],
    interner: StringInterner
) -> [(callee: String, isSuperCall: Bool)] {
    body.compactMap { instruction -> (callee: String, isSuperCall: Bool)? in
        guard case .call(_, let callee, _, _, _, _, let isSuperCall) = instruction else {
            return nil
        }
        return (interner.resolve(callee), isSuperCall)
    }
}

/// Find all KIR function bodies matching the given name (handles overrides with same name).
private func findAllKIRFunctionBodies(
    named name: String,
    in module: KIRModule,
    interner: StringInterner
) -> [[KIRInstruction]] {
    module.arena.declarations.compactMap { decl -> [KIRInstruction]? in
        guard case .function(let function) = decl else { return nil }
        return interner.resolve(function.name) == name ? function.body : nil
    }
}

/// Collect isSuperCall flags across ALL functions with the given name.
private func extractSuperCallFlagsAcrossOverrides(
    named name: String,
    in module: KIRModule,
    interner: StringInterner
) -> [(callee: String, isSuperCall: Bool)] {
    findAllKIRFunctionBodies(named: name, in: module, interner: interner)
        .flatMap { extractSuperCallFlags(from: $0, interner: interner) }
}

final class SuperCallAndQualifiedThisTests: XCTestCase {

    // MARK: - Test 1: super.method() produces isSuperCall=true in KIR

    func testSuperCallProducesIsSuperCallTrueInKIR() throws {
        let source = """
        open class Base {
            open fun greet(): String = "hello"
        }
        class Child : Base() {
            override fun greet(): String = super.greet()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            XCTAssertFalse(ctx.diagnostics.hasError,
                "Expected super call program to compile without sema errors, got: \(ctx.diagnostics.diagnostics.map(\.message))")

            let module = try XCTUnwrap(ctx.kir)
            // Both Base.greet and Child.greet exist; search across all overrides
            let flags = extractSuperCallFlagsAcrossOverrides(named: "greet", in: module, interner: ctx.interner)

            // The overridden greet() should contain a call to greet with isSuperCall=true
            let superGreetCall = flags.first { $0.callee == "greet" && $0.isSuperCall }
            XCTAssertNotNil(superGreetCall, "Expected a call to 'greet' with isSuperCall=true in Child.greet() body, got: \(flags)")
        }
    }

    // MARK: - Test 2: Regular (non-super) method call has isSuperCall=false

    func testRegularMemberCallHasIsSuperCallFalse() throws {
        let source = """
        class Greeter {
            fun greet(): String = "hello"
            fun callGreet(): String = this.greet()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            XCTAssertFalse(ctx.diagnostics.hasError,
                "Expected regular call program to compile without errors.")

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "callGreet", in: module, interner: ctx.interner)
            let flags = extractSuperCallFlags(from: body, interner: ctx.interner)

            let greetCall = flags.first { $0.callee == "greet" }
            XCTAssertNotNil(greetCall, "Expected a call to 'greet' in callGreet() body.")
            XCTAssertFalse(greetCall?.isSuperCall ?? true,
                "Expected this.greet() to have isSuperCall=false, got: \(flags)")
        }
    }

    // MARK: - Test 3: isSuperCall survives full lowering pipeline

    func testIsSuperCallSurvivesFullLoweringPipeline() throws {
        let source = """
        open class Base {
            open fun greet(): String = "hello"
        }
        class Child : Base() {
            override fun greet(): String = super.greet()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            XCTAssertFalse(ctx.diagnostics.hasError,
                "Expected super call program to compile and lower without errors.")

            let module = try XCTUnwrap(ctx.kir)
            // Search across all overrides of 'greet'
            let flags = extractSuperCallFlagsAcrossOverrides(named: "greet", in: module, interner: ctx.interner)

            // After full lowering, the super call should still have isSuperCall=true
            let superGreetCall = flags.first { $0.callee == "greet" && $0.isSuperCall }
            XCTAssertNotNil(superGreetCall,
                "Expected isSuperCall=true to survive full lowering pipeline, got: \(flags)")
        }
    }

    // MARK: - Test 4: isSuperCall preserved through ABI lowering (Any parameter boundary)

    func testIsSuperCallPreservedThroughABILowering() throws {
        // Use Any parameter to force ABI boxing pass to rewrite the call
        let source = """
        open class Base {
            open fun process(x: Any): Any = x
        }
        class Child : Base() {
            override fun process(x: Any): Any = super.process(x)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            XCTAssertFalse(ctx.diagnostics.hasError,
                "Expected ABI boxing super call to compile and lower without errors.")

            let module = try XCTUnwrap(ctx.kir)
            // Search across all overrides of 'process'
            let flags = extractSuperCallFlagsAcrossOverrides(named: "process", in: module, interner: ctx.interner)

            let processCall = flags.first { $0.callee == "process" && $0.isSuperCall }
            XCTAssertNotNil(processCall,
                "Expected isSuperCall=true to survive ABI lowering with boxing, got: \(flags)")
        }
    }

    // MARK: - Test 5: Qualified this@Label resolves to outer class type

    func testQualifiedThisResolvesToOuterClassType() throws {
        let source = """
        class Outer {
            fun getOuter(): Outer = this
            class Inner {
                fun getOuter(): Outer = this@Outer
            }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runSema(ctx)

            // Should compile without errors — this@Outer resolves to Outer type
            let hasError = ctx.diagnostics.diagnostics.contains { $0.severity == .error }
            XCTAssertFalse(hasError,
                "Expected this@Outer in nested class to resolve without errors, got: \(ctx.diagnostics.diagnostics.map(\.message))")
        }
    }

    // MARK: - Test 6: Unresolved qualified this@Label emits SEMA-0053

    func testUnresolvedQualifiedThisEmitsDiagnostic() throws {
        let source = """
        class Outer {
            class Inner {
                fun bad(): Int = this@NonExistent
            }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runSema(ctx)

            assertHasDiagnostic("KSWIFTK-SEMA-0053", in: ctx)
        }
    }

    // MARK: - Test 7: KIR dump format includes super=1 tag for super calls

    func testKIRDumpFormatIncludesSuperTag() throws {
        let source = """
        open class Base {
            open fun greet(): String = "hello"
        }
        class Child : Base() {
            override fun greet(): String = super.greet()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)

            // The full dump should include 'super=1' for the super.greet() call
            let dumpOutput = module.dump(interner: ctx.interner, symbols: ctx.sema?.symbols)
            XCTAssertTrue(dumpOutput.contains("super=1"),
                "Expected KIR dump to contain 'super=1' for super call, got:\n\(dumpOutput)")
        }
    }

    // MARK: - Test 8: Non-super calls do not have super=1 in dump

    func testKIRDumpDoesNotIncludeSuperTagForRegularCalls() throws {
        let source = """
        fun greet(): String = "hello"
        fun main() = greet()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let dumpOutput = module.dump(interner: ctx.interner, symbols: ctx.sema?.symbols)
            XCTAssertFalse(dumpOutput.contains("super=1"),
                "Regular call dump should not contain 'super=1', got:\n\(dumpOutput)")
        }
    }
}
