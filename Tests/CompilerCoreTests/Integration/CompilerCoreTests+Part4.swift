import Foundation
import XCTest
@testable import CompilerCore



extension CompilerCoreTests {
    func testDriverReportsPipelineOutputUnavailableWithoutICE() throws {
        let source = "fun main() = 0"
        let missingDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("missing")
        let outputBase = missingDir.appendingPathComponent("result").path

        try withTemporaryFile(contents: source) { tempSourcePath in
            let options = CompilerOptions(
                moduleName: "PipelineFailure",
                inputs: [tempSourcePath],
                outputPath: outputBase,
                emit: .kirDump,
                target: defaultTargetTriple()
            )
            let driver = CompilerDriver(
                version: CompilerVersion(major: 0, minor: 1, patch: 0, gitHash: nil),
                kotlinVersion: .v2_3_10
            )

            let result = driver.runForTesting(options: options)
            XCTAssertEqual(result.exitCode, 1)
            XCTAssertTrue(result.diagnostics.contains { $0.code == "KSWIFTK-PIPELINE-0003" })
            XCTAssertFalse(result.diagnostics.contains { $0.code == "KSWIFTK-ICE-0001" })
        }
    }

    func testFunctionExpressionBodyWhenRemainsExpressionBody() throws {
        let source = """
        fun classify(v: Int) = when (v) {
            0 -> 10
            else -> 20
        }
        """
        let ctx = makeContextFromSource(source)
        try runFrontend(ctx)

        let ast = try XCTUnwrap(ctx.ast)
        let file = try XCTUnwrap(ast.files.first)
        let declID = try XCTUnwrap(file.topLevelDecls.first)
        guard let decl = ast.arena.decl(declID), case .funDecl(let function) = decl else {
            XCTFail("Expected top-level function declaration.")
            return
        }

        switch function.body {
        case .expr(let exprID, _):
            guard let expr = ast.arena.expr(exprID),
                  case .whenExpr(_, let branches, let elseExpr, _) = expr else {
                XCTFail("Expected expression body to be parsed as when expression.")
                return
            }
            XCTAssertEqual(branches.count, 1)
            XCTAssertNotNil(elseExpr)
        case .block, .unit:
            XCTFail("Expression-body function must not be parsed as block body.")
        }
    }

    func testBlockBodySplitsStatementsOnNewline() throws {
        let source = """
        fun main() {
            println(1)
            println(2)
        }
        """
        let ctx = makeContextFromSource(source)
        try runFrontend(ctx)

        let ast = try XCTUnwrap(ctx.ast)
        let file = try XCTUnwrap(ast.files.first)
        let declID = try XCTUnwrap(file.topLevelDecls.first)
        guard let decl = ast.arena.decl(declID), case .funDecl(let function) = decl else {
            XCTFail("Expected top-level function declaration.")
            return
        }

        switch function.body {
        case .block(let exprIDs, _):
            XCTAssertEqual(exprIDs.count, 2)
            for exprID in exprIDs {
                guard let expr = ast.arena.expr(exprID), case .call = expr else {
                    XCTFail("Expected block statement to parse as call expression.")
                    return
                }
            }
        case .expr, .unit:
            XCTFail("Block-body function should produce block expressions.")
        }
    }

    func testLambdaLiteralExpressionBodyParsesAsDedicatedExprNode() throws {
        let source = """
        fun build() = { x: Int -> x + 1 }
        """
        let ctx = makeContextFromSource(source)
        try runFrontend(ctx)

        let ast = try XCTUnwrap(ctx.ast)
        let function = try XCTUnwrap(topLevelFunction(named: "build", in: ast, interner: ctx.interner))
        guard case .expr(let exprID, _) = function.body,
              let expr = ast.arena.expr(exprID),
              case .lambdaLiteral(let params, let bodyExprID, _, _) = expr else {
            XCTFail("Expected lambda literal expression body.")
            return
        }

        XCTAssertEqual(params.map { ctx.interner.resolve($0) }, ["x"])
        guard let bodyExpr = ast.arena.expr(bodyExprID),
              case .binary = bodyExpr else {
            XCTFail("Expected parsed lambda body expression.")
            return
        }
    }

    func testObjectLiteralExpressionBodyParsesAsDedicatedExprNode() throws {
        let source = """
        interface I
        fun build() = object : I {}
        """
        let ctx = makeContextFromSource(source)
        try runFrontend(ctx)

        let ast = try XCTUnwrap(ctx.ast)
        let function = try XCTUnwrap(topLevelFunction(named: "build", in: ast, interner: ctx.interner))
        guard case .expr(let exprID, _) = function.body,
              let expr = ast.arena.expr(exprID),
              case .objectLiteral(let superTypes, _) = expr else {
            XCTFail("Expected object literal expression body.")
            return
        }

        XCTAssertEqual(superTypes.count, 1)
        let superType = try XCTUnwrap(ast.arena.typeRef(superTypes[0]))
        guard case .named(let path, _, _) = superType,
              let first = path.first else {
            XCTFail("Expected named super type in object literal.")
            return
        }
        XCTAssertEqual(ctx.interner.resolve(first), "I")
    }

    func testCallableReferenceExpressionBodyParsesAsDedicatedExprNode() throws {
        let source = """
        fun target(x: Int) = x
        fun unbound() = ::target
        fun bound(x: Int) = x::toString
        """
        let ctx = makeContextFromSource(source)
        try runFrontend(ctx)

        let ast = try XCTUnwrap(ctx.ast)
        let unbound = try XCTUnwrap(topLevelFunction(named: "unbound", in: ast, interner: ctx.interner))
        guard case .expr(let unboundExprID, _) = unbound.body,
              let unboundExpr = ast.arena.expr(unboundExprID),
              case .callableRef(let unboundReceiver, let unboundMember, _) = unboundExpr else {
            XCTFail("Expected unbound callable reference.")
            return
        }
        XCTAssertNil(unboundReceiver)
        XCTAssertEqual(ctx.interner.resolve(unboundMember), "target")

        let bound = try XCTUnwrap(topLevelFunction(named: "bound", in: ast, interner: ctx.interner))
        guard case .expr(let boundExprID, _) = bound.body,
              let boundExpr = ast.arena.expr(boundExprID),
              case .callableRef(let boundReceiver, let boundMember, _) = boundExpr else {
            XCTFail("Expected bound callable reference.")
            return
        }
        XCTAssertEqual(ctx.interner.resolve(boundMember), "toString")
        let receiverExprID = try XCTUnwrap(boundReceiver)
        guard let receiverExpr = ast.arena.expr(receiverExprID),
              case .nameRef(let receiverName, _) = receiverExpr else {
            XCTFail("Expected callable reference receiver expression.")
            return
        }
        XCTAssertEqual(ctx.interner.resolve(receiverName), "x")
    }

    func testSubjectLessWhenParsesCorrectly() throws {
        let source = """
        fun classify(x: Int, y: Int): Int {
            return when {
                x > 0 -> 1
                y > 0 -> 2
                else -> 0
            }
        }
        """
        let ctx = makeContextFromSource(source)
        try runFrontend(ctx)

        let ast = try XCTUnwrap(ctx.ast)
        let file = try XCTUnwrap(ast.files.first)
        let declID = try XCTUnwrap(file.topLevelDecls.first)
        guard let decl = ast.arena.decl(declID), case .funDecl(let function) = decl else {
            XCTFail("Expected top-level function declaration.")
            return
        }

        switch function.body {
        case .block(let stmts, _):
            guard let returnExprID = stmts.first,
                  let returnExpr = ast.arena.expr(returnExprID),
                  case .returnExpr(let whenID, _, _) = returnExpr,
                  let whenID,
                  let whenExpr = ast.arena.expr(whenID),
                  case .whenExpr(let subject, let branches, let elseExpr, _) = whenExpr else {
                XCTFail("Expected return of when expression.")
                return
            }
            XCTAssertNil(subject, "Subject-less when must have nil subject.")
            XCTAssertEqual(branches.count, 2)
            XCTAssertNotNil(elseExpr)
        case .expr, .unit:
            XCTFail("Block-body function should produce block expressions.")
        }
    }

    func testSubjectLessWhenGuardChainSemaPassesWithElse() throws {
        let source = """
        fun classify(x: Int, y: Int): Int = when {
            x > 0 -> 1
            y > 0 -> 2
            else -> 0
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0004", in: ctx)
    }

    func testSubjectLessWhenWithoutElseIsNonExhaustive() throws {
        let source = """
        fun classify(x: Int): Int {
            when {
                x > 0 -> 1
            }
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0004", in: ctx)
    }

    func testSubjectLessWhenWithNonBooleanConditionEmitsDiagnostic() throws {
        let source = """
        fun test() = when {
            42 -> "invalid"
            else -> "ok"
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0032", in: ctx)
    }

    func testUnresolvedIdentifierEmitsDiagnostic() throws {
        let source = """
        fun test() = unknownVariable
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0022", in: ctx)
    }

    func testUnresolvedFunctionCallEmitsDiagnostic() throws {
        let source = """
        fun test() = unknownFunction(1)
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0023", in: ctx)
    }

    func testUnresolvedTypeAnnotationEmitsDiagnostic() throws {
        let source = """
        fun test(x: UnknownType) = x
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0025", in: ctx)
    }

    func topLevelFunction(
        named name: String,
        in ast: ASTModule,
        interner: StringInterner
    ) -> FunDecl? {
        for file in ast.files {
            for declID in file.topLevelDecls {
                guard let decl = ast.arena.decl(declID),
                      case .funDecl(let function) = decl else {
                    continue
                }
                if interner.resolve(function.name) == name {
                    return function
                }
            }
        }
        return nil
    }


}
