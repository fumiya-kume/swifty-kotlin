@testable import CompilerCore
import Foundation
import XCTest

extension BuildKIRRegressionTests {
    func testNestedReturnInBothIfElseBranchesDoesNotEmitDeadEpilogue() throws {
        let source = """
        fun pick(flag: Boolean): Int {
            if (flag) {
                return 1
            } else {
                return 2
            }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "pick", in: module, interner: ctx.interner)

            let returnValues = body.compactMap { instruction -> KIRExprID? in
                guard case let .returnValue(id) = instruction else { return nil }
                return id
            }
            // Should have exactly 2 returns: one from each branch, no spurious epilogue return
            XCTAssertEqual(returnValues.count, 2, "Expected exactly 2 returnValue instructions (then + else), got \(returnValues.count)")
        }
    }

    func testNestedReturnInWhenBranchDoesNotEmitDeadCopyInstruction() throws {
        let source = """
        fun classify(x: Int): Int {
            when (x) {
                1 -> return 10
                2 -> return 20
                else -> return 30
            }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "classify", in: module, interner: ctx.interner)

            let returnValues = body.compactMap { instruction -> KIRExprID? in
                guard case let .returnValue(id) = instruction else { return nil }
                return id
            }
            XCTAssertGreaterThanOrEqual(returnValues.count, 3, "Expected at least 3 returnValue instructions for when-branch returns, got \(returnValues.count)")

            // Verify no dead copy follows a returnValue in the when branches
            var deadCopyAfterReturn = false
            for (index, instruction) in body.enumerated() {
                if case .returnValue = instruction {
                    var nextIndex = index + 1
                    while nextIndex < body.count {
                        if case .label = body[nextIndex] {
                            nextIndex += 1
                            continue
                        }
                        if case .copy = body[nextIndex] {
                            deadCopyAfterReturn = true
                        }
                        break
                    }
                }
            }
            XCTAssertFalse(deadCopyAfterReturn, "No dead copy should follow a returnValue in when branches")
        }
    }

    func testBlockExprStopsLoweringAfterNestedReturn() throws {
        let source = """
        fun earlyReturn(flag: Boolean): Int {
            if (flag) {
                return 42
                val x = 99
            }
            return 0
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "earlyReturn", in: module, interner: ctx.interner)

            // The val x = 99 after return should not produce any const 99 in the body
            let has99 = body.contains { instruction in
                guard case let .constValue(_, value) = instruction else { return false }
                if case .intLiteral(99) = value { return true }
                return false
            }
            XCTAssertFalse(has99, "Dead code after return in block should not be lowered")
        }
    }

    func testNestedReturnInTryCatchBranchPropagatesCorrectly() throws {
        let source = """
        fun safeDivide(a: Int, b: Int): Int {
            try {
                return a / b
            } catch (e: Any) {
                return 0
            }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "safeDivide", in: module, interner: ctx.interner)

            let returnValues = body.compactMap { instruction -> KIRExprID? in
                guard case let .returnValue(id) = instruction else { return nil }
                return id
            }
            XCTAssertGreaterThanOrEqual(returnValues.count, 2, "Expected at least 2 returnValue instructions (try body + catch), got \(returnValues.count)")

            let callees = extractCallees(from: body, interner: ctx.interner)
            XCTAssertTrue(
                callees.contains("kk_throwable_is_cancellation"),
                "Try/catch lowering must guard CancellationException with runtime predicate"
            )
            let throwFlags = extractThrowFlags(from: body, interner: ctx.interner)
            XCTAssertEqual(throwFlags["kk_throwable_is_cancellation"]?.allSatisfy { $0 == false }, true)
        }
    }

    func testIfExprLoweringUsesLabelBasedBranching() throws {
        let source = """
        fun branch(flag: Boolean): Int {
            val x = if (flag) 1 else 2
            return x
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "branch", in: module, interner: ctx.interner)
            let hasJump = body.contains { instruction in
                if case .jump = instruction { return true }
                return false
            }
            let hasLabel = body.contains { instruction in
                if case .label = instruction { return true }
                return false
            }
            XCTAssertTrue(hasJump, "if-expr lowering should use jump instructions for branching")
            XCTAssertTrue(hasLabel, "if-expr lowering should use label instructions for branching")
        }
    }

    func testWhenExprLoweringUsesLabelBasedBranching() throws {
        let source = """
        fun pick(x: Int): Int {
            return when (x) {
                1 -> 10
                2 -> 20
                else -> 0
            }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "pick", in: module, interner: ctx.interner)
            let labelCount = body.filter { instruction in
                if case .label = instruction { return true }
                return false
            }.count
            let jumpCount = body.filter { instruction in
                if case .jump = instruction { return true }
                return false
            }.count
            XCTAssertGreaterThanOrEqual(labelCount, 2, "when-expr should have labels for branch dispatch")
            XCTAssertGreaterThanOrEqual(jumpCount, 2, "when-expr should have jumps for branch dispatch")
        }
    }

    func testVarargNonTrailingWithNamedTailPacksCorrectly() throws {
        let source = """
        fun tagged(vararg nums: Int, tail: Int): Int = tail
        fun main() = tagged(10, 20, tail = 99)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let mainFunction = module.arena.declarations.compactMap { decl -> KIRFunction? in
                guard case let .function(function) = decl else { return nil }
                return ctx.interner.resolve(function.name) == "main" ? function : nil
            }.first
            let body = try XCTUnwrap(mainFunction?.body)
            let callNames = body.compactMap { instruction -> String? in
                guard case let .call(_, callee, _, _, _, _, _) = instruction else { return nil }
                return ctx.interner.resolve(callee)
            }
            XCTAssertTrue(callNames.contains("kk_array_new"), "Expected kk_array_new for non-trailing vararg, got: \(callNames)")
            XCTAssertTrue(callNames.contains("kk_array_set"), "Expected kk_array_set for non-trailing vararg, got: \(callNames)")
        }
    }

    // MARK: - if/when Control Flow (P5-51)

    func testIfExprUsesControlFlowInsteadOfSelect() throws {
        let source = """
        fun pick(flag: Boolean): Int = if (flag) 1 else 2
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "pick", in: module, interner: ctx.interner)

            // .select was removed from KIRInstruction; verify control-flow is used
            let labelCount = body.filter { if case .label = $0 { return true }; return false }.count
            XCTAssertGreaterThanOrEqual(labelCount, 2, "ifExpr needs at least elseLabel + endLabel")

            let jumpCount = body.filter { instruction in
                if case .jump = instruction { return true }
                if case .jumpIfEqual = instruction { return true }
                return false
            }.count
            XCTAssertGreaterThanOrEqual(jumpCount, 2, "ifExpr needs conditional + unconditional jump")
        }
    }

    func testWhenExprUsesControlFlowInsteadOfSelect() throws {
        let source = """
        fun pick(x: Int): Int = when (x) { 1 -> 10, 2 -> 20, else -> 0 }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "pick", in: module, interner: ctx.interner)

            // .select was removed from KIRInstruction; verify control-flow is used
            let labelCount = body.filter { if case .label = $0 { return true }; return false }.count
            XCTAssertGreaterThanOrEqual(labelCount, 3, "whenExpr with 2 branches + else needs at least 3 labels")
        }
    }
}

private struct KIRDirectLoweringFixture {
    let interner: StringInterner
    let diagnostics: DiagnosticEngine
    let symbols: SymbolTable
    let types: TypeSystem
    let bindings: BindingTable
    let sema: SemaModule
    let astArena: ASTArena
    let ast: ASTModule
    let kirArena: KIRArena
    let driver: KIRLoweringDriver

    func makeShared(
        propertyConstantInitializers: [SymbolID: KIRExprKind] = [:]
    ) -> KIRLoweringSharedContext {
        KIRLoweringSharedContext(
            ast: ast,
            sema: sema,
            arena: kirArena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers
        )
    }
}

private func makeKIRDirectLoweringFixture() -> KIRDirectLoweringFixture {
    let interner = StringInterner()
    let diagnostics = DiagnosticEngine()
    let symbols = SymbolTable()
    let types = TypeSystem()
    let bindings = BindingTable()
    let sema = SemaModule(
        symbols: symbols,
        types: types,
        bindings: bindings,
        diagnostics: diagnostics
    )
    let astArena = ASTArena()
    let file = ASTFile(
        fileID: FileID(rawValue: 0),
        packageFQName: [interner.intern("pkg")],
        imports: [],
        topLevelDecls: [],
        scriptBody: []
    )
    let ast = ASTModule(
        files: [file],
        arena: astArena,
        declarationCount: 0,
        tokenCount: 0
    )
    let kirArena = KIRArena()
    let loweringContext = KIRLoweringContext()
    loweringContext.initializeSyntheticLambdaSymbolAllocator(sema: sema)
    let driver = KIRLoweringDriver(ctx: loweringContext)
    return KIRDirectLoweringFixture(
        interner: interner,
        diagnostics: diagnostics,
        symbols: symbols,
        types: types,
        bindings: bindings,
        sema: sema,
        astArena: astArena,
        ast: ast,
        kirArena: kirArena,
        driver: driver
    )
}

private func defineSemanticSymbol(
    in fixture: KIRDirectLoweringFixture,
    kind: SymbolKind,
    fqName: [String],
    flags: SymbolFlags = []
) -> SymbolID {
    precondition(!fqName.isEmpty)
    let interned = fqName.map { fixture.interner.intern($0) }
    return fixture.symbols.define(
        kind: kind,
        name: interned.last!,
        fqName: interned,
        declSite: nil,
        visibility: .public,
        flags: flags
    )
}

private func appendTypedExpr(
    _ expr: Expr,
    type: TypeID?,
    fixture: KIRDirectLoweringFixture
) -> ExprID {
    let exprID = fixture.astArena.appendExpr(expr)
    if let type {
        fixture.bindings.bindExprType(exprID, type: type)
    }
    return exprID
}

private func appendSafeMemberExpr(
    receiver: ExprID,
    callee: InternedString,
    args: [CallArgument],
    type: TypeID,
    fixture: KIRDirectLoweringFixture
) -> ExprID {
    let exprID = fixture.astArena.appendExpr(
        .safeMemberCall(
            receiver: receiver,
            callee: callee,
            typeArgs: [],
            args: args,
            range: makeRange()
        )
    )
    fixture.bindings.bindExprType(exprID, type: type)
    return exprID
}

private func appendSafeMemberExprWithoutType(
    receiver: ExprID,
    callee: InternedString,
    args: [CallArgument],
    fixture: KIRDirectLoweringFixture
) -> ExprID {
    fixture.astArena.appendExpr(
        .safeMemberCall(
            receiver: receiver,
            callee: callee,
            typeArgs: [],
            args: args,
            range: makeRange()
        )
    )
}

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

    // swiftlint:disable:next function_body_length
    func testDirectMemberCallWithInvokeOperatorRoutesToInvokeCallee() {
        let fixture = makeKIRDirectLoweringFixture()
        let range = makeRange()
        let intType = fixture.types.make(.primitive(.int, .nonNull))

        let owner = defineSemanticSymbol(in: fixture, kind: .class, fqName: ["pkg", "Invoker"])
        let invoke = defineSemanticSymbol(in: fixture, kind: .function, fqName: ["pkg", "Invoker", "call"])
        // swiftlint:disable:next line_length
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

    // swiftlint:disable:next function_body_length
    func testDirectSafeMemberCallWithInvokeOperatorRoutesToInvokeCallee() {
        let fixture = makeKIRDirectLoweringFixture()
        let range = makeRange()
        let intType = fixture.types.make(.primitive(.int, .nonNull))

        let owner = defineSemanticSymbol(in: fixture, kind: .class, fqName: ["pkg", "SafeInvoker"])
        let invoke = defineSemanticSymbol(in: fixture, kind: .function, fqName: ["pkg", "SafeInvoker", "call"])
        // swiftlint:disable:next line_length
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

    func testDirectSafeMemberCallConstFoldNonNullAndNullablePaths() {
        let fixture = makeKIRDirectLoweringFixture()
        let range = makeRange()
        let callee = fixture.interner.intern("value")
        let intType = fixture.types.make(.primitive(.int, .nonNull))
        let nullableIntType = fixture.types.make(.primitive(.int, .nullable))

        let constProperty = defineSemanticSymbol(
            in: fixture,
            kind: .property,
            fqName: ["pkg", "Holder", "value"],
            flags: [.constValue]
        )

        let receiverNonNull = appendTypedExpr(
            .nameRef(fixture.interner.intern("r1"), range),
            type: intType,
            fixture: fixture
        )
        let exprFolded = appendSafeMemberExpr(
            receiver: receiverNonNull,
            callee: callee,
            args: [],
            type: intType,
            fixture: fixture
        )
        fixture.bindings.bindCall(
            exprFolded,
            binding: CallBinding(
                chosenCallee: constProperty,
                substitutedTypeArguments: [],
                parameterMapping: [:]
            )
        )

        var emitFolded = KIRLoweringEmitContext()
        _ = fixture.driver.callLowerer.lowerSafeMemberCallExpr(
            exprFolded,
            receiverExpr: receiverNonNull,
            calleeName: callee,
            args: [],
            shared: fixture.makeShared(propertyConstantInitializers: [constProperty: .intLiteral(42)]),
            emit: &emitFolded
        )

        XCTAssertTrue(emitFolded.instructions.contains { instruction in
            guard case let .constValue(_, value) = instruction else { return false }
            if case .intLiteral(42) = value { return true }
            return false
        })
        XCTAssertFalse(emitFolded.instructions.contains { instruction in
            if case .call = instruction { return true }
            return false
        })

        let receiverNullable = appendTypedExpr(
            .nameRef(fixture.interner.intern("r2"), range),
            type: nullableIntType,
            fixture: fixture
        )
        let exprNotFolded = appendSafeMemberExpr(
            receiver: receiverNullable,
            callee: callee,
            args: [],
            type: intType,
            fixture: fixture
        )
        fixture.bindings.bindCall(
            exprNotFolded,
            binding: CallBinding(
                chosenCallee: constProperty,
                substitutedTypeArguments: [],
                parameterMapping: [:]
            )
        )

        var emitNotFolded = KIRLoweringEmitContext()
        _ = fixture.driver.callLowerer.lowerSafeMemberCallExpr(
            exprNotFolded,
            receiverExpr: receiverNullable,
            calleeName: callee,
            args: [],
            shared: fixture.makeShared(propertyConstantInitializers: [constProperty: .intLiteral(42)]),
            emit: &emitNotFolded
        )

        XCTAssertTrue(emitNotFolded.instructions.contains { instruction in
            if case .call = instruction { return true }
            return false
        })
    }

    func testDirectSafeMemberCallConstFoldWithoutBoundTypeUsesAnyFallback() {
        let fixture = makeKIRDirectLoweringFixture()
        let range = makeRange()
        let callee = fixture.interner.intern("value")
        let intType = fixture.types.make(.primitive(.int, .nonNull))

        let constProperty = defineSemanticSymbol(
            in: fixture,
            kind: .property,
            fqName: ["pkg", "Holder", "value"],
            flags: [.constValue]
        )

        let receiver = appendTypedExpr(
            .nameRef(fixture.interner.intern("r"), range),
            type: intType,
            fixture: fixture
        )
        let exprID = appendSafeMemberExprWithoutType(
            receiver: receiver,
            callee: callee,
            args: [],
            fixture: fixture
        )
        fixture.bindings.bindCall(
            exprID,
            binding: CallBinding(
                chosenCallee: constProperty,
                substitutedTypeArguments: [],
                parameterMapping: [:]
            )
        )

        var emit = KIRLoweringEmitContext()
        _ = fixture.driver.callLowerer.lowerSafeMemberCallExpr(
            exprID,
            receiverExpr: receiver,
            calleeName: callee,
            args: [],
            shared: fixture.makeShared(propertyConstantInitializers: [constProperty: .intLiteral(11)]),
            emit: &emit
        )

        XCTAssertTrue(emit.instructions.contains { instruction in
            guard case let .constValue(_, value) = instruction else { return false }
            if case .intLiteral(11) = value { return true }
            return false
        })
    }

    func testDirectSafeMemberCallInvWithoutTypeBindingsFallsBackToDynamicCall() {
        let fixture = makeKIRDirectLoweringFixture()
        let range = makeRange()
        let invName = fixture.interner.intern("inv")

        let receiver = appendTypedExpr(
            .nameRef(fixture.interner.intern("u"), range),
            type: nil,
            fixture: fixture
        )
        let exprID = appendSafeMemberExprWithoutType(
            receiver: receiver,
            callee: invName,
            args: [],
            fixture: fixture
        )

        var emit = KIRLoweringEmitContext()
        _ = fixture.driver.callLowerer.lowerSafeMemberCallExpr(
            exprID,
            receiverExpr: receiver,
            calleeName: invName,
            args: [],
            shared: fixture.makeShared(),
            emit: &emit
        )

        let callees = extractCallees(from: emit.instructions, interner: fixture.interner)
        XCTAssertFalse(callees.contains("kk_op_inv"))
        XCTAssertTrue(callees.contains("inv"))
    }

    func testDirectSafeMemberCallPrimitiveInvFastPathAndFallback() {
        let fixture = makeKIRDirectLoweringFixture()
        let range = makeRange()
        let invName = fixture.interner.intern("inv")
        let intType = fixture.types.make(.primitive(.int, .nonNull))
        let boolType = fixture.types.make(.primitive(.boolean, .nonNull))

        let receiverInt = appendTypedExpr(
            .nameRef(fixture.interner.intern("i"), range),
            type: intType,
            fixture: fixture
        )
        let exprFast = appendSafeMemberExpr(
            receiver: receiverInt,
            callee: invName,
            args: [],
            type: intType,
            fixture: fixture
        )

        var emitFast = KIRLoweringEmitContext()
        _ = fixture.driver.callLowerer.lowerSafeMemberCallExpr(
            exprFast,
            receiverExpr: receiverInt,
            calleeName: invName,
            args: [],
            shared: fixture.makeShared(),
            emit: &emitFast
        )
        XCTAssertTrue(extractCallees(from: emitFast.instructions, interner: fixture.interner).contains("kk_op_inv"))

        let receiverBool = appendTypedExpr(
            .nameRef(fixture.interner.intern("b"), range),
            type: boolType,
            fixture: fixture
        )
        let exprFallback = appendSafeMemberExpr(
            receiver: receiverBool,
            callee: invName,
            args: [],
            type: boolType,
            fixture: fixture
        )

        var emitFallback = KIRLoweringEmitContext()
        _ = fixture.driver.callLowerer.lowerSafeMemberCallExpr(
            exprFallback,
            receiverExpr: receiverBool,
            calleeName: invName,
            args: [],
            shared: fixture.makeShared(),
            emit: &emitFallback
        )
        let fallbackCallees = extractCallees(from: emitFallback.instructions, interner: fixture.interner)
        XCTAssertFalse(fallbackCallees.contains("kk_op_inv"))
        XCTAssertTrue(fallbackCallees.contains("inv"))
    }

    func testDirectSafeMemberCallUnresolvedCoroutineMemberRenames() {
        let fixture = makeKIRDirectLoweringFixture()
        let range = makeRange()
        let handleClass = defineSemanticSymbol(
            in: fixture,
            kind: .class,
            fqName: ["pkg", "CoroutineHandle"]
        )
        let handleType = fixture.types.make(
            .classType(
                ClassType(
                    classSymbol: handleClass,
                    args: [],
                    nullability: .nonNull
                )
            )
        )
        let receiver = appendTypedExpr(
            .nameRef(fixture.interner.intern("h"), range),
            type: handleType,
            fixture: fixture
        )

        let cases: [(input: String, expected: String, expectedArgCount: Int)] = [
            ("await", "kk_kxmini_async_await", 1),
            ("join", "kk_job_join", 1),
            ("cancel", "kk_job_cancel", 1),
            ("noop", "noop", 0),
        ]

        for testCase in cases {
            let callee = fixture.interner.intern(testCase.input)
            let exprID = appendSafeMemberExpr(
                receiver: receiver,
                callee: callee,
                args: [],
                type: fixture.types.anyType,
                fixture: fixture
            )
            var emit = KIRLoweringEmitContext()
            _ = fixture.driver.callLowerer.lowerSafeMemberCallExpr(
                exprID,
                receiverExpr: receiver,
                calleeName: callee,
                args: [],
                shared: fixture.makeShared(),
                emit: &emit
            )
            guard let callInstruction = emit.instructions.first(where: { instruction in
                if case .call = instruction { return true }
                return false
            }) else {
                XCTFail("Expected .call for \(testCase.input)")
                continue
            }
            guard case let .call(_, loweredCallee, arguments, _, _, _, _) = callInstruction else {
                XCTFail("Expected .call payload for \(testCase.input)")
                continue
            }
            XCTAssertEqual(fixture.interner.resolve(loweredCallee), testCase.expected)
            XCTAssertEqual(arguments.count, testCase.expectedArgCount)
        }
    }

    func testDirectSafeMemberCallChosenCalleeUsesExternalLinkAndReceiverInsertion() {
        let fixture = makeKIRDirectLoweringFixture()
        let range = makeRange()
        let intType = fixture.types.make(.primitive(.int, .nonNull))
        let owner = defineSemanticSymbol(in: fixture, kind: .class, fqName: ["pkg", "Vec"])
        let callee = defineSemanticSymbol(in: fixture, kind: .function, fqName: ["pkg", "Vec", "call"])
        let valueParam = defineSemanticSymbol(in: fixture, kind: .valueParameter, fqName: ["pkg", "Vec", "call", "x"])
        fixture.symbols.setParentSymbol(owner, for: callee)
        fixture.symbols.setExternalLinkName("kk_vec_call", for: callee)

        let receiverType = fixture.types.make(
            .classType(
                ClassType(
                    classSymbol: owner,
                    args: [],
                    nullability: .nonNull
                )
            )
        )
        fixture.symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [intType],
                returnType: intType,
                valueParameterSymbols: [valueParam],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [false]
            ),
            for: callee
        )

        let receiver = appendTypedExpr(
            .nameRef(fixture.interner.intern("vec"), range),
            type: receiverType,
            fixture: fixture
        )
        let argumentExpr = appendTypedExpr(.intLiteral(9, range), type: intType, fixture: fixture)
        let args = [CallArgument(expr: argumentExpr)]
        let safeExpr = appendSafeMemberExpr(
            receiver: receiver,
            callee: fixture.interner.intern("call"),
            args: args,
            type: intType,
            fixture: fixture
        )
        fixture.bindings.bindCall(
            safeExpr,
            binding: CallBinding(
                chosenCallee: callee,
                substitutedTypeArguments: [],
                parameterMapping: [0: 0]
            )
        )

        var emit = KIRLoweringEmitContext()
        _ = fixture.driver.callLowerer.lowerSafeMemberCallExpr(
            safeExpr,
            receiverExpr: receiver,
            calleeName: fixture.interner.intern("call"),
            args: args,
            shared: fixture.makeShared(),
            emit: &emit
        )

        guard let callInstruction = emit.instructions.first(where: { instruction in
            guard case let .call(symbol, _, _, _, _, _, _) = instruction else { return false }
            return symbol == callee
        }) else {
            XCTFail("Expected chosen callee call")
            return
        }
        guard case let .call(_, loweredCallee, arguments, _, _, _, _) = callInstruction else {
            XCTFail("Expected .call payload")
            return
        }
        XCTAssertEqual(fixture.interner.resolve(loweredCallee), "kk_vec_call")
        XCTAssertEqual(arguments.count, 2)
    }

    func testDirectSafeMemberCallDefaultMaskPathUsesDefaultStub() {
        let fixture = makeKIRDirectLoweringFixture()
        let range = makeRange()
        let intType = fixture.types.make(.primitive(.int, .nonNull))

        let chosen = defineSemanticSymbol(
            in: fixture,
            kind: .function,
            fqName: ["pkg", "withDefault"]
        )
        let valueParam = defineSemanticSymbol(
            in: fixture,
            kind: .valueParameter,
            fqName: ["pkg", "withDefault", "x"]
        )
        let typeParam = defineSemanticSymbol(
            in: fixture,
            kind: .typeParameter,
            fqName: ["pkg", "withDefault", "T"]
        )
        fixture.symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [intType],
                returnType: intType,
                valueParameterSymbols: [valueParam],
                valueParameterHasDefaultValues: [true],
                valueParameterIsVararg: [false],
                typeParameterSymbols: [typeParam],
                reifiedTypeParameterIndices: [0]
            ),
            for: chosen
        )

        let receiver = appendTypedExpr(
            .nameRef(fixture.interner.intern("obj"), range),
            type: fixture.types.anyType,
            fixture: fixture
        )
        let exprID = appendSafeMemberExpr(
            receiver: receiver,
            callee: fixture.interner.intern("withDefault"),
            args: [],
            type: intType,
            fixture: fixture
        )
        fixture.bindings.bindCall(
            exprID,
            binding: CallBinding(
                chosenCallee: chosen,
                substitutedTypeArguments: [intType],
                parameterMapping: [:]
            )
        )

        var emit = KIRLoweringEmitContext()
        _ = fixture.driver.callLowerer.lowerSafeMemberCallExpr(
            exprID,
            receiverExpr: receiver,
            calleeName: fixture.interner.intern("withDefault"),
            args: [],
            shared: fixture.makeShared(),
            emit: &emit
        )

        let expectedStub = fixture.driver.callSupportLowerer.defaultStubSymbol(for: chosen)
        guard let stubCall = emit.instructions.first(where: { instruction in
            guard case let .call(symbol, _, _, _, _, _, _) = instruction else { return false }
            return symbol == expectedStub
        }) else {
            XCTFail("Expected default stub call")
            return
        }
        guard case let .call(_, callee, arguments, _, _, _, _) = stubCall else {
            XCTFail("Expected .call payload")
            return
        }
        XCTAssertEqual(fixture.interner.resolve(callee), "withDefault$default")
        XCTAssertGreaterThanOrEqual(arguments.count, 2)
    }

    func testDirectSafeMemberCallVirtualDispatchUsesVirtualCallAndDropsReceiverFromArgs() {
        let fixture = makeKIRDirectLoweringFixture()
        let range = makeRange()
        let intType = fixture.types.make(.primitive(.int, .nonNull))

        let owner = defineSemanticSymbol(in: fixture, kind: .class, fqName: ["pkg", "Animal"])
        let child = defineSemanticSymbol(in: fixture, kind: .class, fqName: ["pkg", "Dog"])
        let method = defineSemanticSymbol(in: fixture, kind: .function, fqName: ["pkg", "Animal", "speak"])
        let valueParam = defineSemanticSymbol(in: fixture, kind: .valueParameter, fqName: ["pkg", "Animal", "speak", "times"])
        fixture.symbols.setParentSymbol(owner, for: method)
        fixture.symbols.setDirectSupertypes([owner], for: child)

        let ownerType = fixture.types.make(
            .classType(
                ClassType(
                    classSymbol: owner,
                    args: [],
                    nullability: .nonNull
                )
            )
        )
        fixture.symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: ownerType,
                parameterTypes: [intType],
                returnType: intType,
                valueParameterSymbols: [valueParam],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [false]
            ),
            for: method
        )
        fixture.symbols.setNominalLayout(
            NominalLayout(
                objectHeaderWords: 1,
                instanceFieldCount: 0,
                instanceSizeWords: 1,
                vtableSlots: [method: 3],
                itableSlots: [:],
                superClass: nil
            ),
            for: owner
        )

        let receiver = appendTypedExpr(
            .nameRef(fixture.interner.intern("a"), range),
            type: ownerType,
            fixture: fixture
        )
        let valueExpr = appendTypedExpr(.intLiteral(2, range), type: intType, fixture: fixture)
        let args = [CallArgument(expr: valueExpr)]
        let exprID = appendSafeMemberExpr(
            receiver: receiver,
            callee: fixture.interner.intern("speak"),
            args: args,
            type: intType,
            fixture: fixture
        )
        fixture.bindings.bindCall(
            exprID,
            binding: CallBinding(
                chosenCallee: method,
                substitutedTypeArguments: [],
                parameterMapping: [0: 0]
            )
        )

        var emit = KIRLoweringEmitContext()
        _ = fixture.driver.callLowerer.lowerSafeMemberCallExpr(
            exprID,
            receiverExpr: receiver,
            calleeName: fixture.interner.intern("speak"),
            args: args,
            shared: fixture.makeShared(),
            emit: &emit
        )

        guard let virtualInstruction = emit.instructions.first(where: { instruction in
            if case .virtualCall = instruction { return true }
            return false
        }) else {
            XCTFail("Expected virtualCall instruction")
            return
        }
        guard case let .virtualCall(_, _, _, arguments, _, _, _, dispatch) = virtualInstruction else {
            XCTFail("Expected virtualCall payload")
            return
        }
        XCTAssertEqual(arguments.count, 1)
        XCTAssertEqual(dispatch, .vtable(slot: 3))
    }

    func testDirectSafeMemberCallSuperCallSkipsVirtualDispatch() {
        let fixture = makeKIRDirectLoweringFixture()
        let range = makeRange()
        let intType = fixture.types.make(.primitive(.int, .nonNull))

        let owner = defineSemanticSymbol(in: fixture, kind: .class, fqName: ["pkg", "Base"])
        let child = defineSemanticSymbol(in: fixture, kind: .class, fqName: ["pkg", "Derived"])
        let method = defineSemanticSymbol(in: fixture, kind: .function, fqName: ["pkg", "Base", "act"])
        let valueParam = defineSemanticSymbol(in: fixture, kind: .valueParameter, fqName: ["pkg", "Base", "act", "x"])
        fixture.symbols.setParentSymbol(owner, for: method)
        fixture.symbols.setDirectSupertypes([owner], for: child)

        let ownerType = fixture.types.make(
            .classType(
                ClassType(
                    classSymbol: owner,
                    args: [],
                    nullability: .nonNull
                )
            )
        )
        fixture.symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: ownerType,
                parameterTypes: [intType],
                returnType: intType,
                valueParameterSymbols: [valueParam],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [false]
            ),
            for: method
        )
        fixture.symbols.setNominalLayout(
            NominalLayout(
                objectHeaderWords: 1,
                instanceFieldCount: 0,
                instanceSizeWords: 1,
                vtableSlots: [method: 1],
                itableSlots: [:],
                superClass: nil
            ),
            for: owner
        )

        let receiver = appendTypedExpr(
            .nameRef(fixture.interner.intern("base"), range),
            type: ownerType,
            fixture: fixture
        )
        let valueExpr = appendTypedExpr(.intLiteral(1, range), type: intType, fixture: fixture)
        let args = [CallArgument(expr: valueExpr)]
        let exprID = appendSafeMemberExpr(
            receiver: receiver,
            callee: fixture.interner.intern("act"),
            args: args,
            type: intType,
            fixture: fixture
        )
        fixture.bindings.bindCall(
            exprID,
            binding: CallBinding(
                chosenCallee: method,
                substitutedTypeArguments: [],
                parameterMapping: [0: 0]
            )
        )
        fixture.bindings.markSuperCall(exprID)

        var emit = KIRLoweringEmitContext()
        _ = fixture.driver.callLowerer.lowerSafeMemberCallExpr(
            exprID,
            receiverExpr: receiver,
            calleeName: fixture.interner.intern("act"),
            args: args,
            shared: fixture.makeShared(),
            emit: &emit
        )

        let hasVirtualCall = emit.instructions.contains { instruction in
            if case .virtualCall = instruction { return true }
            return false
        }
        XCTAssertFalse(hasVirtualCall)
        XCTAssertTrue(emit.instructions.contains { instruction in
            guard case let .call(_, _, _, _, _, _, isSuperCall) = instruction else { return false }
            return isSuperCall
        })
    }

    func testResolveVirtualDispatchGuardFailuresReturnNil() {
        let fixture = makeKIRDirectLoweringFixture()
        XCTAssertNil(
            fixture.driver.callLowerer.resolveVirtualDispatch(
                callee: .invalid,
                receiverTypeID: nil,
                sema: fixture.sema
            )
        )

        let method = defineSemanticSymbol(in: fixture, kind: .function, fqName: ["pkg", "free"])
        XCTAssertNil(
            fixture.driver.callLowerer.resolveVirtualDispatch(
                callee: method,
                receiverTypeID: nil,
                sema: fixture.sema
            )
        )

        let parent = defineSemanticSymbol(in: fixture, kind: .class, fqName: ["pkg", "Owner"])
        fixture.symbols.setParentSymbol(parent, for: method)
        XCTAssertNil(
            fixture.driver.callLowerer.resolveVirtualDispatch(
                callee: method,
                receiverTypeID: nil,
                sema: fixture.sema
            )
        )
    }

    func testResolveVirtualDispatchInterfaceBranchCases() {
        let fixture = makeKIRDirectLoweringFixture()
        let iface = defineSemanticSymbol(in: fixture, kind: .interface, fqName: ["pkg", "IWorker"])
        let method = defineSemanticSymbol(in: fixture, kind: .function, fqName: ["pkg", "IWorker", "work"])
        fixture.symbols.setParentSymbol(iface, for: method)
        fixture.symbols.setNominalLayout(
            NominalLayout(
                objectHeaderWords: 1,
                instanceFieldCount: 0,
                instanceSizeWords: 1,
                vtableSlots: [method: 4],
                itableSlots: [:],
                superClass: nil
            ),
            for: iface
        )

        let receiverClass = defineSemanticSymbol(in: fixture, kind: .class, fqName: ["pkg", "WorkerImpl"])
        let receiverType = fixture.types.make(
            .classType(
                ClassType(classSymbol: receiverClass, args: [], nullability: .nonNull)
            )
        )

        XCTAssertNil(
            fixture.driver.callLowerer.resolveVirtualDispatch(
                callee: method,
                receiverTypeID: nil,
                sema: fixture.sema
            )
        )
        XCTAssertNil(
            fixture.driver.callLowerer.resolveVirtualDispatch(
                callee: method,
                receiverTypeID: receiverType,
                sema: fixture.sema
            )
        )

        let receiverChild = defineSemanticSymbol(in: fixture, kind: .class, fqName: ["pkg", "WorkerSub"])
        fixture.symbols.setDirectSupertypes([receiverClass], for: receiverChild)
        XCTAssertNil(
            fixture.driver.callLowerer.resolveVirtualDispatch(
                callee: method,
                receiverTypeID: receiverType,
                sema: fixture.sema
            )
        )

        fixture.symbols.setNominalLayout(
            NominalLayout(
                objectHeaderWords: 1,
                instanceFieldCount: 0,
                instanceSizeWords: 1,
                vtableSlots: [:],
                itableSlots: [iface: 2],
                superClass: nil
            ),
            for: receiverClass
        )
        fixture.symbols.setNominalLayout(
            NominalLayout(
                objectHeaderWords: 1,
                instanceFieldCount: 0,
                instanceSizeWords: 1,
                vtableSlots: [:],
                itableSlots: [:],
                superClass: nil
            ),
            for: iface
        )
        XCTAssertNil(
            fixture.driver.callLowerer.resolveVirtualDispatch(
                callee: method,
                receiverTypeID: receiverType,
                sema: fixture.sema
            )
        )

        fixture.symbols.setNominalLayout(
            NominalLayout(
                objectHeaderWords: 1,
                instanceFieldCount: 0,
                instanceSizeWords: 1,
                vtableSlots: [method: 4],
                itableSlots: [:],
                superClass: nil
            ),
            for: iface
        )
        let dispatch = fixture.driver.callLowerer.resolveVirtualDispatch(
            callee: method,
            receiverTypeID: receiverType,
            sema: fixture.sema
        )
        XCTAssertEqual(dispatch, .itable(interfaceSlot: 2, methodSlot: 4))
    }

    func testResolveVirtualDispatchInterfaceFallsBackToZeroInterfaceSlot() {
        let fixture = makeKIRDirectLoweringFixture()
        let iface = defineSemanticSymbol(in: fixture, kind: .interface, fqName: ["pkg", "IWorker"])
        let method = defineSemanticSymbol(in: fixture, kind: .function, fqName: ["pkg", "IWorker", "work"])
        fixture.symbols.setParentSymbol(iface, for: method)
        fixture.symbols.setNominalLayout(
            NominalLayout(
                objectHeaderWords: 1,
                instanceFieldCount: 0,
                instanceSizeWords: 1,
                vtableSlots: [method: 5],
                itableSlots: [:],
                superClass: nil
            ),
            for: iface
        )

        let receiverClass = defineSemanticSymbol(in: fixture, kind: .class, fqName: ["pkg", "WorkerImpl"])
        let receiverSubClass = defineSemanticSymbol(in: fixture, kind: .class, fqName: ["pkg", "WorkerSub"])
        fixture.symbols.setDirectSupertypes([receiverClass], for: receiverSubClass)
        fixture.symbols.setNominalLayout(
            NominalLayout(
                objectHeaderWords: 1,
                instanceFieldCount: 0,
                instanceSizeWords: 1,
                vtableSlots: [:],
                itableSlots: [:],
                superClass: nil
            ),
            for: receiverClass
        )

        let receiverType = fixture.types.make(
            .classType(
                ClassType(classSymbol: receiverClass, args: [], nullability: .nonNull)
            )
        )
        let dispatch = fixture.driver.callLowerer.resolveVirtualDispatch(
            callee: method,
            receiverTypeID: receiverType,
            sema: fixture.sema
        )
        XCTAssertEqual(dispatch, .itable(interfaceSlot: 0, methodSlot: 5))
    }

    func testResolveVirtualDispatchClassAndOtherParentCases() {
        let fixture = makeKIRDirectLoweringFixture()
        let owner = defineSemanticSymbol(in: fixture, kind: .class, fqName: ["pkg", "Animal"])
        let method = defineSemanticSymbol(in: fixture, kind: .function, fqName: ["pkg", "Animal", "speak"])
        fixture.symbols.setParentSymbol(owner, for: method)
        fixture.symbols.setNominalLayout(
            NominalLayout(
                objectHeaderWords: 1,
                instanceFieldCount: 0,
                instanceSizeWords: 1,
                vtableSlots: [method: 1],
                itableSlots: [:],
                superClass: nil
            ),
            for: owner
        )

        XCTAssertNil(
            fixture.driver.callLowerer.resolveVirtualDispatch(
                callee: method,
                receiverTypeID: nil,
                sema: fixture.sema
            )
        )

        let child = defineSemanticSymbol(in: fixture, kind: .class, fqName: ["pkg", "Dog"])
        fixture.symbols.setDirectSupertypes([owner], for: child)
        fixture.symbols.setNominalLayout(
            NominalLayout(
                objectHeaderWords: 1,
                instanceFieldCount: 0,
                instanceSizeWords: 1,
                vtableSlots: [:],
                itableSlots: [:],
                superClass: nil
            ),
            for: owner
        )
        XCTAssertNil(
            fixture.driver.callLowerer.resolveVirtualDispatch(
                callee: method,
                receiverTypeID: nil,
                sema: fixture.sema
            )
        )

        fixture.symbols.setNominalLayout(
            NominalLayout(
                objectHeaderWords: 1,
                instanceFieldCount: 0,
                instanceSizeWords: 1,
                vtableSlots: [method: 1],
                itableSlots: [:],
                superClass: nil
            ),
            for: owner
        )
        XCTAssertEqual(
            fixture.driver.callLowerer.resolveVirtualDispatch(
                callee: method,
                receiverTypeID: nil,
                sema: fixture.sema
            ),
            .vtable(slot: 1)
        )

        let objectOwner = defineSemanticSymbol(in: fixture, kind: .object, fqName: ["pkg", "Singleton"])
        let objectMethod = defineSemanticSymbol(in: fixture, kind: .function, fqName: ["pkg", "Singleton", "run"])
        fixture.symbols.setParentSymbol(objectOwner, for: objectMethod)
        fixture.symbols.setNominalLayout(
            NominalLayout(
                objectHeaderWords: 1,
                instanceFieldCount: 0,
                instanceSizeWords: 1,
                vtableSlots: [objectMethod: 0],
                itableSlots: [:],
                superClass: nil
            ),
            for: objectOwner
        )
        XCTAssertNil(
            fixture.driver.callLowerer.resolveVirtualDispatch(
                callee: objectMethod,
                receiverTypeID: nil,
                sema: fixture.sema
            )
        )
    }
    // swiftlint:disable:next file_length
}
