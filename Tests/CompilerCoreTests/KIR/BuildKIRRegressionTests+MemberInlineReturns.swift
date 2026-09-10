@testable import CompilerCore
import Testing

extension BuildKIRRegressionTests {
    @Test
    func inlineMemberArgumentsPreserveNonLocalAndLabeledReturns() throws {
        let context = makeContextFromSource("""
        class Receiver {
            inline fun call(crossinline other: () -> Int, action: () -> Int): Int = action()
        }
        fun direct(receiver: Receiver): Int {
            receiver.call({ 0 }) { return 11 }
            return -1
        }
        fun safe(receiver: Receiver?): Int {
            receiver?.call(action = { return 12 }, other = { 0 })
            return -1
        }
        fun labeled(receiver: Receiver): Int {
            receiver.call({ 0 }) { return@call 13 }
            return 14
        }
        fun captured(receiver: Receiver, value: Int): Int {
            receiver.call({ 0 }) { return value }
            return -1
        }
        """)
        try runToKIR(context)
        let errors = context.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors.map(\.message))")
        let module = try #require(context.kir)
        let lambdas = module.arena.declarations.compactMap { declaration -> KIRFunction? in
            guard case let .function(function) = declaration,
                  context.interner.resolve(function.name).hasPrefix("kk_lambda")
            else { return nil }
            return function
        }
        let nonLocalLambdas = lambdas.filter { function in
            function.body.contains { instruction in
                if case .nonLocalReturn = instruction { return true }
                return false
            }
        }
        #expect(nonLocalLambdas.count == 3)
        #expect(nonLocalLambdas.allSatisfy { $0.isInlineOnly })
        #expect(lambdas.count == 8)
        #expect(lambdas.filter { !$0.isInlineOnly }.count == 5)
        #expect(!module.arena.declarations.contains { declaration in
            guard case let .function(function) = declaration else { return false }
            return context.interner.resolve(function.name).hasPrefix("kk_function_value_adapter_")
        })
    }
}
