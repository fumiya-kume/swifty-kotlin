@testable import CompilerCore
import Foundation
import XCTest

extension BuildKIRRegressionTests {
    func testDirectSharedAPICallForwardersAreReachable() {
        let fixture = makeKIRDirectLoweringFixture()
        let range = makeRange()
        let intType = fixture.types.make(.primitive(.int, .nonNull))

        let receiver = appendTypedExpr(
            .nameRef(fixture.interner.intern("receiver"), range),
            type: fixture.types.anyType,
            fixture: fixture
        )
        let lhs = appendTypedExpr(.intLiteral(10, range), type: intType, fixture: fixture)
        let rhs = appendTypedExpr(.intLiteral(20, range), type: intType, fixture: fixture)
        let index = appendTypedExpr(.intLiteral(0, range), type: intType, fixture: fixture)
        let calleeExpr = appendTypedExpr(
            .nameRef(fixture.interner.intern("callee"), range),
            type: fixture.types.anyType,
            fixture: fixture
        )

        let binaryExpr = appendTypedExpr(
            .binary(op: .add, lhs: lhs, rhs: rhs, range: range),
            type: intType,
            fixture: fixture
        )
        let indexedAccessExpr = appendTypedExpr(
            .indexedAccess(receiver: receiver, indices: [index], range: range),
            type: fixture.types.anyType,
            fixture: fixture
        )
        let indexedAssignExpr = appendTypedExpr(
            .indexedAssign(receiver: receiver, indices: [index], value: rhs, range: range),
            type: fixture.types.unitType,
            fixture: fixture
        )
        let indexedCompoundExpr = appendTypedExpr(
            .indexedCompoundAssign(
                op: .plusAssign,
                receiver: receiver,
                indices: [index],
                value: rhs,
                range: range
            ),
            type: fixture.types.unitType,
            fixture: fixture
        )
        let callExpr = appendTypedExpr(
            .call(callee: calleeExpr, typeArgs: [], args: [CallArgument(expr: lhs)], range: range),
            type: fixture.types.anyType,
            fixture: fixture
        )
        let memberCallExpr = appendTypedExpr(
            .memberCall(
                receiver: receiver,
                callee: fixture.interner.intern("ping"),
                typeArgs: [],
                args: [CallArgument(expr: rhs)],
                range: range
            ),
            type: fixture.types.anyType,
            fixture: fixture
        )

        let shared = fixture.makeShared()
        var emit = KIRLoweringEmitContext()
        _ = fixture.driver.callLowerer.lowerBinaryExpr(
            binaryExpr,
            op: .add,
            lhs: lhs,
            rhs: rhs,
            shared: shared,
            emit: &emit
        )
        _ = fixture.driver.callLowerer.lowerIndexedAccessExpr(
            indexedAccessExpr,
            receiverExpr: receiver,
            indices: [index],
            shared: shared,
            emit: &emit
        )
        _ = fixture.driver.callLowerer.lowerIndexedAssignExpr(
            indexedAssignExpr,
            receiverExpr: receiver,
            indices: [index],
            valueExpr: rhs,
            shared: shared,
            emit: &emit
        )
        _ = fixture.driver.callLowerer.lowerIndexedCompoundAssignExpr(
            indexedCompoundExpr,
            receiverExpr: receiver,
            indices: [index],
            valueExpr: rhs,
            shared: shared,
            emit: &emit
        )
        _ = fixture.driver.callLowerer.lowerCallExpr(
            callExpr,
            calleeExpr: calleeExpr,
            args: [CallArgument(expr: lhs)],
            shared: shared,
            emit: &emit
        )
        _ = fixture.driver.callLowerer.lowerMemberCallExpr(
            memberCallExpr,
            receiverExpr: receiver,
            calleeName: fixture.interner.intern("ping"),
            args: [CallArgument(expr: rhs)],
            shared: shared,
            emit: &emit
        )

        let callees = extractCallees(from: emit.instructions, interner: fixture.interner)
        XCTAssertFalse(emit.instructions.isEmpty)
        XCTAssertTrue(callees.contains("kk_array_get"))
        XCTAssertTrue(callees.contains("kk_array_set"))
    }

    func testDirectSharedAPIControlFlowForwardersAreReachable() {
        let fixture = makeKIRDirectLoweringFixture()
        let range = makeRange()
        let boolType = fixture.types.make(.primitive(.boolean, .nonNull))
        let intType = fixture.types.make(.primitive(.int, .nonNull))

        let iterable = appendTypedExpr(
            .nameRef(fixture.interner.intern("items"), range),
            type: fixture.types.anyType,
            fixture: fixture
        )
        let condition = appendTypedExpr(.boolLiteral(true, range), type: boolType, fixture: fixture)
        let bodyValue = appendTypedExpr(.intLiteral(1, range), type: intType, fixture: fixture)
        let elseValue = appendTypedExpr(.intLiteral(2, range), type: intType, fixture: fixture)
        let catchBody = appendTypedExpr(.intLiteral(0, range), type: intType, fixture: fixture)

        let forExpr = appendTypedExpr(
            .forExpr(loopVariable: nil, iterable: iterable, body: bodyValue, range: range),
            type: fixture.types.unitType,
            fixture: fixture
        )
        let whileExpr = appendTypedExpr(
            .whileExpr(condition: condition, body: bodyValue, range: range),
            type: fixture.types.unitType,
            fixture: fixture
        )
        let doWhileExpr = appendTypedExpr(
            .doWhileExpr(body: bodyValue, condition: condition, range: range),
            type: fixture.types.unitType,
            fixture: fixture
        )
        let ifExpr = appendTypedExpr(
            .ifExpr(condition: condition, thenExpr: bodyValue, elseExpr: elseValue, range: range),
            type: intType,
            fixture: fixture
        )
        let catchClause = CatchClause(
            paramName: fixture.interner.intern("e"),
            paramTypeName: fixture.interner.intern("Any"),
            body: catchBody,
            range: range
        )
        let tryExpr = appendTypedExpr(
            .tryExpr(body: bodyValue, catchClauses: [catchClause], finallyExpr: nil, range: range),
            type: intType,
            fixture: fixture
        )

        let shared = fixture.makeShared()
        var emit = KIRLoweringEmitContext()
        _ = fixture.driver.controlFlowLowerer.lowerForExpr(
            forExpr,
            iterableExpr: iterable,
            bodyExpr: bodyValue,
            label: nil,
            shared: shared,
            emit: &emit
        )
        _ = fixture.driver.controlFlowLowerer.lowerWhileExpr(
            whileExpr,
            conditionExpr: condition,
            bodyExpr: bodyValue,
            label: nil,
            shared: shared,
            emit: &emit
        )
        _ = fixture.driver.controlFlowLowerer.lowerDoWhileExpr(
            doWhileExpr,
            bodyExpr: bodyValue,
            conditionExpr: condition,
            label: nil,
            shared: shared,
            emit: &emit
        )
        _ = fixture.driver.controlFlowLowerer.lowerIfExpr(
            ifExpr,
            condition: condition,
            thenExpr: bodyValue,
            elseExpr: elseValue,
            shared: shared,
            emit: &emit
        )
        _ = fixture.driver.controlFlowLowerer.lowerTryExpr(
            tryExpr,
            bodyExpr: bodyValue,
            catchClauses: [catchClause],
            finallyExpr: nil,
            shared: shared,
            emit: &emit
        )

        XCTAssertTrue(emit.instructions.contains { instruction in
            if case .label = instruction { return true }
            return false
        })
    }

    func testDirectMemberCallWithInvokeOperatorRoutesToInvokeCallee() {
        let fixture = makeKIRDirectLoweringFixture()
        let range = makeRange()
        let intType = fixture.types.make(.primitive(.int, .nonNull))

        let owner = defineSemanticSymbol(in: fixture, kind: .class, fqName: ["pkg", "Invoker"])
        let invoke = defineSemanticSymbol(in: fixture, kind: .function, fqName: ["pkg", "Invoker", "call"])
        let valueParam = defineSemanticSymbol(in: fixture, kind: .valueParameter, fqName: ["pkg", "Invoker", "call", "x"])
        let ownerType = fixture.types.make(
            .classType(
                ClassType(
                    classSymbol: owner,
                    args: [],
                    nullability: .nonNull
                )
            )
        )
        fixture.symbols.setParentSymbol(owner, for: invoke)
        fixture.symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: ownerType,
                parameterTypes: [intType],
                returnType: intType,
                valueParameterSymbols: [valueParam],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [false]
            ),
            for: invoke
        )

        let receiver = appendTypedExpr(
            .nameRef(fixture.interner.intern("obj"), range),
            type: ownerType,
            fixture: fixture
        )
        let argExpr = appendTypedExpr(.intLiteral(3, range), type: intType, fixture: fixture)
        let args = [CallArgument(expr: argExpr)]
        let exprID = appendTypedExpr(
            .memberCall(
                receiver: receiver,
                callee: fixture.interner.intern("value"),
                typeArgs: [],
                args: args,
                range: range
            ),
            type: intType,
            fixture: fixture
        )
        fixture.bindings.bindCall(
            exprID,
            binding: CallBinding(
                chosenCallee: invoke,
                substitutedTypeArguments: [],
                parameterMapping: [0: 0]
            )
        )
        fixture.bindings.markInvokeOperatorCall(exprID)

        var emit = KIRLoweringEmitContext()
        _ = fixture.driver.callLowerer.lowerMemberCallExpr(
            exprID,
            receiverExpr: receiver,
            calleeName: fixture.interner.intern("value"),
            args: args,
            shared: fixture.makeShared(),
            emit: &emit
        )

        guard let callInstruction = emit.instructions.first(where: { instruction in
            if case .call = instruction { return true }
            return false
        }) else {
            XCTFail("Expected member invoke call instruction")
            return
        }
        guard case let .call(chosen, loweredCallee, _, _, _, _, _) = callInstruction else {
            XCTFail("Expected .call instruction")
            return
        }
        XCTAssertEqual(chosen, invoke)
        XCTAssertEqual(fixture.interner.resolve(loweredCallee), "invoke")
    }

    func testDirectSafeMemberCallWithInvokeOperatorRoutesToInvokeCallee() {
        let fixture = makeKIRDirectLoweringFixture()
        let range = makeRange()
        let intType = fixture.types.make(.primitive(.int, .nonNull))

        let owner = defineSemanticSymbol(in: fixture, kind: .class, fqName: ["pkg", "SafeInvoker"])
        let invoke = defineSemanticSymbol(in: fixture, kind: .function, fqName: ["pkg", "SafeInvoker", "call"])
        let valueParam = defineSemanticSymbol(in: fixture, kind: .valueParameter, fqName: ["pkg", "SafeInvoker", "call", "x"])
        let ownerType = fixture.types.make(
            .classType(
                ClassType(
                    classSymbol: owner,
                    args: [],
                    nullability: .nonNull
                )
            )
        )
        fixture.symbols.setParentSymbol(owner, for: invoke)
        fixture.symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: ownerType,
                parameterTypes: [intType],
                returnType: intType,
                valueParameterSymbols: [valueParam],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [false]
            ),
            for: invoke
        )

        let receiver = appendTypedExpr(
            .nameRef(fixture.interner.intern("obj"), range),
            type: ownerType,
            fixture: fixture
        )
        let argExpr = appendTypedExpr(.intLiteral(9, range), type: intType, fixture: fixture)
        let args = [CallArgument(expr: argExpr)]
        let exprID = appendSafeMemberExpr(
            receiver: receiver,
            callee: fixture.interner.intern("value"),
            args: args,
            type: intType,
            fixture: fixture
        )
        fixture.bindings.bindCall(
            exprID,
            binding: CallBinding(
                chosenCallee: invoke,
                substitutedTypeArguments: [],
                parameterMapping: [0: 0]
            )
        )
        fixture.bindings.markInvokeOperatorCall(exprID)

        var emit = KIRLoweringEmitContext()
        _ = fixture.driver.callLowerer.lowerSafeMemberCallExpr(
            exprID,
            receiverExpr: receiver,
            calleeName: fixture.interner.intern("value"),
            args: args,
            shared: fixture.makeShared(),
            emit: &emit
        )

        guard let callInstruction = emit.instructions.first(where: { instruction in
            if case .call = instruction { return true }
            return false
        }) else {
            XCTFail("Expected safe member invoke call instruction")
            return
        }
        guard case let .call(chosen, loweredCallee, _, _, _, _, _) = callInstruction else {
            XCTFail("Expected .call instruction")
            return
        }
        XCTAssertEqual(chosen, invoke)
        XCTAssertEqual(fixture.interner.resolve(loweredCallee), "invoke")
    }

    func testDirectSharedAPILambdaAndObjectForwardersAreReachable() {
        let fixture = makeKIRDirectLoweringFixture()
        let range = makeRange()
        let intType = fixture.types.make(.primitive(.int, .nonNull))
        let functionType = fixture.types.make(
            .functionType(
                FunctionType(
                    params: [intType],
                    returnType: intType,
                    isSuspend: false,
                    nullability: .nonNull
                )
            )
        )

        let bodyExpr = appendTypedExpr(.intLiteral(7, range), type: intType, fixture: fixture)
        let lambdaExpr = appendTypedExpr(
            .lambdaLiteral(
                params: [fixture.interner.intern("x")],
                body: bodyExpr,
                range: range
            ),
            type: functionType,
            fixture: fixture
        )
        let callableRefExpr = appendTypedExpr(
            .callableRef(receiver: nil, member: fixture.interner.intern("missing"), range: range),
            type: functionType,
            fixture: fixture
        )
        let objectExpr = appendTypedExpr(
            .objectLiteral(superTypes: [], range: range),
            type: fixture.types.anyType,
            fixture: fixture
        )

        let shared = fixture.makeShared()
        var emit = KIRLoweringEmitContext()
        _ = fixture.driver.lambdaLowerer.lowerLambdaLiteralExpr(
            lambdaExpr,
            params: [fixture.interner.intern("x")],
            bodyExpr: bodyExpr,
            shared: shared,
            emit: &emit
        )
        _ = fixture.driver.lambdaLowerer.lowerCallableRefExpr(
            callableRefExpr,
            receiverExpr: nil,
            memberName: fixture.interner.intern("missing"),
            shared: shared,
            emit: &emit
        )
        _ = fixture.driver.objectLiteralLowerer.lowerObjectLiteralExpr(
            objectExpr,
            superTypes: [],
            shared: shared,
            emit: &emit
        )

        XCTAssertFalse(fixture.kirArena.declarations.isEmpty)
    }
}
