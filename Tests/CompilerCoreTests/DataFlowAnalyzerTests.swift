import XCTest
@testable import CompilerCore

final class DataFlowAnalyzerTests: XCTestCase {

    // MARK: - VariableFlowState

    func testVariableFlowStateEquality() {
        let types = TypeSystem()
        let intType = types.make(.primitive(.int, .nonNull))
        let state1 = VariableFlowState(possibleTypes: [intType], nullability: .nonNull, isStable: true)
        let state2 = VariableFlowState(possibleTypes: [intType], nullability: .nonNull, isStable: true)
        let state3 = VariableFlowState(possibleTypes: [intType], nullability: .nullable, isStable: true)
        XCTAssertEqual(state1, state2)
        XCTAssertNotEqual(state1, state3)
    }

    func testVariableFlowStateStableFlag() {
        let types = TypeSystem()
        let intType = types.make(.primitive(.int, .nonNull))
        let stable = VariableFlowState(possibleTypes: [intType], nullability: .nonNull, isStable: true)
        let unstable = VariableFlowState(possibleTypes: [intType], nullability: .nonNull, isStable: false)
        XCTAssertNotEqual(stable, unstable)
    }

    // MARK: - DataFlowState

    func testDataFlowStateDefaultIsEmpty() {
        let state = DataFlowState()
        XCTAssertTrue(state.variables.isEmpty)
    }

    func testDataFlowStateWithVariables() {
        let types = TypeSystem()
        let intType = types.make(.primitive(.int, .nonNull))
        let sym = SymbolID(rawValue: 0)
        let flow = VariableFlowState(possibleTypes: [intType], nullability: .nonNull, isStable: true)
        let state = DataFlowState(variables: [sym: flow])
        XCTAssertEqual(state.variables.count, 1)
        XCTAssertEqual(state.variables[sym], flow)
    }

    func testDataFlowStateEquality() {
        let types = TypeSystem()
        let intType = types.make(.primitive(.int, .nonNull))
        let sym = SymbolID(rawValue: 0)
        let flow = VariableFlowState(possibleTypes: [intType], nullability: .nonNull, isStable: true)
        let s1 = DataFlowState(variables: [sym: flow])
        let s2 = DataFlowState(variables: [sym: flow])
        XCTAssertEqual(s1, s2)
    }

    // MARK: - WhenBranchSummary

    func testWhenBranchSummaryDefaults() {
        let summary = WhenBranchSummary(coveredSymbols: [], hasElse: false)
        XCTAssertFalse(summary.hasElse)
        XCTAssertFalse(summary.hasNullCase)
        XCTAssertFalse(summary.hasTrueCase)
        XCTAssertFalse(summary.hasFalseCase)
    }

    func testWhenBranchSummaryWithElse() {
        let summary = WhenBranchSummary(coveredSymbols: [], hasElse: true)
        XCTAssertTrue(summary.hasElse)
    }

    func testWhenBranchSummaryWithNullCase() {
        let summary = WhenBranchSummary(coveredSymbols: [], hasElse: false, hasNullCase: true)
        XCTAssertTrue(summary.hasNullCase)
    }

    func testWhenBranchSummaryWithTrueFalse() {
        let summary = WhenBranchSummary(
            coveredSymbols: [],
            hasElse: false,
            hasTrueCase: true,
            hasFalseCase: true
        )
        XCTAssertTrue(summary.hasTrueCase)
        XCTAssertTrue(summary.hasFalseCase)
    }

    func testWhenBranchSummaryAutoDetectsTrueFalseFromInternedStrings() {
        // InternedString(rawValue: 1) = true, InternedString(rawValue: 2) = false
        let trueStr = InternedString(rawValue: 1)
        let falseStr = InternedString(rawValue: 2)
        let summary = WhenBranchSummary(coveredSymbols: [trueStr, falseStr], hasElse: false)
        XCTAssertTrue(summary.hasTrueCase)
        XCTAssertTrue(summary.hasFalseCase)
    }

    // MARK: - ConditionBranch

    func testConditionBranchEquality() {
        let base = DataFlowState()
        let branch1 = ConditionBranch(trueState: base, falseState: base)
        let branch2 = ConditionBranch(trueState: base, falseState: base)
        XCTAssertEqual(branch1, branch2)
    }

    // MARK: - Merge

    func testMergeEmptyStates() {
        let analyzer = DataFlowAnalyzer()
        let lhs = DataFlowState()
        let rhs = DataFlowState()
        let result = analyzer.merge(lhs, rhs)
        XCTAssertTrue(result.variables.isEmpty)
    }

    func testMergeOnlyKeepsSharedSymbols() {
        let analyzer = DataFlowAnalyzer()
        let types = TypeSystem()
        let intType = types.make(.primitive(.int, .nonNull))
        let sym1 = SymbolID(rawValue: 0)
        let sym2 = SymbolID(rawValue: 1)
        let flow = VariableFlowState(possibleTypes: [intType], nullability: .nonNull, isStable: true)

        let lhs = DataFlowState(variables: [sym1: flow, sym2: flow])
        let rhs = DataFlowState(variables: [sym1: flow])
        let result = analyzer.merge(lhs, rhs)
        XCTAssertEqual(result.variables.count, 1)
        XCTAssertNotNil(result.variables[sym1])
        XCTAssertNil(result.variables[sym2])
    }

    func testMergeUnionsPossibleTypes() {
        let analyzer = DataFlowAnalyzer()
        let types = TypeSystem()
        let intType = types.make(.primitive(.int, .nonNull))
        let stringType = types.make(.primitive(.string, .nonNull))
        let sym = SymbolID(rawValue: 0)

        let lhs = DataFlowState(variables: [sym: VariableFlowState(possibleTypes: [intType], nullability: .nonNull, isStable: true)])
        let rhs = DataFlowState(variables: [sym: VariableFlowState(possibleTypes: [stringType], nullability: .nonNull, isStable: true)])
        let result = analyzer.merge(lhs, rhs)
        XCTAssertEqual(result.variables[sym]!.possibleTypes.count, 2)
        XCTAssertTrue(result.variables[sym]!.possibleTypes.contains(intType))
        XCTAssertTrue(result.variables[sym]!.possibleTypes.contains(stringType))
    }

    func testMergeNullabilityIsNullableIfEitherIsNullable() {
        let analyzer = DataFlowAnalyzer()
        let types = TypeSystem()
        let intType = types.make(.primitive(.int, .nonNull))
        let sym = SymbolID(rawValue: 0)

        let lhs = DataFlowState(variables: [sym: VariableFlowState(possibleTypes: [intType], nullability: .nonNull, isStable: true)])
        let rhs = DataFlowState(variables: [sym: VariableFlowState(possibleTypes: [intType], nullability: .nullable, isStable: true)])
        let result = analyzer.merge(lhs, rhs)
        XCTAssertEqual(result.variables[sym]!.nullability, .nullable)
    }

    func testMergeStabilityIsFalseIfEitherUnstable() {
        let analyzer = DataFlowAnalyzer()
        let types = TypeSystem()
        let intType = types.make(.primitive(.int, .nonNull))
        let sym = SymbolID(rawValue: 0)

        let lhs = DataFlowState(variables: [sym: VariableFlowState(possibleTypes: [intType], nullability: .nonNull, isStable: true)])
        let rhs = DataFlowState(variables: [sym: VariableFlowState(possibleTypes: [intType], nullability: .nonNull, isStable: false)])
        let result = analyzer.merge(lhs, rhs)
        XCTAssertFalse(result.variables[sym]!.isStable)
    }

    // MARK: - isWhenExhaustive

    func testIsWhenExhaustiveWithElseReturnsTrue() {
        let analyzer = DataFlowAnalyzer()
        let (sema, _, types, _) = makeSemaModule()
        let intType = types.make(.primitive(.int, .nonNull))
        let summary = WhenBranchSummary(coveredSymbols: [], hasElse: true)
        XCTAssertTrue(analyzer.isWhenExhaustive(subjectType: intType, branches: summary, sema: sema))
    }

    func testIsWhenExhaustiveBooleanNonNull() {
        let analyzer = DataFlowAnalyzer()
        let (sema, _, types, _) = makeSemaModule()
        let boolType = types.make(.primitive(.boolean, .nonNull))

        let incomplete = WhenBranchSummary(coveredSymbols: [], hasElse: false, hasTrueCase: true, hasFalseCase: false)
        XCTAssertFalse(analyzer.isWhenExhaustive(subjectType: boolType, branches: incomplete, sema: sema))

        let complete = WhenBranchSummary(coveredSymbols: [], hasElse: false, hasTrueCase: true, hasFalseCase: true)
        XCTAssertTrue(analyzer.isWhenExhaustive(subjectType: boolType, branches: complete, sema: sema))
    }

    func testIsWhenExhaustiveBooleanNullable() {
        let analyzer = DataFlowAnalyzer()
        let (sema, _, types, _) = makeSemaModule()
        let nullableBool = types.make(.primitive(.boolean, .nullable))

        let withoutNull = WhenBranchSummary(coveredSymbols: [], hasElse: false, hasTrueCase: true, hasFalseCase: true)
        XCTAssertFalse(analyzer.isWhenExhaustive(subjectType: nullableBool, branches: withoutNull, sema: sema))

        let withNull = WhenBranchSummary(coveredSymbols: [], hasElse: false, hasNullCase: true, hasTrueCase: true, hasFalseCase: true)
        XCTAssertTrue(analyzer.isWhenExhaustive(subjectType: nullableBool, branches: withNull, sema: sema))
    }

    func testIsWhenExhaustiveNonBoolNonClassReturnsFalse() {
        let analyzer = DataFlowAnalyzer()
        let (sema, _, types, _) = makeSemaModule()
        let intType = types.make(.primitive(.int, .nonNull))
        let summary = WhenBranchSummary(coveredSymbols: [], hasElse: false)
        XCTAssertFalse(analyzer.isWhenExhaustive(subjectType: intType, branches: summary, sema: sema))
    }

    func testIsWhenExhaustiveNullableAnyReturnsFalse() {
        let analyzer = DataFlowAnalyzer()
        let (sema, _, types, _) = makeSemaModule()
        let summary = WhenBranchSummary(coveredSymbols: [], hasElse: false)
        XCTAssertFalse(analyzer.isWhenExhaustive(subjectType: types.nullableAnyType, branches: summary, sema: sema))
    }

    func testIsWhenExhaustiveEnumClass() {
        let analyzer = DataFlowAnalyzer()
        let (sema, symbols, types, interner) = makeSemaModule()

        let enumName = interner.intern("Color")
        let enumSym = symbols.define(kind: .enumClass, name: enumName, fqName: [enumName], declSite: nil, visibility: .public)

        let redName = interner.intern("RED")
        let greenName = interner.intern("GREEN")
        let blueName = interner.intern("BLUE")

        _ = symbols.define(kind: .field, name: redName, fqName: [enumName, redName], declSite: nil, visibility: .public)
        _ = symbols.define(kind: .field, name: greenName, fqName: [enumName, greenName], declSite: nil, visibility: .public)
        _ = symbols.define(kind: .field, name: blueName, fqName: [enumName, blueName], declSite: nil, visibility: .public)

        let enumType = types.make(.classType(ClassType(classSymbol: enumSym)))

        // Missing BLUE
        let incomplete = WhenBranchSummary(coveredSymbols: [redName, greenName], hasElse: false)
        XCTAssertFalse(analyzer.isWhenExhaustive(subjectType: enumType, branches: incomplete, sema: sema))

        // All entries covered
        let complete = WhenBranchSummary(coveredSymbols: [redName, greenName, blueName], hasElse: false)
        XCTAssertTrue(analyzer.isWhenExhaustive(subjectType: enumType, branches: complete, sema: sema))
    }

    func testIsWhenExhaustiveNullableEnumClass() {
        let analyzer = DataFlowAnalyzer()
        let (sema, symbols, types, interner) = makeSemaModule()

        let enumName = interner.intern("Status")
        let enumSym = symbols.define(kind: .enumClass, name: enumName, fqName: [enumName], declSite: nil, visibility: .public)
        let okName = interner.intern("OK")
        _ = symbols.define(kind: .field, name: okName, fqName: [enumName, okName], declSite: nil, visibility: .public)

        let nullableEnumType = types.make(.classType(ClassType(classSymbol: enumSym, nullability: .nullable)))

        // All entries but no null case
        let withoutNull = WhenBranchSummary(coveredSymbols: [okName], hasElse: false)
        XCTAssertFalse(analyzer.isWhenExhaustive(subjectType: nullableEnumType, branches: withoutNull, sema: sema))

        // All entries and null case
        let withNull = WhenBranchSummary(coveredSymbols: [okName], hasElse: false, hasNullCase: true)
        XCTAssertTrue(analyzer.isWhenExhaustive(subjectType: nullableEnumType, branches: withNull, sema: sema))
    }

    func testIsWhenExhaustiveSealedClass() {
        let analyzer = DataFlowAnalyzer()
        let (sema, symbols, types, interner) = makeSemaModule()

        let sealedName = interner.intern("Result")
        let sealedSym = symbols.define(
            kind: .class, name: sealedName, fqName: [sealedName],
            declSite: nil, visibility: .public, flags: .sealedType
        )

        let successName = interner.intern("Success")
        let failureName = interner.intern("Failure")
        let successSym = symbols.define(kind: .class, name: successName, fqName: [successName], declSite: nil, visibility: .public)
        let failureSym = symbols.define(kind: .class, name: failureName, fqName: [failureName], declSite: nil, visibility: .public)
        symbols.setDirectSupertypes([sealedSym], for: successSym)
        symbols.setDirectSupertypes([sealedSym], for: failureSym)

        let sealedType = types.make(.classType(ClassType(classSymbol: sealedSym)))

        // Missing Failure
        let incomplete = WhenBranchSummary(coveredSymbols: [successName], hasElse: false)
        XCTAssertFalse(analyzer.isWhenExhaustive(subjectType: sealedType, branches: incomplete, sema: sema))

        // All subtypes
        let complete = WhenBranchSummary(coveredSymbols: [successName, failureName], hasElse: false)
        XCTAssertTrue(analyzer.isWhenExhaustive(subjectType: sealedType, branches: complete, sema: sema))
    }

    func testIsWhenExhaustiveNullableSealedClass() {
        let analyzer = DataFlowAnalyzer()
        let (sema, symbols, types, interner) = makeSemaModule()

        let sealedName = interner.intern("R")
        let sealedSym = symbols.define(
            kind: .class, name: sealedName, fqName: [sealedName],
            declSite: nil, visibility: .public, flags: .sealedType
        )
        let subName = interner.intern("S")
        let subSym = symbols.define(kind: .class, name: subName, fqName: [subName], declSite: nil, visibility: .public)
        symbols.setDirectSupertypes([sealedSym], for: subSym)

        let nullableSealedType = types.make(.classType(ClassType(classSymbol: sealedSym, nullability: .nullable)))

        let withoutNull = WhenBranchSummary(coveredSymbols: [subName], hasElse: false)
        XCTAssertFalse(analyzer.isWhenExhaustive(subjectType: nullableSealedType, branches: withoutNull, sema: sema))

        let withNull = WhenBranchSummary(coveredSymbols: [subName], hasElse: false, hasNullCase: true)
        XCTAssertTrue(analyzer.isWhenExhaustive(subjectType: nullableSealedType, branches: withNull, sema: sema))
    }

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
}
