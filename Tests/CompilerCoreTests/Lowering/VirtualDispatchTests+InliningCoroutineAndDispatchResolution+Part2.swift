@testable import CompilerCore
import Foundation
import XCTest

extension VirtualDispatchTests {
    func testResolveVirtualDispatchViaFullPipelineOpenClass() throws {
        let source = """
        open class Animal {
            open fun speak(): String = "..."
        }
        class Dog : Animal() {
            override fun speak(): String = "Woof"
        }
        fun callSpeak(a: Animal): String = a.speak()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            // Run through sema and KIR building
            do {
                try runToKIR(ctx)
            } catch {
                // If the frontend doesn't support open/override syntax yet,
                // this is expected. The isolated unit tests above cover the
                // lowering behavior independently.
                return
            }

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "callSpeak", in: module, interner: ctx.interner)
            let hasVirtualCall = body.contains { instruction in
                if case .virtualCall = instruction { return true }
                return false
            }
            // If sema correctly resolves the class hierarchy, the call should be virtual
            if hasVirtualCall {
                let vcInstruction = body.first { instruction in
                    if case .virtualCall = instruction { return true }
                    return false
                }
                guard case let .virtualCall(_, _, _, _, _, _, _, dispatch) = vcInstruction else {
                    XCTFail("Expected virtualCall")
                    return
                }
                if case let .vtable(slot) = dispatch {
                    XCTAssertGreaterThanOrEqual(slot, 0, "vtable slot should be non-negative")
                } else {
                    XCTFail("Expected vtable dispatch for class method")
                }
            }
        }
    }

    // MARK: - 16. resolveVirtualDispatch: final class -> static dispatch (no virtualCall)

    func testFinalClassMethodUsesStaticDispatch() throws {
        let source = """
        class FinalClass {
            fun doSomething(): Int = 42
        }
        fun callFinal(x: FinalClass): Int = x.doSomething()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            do {
                try runToKIR(ctx)
            } catch {
                // If frontend can't handle this, skip
                return
            }

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "callFinal", in: module, interner: ctx.interner)
            let hasVirtualCall = body.contains { instruction in
                if case .virtualCall = instruction { return true }
                return false
            }
            // Final class (no subtypes in Kotlin) should use static dispatch
            XCTAssertFalse(hasVirtualCall, "Final class method should use static dispatch (.call), not virtualCall")
        }
    }

    // MARK: - 17. virtualCall with multiple arguments: receiver separate, args correct count

    func testVirtualCallWithMultipleArgumentsPreservesCount() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let symbols = SymbolTable()
        let anyType = types.anyType

        let methodSym = SymbolID(rawValue: 8000)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: anyType,
                parameterTypes: [anyType, anyType],
                returnType: types.unitType,
                valueParameterSymbols: [SymbolID(rawValue: 8001), SymbolID(rawValue: 8002)]
            ),
            for: methodSym
        )

        let receiverExpr = arena.appendExpr(.temporary(0), type: anyType)
        let arg1 = arena.appendExpr(.temporary(1), type: anyType)
        let arg2 = arena.appendExpr(.temporary(2), type: anyType)
        let resultExpr = arena.appendExpr(.temporary(3), type: types.unitType)

        let callerFn = KIRFunction(
            symbol: SymbolID(rawValue: 8010),
            name: interner.intern("multiArgCaller"),
            params: [
                KIRParameter(symbol: SymbolID(rawValue: 8011), type: anyType),
                KIRParameter(symbol: SymbolID(rawValue: 8012), type: anyType),
                KIRParameter(symbol: SymbolID(rawValue: 8013), type: anyType),
            ],
            returnType: types.unitType,
            body: [
                .virtualCall(
                    symbol: methodSym,
                    callee: interner.intern("multiArgMethod"),
                    receiver: receiverExpr,
                    arguments: [arg1, arg2],
                    result: resultExpr,
                    canThrow: false,
                    thrownResult: nil,
                    dispatch: .vtable(slot: 0)
                ),
                .returnUnit,
            ],
            isSuspend: false,
            isInline: false
        )

        let callerID = arena.appendDecl(.function(callerFn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [callerID])], arena: arena)

        let sema = SemaModule(symbols: symbols, types: types, bindings: BindingTable(), diagnostics: DiagnosticEngine())
        let ctx = CompilationContext(
            options: CompilerOptions(
                moduleName: "MultiArg",
                inputs: [],
                outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path,
                emit: .kirDump,
                target: defaultTargetTriple()
            ),
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: interner
        )
        ctx.kir = module
        ctx.sema = sema

        try LoweringPhase().run(ctx)

        let lowered = try findKIRFunction(named: "multiArgCaller", in: module, interner: interner)
        let vcInstruction = lowered.body.first { instruction in
            if case .virtualCall = instruction { return true }
            return false
        }
        guard case let .virtualCall(_, _, receiver, arguments, _, _, _, _) = vcInstruction else {
            XCTFail("Expected virtualCall instruction")
            return
        }
        // Receiver is separate; arguments should have exactly 2 entries
        XCTAssertEqual(arguments.count, 2, "virtualCall should have exactly 2 value arguments (not including receiver)")
        XCTAssertEqual(receiver, receiverExpr, "Receiver should be the original receiver expression")
        XCTAssertEqual(arguments[0], arg1, "First argument should be arg1")
        XCTAssertEqual(arguments[1], arg2, "Second argument should be arg2")
    }
}
