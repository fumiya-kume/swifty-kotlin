@testable import CompilerCore
import XCTest

extension ASTModelsTests {
    // MARK: - Expr variants

    func testExprIntLiteral() {
        let r = makeRange(start: 0, end: 3)
        let expr = Expr.intLiteral(42, r)
        if case let .intLiteral(val, range) = expr {
            XCTAssertEqual(val, 42)
            XCTAssertEqual(range, r)
        } else {
            XCTFail("Expected .intLiteral")
        }
    }

    func testExprLongLiteral() {
        let r = makeRange(start: 0, end: 3)
        let expr = Expr.longLiteral(Int64.max, r)
        if case let .longLiteral(val, _) = expr {
            XCTAssertEqual(val, Int64.max)
        } else {
            XCTFail("Expected .longLiteral")
        }
    }

    func testExprFloatAndDoubleLiteral() {
        let r = makeRange(start: 0, end: 3)
        let floatExpr = Expr.floatLiteral(3.14, r)
        if case let .floatLiteral(val, _) = floatExpr {
            XCTAssertEqual(val, 3.14)
        } else {
            XCTFail("Expected .floatLiteral")
        }
        let doubleExpr = Expr.doubleLiteral(2.718, r)
        if case let .doubleLiteral(val, _) = doubleExpr {
            XCTAssertEqual(val, 2.718)
        } else {
            XCTFail("Expected .doubleLiteral")
        }
    }

    func testExprCharLiteral() {
        let r = makeRange(start: 0, end: 3)
        let expr = Expr.charLiteral(65, r)
        if case let .charLiteral(val, _) = expr {
            XCTAssertEqual(val, 65)
        } else {
            XCTFail("Expected .charLiteral")
        }
    }

    func testExprBoolLiteral() {
        let r = makeRange(start: 0, end: 3)
        let trueExpr = Expr.boolLiteral(true, r)
        let falseExpr = Expr.boolLiteral(false, r)
        if case let .boolLiteral(val, _) = trueExpr {
            XCTAssertTrue(val)
        } else {
            XCTFail("Expected .boolLiteral")
        }
        if case let .boolLiteral(val, _) = falseExpr {
            XCTAssertFalse(val)
        } else {
            XCTFail("Expected .boolLiteral")
        }
    }

    func testExprStringLiteralAndTemplate() {
        let interner = StringInterner()
        let r = makeRange(start: 0, end: 3)
        let strExpr = Expr.stringLiteral(interner.intern("hello"), r)
        if case let .stringLiteral(val, _) = strExpr {
            XCTAssertEqual(val, interner.intern("hello"))
        } else {
            XCTFail("Expected .stringLiteral")
        }

        let arena = ASTArena()
        let innerExprID = arena.appendExpr(.intLiteral(1, r))
        let templateExpr = Expr.stringTemplate(
            parts: [.literal(interner.intern("x=")), .expression(innerExprID)],
            range: r
        )
        if case let .stringTemplate(parts, _) = templateExpr {
            XCTAssertEqual(parts.count, 2)
        } else {
            XCTFail("Expected .stringTemplate")
        }
    }

    func testExprNameRef() {
        let interner = StringInterner()
        let r = makeRange(start: 0, end: 3)
        let expr = Expr.nameRef(interner.intern("myVar"), r)
        if case let .nameRef(name, _) = expr {
            XCTAssertEqual(name, interner.intern("myVar"))
        } else {
            XCTFail("Expected .nameRef")
        }
    }

    func testExprControlFlow() {
        let r = makeRange(start: 0, end: 10)
        let arena = ASTArena()
        let interner = StringInterner()
        let bodyID = arena.appendExpr(.intLiteral(1, r))
        let condID = arena.appendExpr(.boolLiteral(true, r))
        let loopVar = interner.intern("i")

        let forExpr = Expr.forExpr(loopVariable: loopVar, iterable: bodyID, body: bodyID, range: r)
        if case let .forExpr(lv, _, _, _, _) = forExpr {
            XCTAssertEqual(lv, loopVar)
        } else { XCTFail("Expected .forExpr") }

        let whileExpr = Expr.whileExpr(condition: condID, body: bodyID, range: r)
        if case let .whileExpr(c, b, _, _) = whileExpr {
            XCTAssertEqual(c, condID)
            XCTAssertEqual(b, bodyID)
        } else { XCTFail("Expected .whileExpr") }

        let doWhileExpr = Expr.doWhileExpr(body: bodyID, condition: condID, range: r)
        if case let .doWhileExpr(b, c, _, _) = doWhileExpr {
            XCTAssertEqual(b, bodyID)
            XCTAssertEqual(c, condID)
        } else { XCTFail("Expected .doWhileExpr") }

        let breakExpr = Expr.breakExpr(range: r)
        if case let .breakExpr(_, range) = breakExpr {
            XCTAssertEqual(range, r)
        } else { XCTFail("Expected .breakExpr") }

        let continueExpr = Expr.continueExpr(range: r)
        if case let .continueExpr(_, range) = continueExpr {
            XCTAssertEqual(range, r)
        } else { XCTFail("Expected .continueExpr") }
    }

    func testExprLocalDeclAndAssign() {
        let interner = StringInterner()
        let r = makeRange(start: 0, end: 10)
        let arena = ASTArena()
        let initID = arena.appendExpr(.intLiteral(5, r))
        let name = interner.intern("x")
        let typeRefID = arena.appendTypeRef(.named(path: [interner.intern("Int")], args: [], nullable: false))

        let localDecl = Expr.localDecl(name: name, isMutable: true, typeAnnotation: typeRefID, initializer: initID, range: r)
        if case let .localDecl(n, mut, ta, init_, _, _) = localDecl {
            XCTAssertEqual(n, name)
            XCTAssertTrue(mut)
            XCTAssertEqual(ta, typeRefID)
            XCTAssertEqual(init_, initID)
        } else { XCTFail("Expected .localDecl") }

        let localAssign = Expr.localAssign(name: name, value: initID, range: r)
        if case let .localAssign(n, v, _) = localAssign {
            XCTAssertEqual(n, name)
            XCTAssertEqual(v, initID)
        } else { XCTFail("Expected .localAssign") }

        let memberAssign = Expr.memberAssign(receiver: initID, callee: interner.intern("value"), value: initID, range: r)
        if case let .memberAssign(receiver, callee, value, _) = memberAssign {
            XCTAssertEqual(receiver, initID)
            XCTAssertEqual(callee, interner.intern("value"))
            XCTAssertEqual(value, initID)
        } else { XCTFail("Expected .memberAssign") }

        let arrExprID = arena.appendExpr(.intLiteral(0, r))
        let idxExprID = arena.appendExpr(.intLiteral(1, r))
        let indexedAssign = Expr.indexedAssign(receiver: arrExprID, indices: [idxExprID], value: initID, range: r)
        if case let .indexedAssign(a, indices, v, _) = indexedAssign {
            XCTAssertEqual(a, arrExprID)
            XCTAssertEqual(indices, [idxExprID])
            XCTAssertEqual(v, initID)
        } else { XCTFail("Expected .indexedAssign") }
    }

    func testExprCallAndMemberCall() {
        let interner = StringInterner()
        let r = makeRange(start: 0, end: 10)
        let arena = ASTArena()
        let calleeID = arena.appendExpr(.nameRef(interner.intern("foo"), r))
        let argExprID = arena.appendExpr(.intLiteral(1, r))
        let typeRefID = arena.appendTypeRef(.named(path: [interner.intern("Int")], args: [], nullable: false))
        let arg = CallArgument(label: interner.intern("x"), isSpread: false, expr: argExprID)

        let callExpr = Expr.call(callee: calleeID, typeArgs: [typeRefID], args: [arg], range: r)
        if case let .call(c, ta, args, _) = callExpr {
            XCTAssertEqual(c, calleeID)
            XCTAssertEqual(ta.count, 1)
            XCTAssertEqual(args.count, 1)
            XCTAssertEqual(args[0].label, interner.intern("x"))
        } else { XCTFail("Expected .call") }

        let receiverID = arena.appendExpr(.nameRef(interner.intern("obj"), r))
        let memberCall = Expr.memberCall(receiver: receiverID, callee: interner.intern("bar"), typeArgs: [], args: [arg], range: r)
        if case let .memberCall(recv, callee, _, args, _) = memberCall {
            XCTAssertEqual(recv, receiverID)
            XCTAssertEqual(callee, interner.intern("bar"))
            XCTAssertEqual(args.count, 1)
        } else { XCTFail("Expected .memberCall") }

        let safeMemberCall = Expr.safeMemberCall(receiver: receiverID, callee: interner.intern("baz"), typeArgs: [], args: [], range: r)
        if case let .safeMemberCall(recv, callee, _, _, _) = safeMemberCall {
            XCTAssertEqual(recv, receiverID)
            XCTAssertEqual(callee, interner.intern("baz"))
        } else { XCTFail("Expected .safeMemberCall") }
    }

    func testExprIndexedAccess() {
        let r = makeRange(start: 0, end: 5)
        let arena = ASTArena()
        let arrID = arena.appendExpr(.intLiteral(0, r))
        let idxID = arena.appendExpr(.intLiteral(1, r))
        let expr = Expr.indexedAccess(receiver: arrID, indices: [idxID], range: r)
        if case let .indexedAccess(a, indices, _) = expr {
            XCTAssertEqual(a, arrID)
            XCTAssertEqual(indices, [idxID])
        } else { XCTFail("Expected .indexedAccess") }
    }

    func testExprBinaryAllOps() {
        let r = makeRange(start: 0, end: 5)
        let arena = ASTArena()
        let lhs = arena.appendExpr(.intLiteral(1, r))
        let rhs = arena.appendExpr(.intLiteral(2, r))
        let ops: [BinaryOp] = [
            .add, .subtract, .multiply, .divide, .modulo,
            .equal, .notEqual, .lessThan, .lessOrEqual,
            .greaterThan, .greaterOrEqual, .logicalAnd,
            .logicalOr, .elvis, .rangeTo,
        ]
        for op in ops {
            let expr = Expr.binary(op: op, lhs: lhs, rhs: rhs, range: r)
            if case let .binary(o, _, _, _) = expr {
                XCTAssertEqual(o, op)
            } else { XCTFail("Expected .binary for op \(op)") }
        }
    }

    func testExprUnaryAllOps() {
        let r = makeRange(start: 0, end: 5)
        let arena = ASTArena()
        let operand = arena.appendExpr(.intLiteral(1, r))
        let ops: [UnaryOp] = [.not, .unaryPlus, .unaryMinus]
        for op in ops {
            let expr = Expr.unaryExpr(op: op, operand: operand, range: r)
            if case let .unaryExpr(o, _, _) = expr {
                XCTAssertEqual(o, op)
            } else { XCTFail("Expected .unaryExpr for op \(op)") }
        }
    }

    func testExprCompoundAssignAllOps() {
        let interner = StringInterner()
        let r = makeRange(start: 0, end: 5)
        let arena = ASTArena()
        let valID = arena.appendExpr(.intLiteral(1, r))
        let name = interner.intern("x")
        let ops: [CompoundAssignOp] = [.plusAssign, .minusAssign, .timesAssign, .divAssign, .modAssign]
        for op in ops {
            let expr = Expr.compoundAssign(op: op, name: name, value: valID, range: r)
            if case let .compoundAssign(o, _, _, _) = expr {
                XCTAssertEqual(o, op)
            } else { XCTFail("Expected .compoundAssign for op \(op)") }
        }
    }
}
