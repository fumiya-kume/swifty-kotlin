#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension BuildKIRRegressionTests {
    /// KSP-1475: TimeSource measurement APIs remain bundled Kotlin calls in user KIR.
    @Test func testTimeSourceMeasureCallsLowerToBundledKotlinCallees() throws {
        let source = """
        import kotlin.time.ExperimentalTime
        import kotlin.time.TimeSource
        import kotlin.time.measureTime
        import kotlin.time.measureTimedValue

        @OptIn(ExperimentalTime::class)
        fun main() {
            val source: TimeSource = TimeSource.Monotonic
            source.measureTime { }
            source.measureTimedValue { "value" }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            #expect(callees.contains("measureTime"), "Expected a call to bundled TimeSource.measureTime")
            #expect(
                callees.contains("measureTimedValue"),
                "Expected a call to bundled TimeSource.measureTimedValue"
            )
            #expect(!callees.contains("__kk_time_source_mark_now"))
        }
    }

    /// KSP-1475: compiler-only contract DSL lambdas must not leave runtime KIR.
    @Test func testCompilerOnlyContractLambdaIsNotLowered() throws {
        let source = """
        import kotlin.contracts.ExperimentalContracts
        import kotlin.contracts.InvocationKind
        import kotlin.contracts.contract

        @OptIn(ExperimentalContracts::class)
        inline fun <T> contractProbe(block: () -> T): T {
            contract {
                callsInPlace(block, InvocationKind.EXACTLY_ONCE)
            }
            return block()
        }

        fun main() {
            println(contractProbe { "ok" })
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let allCallees = module.arena.declarations.compactMap { declaration -> KIRFunction? in
                guard case let .function(function) = declaration else { return nil }
                return function
            }.flatMap { function in
                extractCallees(from: function.body, interner: ctx.interner)
            }
            #expect(
                !allCallees.contains("contract"),
                "Compiler-only contract call must not be emitted into KIR: \(allCallees)"
            )
            #expect(
                !allCallees.contains(where: { $0.hasPrefix("$enumConstructorProperty$") }),
                "Contract effect enum access must not emit constructor-property helpers: \(allCallees)"
            )
        }
    }
}
#endif
