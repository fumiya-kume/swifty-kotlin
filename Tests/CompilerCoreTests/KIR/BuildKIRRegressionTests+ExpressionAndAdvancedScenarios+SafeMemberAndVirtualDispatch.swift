#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension BuildKIRRegressionTests {
    // BUG-211: an interface property read must remain an itable dispatch in
    // KIR. The backend then boxes the receiver before doing the dynamic lookup.
    @Test func testBug211CharSequenceLengthUsesDynamicItableDispatch() throws {
        let source = """
        fun lengthOf(value: CharSequence): Int = value.length
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "lengthOf", in: module, interner: ctx.interner)
            let dispatches = body.compactMap { instruction -> KIRDispatchKind? in
                guard case let .virtualCall(_, _, _, _, _, _, _, dispatch) = instruction else {
                    return nil
                }
                return dispatch
            }

            let sema = try #require(ctx.sema)
            let charSequenceFQName = ["kotlin", "CharSequence"].map { ctx.interner.intern($0) }
            let charSequence = try #require(sema.symbols.lookup(fqName: charSequenceFQName))
            let length = try #require(
                sema.symbols.lookup(fqName: charSequenceFQName + [ctx.interner.intern("length")])
            )
            let expectedLengthSlot = try #require(
                kirInterfacePropertyGetterSlot(
                    interfaceProperty: length,
                    interfaceSymbol: charSequence,
                    sema: sema,
                    interner: ctx.interner
                )
            )

            #expect(dispatches.contains { dispatch in
                if case .itableDynamic(_, expectedLengthSlot) = dispatch { return true }
                return false
            })
        }
    }

    // KSP-817: an interface operator member must remain a dynamic itable call.
    @Test func testKsp817CharSequenceGetUsesDynamicItableDispatch() throws {
        let source = """
        fun getAt(value: CharSequence): Char = value[0]
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "getAt", in: module, interner: ctx.interner)
            let dispatches = body.compactMap { instruction -> KIRDispatchKind? in
                guard case let .virtualCall(_, _, _, _, _, _, _, dispatch) = instruction else {
                    return nil
                }
                return dispatch
            }

            #expect(dispatches.contains { dispatch in
                if case .itableDynamic(_, 0) = dispatch { return true }
                return false
            })
        }
    }

    // KSP-1390: CharSequence.subSequence must use the adjacent dynamic method slot.
    @Test func testKsp1390CharSequenceSubSequenceUsesDynamicItableDispatch() throws {
        let source = """
        fun subSequenceOf(value: CharSequence): CharSequence = value.subSequence(0, 1)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "subSequenceOf", in: module, interner: ctx.interner)
            let dispatches = body.compactMap { instruction -> KIRDispatchKind? in
                guard case let .virtualCall(_, _, _, _, _, _, _, dispatch) = instruction else {
                    return nil
                }
                return dispatch
            }

            #expect(dispatches.contains { dispatch in
                if case .itableDynamic(_, 1) = dispatch { return true }
                return false
            })
        }
    }

    @Test func testDirectSafeMemberCallConstFoldNonNullAndNullablePaths() {
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

        #expect(emitFolded.instructions.contains { instruction in
            guard case let .constValue(_, value) = instruction else { return false }
            if case .intLiteral(42) = value { return true }
            return false
        })
        #expect(!(emitFolded.instructions.contains { instruction in
            if case .call = instruction { return true }
            return false
        }))

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

        #expect(emitNotFolded.instructions.contains { instruction in
            if case .call = instruction { return true }
            return false
        })
    }

    @Test func testDirectSafeMemberCallConstFoldWithoutBoundTypeUsesAnyFallback() {
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

        #expect(emit.instructions.contains { instruction in
            guard case let .constValue(_, value) = instruction else { return false }
            if case .intLiteral(11) = value { return true }
            return false
        })
    }

    @Test func testDirectSafeMemberCallInvWithoutTypeBindingsFallsBackToDynamicCall() {
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
        #expect(!(callees.contains("kk_op_inv")))
        #expect(callees.contains("inv"))
    }

    @Test func testDirectSafeMemberCallPrimitiveInvFastPathAndFallback() {
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
        #expect(extractCallees(from: emitFast.instructions, interner: fixture.interner).contains("kk_op_inv"))

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
        #expect(!(fallbackCallees.contains("kk_op_inv")))
        #expect(fallbackCallees.contains("inv"))
    }

    @Test func testDirectSafeMemberCallUnresolvedCoroutineMemberRenames() {
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
                Issue.record("Expected .call for \(testCase.input)")
                continue
            }
            guard case let .call(_, loweredCallee, arguments, _, _, _, _, _) = callInstruction else {
                Issue.record("Expected .call payload for \(testCase.input)")
                continue
            }
            #expect(fixture.interner.resolve(loweredCallee) == testCase.expected)
            #expect(arguments.count == testCase.expectedArgCount)
        }
    }

    @Test func testDirectSafeMemberCallChosenCalleeUsesExternalLinkAndReceiverInsertion() {
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
            guard case let .call(symbol, _, _, _, _, _, _, _) = instruction else { return false }
            return symbol == callee
        }) else {
            Issue.record("Expected chosen callee call")
            return
        }
        guard case let .call(_, loweredCallee, arguments, _, _, _, _, _) = callInstruction else {
            Issue.record("Expected .call payload")
            return
        }
        #expect(fixture.interner.resolve(loweredCallee) == "kk_vec_call")
        #expect(arguments.count == 2)
    }

    @Test func testDirectSafeMemberCallDefaultMaskPathUsesDefaultStub() {
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
            guard case let .call(symbol, _, _, _, _, _, _, _) = instruction else { return false }
            return symbol == expectedStub
        }) else {
            Issue.record("Expected default stub call")
            return
        }
        guard case let .call(_, callee, arguments, _, _, _, _, _) = stubCall else {
            Issue.record("Expected .call payload")
            return
        }
        #expect(fixture.interner.resolve(callee) == "withDefault$default")
        #expect(arguments.count >= 2)
    }

    @Test func testDirectSafeMemberCallVirtualDispatchUsesVirtualCallAndDropsReceiverFromArgs() {
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

        let hasVirtualCall = emit.instructions.contains { instruction in
            if case .virtualCall = instruction { return true }
            return false
        }
        #expect(hasVirtualCall, "Open class safe calls should emit vtable virtualCall.")
        guard let virtualInstruction = emit.instructions.first(where: { instruction in
            if case .virtualCall = instruction { return true }
            return false
        }) else {
            Issue.record("Expected virtualCall instruction")
            return
        }
        guard case let .virtualCall(_, _, virtualReceiver, arguments, _, _, _, dispatch) = virtualInstruction else {
            Issue.record("Expected virtualCall instruction payload")
            return
        }
        #expect(arguments.count == 1, "virtualCall should keep the receiver separate from value arguments.")
        #expect(!arguments.contains(virtualReceiver))
        #expect(dispatch == .vtable(slot: 3))
    }

    @Test func testDirectSafeMemberCallSuperCallSkipsVirtualDispatch() {
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
        #expect(!(hasVirtualCall))
        #expect(emit.instructions.contains { instruction in
            guard case let .call(_, _, _, _, _, _, isSuperCall, _) = instruction else { return false }
            return isSuperCall
        })
    }

    @Test func testResolveVirtualDispatchGuardFailuresReturnNil() {
        let fixture = makeKIRDirectLoweringFixture()
        #expect(
            fixture.driver.callLowerer.resolveVirtualDispatch(
                callee: .invalid,
                receiverTypeID: nil,
                sema: fixture.sema, interner: fixture.interner
            ) == nil
        )

        let method = defineSemanticSymbol(in: fixture, kind: .function, fqName: ["pkg", "free"])
        #expect(
            fixture.driver.callLowerer.resolveVirtualDispatch(
                callee: method,
                receiverTypeID: nil,
                sema: fixture.sema, interner: fixture.interner
            ) == nil
        )

        let parent = defineSemanticSymbol(in: fixture, kind: .class, fqName: ["pkg", "Owner"])
        fixture.symbols.setParentSymbol(parent, for: method)
        #expect(
            fixture.driver.callLowerer.resolveVirtualDispatch(
                callee: method,
                receiverTypeID: nil,
                sema: fixture.sema, interner: fixture.interner
            ) == nil
        )
    }

    @Test func testResolveVirtualDispatchInterfaceBranchCases() {
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

        #expect(
            fixture.driver.callLowerer.resolveVirtualDispatch(
                callee: method,
                receiverTypeID: nil,
                sema: fixture.sema, interner: fixture.interner
            ) == nil
        )
        #expect(
            fixture.driver.callLowerer.resolveVirtualDispatch(
                callee: method,
                receiverTypeID: receiverType,
                sema: fixture.sema, interner: fixture.interner
            ) == nil
        )

        let receiverChild = defineSemanticSymbol(in: fixture, kind: .class, fqName: ["pkg", "WorkerSub"])
        fixture.symbols.setDirectSupertypes([receiverClass], for: receiverChild)
        #expect(
            fixture.driver.callLowerer.resolveVirtualDispatch(
                callee: method,
                receiverTypeID: receiverType,
                sema: fixture.sema, interner: fixture.interner
            ) == nil
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
        #expect(
            fixture.driver.callLowerer.resolveVirtualDispatch(
                callee: method,
                receiverTypeID: receiverType,
                sema: fixture.sema, interner: fixture.interner
            ) == nil
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
            sema: fixture.sema, interner: fixture.interner
        )
        #expect(dispatch == .itable(interfaceSlot: 2, methodSlot: 4))
    }

    @Test func testResolveVirtualDispatchInterfaceFallsBackToZeroInterfaceSlot() {
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
            sema: fixture.sema, interner: fixture.interner
        )
        #expect(dispatch == .itable(interfaceSlot: 0, methodSlot: 5))
    }

    @Test func testResolveVirtualDispatchClassAndOtherParentCases() {
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

        #expect(
            fixture.driver.callLowerer.resolveVirtualDispatch(
                callee: method,
                receiverTypeID: nil,
                sema: fixture.sema, interner: fixture.interner
            ) == nil
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
        #expect(
            fixture.driver.callLowerer.resolveVirtualDispatch(
                callee: method,
                receiverTypeID: nil,
                sema: fixture.sema, interner: fixture.interner
            ) == nil
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
        #expect(
            fixture.driver.callLowerer.resolveVirtualDispatch(
                callee: method,
                receiverTypeID: nil,
                sema: fixture.sema, interner: fixture.interner
            ) == .vtable(slot: 1)
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
        #expect(
            fixture.driver.callLowerer.resolveVirtualDispatch(
                callee: objectMethod,
                receiverTypeID: nil,
                sema: fixture.sema, interner: fixture.interner
            ) == nil
        )
    }
}
#endif
