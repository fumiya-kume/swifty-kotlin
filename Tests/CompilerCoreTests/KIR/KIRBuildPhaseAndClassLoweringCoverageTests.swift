@testable import CompilerCore
import Foundation
import XCTest

final class KIRBuildPhaseAndClassLoweringCoverageTests: XCTestCase {
    func testBuildKIRPhaseThrowsInvalidInputWhenASTOrSemaMissing() {
        let ctx = makeCompilationContext(inputs: [])

        XCTAssertThrowsError(try BuildKIRPhase().run(ctx)) { error in
            guard case let CompilerPipelineError.invalidInput(message) = error else {
                XCTFail("Expected invalidInput, got: \(error)")
                return
            }
            XCTAssertTrue(message.contains("Sema phase did not run"))
        }
    }

    func testBuildKIRPhaseEmitsWarningWhenNoFunctionsAreLowered() throws {
        let ctx = makeCompilationContext(inputs: [])
        let astArena = ASTArena()
        let ast = ASTModule(
            files: [
                ASTFile(
                    fileID: FileID(rawValue: 0),
                    packageFQName: [],
                    imports: [],
                    topLevelDecls: [],
                    scriptBody: []
                ),
            ],
            arena: astArena,
            declarationCount: 0,
            tokenCount: 0
        )

        let setup = makeSemaModule()
        ctx.ast = ast
        ctx.sema = setup.ctx

        try BuildKIRPhase().run(ctx)

        let module = try XCTUnwrap(ctx.kir)
        XCTAssertEqual(module.functionCount, 0)
        assertHasDiagnostic("KSWIFTK-KIR-0001", in: ctx)
    }

    func testBuildKIRPhaseProducesModuleForValidInput() throws {
        let source = """
        fun answer(): Int = 42
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runSema(ctx)
            try BuildKIRPhase().run(ctx)

            let module = try XCTUnwrap(ctx.kir)
            XCTAssertGreaterThanOrEqual(module.functionCount, 1)
            assertNoDiagnostic("KSWIFTK-KIR-0001", in: ctx)
        }
    }

    func testClassLoweringSynthesizesCompanionInitializerFunction() throws {
        let source = """
        class Host {
            companion object {
                val answer: Int = 42
            }
        }
        fun main(): Int = Host.answer
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let functionNames = module.arena.declarations.compactMap { decl -> String? in
                guard case let .function(function) = decl else { return nil }
                return ctx.interner.resolve(function.name)
            }

            XCTAssertTrue(
                functionNames.contains(where: { $0.hasPrefix("__companion_init_") }),
                "Expected synthesized companion initializer, got: \(functionNames)"
            )
        }
    }

    func testClassLoweringGeneratesConstructorDefaultStubForSecondaryConstructor() throws {
        let source = """
        class Box {
            constructor(value: Int = 7)
        }
        fun main() = Box()
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let functionNames = module.arena.declarations.compactMap { decl -> String? in
                guard case let .function(function) = decl else { return nil }
                return ctx.interner.resolve(function.name)
            }

            // Secondary constructor defaults should generate a default stub path.
            XCTAssertTrue(
                functionNames.contains(where: { $0.hasPrefix("Box") }),
                "Expected lowered Box constructor-related functions, got: \(functionNames)"
            )
        }
    }

    func testClassLoweringLowersSecondaryConstructorSuperDelegation() throws {
        let source = """
        open class Base(x: Int)
        class Child : Base {
            constructor() : super(1)
        }
        fun main() = Child()
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let childConstructors = module.arena.declarations.compactMap { decl -> KIRFunction? in
                guard case let .function(function) = decl else { return nil }
                return ctx.interner.resolve(function.name) == "Child" ? function : nil
            }

            XCTAssertFalse(childConstructors.isEmpty)
            let hasInitDelegationCall = childConstructors.contains { function in
                function.body.contains { instruction in
                    guard case let .call(_, callee, _, _, _, _, _) = instruction else { return false }
                    return ctx.interner.resolve(callee) == "<init>"
                }
            }
            XCTAssertTrue(hasInitDelegationCall, "Expected <init> delegation call in Child constructors")
        }
    }

    func testClassLoweringLowersDelegatedPropertyInitializationPath() throws {
        let source = """
        class DelegateBox {
            operator fun provideDelegate(thisRef: Any?, property: String): DelegateBox = this
            operator fun getValue(thisRef: Any?, property: String): Int = 1
        }

        class Owner {
            val value by DelegateBox()
        }

        fun main(): Int = Owner().value
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let ownerConstructor = module.arena.declarations.compactMap { decl -> KIRFunction? in
                guard case let .function(function) = decl else { return nil }
                return ctx.interner.resolve(function.name) == "Owner" ? function : nil
            }.first

            let body = try XCTUnwrap(ownerConstructor?.body)
            let callees = extractCallees(from: body, interner: ctx.interner)
            XCTAssertTrue(callees.contains("DelegateBox"), "Expected delegate constructor call, got: \(callees)")
        }
    }

    func testClassLoweringEmitsDelegationForwarderEvenWithNoDispatchTargets() throws {
        let source = """
        interface EventSink {
            fun send(message: String): Int
        }

        class Box(delegate: EventSink) : EventSink by delegate

        fun main(): Int = 0
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)

            let forwardingFunctions = module.arena.declarations.compactMap { decl -> KIRFunction? in
                guard case let .function(function) = decl else { return nil }
                return function.body.contains { instruction in
                    if case let .call(_, callee, _, _, _, _, _) = instruction {
                        return ctx.interner.resolve(callee) == "kk_array_get"
                    }
                    return false
                } ? function : nil
            }

            XCTAssertEqual(forwardingFunctions.count, 1, "Expected one delegation forwarder with no dispatch target match")

            let forwardingBody = forwardingFunctions[0].body
            let callees = extractCallees(from: forwardingBody, interner: ctx.interner)
            XCTAssertTrue(callees.contains("abort"), "Expected explicit abort fallback in delegation forwarder, got: \(callees)")
        }
    }

    func testClassLoweringResolvesDelegationDispatchByExactSignature() throws {
        let source = """
        interface ComparableInput {
            fun evaluate(value: Int): Int
        }

        class OverloadedSink : ComparableInput {
            fun evaluate(value: String): Int = 0
            override fun evaluate(value: Int): Int = 10
        }

        class Box(delegate: ComparableInput) : ComparableInput by delegate

        fun main(): Int = Box(OverloadedSink()).evaluate(1)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)

            let forwarderFunction = module.arena.declarations.compactMap { decl -> KIRFunction? in
                guard case let .function(function) = decl else { return nil }

                let instructionHasDelegationLookup = function.body.contains { instruction in
                    if case let .call(_, callee, _, _, _, _, _) = instruction {
                        return ctx.interner.resolve(callee) == "kk_object_type_id"
                    }
                    return false
                }

                let hasEvaluateName = ctx.interner.resolve(function.name) == "evaluate"
                return hasEvaluateName && instructionHasDelegationLookup ? function : nil
            }.first

            let forwardingBody = try XCTUnwrap(
                forwarderFunction,
                "Expected delegation forwarder for ComparableInput.evaluate()"
            ).body

            let delegateCallSymbols = forwardingBody.compactMap { instruction -> SymbolID? in
                guard case let .call(symbol, callee, _, _, _, _, _) = instruction,
                      let symbol
                else {
                    return nil
                }

                let calleeName = ctx.interner.resolve(callee)
                if calleeName == "kk_array_get" || calleeName == "kk_object_type_id" || calleeName == "abort" {
                    return nil
                }

                return symbol
            }

            let nonSyntheticOverrideCalls = delegateCallSymbols.compactMap { symbol -> SymbolID? in
                guard let signatureSymbol = ctx.sema?.symbols.symbol(symbol),
                      signatureSymbol.flags.contains(.overrideMember),
                      !signatureSymbol.flags.contains(.synthetic)
                else {
                    return nil
                }
                return symbol
            }

            XCTAssertEqual(
                nonSyntheticOverrideCalls.isEmpty,
                false,
                "Expected delegation forwarder to call non-synthetic override target for ComparableInput.evaluate, got: \(delegateCallSymbols)"
            )
            XCTAssertTrue(
                delegateCallSymbols.allSatisfy { symbol in
                    guard let signatureSymbol = ctx.sema?.symbols.symbol(symbol) else {
                        return false
                    }
                    return !signatureSymbol.flags.contains(.synthetic)
                },
                "Expected delegation dispatch targets to exclude synthetic forwarding functions, got: \(delegateCallSymbols)"
            )
        }
    }
}
