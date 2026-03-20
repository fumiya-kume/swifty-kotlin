@testable import CompilerCore
import Foundation
import XCTest

extension LoweringPassRegressionTests {
    func testFileForEachLineRewriteAddsClosureRawArgument() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let ctx = KIRContext(
            diagnostics: DiagnosticEngine(),
            options: CompilerOptions(
                moduleName: "FileForEachLineRewrite",
                inputs: [],
                outputPath: FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString).path,
                emit: .kirDump,
                target: defaultTargetTriple()
            ),
            interner: interner
        )

        let fileExpr = arena.appendExpr(.temporary(0))
        let lambdaExpr = arena.appendExpr(.temporary(1))
        let resultExpr = arena.appendExpr(.temporary(2))
        let fn = KIRFunction(
            symbol: SymbolID(rawValue: 1),
            name: interner.intern("main"),
            params: [],
            returnType: TypeSystem().unitType,
            body: [
                .call(
                    symbol: nil,
                    callee: interner.intern("kk_file_new"),
                    arguments: [arena.appendExpr(.stringLiteral(interner.intern("demo.txt")), type: nil)],
                    result: fileExpr,
                    canThrow: false,
                    thrownResult: nil
                ),
                .virtualCall(
                    symbol: nil,
                    callee: interner.intern("forEachLine"),
                    receiver: fileExpr,
                    arguments: [lambdaExpr],
                    result: resultExpr,
                    canThrow: true,
                    thrownResult: nil,
                    dispatch: .vtable(slot: 0)
                ),
                .returnUnit,
            ],
            isSuspend: false,
            isInline: false
        )
        let declID = arena.appendDecl(.function(fn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [declID])], arena: arena)

        try CollectionLiteralLoweringPass().run(module: module, ctx: ctx)

        guard case let .function(lowered)? = module.arena.decl(declID) else {
            XCTFail("expected lowered function")
            return
        }

        let forEachLineCall = lowered.body.compactMap { instruction -> (arguments: [KIRExprID], canThrow: Bool)? in
            guard case let .call(_, callee, arguments, _, canThrow, _, _) = instruction,
                  interner.resolve(callee) == "kk_file_forEachLine"
            else {
                return nil
            }
            return (arguments, canThrow)
        }.first

        guard let call = forEachLineCall else {
            XCTFail("Expected kk_file_forEachLine call after collection literal lowering")
            return
        }
        XCTAssertEqual(call.arguments.count, 3, "kk_file_forEachLine should receive fileRaw, fnPtr, and closureRaw")
        XCTAssertTrue(call.canThrow)
    }

    func testFileWalkRewriteKeepsListTrackingForChainedForEach() throws {
        let source = """
        import java.io.File

        fun main() {
            File("demo").walk().forEach { println(it.path) }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "FileWalkRewrite", emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: mainBody, interner: ctx.interner)

            XCTAssertTrue(callees.contains("kk_file_walk"))
            XCTAssertTrue(callees.contains("kk_list_forEach"))
            XCTAssertFalse(callees.contains("walk"))
        }
    }

    func testFileMkdirsRewrite() throws {
        let source = """
        import java.io.File

        fun main() {
            File("/tmp/test").mkdirs()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "FileMkdirsRewrite", emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: mainBody, interner: ctx.interner)

            XCTAssertTrue(callees.contains("kk_file_mkdirs"))
            XCTAssertFalse(callees.contains("mkdirs"))
        }
    }

    func testFileDeleteRewrite() throws {
        let source = """
        import java.io.File

        fun main() {
            File("/tmp/test").delete()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "FileDeleteRewrite", emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: mainBody, interner: ctx.interner)

            XCTAssertTrue(callees.contains("kk_file_delete"))
            XCTAssertFalse(callees.contains("delete"))
        }
    }

    func testFileListFilesRewrite() throws {
        let source = """
        import java.io.File

        fun main() {
            File("/tmp/test").listFiles()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "FileListFilesRewrite", emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: mainBody, interner: ctx.interner)

            XCTAssertTrue(callees.contains("kk_file_listFiles"))
            XCTAssertFalse(callees.contains("listFiles"))
        }
    }

    func testFileWalkRewrite() throws {
        let source = """
        import java.io.File

        fun main() {
            File("/tmp/test").walk()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "FileWalkRewrite", emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: mainBody, interner: ctx.interner)

            XCTAssertTrue(callees.contains("kk_file_walk"))
            XCTAssertFalse(callees.contains("walk"))
        }
    }

}
