@testable import CompilerCore
import Foundation
import XCTest

final class KIRBuildPhaseClassLoweringTests: XCTestCase {
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
}
