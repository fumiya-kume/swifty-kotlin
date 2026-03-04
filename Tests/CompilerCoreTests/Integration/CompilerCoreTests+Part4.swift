@testable import CompilerCore
import Foundation
import XCTest

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
        guard let decl = ast.arena.decl(declID), case let .funDecl(function) = decl else {
            XCTFail("Expected top-level function declaration.")
            return
        }

        switch function.body {
        case let .expr(exprID, _):
            guard let expr = ast.arena.expr(exprID),
                  case let .whenExpr(_, branches, elseExpr, _) = expr
            else {
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
        guard let decl = ast.arena.decl(declID), case let .funDecl(function) = decl else {
            XCTFail("Expected top-level function declaration.")
            return
        }

        switch function.body {
        case let .block(exprIDs, _):
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

    func testDoWhileInlineBodyParsesConditionOutsideBody() throws {
        let source = """
        fun main(): Int {
            var x = 0
            do x = x + 1 while (x < 3)
            return x
        }
        """
        let ctx = makeContextFromSource(source)
        try runFrontend(ctx)

        let ast = try XCTUnwrap(ctx.ast)
        let function = try XCTUnwrap(topLevelFunction(named: "main", in: ast, interner: ctx.interner))
        guard case let .block(stmts, _) = function.body else {
            XCTFail("Expected block-body function.")
            return
        }
        let doWhileExprID = try XCTUnwrap(stmts.first(where: { exprID in
            guard let expr = ast.arena.expr(exprID) else { return false }
            if case .doWhileExpr = expr { return true }
            return false
        }))

        guard let doWhileExpr = ast.arena.expr(doWhileExprID),
              case let .doWhileExpr(bodyExprID, conditionExprID, _, _) = doWhileExpr
        else {
            XCTFail("Expected do-while expression.")
            return
        }

        guard let bodyExpr = ast.arena.expr(bodyExprID),
              case let .localAssign(name, _, _) = bodyExpr
        else {
            XCTFail("Expected inline do-while body to parse as local assignment.")
            return
        }
        XCTAssertEqual(ctx.interner.resolve(name), "x")

        guard let conditionExpr = ast.arena.expr(conditionExprID),
              case let .binary(op, _, _, _) = conditionExpr
        else {
            XCTFail("Expected do-while condition to parse as binary expression.")
            return
        }
        XCTAssertEqual(op, .lessThan)

        if let bodyRange = ast.arena.exprRange(bodyExprID),
           let conditionRange = ast.arena.exprRange(conditionExprID) {
            XCTAssertLessThanOrEqual(bodyRange.end.offset, conditionRange.start.offset)
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
        guard case let .expr(exprID, _) = function.body,
              let expr = ast.arena.expr(exprID),
              case let .lambdaLiteral(params, bodyExprID, _, _) = expr
        else {
            XCTFail("Expected lambda literal expression body.")
            return
        }

        XCTAssertEqual(params.map { ctx.interner.resolve($0) }, ["x"])
        // Lambda body may be wrapped in blockExpr(statements: [], trailingExpr: expr)
        let effectiveBodyID: ExprID = if let bodyExpr = ast.arena.expr(bodyExprID),
                                         case let .blockExpr(_, trailing, _) = bodyExpr,
                                         let trailingID = trailing
        {
            trailingID
        } else {
            bodyExprID
        }
        guard let bodyExpr = ast.arena.expr(effectiveBodyID),
              case .binary = bodyExpr
        else {
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
        guard case let .expr(exprID, _) = function.body,
              let expr = ast.arena.expr(exprID),
              case let .objectLiteral(superTypes, _) = expr
        else {
            XCTFail("Expected object literal expression body.")
            return
        }

        XCTAssertEqual(superTypes.count, 1)
        let superType = try XCTUnwrap(ast.arena.typeRef(superTypes[0]))
        guard case let .named(path, _, _) = superType,
              let first = path.first
        else {
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
        guard case let .expr(unboundExprID, _) = unbound.body,
              let unboundExpr = ast.arena.expr(unboundExprID),
              case let .callableRef(unboundReceiver, unboundMember, _) = unboundExpr
        else {
            XCTFail("Expected unbound callable reference.")
            return
        }
        XCTAssertNil(unboundReceiver)
        XCTAssertEqual(ctx.interner.resolve(unboundMember), "target")

        let bound = try XCTUnwrap(topLevelFunction(named: "bound", in: ast, interner: ctx.interner))
        guard case let .expr(boundExprID, _) = bound.body,
              let boundExpr = ast.arena.expr(boundExprID),
              case let .callableRef(boundReceiver, boundMember, _) = boundExpr
        else {
            XCTFail("Expected bound callable reference.")
            return
        }
        XCTAssertEqual(ctx.interner.resolve(boundMember), "toString")
        let receiverExprID = try XCTUnwrap(boundReceiver)
        guard let receiverExpr = ast.arena.expr(receiverExprID),
              case let .nameRef(receiverName, _) = receiverExpr
        else {
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
        guard let decl = ast.arena.decl(declID), case let .funDecl(function) = decl else {
            XCTFail("Expected top-level function declaration.")
            return
        }

        switch function.body {
        case let .block(stmts, _):
            guard let returnExprID = stmts.first,
                  let returnExpr = ast.arena.expr(returnExprID),
                  case let .returnExpr(whenID, _, _) = returnExpr,
                  let whenID,
                  let whenExpr = ast.arena.expr(whenID),
                  case let .whenExpr(subject, branches, elseExpr, _) = whenExpr
            else {
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
                      case let .funDecl(function) = decl
                else {
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
