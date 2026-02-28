import XCTest
@testable import CompilerCore


extension DataFlowAnalyzerTests {
    func testIsWhenExhaustiveNonSealedClassReturnsFalse() {
        let analyzer = DataFlowAnalyzer()
        let (sema, symbols, types, interner) = makeSemaModule()

        let className = interner.intern("Foo")
        let classSym = symbols.define(kind: .class, name: className, fqName: [className], declSite: nil, visibility: .public)
        let classType = types.make(.classType(ClassType(classSymbol: classSym)))

        let summary = WhenBranchSummary(coveredSymbols: [className], hasElse: false)
        XCTAssertFalse(analyzer.isWhenExhaustive(subjectType: classType, branches: summary, sema: sema))
    }

    func testIsWhenExhaustiveEmptyEnumReturnsFalse() {
        let analyzer = DataFlowAnalyzer()
        let (sema, symbols, types, interner) = makeSemaModule()

        let enumName = interner.intern("Empty")
        let enumSym = symbols.define(kind: .enumClass, name: enumName, fqName: [enumName], declSite: nil, visibility: .public)
        let enumType = types.make(.classType(ClassType(classSymbol: enumSym)))

        let summary = WhenBranchSummary(coveredSymbols: [], hasElse: false)
        XCTAssertFalse(analyzer.isWhenExhaustive(subjectType: enumType, branches: summary, sema: sema))
    }

    func testIsWhenExhaustiveEmptySealedReturnsFalse() {
        let analyzer = DataFlowAnalyzer()
        let (sema, symbols, types, interner) = makeSemaModule()

        let sealedName = interner.intern("Empty")
        let sealedSym = symbols.define(
            kind: .class, name: sealedName, fqName: [sealedName],
            declSite: nil, visibility: .public, flags: .sealedType
        )
        let sealedType = types.make(.classType(ClassType(classSymbol: sealedSym)))

        let summary = WhenBranchSummary(coveredSymbols: [], hasElse: false)
        XCTAssertFalse(analyzer.isWhenExhaustive(subjectType: sealedType, branches: summary, sema: sema))
    }

    // MARK: - resolvedTypeFromFlowState

    func testResolvedTypeFromFlowStateReturnsSingleType() {
        let analyzer = DataFlowAnalyzer()
        let types = TypeSystem()
        let intType = types.make(.primitive(.int, .nonNull))
        let sym = SymbolID(rawValue: 0)
        let state = DataFlowState(variables: [
            sym: VariableFlowState(possibleTypes: [intType], nullability: .nonNull, isStable: true)
        ])
        XCTAssertEqual(analyzer.resolvedTypeFromFlowState(state, symbol: sym), intType)
    }

    func testResolvedTypeFromFlowStateReturnsNilForMultipleTypes() {
        let analyzer = DataFlowAnalyzer()
        let types = TypeSystem()
        let intType = types.make(.primitive(.int, .nonNull))
        let stringType = types.make(.primitive(.string, .nonNull))
        let sym = SymbolID(rawValue: 0)
        let state = DataFlowState(variables: [
            sym: VariableFlowState(possibleTypes: [intType, stringType], nullability: .nonNull, isStable: true)
        ])
        XCTAssertNil(analyzer.resolvedTypeFromFlowState(state, symbol: sym))
    }

    func testResolvedTypeFromFlowStateReturnsNilForUnknownSymbol() {
        let analyzer = DataFlowAnalyzer()
        let state = DataFlowState()
        XCTAssertNil(analyzer.resolvedTypeFromFlowState(state, symbol: SymbolID(rawValue: 0)))
    }

    func testResolvedTypeFromFlowStateReturnsNilForEmptyTypes() {
        let analyzer = DataFlowAnalyzer()
        let sym = SymbolID(rawValue: 0)
        let state = DataFlowState(variables: [
            sym: VariableFlowState(possibleTypes: [], nullability: .nonNull, isStable: true)
        ])
        XCTAssertNil(analyzer.resolvedTypeFromFlowState(state, symbol: sym))
    }

    // MARK: - whenElseState

    func testWhenElseStateWithNoExplicitNullBranchReturnsBase() {
        let analyzer = DataFlowAnalyzer()
        let (sema, _, types, _) = makeSemaModule()
        let sym = SymbolID(rawValue: 0)
        let nullableInt = types.make(.primitive(.int, .nullable))
        let base = DataFlowState()

        let result = analyzer.whenElseState(
            subjectSymbol: sym,
            subjectType: nullableInt,
            hasExplicitNullBranch: false,
            base: base,
            sema: sema
        )
        XCTAssertEqual(result, base)
    }

    func testWhenElseStateWithExplicitNullBranchNarrowsToNonNull() {
        let analyzer = DataFlowAnalyzer()
        let (sema, _, types, _) = makeSemaModule()
        let sym = SymbolID(rawValue: 0)
        let nullableInt = types.make(.primitive(.int, .nullable))
        let nonNullInt = types.make(.primitive(.int, .nonNull))
        let base = DataFlowState()

        let result = analyzer.whenElseState(
            subjectSymbol: sym,
            subjectType: nullableInt,
            hasExplicitNullBranch: true,
            base: base,
            sema: sema
        )
        XCTAssertEqual(result.variables[sym]?.possibleTypes, [nonNullInt])
        XCTAssertEqual(result.variables[sym]?.nullability, .nonNull)
    }

    // MARK: - whenNonNullBranchState

    func testWhenNonNullBranchStateNarrowsToNonNull() {
        let analyzer = DataFlowAnalyzer()
        let (sema, _, types, _) = makeSemaModule()
        let sym = SymbolID(rawValue: 0)
        let nullableString = types.make(.primitive(.string, .nullable))
        let nonNullString = types.make(.primitive(.string, .nonNull))
        let base = DataFlowState()

        let result = analyzer.whenNonNullBranchState(
            subjectSymbol: sym,
            subjectType: nullableString,
            base: base,
            sema: sema
        )
        XCTAssertEqual(result.variables[sym]?.possibleTypes, [nonNullString])
        XCTAssertEqual(result.variables[sym]?.nullability, .nonNull)
    }

    func testWhenNonNullBranchStateAlreadyNonNull() {
        let analyzer = DataFlowAnalyzer()
        let (sema, _, types, _) = makeSemaModule()
        let sym = SymbolID(rawValue: 0)
        let nonNullInt = types.make(.primitive(.int, .nonNull))
        let base = DataFlowState()

        let result = analyzer.whenNonNullBranchState(
            subjectSymbol: sym,
            subjectType: nonNullInt,
            base: base,
            sema: sema
        )
        XCTAssertEqual(result.variables[sym]?.possibleTypes, [nonNullInt])
    }

    // MARK: - makeTypeNonNullable coverage through whenNonNullBranchState

    func testMakeTypeNonNullableForNullableAny() {
        let analyzer = DataFlowAnalyzer()
        let (sema, _, types, _) = makeSemaModule()
        let sym = SymbolID(rawValue: 0)
        let base = DataFlowState()

        let result = analyzer.whenNonNullBranchState(
            subjectSymbol: sym,
            subjectType: types.nullableAnyType,
            base: base,
            sema: sema
        )
        XCTAssertEqual(result.variables[sym]?.possibleTypes, [types.anyType])
    }

    func testMakeTypeNonNullableForNullableClass() {
        let analyzer = DataFlowAnalyzer()
        let (sema, _, types, _) = makeSemaModule()
        let sym = SymbolID(rawValue: 0)
        let base = DataFlowState()
        let classSym = SymbolID(rawValue: 10)
        let nullableClass = types.make(.classType(ClassType(classSymbol: classSym, nullability: .nullable)))
        let nonNullClass = types.make(.classType(ClassType(classSymbol: classSym, nullability: .nonNull)))

        let result = analyzer.whenNonNullBranchState(
            subjectSymbol: sym,
            subjectType: nullableClass,
            base: base,
            sema: sema
        )
        XCTAssertEqual(result.variables[sym]?.possibleTypes, [nonNullClass])
    }

    func testMakeTypeNonNullableForNullableTypeParam() {
        let analyzer = DataFlowAnalyzer()
        let (sema, _, types, _) = makeSemaModule()
        let sym = SymbolID(rawValue: 0)
        let base = DataFlowState()
        let tpSym = SymbolID(rawValue: 10)
        let nullableTP = types.make(.typeParam(TypeParamType(symbol: tpSym, nullability: .nullable)))
        let nonNullTP = types.make(.typeParam(TypeParamType(symbol: tpSym, nullability: .nonNull)))

        let result = analyzer.whenNonNullBranchState(
            subjectSymbol: sym,
            subjectType: nullableTP,
            base: base,
            sema: sema
        )
        XCTAssertEqual(result.variables[sym]?.possibleTypes, [nonNullTP])
    }

    func testMakeTypeNonNullableForNullableFunctionType() {
        let analyzer = DataFlowAnalyzer()
        let (sema, _, types, _) = makeSemaModule()
        let sym = SymbolID(rawValue: 0)
        let base = DataFlowState()
        let intType = types.make(.primitive(.int, .nonNull))
        let nullableFn = types.make(.functionType(FunctionType(params: [], returnType: intType, nullability: .nullable)))
        let nonNullFn = types.make(.functionType(FunctionType(params: [], returnType: intType, nullability: .nonNull)))

        let result = analyzer.whenNonNullBranchState(
            subjectSymbol: sym,
            subjectType: nullableFn,
            base: base,
            sema: sema
        )
        XCTAssertEqual(result.variables[sym]?.possibleTypes, [nonNullFn])
    }

    func testMakeTypeNonNullableForNonNullableTypeIsIdentity() {
        let analyzer = DataFlowAnalyzer()
        let (sema, _, types, _) = makeSemaModule()
        let sym = SymbolID(rawValue: 0)
        let base = DataFlowState()
        let intType = types.make(.primitive(.int, .nonNull))

        let result = analyzer.whenNonNullBranchState(
            subjectSymbol: sym,
            subjectType: intType,
            base: base,
            sema: sema
        )
        XCTAssertEqual(result.variables[sym]?.possibleTypes, [intType])
    }

    // MARK: - narrowToNonNull (P5-66)

    func testNarrowToNonNullNarrowsNullableIntToNonNull() {
        let analyzer = DataFlowAnalyzer()
        let (_, _, types, _) = makeSemaModule()
        let sym = SymbolID(rawValue: 0)
        let base = DataFlowState()
        let nullableInt = types.make(.primitive(.int, .nullable))
        let nonNullInt = types.make(.primitive(.int, .nonNull))

        let result = analyzer.narrowToNonNull(symbol: sym, type: nullableInt, base: base, types: types)
        XCTAssertEqual(result.variables[sym]?.possibleTypes, [nonNullInt])
        XCTAssertEqual(result.variables[sym]?.nullability, .nonNull)
        XCTAssertTrue(result.variables[sym]?.isStable == true)
    }

    func testNarrowToNonNullPreservesExistingVariables() {
        let analyzer = DataFlowAnalyzer()
        let (_, _, types, _) = makeSemaModule()
        let sym1 = SymbolID(rawValue: 0)
        let sym2 = SymbolID(rawValue: 1)
        let intType = types.make(.primitive(.int, .nonNull))
        let nullableString = types.make(.primitive(.string, .nullable))
        let nonNullString = types.make(.primitive(.string, .nonNull))
        let existing = VariableFlowState(possibleTypes: [intType], nullability: .nonNull, isStable: true)
        let base = DataFlowState(variables: [sym1: existing])

        let result = analyzer.narrowToNonNull(symbol: sym2, type: nullableString, base: base, types: types)
        XCTAssertEqual(result.variables[sym1]?.possibleTypes, [intType])
        XCTAssertEqual(result.variables[sym2]?.possibleTypes, [nonNullString])
    }

    func testNarrowToNonNullAlreadyNonNullIsIdentity() {
        let analyzer = DataFlowAnalyzer()
        let (_, _, types, _) = makeSemaModule()
        let sym = SymbolID(rawValue: 0)
        let base = DataFlowState()
        let nonNullInt = types.make(.primitive(.int, .nonNull))

        let result = analyzer.narrowToNonNull(symbol: sym, type: nonNullInt, base: base, types: types)
        XCTAssertEqual(result.variables[sym]?.possibleTypes, [nonNullInt])
        XCTAssertEqual(result.variables[sym]?.nullability, .nonNull)
    }

    // MARK: - invalidateVariable (P5-66)

    func testInvalidateVariableRemovesSmartCast() {
        let analyzer = DataFlowAnalyzer()
        let types = TypeSystem()
        let sym = SymbolID(rawValue: 0)
        let intType = types.make(.primitive(.int, .nonNull))
        let flow = VariableFlowState(possibleTypes: [intType], nullability: .nonNull, isStable: true)
        let base = DataFlowState(variables: [sym: flow])

        let result = analyzer.invalidateVariable(symbol: sym, base: base)
        XCTAssertNil(result.variables[sym])
    }

    func testInvalidateVariablePreservesOtherVariables() {
        let analyzer = DataFlowAnalyzer()
        let types = TypeSystem()
        let sym1 = SymbolID(rawValue: 0)
        let sym2 = SymbolID(rawValue: 1)
        let intType = types.make(.primitive(.int, .nonNull))
        let flow = VariableFlowState(possibleTypes: [intType], nullability: .nonNull, isStable: true)
        let base = DataFlowState(variables: [sym1: flow, sym2: flow])

        let result = analyzer.invalidateVariable(symbol: sym1, base: base)
        XCTAssertNil(result.variables[sym1])
        XCTAssertNotNil(result.variables[sym2])
    }

    func testInvalidateVariableOnEmptyStateIsNoOp() {
        let analyzer = DataFlowAnalyzer()
        let sym = SymbolID(rawValue: 0)
        let base = DataFlowState()

        let result = analyzer.invalidateVariable(symbol: sym, base: base)
        XCTAssertTrue(result.variables.isEmpty)
    }
}
