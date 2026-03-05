@testable import CompilerCore
import Foundation
import XCTest

extension BuildKIRRegressionTests {
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
}
