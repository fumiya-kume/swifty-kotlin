#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct CollectionClassificationTests {
    private typealias State = CollectionLiteralLoweringSupport.CollectionRewriteState

    private struct Fixture {
        let interner = StringInterner()
        let arena = KIRArena()
        let sema = makeSemaModule().ctx

        func classType(_ components: [String]) -> TypeID {
            let symbol = sema.symbols.define(
                kind: .class,
                name: interner.intern(components.last!),
                fqName: components.map(interner.intern),
                declSite: nil,
                visibility: .public,
                flags: []
            )
            return sema.types.make(.classType(ClassType(classSymbol: symbol)))
        }

        func function(_ body: [KIRInstruction], params: [KIRParameter] = []) -> KIRFunction {
            KIRFunction(
                symbol: SymbolID(rawValue: 1000), name: interner.intern("probe"),
                params: params, returnType: sema.types.unitType,
                body: body + [.returnUnit], isSuspend: false, isInline: false
            )
        }

        func call(_ name: String, arguments: [KIRExprID] = [], result: KIRExprID) -> KIRInstruction {
            .call(
                symbol: nil, callee: interner.intern(name), arguments: arguments,
                result: result, canThrow: false, thrownResult: nil
            )
        }

        func scan(_ function: KIRFunction) -> State {
            var state = State()
            CollectionLiteralLoweringSupport().collectInitialCollectionExprIDs(
                function: function, lookup: CollectionLiteralLookupTables(interner: interner),
                arena: arena, sema: sema, interner: interner,
                listExprIDs: &state.listExprIDs, setExprIDs: &state.setExprIDs,
                mapExprIDs: &state.mapExprIDs, arrayExprIDs: &state.arrayExprIDs,
                sequenceExprIDs: &state.sequenceExprIDs, rangeExprIDs: &state.rangeExprIDs,
                charRangeExprIDs: &state.charRangeExprIDs, ulongRangeExprIDs: &state.ulongRangeExprIDs,
                stringExprIDs: &state.stringExprIDs, fileExprIDs: &state.fileExprIDs,
                pathExprIDs: &state.pathExprIDs
            )
            return state
        }
    }

    @Test
    func staticCollectionTypesSeedParametersCallResultsAndCopyChains() {
        let cases: [([String], WritableKeyPath<State, Set<Int32>>)] = [
            (["kotlin", "collections", "List"], \.listExprIDs),
            (["kotlin", "collections", "Set"], \.setExprIDs),
            (["kotlin", "collections", "Map"], \.mapExprIDs),
            (["kotlin", "Array"], \.arrayExprIDs),
            (["kotlin", "UIntArray"], \.arrayExprIDs),
            (["kotlin", "String"], \.stringExprIDs),
        ]
        for (name, classification) in cases {
            let fixture = Fixture()
            let type = fixture.classType(name)
            let parameterSymbol = SymbolID(rawValue: 100)
            let parameter = fixture.arena.appendExpr(.symbolRef(parameterSymbol), type: type)
            let result = fixture.arena.appendTemporary(type: type)
            let firstCopy = fixture.arena.appendTemporary(type: nil)
            let secondCopy = fixture.arena.appendTemporary(type: nil)
            let function = fixture.function([
                fixture.call("userFactory", arguments: [parameter], result: result),
                .copy(from: result, to: firstCopy),
                .copy(from: firstCopy, to: secondCopy),
            ], params: [KIRParameter(symbol: parameterSymbol, type: type)])

            let state = fixture.scan(function)

            #expect(state[keyPath: classification] == Set([
                parameter.rawValue, result.rawValue, firstCopy.rawValue, secondCopy.rawValue,
            ]), "missing classification for \(name)")

            let module = KIRModule(files: [], arena: fixture.arena)
            var directState = State()
            for expr in [parameter, result] {
                CollectionLiteralLoweringSupport().classifyTrackedExprByStaticType(
                    expr, module: module, sema: fixture.sema,
                    interner: fixture.interner, state: &directState
                )
            }
            #expect(directState[keyPath: classification] == [parameter.rawValue, result.rawValue])
        }
    }

    @Test
    func directStaticClassificationRejectsUserTypesWithStdlibNames() {
        let fixture = Fixture()
        let module = KIRModule(files: [], arena: fixture.arena)
        var state = State()
        for name in ["List", "Set", "Map", "Array", "String", "Range", "Iterator", "File", "Path"] {
            let expr = fixture.arena.appendTemporary(type: fixture.classType(["user", name]))
            CollectionLiteralLoweringSupport().classifyTrackedExprByStaticType(
                expr, module: module, sema: fixture.sema, interner: fixture.interner, state: &state
            )
        }

        #expect(state.listExprIDs.isEmpty && state.setExprIDs.isEmpty && state.mapExprIDs.isEmpty)
        #expect(state.arrayExprIDs.isEmpty && state.stringExprIDs.isEmpty && state.rangeExprIDs.isEmpty)
        #expect(state.listIteratorExprIDs.isEmpty && state.mapIteratorExprIDs.isEmpty)
        #expect(state.fileExprIDs.isEmpty && state.pathExprIDs.isEmpty)
    }

    @Test
    func sourceObjectTypesAloneDoNotProveSpecializedRuntimeRepresentations() {
        let fixture = Fixture()
        let names = [
            ["kotlin", "sequences", "Sequence"],
            ["kotlin", "collections", "Iterator"],
            ["kotlin", "ranges", "IntRange"],
            ["kotlin", "ranges", "CharRange"],
            ["kotlin", "ranges", "ULongRange"],
            ["java", "io", "File"],
            ["java", "nio", "file", "Path"],
        ]
        let arguments = names.map { fixture.arena.appendTemporary(type: fixture.classType($0)) }
        let result = fixture.arena.appendTemporary(type: nil)
        let state = fixture.scan(fixture.function([
            fixture.call("consumeSourceObjects", arguments: arguments, result: result),
        ]))

        #expect(state.sequenceExprIDs.isEmpty)
        #expect(state.rangeExprIDs.isEmpty && state.charRangeExprIDs.isEmpty && state.ulongRangeExprIDs.isEmpty)
        #expect(state.listIteratorExprIDs.isEmpty && state.mapIteratorExprIDs.isEmpty)
        #expect(state.fileExprIDs.isEmpty && state.pathExprIDs.isEmpty)
    }

    @Test
    func knownFactoryResultsAndStringLiteralsPropagateWithoutStaticTypes() {
        let cases: [(String, WritableKeyPath<State, Set<Int32>>)] = [
            ("listOf", \.listExprIDs), ("setOf", \.setExprIDs),
            ("mapOf", \.mapExprIDs), ("arrayOf", \.arrayExprIDs),
            ("__kk_file_new", \.fileExprIDs),
        ]
        for (name, classification) in cases {
            let fixture = Fixture()
            let result = fixture.arena.appendTemporary(type: nil)
            let copy = fixture.arena.appendTemporary(type: nil)
            let state = fixture.scan(fixture.function([
                fixture.call(name, result: result), .copy(from: result, to: copy),
            ]))
            #expect(state[keyPath: classification] == [result.rawValue, copy.rawValue])
        }

        let fixture = Fixture()
        let string = fixture.arena.appendTemporary(type: fixture.sema.types.stringType)
        let copy = fixture.arena.appendTemporary(type: nil)
        let unknown = fixture.arena.appendTemporary(type: nil)
        let unknownCopy = fixture.arena.appendTemporary(type: nil)
        let state = fixture.scan(fixture.function([
            .constValue(result: string, value: .stringLiteral(fixture.interner.intern("text"))),
            .copy(from: string, to: copy), .copy(from: unknown, to: unknownCopy),
        ]))
        #expect(state.stringExprIDs == [string.rawValue, copy.rawValue])
        #expect(state.listExprIDs.isEmpty && state.arrayExprIDs.isEmpty)
    }

    @Test
    func rangeFactoriesAndCopyChainsPreserveSpecialization() {
        let fixture = Fixture()
        let char = fixture.arena.appendTemporary(type: fixture.sema.types.charType)
        let ulong = fixture.arena.appendTemporary(type: fixture.sema.types.ulongType)
        let charRange = fixture.arena.appendTemporary(type: nil)
        let ulongRange = fixture.arena.appendTemporary(type: nil)
        let charAlias = fixture.arena.appendTemporary(type: nil)
        let ulongAlias = fixture.arena.appendTemporary(type: nil)
        let stepped = fixture.arena.appendTemporary(type: nil)
        let state = fixture.scan(fixture.function([
            .constValue(result: char, value: .charLiteral(97)),
            .constValue(result: ulong, value: .ulongLiteral(1)),
            fixture.call("kk_op_rangeTo", arguments: [char, char], result: charRange),
            fixture.call("kk_op_rangeTo", arguments: [ulong, ulong], result: ulongRange),
            .copy(from: charRange, to: charAlias), .copy(from: ulongRange, to: ulongAlias),
            fixture.call("__kk_op_step", arguments: [ulongAlias, ulong], result: stepped),
        ]))

        #expect(state.rangeExprIDs == Set([charRange, ulongRange, charAlias, ulongAlias, stepped].map(\.rawValue)))
        #expect(state.charRangeExprIDs == [charRange.rawValue, charAlias.rawValue])
        #expect(state.ulongRangeExprIDs == [ulongRange.rawValue, ulongAlias.rawValue, stepped.rawValue])
    }

    @Test
    func iteratorReassignmentKeepsTheGenericCallAndItsThrowChannel() throws {
        let fixture = Fixture()
        let collection = fixture.arena.appendTemporary(type: nil)
        let listIterator = fixture.arena.appendTemporary(type: nil)
        let storage = fixture.arena.appendTemporary(type: nil)
        let replacement = fixture.arena.appendTemporary(type: nil)
        let result = fixture.arena.appendTemporary(type: fixture.sema.types.intType)
        let thrown = fixture.arena.appendTemporary(type: fixture.sema.types.anyType)
        let function = fixture.function([
            fixture.call("kk_list_iterator", arguments: [collection], result: listIterator),
            .copy(from: listIterator, to: storage),
            fixture.call("userIteratorFactory", result: replacement),
            .copy(from: replacement, to: storage),
            .call(
                symbol: nil, callee: fixture.interner.intern("kk_iterator_next"),
                arguments: [storage], result: result, canThrow: true, thrownResult: thrown
            ),
        ])
        let declaration = fixture.arena.appendDecl(.function(function))
        let module = KIRModule(files: [], arena: fixture.arena)
        let options = makeCompilationContext(inputs: [], includeStdlib: false).options
        let context = KIRContext(
            diagnostics: DiagnosticEngine(), options: options,
            interner: fixture.interner, sema: fixture.sema
        )

        try CollectionLiteralLoweringPass().run(module: module, ctx: context)

        guard case let .function(lowered) = module.arena.decl(declaration) else {
            Issue.record("The collection pass removed the probe function")
            return
        }
        let iteratorCalls = lowered.body.filter { instruction in
            guard case let .call(_, _, _, returned, _, _, _, _) = instruction else { return false }
            return returned == result
        }
        #expect(iteratorCalls.count == 1)
        guard case let .call(_, callee, arguments, returned, canThrow, thrownResult, _, _) = try #require(iteratorCalls.first) else {
            Issue.record("The iterator operation is no longer a call")
            return
        }
        #expect(fixture.interner.resolve(callee) == "kk_iterator_next")
        #expect(arguments == [storage] && returned == result)
        #expect(canThrow && thrownResult == thrown)
    }
}
#endif
