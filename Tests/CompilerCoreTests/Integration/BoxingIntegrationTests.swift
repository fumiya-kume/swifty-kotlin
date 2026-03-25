@testable import CompilerCore
import Foundation
import XCTest

final class BoxingIntegrationTests: XCTestCase {
    func testPairTripleBoxingSurgicalFix() throws {
        let source = """
        fun test() {
            val p = Pair(1, "one")
            val t = Triple(2, 3, "three")
            val p2 = 4 to "four"
        }
        """
        
        let ctx = makeCompilationContext(
            inputs: ["test.kt"],
            moduleName: "Test",
            emit: .kirDump
        )
        ctx.sourceManager.addFile(path: "test.kt", contents: source.data(using: .utf8)!)
        
        // Run full pipeline up to lowerings
        try LoadSourcesPhase().run(ctx)
        try LexPhase().run(ctx)
        try ParsePhase().run(ctx)
        try BuildASTPhase().run(ctx)
        try SemaPhase().run(ctx)
        try BuildKIRPhase().run(ctx)
        try LoweringPhase().run(ctx)
        
        let module: KIRModule = try XCTUnwrap(ctx.kir)
        let testFunc: KIRFunction = try XCTUnwrap(module.arena.declarations.compactMap { decl -> KIRFunction? in
            if case let .function(fn) = decl, ctx.interner.resolve(fn.name) == "test" {
                return fn
            }
            return nil
        }.first)
        
        let boxingCalls = testFunc.body.filter { instruction in
            if case let .call(_, callee, _, _, _, _, _, _) = instruction {
                return ctx.interner.resolve(callee) == "kk_box_int"
            }
            return false
        }
        
        // We expect at least 4 boxing calls: 1 for Pair(1, ...), 2 for Triple(2, 3, ...), 1 for 4 to ...
        XCTAssertGreaterThanOrEqual(boxingCalls.count, 4, "Should have boxed primitive arguments for Pair and Triple. Found \(boxingCalls.count)")
    }
    
    func testMutableListAddNoUnnecessaryBoxing() throws {
        let source = """
        fun test(list: MutableList<Int>) {
            list.add(1)
        }
        """
        
        let ctx = makeCompilationContext(
            inputs: ["test.kt"],
            moduleName: "Test",
            emit: .kirDump
        )
        ctx.sourceManager.addFile(path: "test.kt", contents: source.data(using: .utf8)!)
        
        try LoadSourcesPhase().run(ctx)
        try LexPhase().run(ctx)
        try ParsePhase().run(ctx)
        try BuildASTPhase().run(ctx)
        try SemaPhase().run(ctx)
        try BuildKIRPhase().run(ctx)
        try LoweringPhase().run(ctx)
        
        let module: KIRModule = try XCTUnwrap(ctx.kir)
        let testFunc: KIRFunction = try XCTUnwrap(module.arena.declarations.compactMap { decl -> KIRFunction? in
            if case let .function(fn) = decl, ctx.interner.resolve(fn.name) == "test" {
                return fn
            }
            return nil
        }.first)
        
        let boxingCalls = testFunc.body.filter { instruction in
            if case let .call(_, callee, _, _, _, _, _, _) = instruction {
                return ctx.interner.resolve(callee) == "kk_box_int"
            }
            return false
        }
        
        // MutableList.add(1) should NOT be boxed by AbiloweringPass (it remains as i32)
        // because we only box for Pair/Triple explicitly.
        XCTAssertEqual(boxingCalls.count, 0, "Should NOT have boxed primitive argument for MutableList.add. Found \(boxingCalls.count)")
    }
}
