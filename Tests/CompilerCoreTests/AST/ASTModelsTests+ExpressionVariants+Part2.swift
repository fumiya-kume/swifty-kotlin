@testable import CompilerCore
import XCTest

extension ASTModelsTests {
    func testExprWhenExpr() {
        let r = makeRange(start: 0, end: 10)
        let arena = ASTArena()
        let subjectID = arena.appendExpr(.intLiteral(1, r))
        let bodyID = arena.appendExpr(.intLiteral(2, r))
        let condID = arena.appendExpr(.boolLiteral(true, r))
        let elseID = arena.appendExpr(.intLiteral(3, r))
        let branch = WhenBranch(conditions: [condID], body: bodyID, range: r)
        let expr = Expr.whenExpr(subject: subjectID, branches: [branch], elseExpr: elseID, range: r)
        if case let .whenExpr(s, bs, e, _) = expr {
            XCTAssertEqual(s, subjectID)
            XCTAssertEqual(bs.count, 1)
            XCTAssertEqual(e, elseID)
        } else { XCTFail("Expected .whenExpr") }
    }

    func testExprReturnAndThrow() {
        let r = makeRange(start: 0, end: 5)
        let arena = ASTArena()
        let valID = arena.appendExpr(.intLiteral(1, r))

        let returnWithValue = Expr.returnExpr(value: valID, range: r)
        if case let .returnExpr(v, _, _) = returnWithValue {
            XCTAssertEqual(v, valID)
        } else { XCTFail("Expected .returnExpr") }

        let returnVoid = Expr.returnExpr(value: nil, range: r)
        if case let .returnExpr(v, _, _) = returnVoid {
            XCTAssertNil(v)
        } else { XCTFail("Expected .returnExpr") }

        let throwExpr = Expr.throwExpr(value: valID, range: r)
        if case let .throwExpr(v, _) = throwExpr {
            XCTAssertEqual(v, valID)
        } else { XCTFail("Expected .throwExpr") }
    }

    func testExprIfExpr() {
        let r = makeRange(start: 0, end: 10)
        let arena = ASTArena()
        let condID = arena.appendExpr(.boolLiteral(true, r))
        let thenID = arena.appendExpr(.intLiteral(1, r))
        let elseID = arena.appendExpr(.intLiteral(2, r))

        let withElse = Expr.ifExpr(condition: condID, thenExpr: thenID, elseExpr: elseID, range: r)
        if case let .ifExpr(c, t, e, _) = withElse {
            XCTAssertEqual(c, condID)
            XCTAssertEqual(t, thenID)
            XCTAssertEqual(e, elseID)
        } else { XCTFail("Expected .ifExpr") }

        let withoutElse = Expr.ifExpr(condition: condID, thenExpr: thenID, elseExpr: nil, range: r)
        if case let .ifExpr(_, _, e, _) = withoutElse {
            XCTAssertNil(e)
        } else { XCTFail("Expected .ifExpr") }
    }

    func testExprTryExpr() {
        let interner = StringInterner()
        let r = makeRange(start: 0, end: 10)
        let arena = ASTArena()
        let bodyID = arena.appendExpr(.intLiteral(1, r))
        let catchBodyID = arena.appendExpr(.intLiteral(2, r))
        let finallyID = arena.appendExpr(.intLiteral(3, r))
        let catchClause = CatchClause(paramName: interner.intern("e"), paramTypeName: interner.intern("Exception"), body: catchBodyID, range: r)

        let tryExpr = Expr.tryExpr(body: bodyID, catchClauses: [catchClause], finallyExpr: finallyID, range: r)
        if case let .tryExpr(b, cc, f, _) = tryExpr {
            XCTAssertEqual(b, bodyID)
            XCTAssertEqual(cc.count, 1)
            XCTAssertEqual(f, finallyID)
        } else { XCTFail("Expected .tryExpr") }
    }

    func testExprIsCheckAndAsCast() {
        let r = makeRange(start: 0, end: 5)
        let arena = ASTArena()
        let exprID = arena.appendExpr(.intLiteral(1, r))
        let typeRefID = arena.appendTypeRef(.named(path: [], args: [], nullable: false))

        let isCheck = Expr.isCheck(expr: exprID, type: typeRefID, negated: false, range: r)
        if case let .isCheck(_, _, neg, _) = isCheck {
            XCTAssertFalse(neg)
        } else { XCTFail("Expected .isCheck") }

        let isNotCheck = Expr.isCheck(expr: exprID, type: typeRefID, negated: true, range: r)
        if case let .isCheck(_, _, neg, _) = isNotCheck {
            XCTAssertTrue(neg)
        } else { XCTFail("Expected .isCheck negated") }

        let safeCast = Expr.asCast(expr: exprID, type: typeRefID, isSafe: true, range: r)
        if case let .asCast(_, _, safe, _) = safeCast {
            XCTAssertTrue(safe)
        } else { XCTFail("Expected .asCast safe") }

        let unsafeCast = Expr.asCast(expr: exprID, type: typeRefID, isSafe: false, range: r)
        if case let .asCast(_, _, safe, _) = unsafeCast {
            XCTAssertFalse(safe)
        } else { XCTFail("Expected .asCast unsafe") }
    }

    func testExprNullAssert() {
        let r = makeRange(start: 0, end: 5)
        let arena = ASTArena()
        let exprID = arena.appendExpr(.intLiteral(1, r))
        let nullAssert = Expr.nullAssert(expr: exprID, range: r)
        if case let .nullAssert(e, _) = nullAssert {
            XCTAssertEqual(e, exprID)
        } else { XCTFail("Expected .nullAssert") }
    }

    func testExprLambdaLiteral() {
        let interner = StringInterner()
        let r = makeRange(start: 0, end: 10)
        let arena = ASTArena()
        let bodyID = arena.appendExpr(.intLiteral(1, r))
        let params = [interner.intern("x"), interner.intern("y")]
        let lambda = Expr.lambdaLiteral(params: params, body: bodyID, range: r)
        if case let .lambdaLiteral(p, b, _, _) = lambda {
            XCTAssertEqual(p.count, 2)
            XCTAssertEqual(b, bodyID)
        } else { XCTFail("Expected .lambdaLiteral") }
    }

    func testExprObjectLiteral() {
        let r = makeRange(start: 0, end: 5)
        let arena = ASTArena()
        let typeRefID = arena.appendTypeRef(.named(path: [], args: [], nullable: false))
        let obj = Expr.objectLiteral(superTypes: [typeRefID], range: r)
        if case let .objectLiteral(st, _) = obj {
            XCTAssertEqual(st.count, 1)
        } else { XCTFail("Expected .objectLiteral") }
    }

    func testExprCallableRef() {
        let interner = StringInterner()
        let r = makeRange(start: 0, end: 5)
        let arena = ASTArena()
        let receiverID = arena.appendExpr(.nameRef(interner.intern("MyClass"), r))
        let ref = Expr.callableRef(receiver: receiverID, member: interner.intern("method"), range: r)
        if case let .callableRef(recv, member, _) = ref {
            XCTAssertEqual(recv, receiverID)
            XCTAssertEqual(member, interner.intern("method"))
        } else { XCTFail("Expected .callableRef") }

        let refNoReceiver = Expr.callableRef(receiver: nil, member: interner.intern("topFun"), range: r)
        if case let .callableRef(recv, _, _) = refNoReceiver {
            XCTAssertNil(recv)
        } else { XCTFail("Expected .callableRef without receiver") }
    }

    func testExprLocalFunDecl() {
        let interner = StringInterner()
        let r = makeRange(start: 0, end: 10)
        let arena = ASTArena()
        let bodyID = arena.appendExpr(.intLiteral(1, r))
        let param = ValueParamDecl(name: interner.intern("a"), type: TypeRefID(rawValue: 0))
        let typeRefID = arena.appendTypeRef(.named(path: [interner.intern("Int")], args: [], nullable: false))
        let localFun = Expr.localFunDecl(name: interner.intern("helper"), valueParams: [param], returnType: typeRefID, body: .expr(bodyID, r), range: r)
        if case let .localFunDecl(name, params, ret, body, _) = localFun {
            XCTAssertEqual(name, interner.intern("helper"))
            XCTAssertEqual(params.count, 1)
            XCTAssertEqual(ret, typeRefID)
            if case let .expr(e, _) = body {
                XCTAssertEqual(e, bodyID)
            } else { XCTFail("Expected .expr body") }
        } else { XCTFail("Expected .localFunDecl") }
    }

    func testExprBlockExpr() {
        let r = makeRange(start: 0, end: 10)
        let arena = ASTArena()
        let stmt1 = arena.appendExpr(.intLiteral(1, r))
        let stmt2 = arena.appendExpr(.intLiteral(2, r))
        let trailing = arena.appendExpr(.intLiteral(3, r))
        let block = Expr.blockExpr(statements: [stmt1, stmt2], trailingExpr: trailing, range: r)
        if case let .blockExpr(stmts, trail, _) = block {
            XCTAssertEqual(stmts.count, 2)
            XCTAssertEqual(trail, trailing)
        } else { XCTFail("Expected .blockExpr") }

        let blockNoTrail = Expr.blockExpr(statements: [stmt1], trailingExpr: nil, range: r)
        if case let .blockExpr(_, trail, _) = blockNoTrail {
            XCTAssertNil(trail)
        } else { XCTFail("Expected .blockExpr without trailing") }
    }

    func testExprSuperRefAndThisRef() {
        let interner = StringInterner()
        let r = makeRange(start: 0, end: 5)
        let superRef = Expr.superRef(interfaceQualifier: nil, r)
        if case let .superRef(qualifier, range) = superRef {
            XCTAssertNil(qualifier)
            XCTAssertEqual(range, r)
        } else { XCTFail("Expected .superRef") }

        let qualifiedSuperRef = Expr.superRef(interfaceQualifier: interner.intern("MyInterface"), r)
        if case let .superRef(qualifier, range) = qualifiedSuperRef {
            XCTAssertEqual(qualifier, interner.intern("MyInterface"))
            XCTAssertEqual(range, r)
        } else { XCTFail("Expected .superRef with qualifier") }

        let thisRef = Expr.thisRef(label: nil, r)
        if case let .thisRef(label, _) = thisRef {
            XCTAssertNil(label)
        } else { XCTFail("Expected .thisRef") }

        let thisRefLabeled = Expr.thisRef(label: interner.intern("Outer"), r)
        if case let .thisRef(label, _) = thisRefLabeled {
            XCTAssertEqual(label, interner.intern("Outer"))
        } else { XCTFail("Expected .thisRef with label") }
    }

    // MARK: - ASTArena expr() method

    func testASTArenaExprLookup() {
        let r = makeRange(start: 0, end: 5)
        let arena = ASTArena()
        let id0 = arena.appendExpr(.intLiteral(42, r))
        let id1 = arena.appendExpr(.boolLiteral(true, r))

        if case let .intLiteral(val, _) = arena.expr(id0) {
            XCTAssertEqual(val, 42)
        } else {
            XCTFail("Expected .intLiteral from arena.expr()")
        }

        if case let .boolLiteral(val, _) = arena.expr(id1) {
            XCTAssertTrue(val)
        } else {
            XCTFail("Expected .boolLiteral from arena.expr()")
        }
    }

    func testASTArenaExprReturnsNilForInvalidID() {
        let arena = ASTArena()
        XCTAssertNil(arena.expr(ExprID(rawValue: -1)))
        XCTAssertNil(arena.expr(ExprID(rawValue: 0)))
        XCTAssertNil(arena.expr(ExprID(rawValue: 999)))
    }

    func testASTArenaExprSequentialIDs() {
        let r = makeRange(start: 0, end: 5)
        let arena = ASTArena()
        let id0 = arena.appendExpr(.intLiteral(1, r))
        let id1 = arena.appendExpr(.intLiteral(2, r))
        let id2 = arena.appendExpr(.intLiteral(3, r))
        XCTAssertEqual(id0.rawValue, 0)
        XCTAssertEqual(id1.rawValue, 1)
        XCTAssertEqual(id2.rawValue, 2)
    }

    func testASTArenaExprWithMultipleTypes() {
        let interner = StringInterner()
        let r = makeRange(start: 0, end: 10)
        let arena = ASTArena()
        let intID = arena.appendExpr(.intLiteral(1, r))
        let boolID = arena.appendExpr(.boolLiteral(false, r))
        let strID = arena.appendExpr(.stringLiteral(interner.intern("test"), r))
        let breakID = arena.appendExpr(.breakExpr(range: r))

        if case .intLiteral = arena.expr(intID) {} else { XCTFail("Expected .intLiteral") }
        if case .boolLiteral = arena.expr(boolID) {} else { XCTFail("Expected .boolLiteral") }
        if case .stringLiteral = arena.expr(strID) {} else { XCTFail("Expected .stringLiteral") }
        if case .breakExpr = arena.expr(breakID) {} else { XCTFail("Expected .breakExpr") }
    }
}
