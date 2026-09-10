#if canImport(Testing)
@testable import CompilerCore
import Testing

extension LoweringPassRegressionTests {
    @Test
    func testInlineLoweringPreservesResolvedNonInlineOverload() throws {
        let source = """
        inline fun choose(value: Int): Int = value + 1
        fun choose(value: Long): Long = value + 2L
        fun caller() {
            choose(1)
            choose(2L)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let context = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runToKIR(context)
            #expect(!context.diagnostics.hasError)
            let module = try #require(context.kir)
            let before = try findKIRFunction(named: "caller", in: module, interner: context.interner)
            let calls = before.body.compactMap { instruction -> SymbolID? in
                guard case let .call(symbol, callee, _, _, _, _, _, _) = instruction,
                      callee == context.interner.intern("choose") else { return nil }
                return symbol
            }
            #expect(calls.count == 2)
            let sema = try #require(context.sema)
            let regularSymbol = try #require(calls.first {
                sema.symbols.symbol($0)?.flags.contains(.inlineFunction) == false
            })
            let inlineSymbol = try #require(calls.first {
                sema.symbols.symbol($0)?.flags.contains(.inlineFunction) == true
            })

            try InlineLoweringPass().run(module: module, ctx: KIRContext(
                diagnostics: context.diagnostics, options: context.options,
                interner: context.interner, sema: sema
            ))

            let after = try findKIRFunction(named: "caller", in: module, interner: context.interner)
            let survivingSymbols = after.body.compactMap { instruction -> SymbolID? in
                guard case let .call(symbol, _, _, _, _, _, _, _) = instruction else { return nil }
                return symbol
            }
            #expect(survivingSymbols.contains(regularSymbol))
            #expect(!survivingSymbols.contains(inlineSymbol))
        }
    }

    @Test(arguments: [false, true])
    func testInlineExpansionPreservesVirtualAndQualifiedSuperMetadata(throughLambda: Bool) throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let parameter = SymbolID(rawValue: 1)
        let inlineSymbol = SymbolID(rawValue: 2)
        let targetSymbol = SymbolID(rawValue: 3)
        let qualifier = SymbolID(rawValue: 4)
        let paramExpr = arena.appendExpr(.symbolRef(parameter), type: types.anyType)
        let localResult = arena.appendTemporary(type: types.intType)
        let virtualResult = arena.appendTemporary(type: types.intType)
        let localThrown = arena.appendTemporary(type: types.nullableAnyType)
        let inlineFunction = KIRFunction(
            symbol: inlineSymbol, name: interner.intern("forward"),
            params: [KIRParameter(symbol: parameter, type: types.anyType)],
            returnType: types.intType,
            body: [
                .constValue(result: paramExpr, value: .symbolRef(parameter)),
                .call(
                    symbol: targetSymbol, callee: interner.intern("baseValue"),
                    arguments: [paramExpr], result: localResult, canThrow: true,
                    thrownResult: localThrown, isSuperCall: true, qualifiedSuperType: qualifier
                ),
                .virtualCall(
                    symbol: targetSymbol, callee: interner.intern("virtualValue"),
                    receiver: paramExpr, arguments: [localResult], result: virtualResult,
                    canThrow: true, thrownResult: localThrown,
                    dispatch: .itableDynamic(interfaceTypeID: 77, methodSlot: 2)
                ),
                .returnValue(virtualResult),
            ], isSuspend: false, isInline: !throughLambda
        )
        let argument = arena.appendTemporary(type: types.anyType)
        let result = arena.appendTemporary(type: types.intType)
        var target = inlineFunction
        var arguments = [argument]
        if throughLambda {
            let valueParameter = SymbolID(rawValue: 6)
            let blockParameter = SymbolID(rawValue: 7)
            let valueExpr = arena.appendExpr(.symbolRef(valueParameter), type: types.anyType)
            let blockExpr = arena.appendExpr(.symbolRef(blockParameter), type: types.anyType)
            let blockResult = arena.appendTemporary(type: types.intType)
            target = KIRFunction(
                symbol: SymbolID(rawValue: 8), name: interner.intern("applyBlock"),
                params: [
                    KIRParameter(symbol: valueParameter, type: types.anyType),
                    KIRParameter(symbol: blockParameter, type: types.anyType),
                ],
                returnType: types.intType,
                body: [
                    .constValue(result: valueExpr, value: .symbolRef(valueParameter)),
                    .constValue(result: blockExpr, value: .symbolRef(blockParameter)),
                    .call(
                        symbol: nil, callee: interner.intern("kk_function_invoke"),
                        arguments: [blockExpr, valueExpr], result: blockResult,
                        canThrow: true, thrownResult: nil
                    ),
                    .returnValue(blockResult),
                ], isSuspend: false, isInline: true
            )
            let lambdaRef = arena.appendExpr(.symbolRef(inlineSymbol), type: types.anyType)
            arguments.append(lambdaRef)
            _ = arena.appendDecl(.function(target))
        }
        let caller = KIRFunction(
            symbol: SymbolID(rawValue: 5), name: interner.intern("caller"), params: [],
            returnType: types.intType,
            body: [
                .call(
                    symbol: target.symbol, callee: target.name, arguments: arguments,
                    result: result, canThrow: true, thrownResult: nil
                ),
                .returnValue(result),
            ], isSuspend: false, isInline: false
        )
        let callerID = arena.appendDecl(.function(caller))
        _ = arena.appendDecl(.function(inlineFunction))
        let module = KIRModule(files: [], arena: arena)
        let context = makeCompilationContext(inputs: [], includeStdlib: false)

        try InlineLoweringPass().run(module: module, ctx: KIRContext(
            diagnostics: context.diagnostics, options: context.options, interner: interner
        ))

        guard case let .function(lowered) = arena.decl(callerID) else {
            Issue.record("Missing expanded caller")
            return
        }
        let superCall = try #require(lowered.body.first {
            guard case let .call(_, _, _, _, _, _, isSuperCall, _) = $0 else { return false }
            return isSuperCall
        })
        guard case let .call(symbol, callee, arguments, returned, canThrow, thrown, isSuper, superType) = superCall else {
            Issue.record("Missing expanded super call")
            return
        }
        #expect(symbol == targetSymbol && callee == interner.intern("baseValue"))
        #expect(arguments == [argument])
        #expect(isSuper)
        #expect(superType == qualifier)
        #expect(canThrow && thrown != nil && thrown != localThrown)
        #expect(returned != localResult && returned.flatMap(arena.exprType) == types.intType)

        let virtualCall = try #require(lowered.body.first { if case .virtualCall = $0 { true } else { false } })
        guard case let .virtualCall(virtualSymbol, virtualName, receiver, virtualArgs, _, virtualCanThrow, virtualThrown, dispatch) = virtualCall else {
            Issue.record("Missing expanded virtual call")
            return
        }
        #expect(virtualSymbol == targetSymbol && virtualName == interner.intern("virtualValue"))
        let expandedResult = try #require(returned)
        #expect(receiver == argument && virtualArgs == [expandedResult])
        #expect(virtualCanThrow && virtualThrown == thrown)
        #expect(dispatch == .itableDynamic(interfaceTypeID: 77, methodSlot: 2))
    }

    @Test
    func testSourceInlinePreservesQualifiedSuperTarget() throws {
        let source = """
        interface Left { fun value(): String = "left" }
        interface Right { fun value(): String = "right" }
        class Both : Left, Right {
            private inline fun inlineLeft(): String = super<Left>.value()
            override fun value(): String = super<Right>.value()
            fun throughInline(): String = inlineLeft()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let context = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runToKIR(context)
            #expect(!context.diagnostics.hasError)
            let module = try #require(context.kir)
            let sema = try #require(context.sema)
            let left = try #require(sema.symbols.lookup(fqName: [context.interner.intern("Left")]))
            let before = try findKIRFunction(named: "inlineLeft", in: module, interner: context.interner)
            #expect(before.body.contains {
                guard case let .call(_, _, _, _, _, _, isSuper, superType) = $0 else { return false }
                return isSuper && superType == left
            })

            try InlineLoweringPass().run(module: module, ctx: KIRContext(
                diagnostics: context.diagnostics, options: context.options,
                interner: context.interner, sema: sema
            ))

            let expanded = try findKIRFunction(named: "throughInline", in: module, interner: context.interner)
            #expect(expanded.body.contains {
                guard case let .call(_, _, _, _, _, _, isSuper, superType) = $0 else { return false }
                return isSuper && superType == left
            })
        }
    }

    @Test
    func testNestedInlineLabelRelocationIsDeterministicAndCollisionFree() throws {
        func expand() throws -> [KIRInstruction] {
            let interner = StringInterner()
            let arena = KIRArena()
            let types = TypeSystem()
            let leafSymbol = SymbolID(rawValue: 1)
            let middleSymbol = SymbolID(rawValue: 2)
            let value = arena.appendExpr(.intLiteral(42), type: types.intType)
            let leaf = KIRFunction(
                symbol: leafSymbol, name: interner.intern("leaf"), params: [],
                returnType: types.intType,
                body: [.label(10), .constValue(result: value, value: .intLiteral(42)), .jump(20), .label(20), .returnValue(value)],
                isSuspend: false, isInline: true
            )
            let middleResult = arena.appendTemporary(type: types.intType)
            let middle = KIRFunction(
                symbol: middleSymbol, name: interner.intern("middle"), params: [],
                returnType: types.intType,
                body: [
                    .label(10),
                    .call(symbol: leafSymbol, callee: leaf.name, arguments: [], result: middleResult, canThrow: false, thrownResult: nil),
                    .returnValue(middleResult),
                ], isSuspend: false, isInline: true
            )
            let firstResult = arena.appendTemporary(type: types.intType)
            let secondResult = arena.appendTemporary(type: types.intType)
            let caller = KIRFunction(
                symbol: SymbolID(rawValue: 3), name: interner.intern("caller"), params: [],
                returnType: types.intType,
                body: [
                    .label(10),
                    .call(symbol: middleSymbol, callee: middle.name, arguments: [], result: firstResult, canThrow: false, thrownResult: nil),
                    .call(symbol: middleSymbol, callee: middle.name, arguments: [], result: secondResult, canThrow: false, thrownResult: nil),
                    .returnValue(secondResult),
                ], isSuspend: false, isInline: false
            )
            let callerID = arena.appendDecl(.function(caller))
            _ = arena.appendDecl(.function(middle))
            _ = arena.appendDecl(.function(leaf))
            let module = KIRModule(files: [], arena: arena)
            let context = makeCompilationContext(inputs: [], includeStdlib: false)
            try InlineLoweringPass().run(module: module, ctx: KIRContext(
                diagnostics: context.diagnostics, options: context.options, interner: interner
            ))
            guard case let .function(lowered) = arena.decl(callerID) else {
                Issue.record("Missing expanded caller")
                return []
            }
            #expect(!lowered.body.contains { if case .call = $0 { true } else { false } })
            let labels = lowered.body.compactMap { instruction -> Int32? in
                guard case let .label(label) = instruction else { return nil }
                return label
            }
            let targets = lowered.body.compactMap { instruction -> Int32? in
                guard case let .jump(target) = instruction else { return nil }
                return target
            }
            #expect(labels.count > 1 && Set(labels).count == labels.count)
            #expect(Set(targets).isSubset(of: Set(labels)))
            return lowered.body
        }

        let first = try expand()
        let second = try expand()
        #expect(first == second)
    }
}
#endif
