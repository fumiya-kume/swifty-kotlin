import XCTest
@testable import CompilerCore

final class TypeSystemTests: XCTestCase {

    // MARK: - Built-in Types

    func testBuiltInTypesArePreInitialized() {
        let ts = TypeSystem()
        XCTAssertEqual(ts.kind(of: ts.errorType), .error)
        XCTAssertEqual(ts.kind(of: ts.unitType), .unit)
        XCTAssertEqual(ts.kind(of: ts.nothingType), .nothing)
        XCTAssertEqual(ts.kind(of: ts.anyType), .any(.nonNull))
        XCTAssertEqual(ts.kind(of: ts.nullableAnyType), .any(.nullable))
    }

    func testBuiltInTypeIDsAreDistinct() {
        let ts = TypeSystem()
        let ids: [TypeID] = [ts.errorType, ts.unitType, ts.nothingType, ts.anyType, ts.nullableAnyType]
        let uniqueIDs = Set(ids)
        XCTAssertEqual(uniqueIDs.count, 5)
    }

    // MARK: - make / kind

    func testMakeDeduplicatesIdenticalTypes() {
        let ts = TypeSystem()
        let intA = ts.make(.primitive(.int, .nonNull))
        let intB = ts.make(.primitive(.int, .nonNull))
        XCTAssertEqual(intA, intB)
    }

    func testMakeDistinguishesDifferentNullability() {
        let ts = TypeSystem()
        let nonNull = ts.make(.primitive(.int, .nonNull))
        let nullable = ts.make(.primitive(.int, .nullable))
        XCTAssertNotEqual(nonNull, nullable)
    }

    func testMakeAllPrimitiveTypes() {
        let ts = TypeSystem()
        let primitives: [PrimitiveType] = [.boolean, .char, .int, .long, .float, .double, .string]
        for prim in primitives {
            let id = ts.make(.primitive(prim, .nonNull))
            XCTAssertEqual(ts.kind(of: id), .primitive(prim, .nonNull))
        }
    }

    func testKindReturnsErrorForInvalidID() {
        let ts = TypeSystem()
        XCTAssertEqual(ts.kind(of: TypeID(rawValue: -1)), .error)
        XCTAssertEqual(ts.kind(of: TypeID(rawValue: 99999)), .error)
    }

    func testMakeClassType() {
        let ts = TypeSystem()
        let classType = ClassType(classSymbol: SymbolID(rawValue: 0), args: [], nullability: .nonNull)
        let id = ts.make(.classType(classType))
        if case .classType(let ct) = ts.kind(of: id) {
            XCTAssertEqual(ct.classSymbol, SymbolID(rawValue: 0))
            XCTAssertEqual(ct.nullability, .nonNull)
        } else {
            XCTFail("Expected classType")
        }
    }

    func testMakeTypeParam() {
        let ts = TypeSystem()
        let tp = TypeParamType(symbol: SymbolID(rawValue: 1), nullability: .nullable)
        let id = ts.make(.typeParam(tp))
        if case .typeParam(let result) = ts.kind(of: id) {
            XCTAssertEqual(result.symbol, SymbolID(rawValue: 1))
            XCTAssertEqual(result.nullability, .nullable)
        } else {
            XCTFail("Expected typeParam")
        }
    }

    func testMakeFunctionType() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        let ft = FunctionType(
            receiver: nil,
            params: [intType],
            returnType: intType,
            isSuspend: false,
            nullability: .nonNull
        )
        let id = ts.make(.functionType(ft))
        if case .functionType(let result) = ts.kind(of: id) {
            XCTAssertEqual(result.params.count, 1)
            XCTAssertNil(result.receiver)
            XCTAssertFalse(result.isSuspend)
        } else {
            XCTFail("Expected functionType")
        }
    }

    func testMakeIntersectionType() {
        let ts = TypeSystem()
        let a = ts.make(.primitive(.int, .nonNull))
        let b = ts.make(.primitive(.string, .nonNull))
        let id = ts.make(.intersection([a, b]))
        if case .intersection(let parts) = ts.kind(of: id) {
            XCTAssertEqual(parts.count, 2)
            XCTAssertTrue(parts.contains(a))
            XCTAssertTrue(parts.contains(b))
        } else {
            XCTFail("Expected intersection")
        }
    }

    // MARK: - Subtyping

    func testSameTypeIsSubtype() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        XCTAssertTrue(ts.isSubtype(intType, intType))
    }

    func testNothingIsSubtypeOfEverything() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        XCTAssertTrue(ts.isSubtype(ts.nothingType, intType))
        XCTAssertTrue(ts.isSubtype(ts.nothingType, ts.anyType))
        XCTAssertTrue(ts.isSubtype(ts.nothingType, ts.nullableAnyType))
    }

    func testErrorIsSubtypeOfAnything() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        XCTAssertTrue(ts.isSubtype(ts.errorType, intType))
        XCTAssertTrue(ts.isSubtype(intType, ts.errorType))
    }

    func testEverythingIsSubtypeOfNullableAny() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        let nullableInt = ts.make(.primitive(.int, .nullable))
        XCTAssertTrue(ts.isSubtype(intType, ts.nullableAnyType))
        XCTAssertTrue(ts.isSubtype(nullableInt, ts.nullableAnyType))
    }

    func testNonNullIsSubtypeOfAny() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        XCTAssertTrue(ts.isSubtype(intType, ts.anyType))
    }

    func testNullableIsNotSubtypeOfNonNullAny() {
        let ts = TypeSystem()
        let nullableInt = ts.make(.primitive(.int, .nullable))
        XCTAssertFalse(ts.isSubtype(nullableInt, ts.anyType))
    }

    func testNonNullAnyIsSubtypeOfNullableAny() {
        let ts = TypeSystem()
        XCTAssertTrue(ts.isSubtype(ts.anyType, ts.nullableAnyType))
    }

    func testNullabilitySubtype() {
        let ts = TypeSystem()
        let nonNull = ts.make(.primitive(.int, .nonNull))
        let nullable = ts.make(.primitive(.int, .nullable))
        XCTAssertTrue(ts.isSubtype(nonNull, nullable))
        XCTAssertFalse(ts.isSubtype(nullable, nonNull))
    }

    func testDifferentPrimitivesNotSubtype() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        let stringType = ts.make(.primitive(.string, .nonNull))
        XCTAssertFalse(ts.isSubtype(intType, stringType))
    }

    func testFunctionSubtypingParamCountMismatch() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        let f1 = ts.make(.functionType(FunctionType(params: [intType], returnType: intType)))
        let f2 = ts.make(.functionType(FunctionType(params: [intType, intType], returnType: intType)))
        XCTAssertFalse(ts.isSubtype(f1, f2))
    }

    func testFunctionSubtypingSuspendMismatch() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        let suspendFn = ts.make(.functionType(FunctionType(params: [], returnType: intType, isSuspend: true)))
        let normalFn = ts.make(.functionType(FunctionType(params: [], returnType: intType, isSuspend: false)))
        XCTAssertFalse(ts.isSubtype(suspendFn, normalFn))
    }

    func testFunctionSubtypingReceiverMismatch() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        let withReceiver = ts.make(.functionType(FunctionType(receiver: intType, params: [], returnType: intType)))
        let withoutReceiver = ts.make(.functionType(FunctionType(params: [], returnType: intType)))
        XCTAssertFalse(ts.isSubtype(withReceiver, withoutReceiver))
    }

    func testFunctionSubtypingContravariantParams() {
        let ts = TypeSystem()
        let anyNonNull = ts.anyType
        let intType = ts.make(.primitive(.int, .nonNull))
        // (Any) -> Int <: (Int) -> Int  -- param contravariance
        let fAny = ts.make(.functionType(FunctionType(params: [anyNonNull], returnType: intType)))
        let fInt = ts.make(.functionType(FunctionType(params: [intType], returnType: intType)))
        XCTAssertTrue(ts.isSubtype(fAny, fInt))
        XCTAssertFalse(ts.isSubtype(fInt, fAny))
    }

    func testFunctionSubtypingCovariantReturn() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        let anyNonNull = ts.anyType
        // () -> Int <: () -> Any
        let fRetInt = ts.make(.functionType(FunctionType(params: [], returnType: intType)))
        let fRetAny = ts.make(.functionType(FunctionType(params: [], returnType: anyNonNull)))
        XCTAssertTrue(ts.isSubtype(fRetInt, fRetAny))
    }

    func testClassSubtypingWithNominalHierarchy() {
        let ts = TypeSystem()
        let parentSymbol = SymbolID(rawValue: 0)
        let childSymbol = SymbolID(rawValue: 1)
        ts.setNominalDirectSupertypes([parentSymbol], for: childSymbol)

        let parentType = ts.make(.classType(ClassType(classSymbol: parentSymbol)))
        let childType = ts.make(.classType(ClassType(classSymbol: childSymbol)))
        XCTAssertTrue(ts.isSubtype(childType, parentType))
        XCTAssertFalse(ts.isSubtype(parentType, childType))
    }

    func testIntersectionSubtypingAllPartsSubtype() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        let intersect = ts.make(.intersection([intType]))
        XCTAssertTrue(ts.isSubtype(intersect, ts.anyType))
    }

    func testSubtypeOfIntersectionContainsMatch() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        let intersect = ts.make(.intersection([intType, ts.anyType]))
        XCTAssertTrue(ts.isSubtype(intType, intersect))
    }

    // MARK: - LUB / GLB

    func testLubOfEmptyReturnsError() {
        let ts = TypeSystem()
        XCTAssertEqual(ts.lub([]), ts.errorType)
    }

    func testLubOfSingleTypeReturnsThatType() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        XCTAssertEqual(ts.lub([intType]), intType)
    }

    func testLubOfIdenticalTypesReturnsThatType() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        XCTAssertEqual(ts.lub([intType, intType, intType]), intType)
    }

    func testLubOfMixedTypesReturnsNullableAny() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        let stringType = ts.make(.primitive(.string, .nonNull))
        XCTAssertEqual(ts.lub([intType, stringType]), ts.nullableAnyType)
    }

    func testLubFiltersNothingAndError() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        XCTAssertEqual(ts.lub([intType, ts.nothingType]), intType)
        XCTAssertEqual(ts.lub([intType, ts.errorType]), intType)
    }

    func testLubOfOnlyNothingReturnsNothing() {
        let ts = TypeSystem()
        XCTAssertEqual(ts.lub([ts.nothingType]), ts.nothingType)
    }

    func testLubOfNullableTypesReturnsNullableAny() {
        let ts = TypeSystem()
        let nullableInt = ts.make(.primitive(.int, .nullable))
        let nullableString = ts.make(.primitive(.string, .nullable))
        XCTAssertEqual(ts.lub([nullableInt, nullableString]), ts.nullableAnyType)
    }

    func testGlbOfEmptyReturnsError() {
        let ts = TypeSystem()
        XCTAssertEqual(ts.glb([]), ts.errorType)
    }

    func testGlbOfIdenticalReturnsType() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        XCTAssertEqual(ts.glb([intType, intType]), intType)
    }

    func testGlbContainingNothingReturnsNothing() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        XCTAssertEqual(ts.glb([intType, ts.nothingType]), ts.nothingType)
    }

    func testGlbOfDifferentTypesReturnsIntersection() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        let stringType = ts.make(.primitive(.string, .nonNull))
        let result = ts.glb([intType, stringType])
        if case .intersection(let parts) = ts.kind(of: result) {
            XCTAssertEqual(parts.count, 2)
        } else {
            XCTFail("Expected intersection type from glb")
        }
    }

    // MARK: - Deprecated Aliases

    @available(*, deprecated)
    func testLeastUpperBoundCallsLub() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        XCTAssertEqual(ts.leastUpperBound([intType]), ts.lub([intType]))
    }

    @available(*, deprecated)
    func testGreatestLowerBoundCallsGlb() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        XCTAssertEqual(ts.greatestLowerBound([intType]), ts.glb([intType]))
    }

    // MARK: - Nominal Supertypes

    func testSetAndGetNominalDirectSupertypes() {
        let ts = TypeSystem()
        let sym = SymbolID(rawValue: 0)
        let parent = SymbolID(rawValue: 1)
        ts.setNominalDirectSupertypes([parent], for: sym)
        XCTAssertEqual(ts.directNominalSupertypes(for: sym), [parent])
    }

    func testDirectNominalSupertypesReturnsEmptyForUnknown() {
        let ts = TypeSystem()
        XCTAssertEqual(ts.directNominalSupertypes(for: SymbolID(rawValue: 99)), [])
    }

    func testSetNominalDirectSupertypesDeduplicates() {
        let ts = TypeSystem()
        let sym = SymbolID(rawValue: 0)
        let parent = SymbolID(rawValue: 1)
        ts.setNominalDirectSupertypes([parent, parent, parent], for: sym)
        XCTAssertEqual(ts.directNominalSupertypes(for: sym).count, 1)
    }

    // MARK: - Type Parameter Variances

    func testSetAndGetTypeParameterVariances() {
        let ts = TypeSystem()
        let sym = SymbolID(rawValue: 0)
        ts.setNominalTypeParameterVariances([.out, .in, .invariant], for: sym)
        XCTAssertEqual(ts.nominalTypeParameterVariances(for: sym), [.out, .in, .invariant])
    }

    func testTypeParameterVariancesReturnsEmptyForUnknown() {
        let ts = TypeSystem()
        XCTAssertEqual(ts.nominalTypeParameterVariances(for: SymbolID(rawValue: 42)), [])
    }

    // MARK: - renderType

    func testRenderTypeForBuiltIns() {
        let ts = TypeSystem()
        XCTAssertEqual(ts.renderType(ts.errorType), "<error>")
        XCTAssertEqual(ts.renderType(ts.unitType), "Unit")
        XCTAssertEqual(ts.renderType(ts.nothingType), "Nothing")
        XCTAssertEqual(ts.renderType(ts.anyType), "Any")
        XCTAssertEqual(ts.renderType(ts.nullableAnyType), "Any?")
    }

    func testRenderTypeForPrimitives() {
        let ts = TypeSystem()
        XCTAssertEqual(ts.renderType(ts.make(.primitive(.boolean, .nonNull))), "Boolean")
        XCTAssertEqual(ts.renderType(ts.make(.primitive(.char, .nonNull))), "Char")
        XCTAssertEqual(ts.renderType(ts.make(.primitive(.int, .nonNull))), "Int")
        XCTAssertEqual(ts.renderType(ts.make(.primitive(.long, .nonNull))), "Long")
        XCTAssertEqual(ts.renderType(ts.make(.primitive(.float, .nonNull))), "Float")
        XCTAssertEqual(ts.renderType(ts.make(.primitive(.double, .nonNull))), "Double")
        XCTAssertEqual(ts.renderType(ts.make(.primitive(.string, .nonNull))), "String")
    }

    func testRenderTypeNullablePrimitive() {
        let ts = TypeSystem()
        XCTAssertEqual(ts.renderType(ts.make(.primitive(.int, .nullable))), "Int?")
    }

    func testRenderTypeClassType() {
        let ts = TypeSystem()
        let ct = ts.make(.classType(ClassType(classSymbol: SymbolID(rawValue: 5))))
        XCTAssertTrue(ts.renderType(ct).contains("Class#5"))
    }

    func testRenderTypeClassTypeNullable() {
        let ts = TypeSystem()
        let ct = ts.make(.classType(ClassType(classSymbol: SymbolID(rawValue: 3), nullability: .nullable)))
        XCTAssertTrue(ts.renderType(ct).hasSuffix("?"))
    }

    func testRenderTypeTypeParam() {
        let ts = TypeSystem()
        let tp = ts.make(.typeParam(TypeParamType(symbol: SymbolID(rawValue: 7))))
        XCTAssertEqual(ts.renderType(tp), "T#7")
    }

    func testRenderTypeTypeParamNullable() {
        let ts = TypeSystem()
        let tp = ts.make(.typeParam(TypeParamType(symbol: SymbolID(rawValue: 2), nullability: .nullable)))
        XCTAssertEqual(ts.renderType(tp), "T#2?")
    }

    func testRenderTypeFunctionType() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        let ft = ts.make(.functionType(FunctionType(params: [intType], returnType: intType)))
        let rendered = ts.renderType(ft)
        XCTAssertTrue(rendered.contains("(Int) -> Int"))
    }

    func testRenderTypeSuspendFunctionType() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        let ft = ts.make(.functionType(FunctionType(params: [], returnType: intType, isSuspend: true)))
        let rendered = ts.renderType(ft)
        XCTAssertTrue(rendered.hasPrefix("suspend "))
    }

    func testRenderTypeFunctionTypeWithReceiver() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        let stringType = ts.make(.primitive(.string, .nonNull))
        let ft = ts.make(.functionType(FunctionType(receiver: stringType, params: [], returnType: intType)))
        let rendered = ts.renderType(ft)
        XCTAssertTrue(rendered.contains("String."))
    }

    func testRenderTypeIntersection() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        let stringType = ts.make(.primitive(.string, .nonNull))
        let inter = ts.make(.intersection([intType, stringType]))
        let rendered = ts.renderType(inter)
        XCTAssertTrue(rendered.contains(" & "))
    }

    func testRenderTypeClassTypeWithTypeArgs() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        let ct = ts.make(.classType(ClassType(
            classSymbol: SymbolID(rawValue: 0),
            args: [.invariant(intType), .out(intType), .in(intType), .star]
        )))
        let rendered = ts.renderType(ct)
        XCTAssertTrue(rendered.contains("out "))
        XCTAssertTrue(rendered.contains("in "))
        XCTAssertTrue(rendered.contains("*"))
    }

    // MARK: - substituteTypeParameters

    func testSubstituteTypeParameterReplacesMatching() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        let tpSym = SymbolID(rawValue: 0)
        let tp = ts.make(.typeParam(TypeParamType(symbol: tpSym)))

        let varMap = ts.makeTypeVarBySymbol([tpSym])
        let tv = varMap[tpSym]!
        let result = ts.substituteTypeParameters(
            in: tp,
            substitution: [tv: intType],
            typeVarBySymbol: varMap
        )
        XCTAssertEqual(result, intType)
    }

    func testSubstituteTypeParameterLeavesUnmatchedAlone() {
        let ts = TypeSystem()
        let tpSym = SymbolID(rawValue: 0)
        let otherSym = SymbolID(rawValue: 1)
        let tp = ts.make(.typeParam(TypeParamType(symbol: tpSym)))

        let varMap = ts.makeTypeVarBySymbol([otherSym])
        let result = ts.substituteTypeParameters(
            in: tp,
            substitution: [:],
            typeVarBySymbol: varMap
        )
        XCTAssertEqual(result, tp)
    }

    func testSubstituteInClassTypeArgs() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        let tpSym = SymbolID(rawValue: 0)
        let tp = ts.make(.typeParam(TypeParamType(symbol: tpSym)))

        let classSym = SymbolID(rawValue: 10)
        let classWithT = ts.make(.classType(ClassType(
            classSymbol: classSym,
            args: [.invariant(tp)]
        )))

        let varMap = ts.makeTypeVarBySymbol([tpSym])
        let tv = varMap[tpSym]!
        let result = ts.substituteTypeParameters(
            in: classWithT,
            substitution: [tv: intType],
            typeVarBySymbol: varMap
        )

        if case .classType(let ct) = ts.kind(of: result) {
            XCTAssertEqual(ct.args.count, 1)
            if case .invariant(let inner) = ct.args[0] {
                XCTAssertEqual(inner, intType)
            } else {
                XCTFail("Expected invariant type arg")
            }
        } else {
            XCTFail("Expected classType after substitution")
        }
    }

    func testSubstituteInFunctionType() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        let tpSym = SymbolID(rawValue: 0)
        let tp = ts.make(.typeParam(TypeParamType(symbol: tpSym)))

        let ft = ts.make(.functionType(FunctionType(params: [tp], returnType: tp)))
        let varMap = ts.makeTypeVarBySymbol([tpSym])
        let tv = varMap[tpSym]!
        let result = ts.substituteTypeParameters(
            in: ft,
            substitution: [tv: intType],
            typeVarBySymbol: varMap
        )

        if case .functionType(let resultFt) = ts.kind(of: result) {
            XCTAssertEqual(resultFt.params, [intType])
            XCTAssertEqual(resultFt.returnType, intType)
        } else {
            XCTFail("Expected functionType after substitution")
        }
    }

    func testSubstituteInIntersectionType() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        let tpSym = SymbolID(rawValue: 0)
        let tp = ts.make(.typeParam(TypeParamType(symbol: tpSym)))

        let inter = ts.make(.intersection([tp, ts.anyType]))
        let varMap = ts.makeTypeVarBySymbol([tpSym])
        let tv = varMap[tpSym]!
        let result = ts.substituteTypeParameters(
            in: inter,
            substitution: [tv: intType],
            typeVarBySymbol: varMap
        )

        if case .intersection(let parts) = ts.kind(of: result) {
            XCTAssertTrue(parts.contains(intType))
        } else {
            XCTFail("Expected intersection after substitution")
        }
    }

    func testSubstituteNoOpForPrimitive() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        let result = ts.substituteTypeParameters(in: intType, substitution: [:], typeVarBySymbol: [:])
        XCTAssertEqual(result, intType)
    }

    func testSubstituteClassTypeNoChangeReturnsSameID() {
        let ts = TypeSystem()
        let classSym = SymbolID(rawValue: 0)
        let intType = ts.make(.primitive(.int, .nonNull))
        let ct = ts.make(.classType(ClassType(classSymbol: classSym, args: [.invariant(intType)])))
        let result = ts.substituteTypeParameters(in: ct, substitution: [:], typeVarBySymbol: [:])
        XCTAssertEqual(result, ct)
    }

    // MARK: - makeTypeVarBySymbol

    func testMakeTypeVarBySymbolCreatesCorrectMapping() {
        let ts = TypeSystem()
        let syms = [SymbolID(rawValue: 10), SymbolID(rawValue: 20)]
        let mapping = ts.makeTypeVarBySymbol(syms)
        XCTAssertEqual(mapping.count, 2)
        XCTAssertEqual(mapping[syms[0]]?.rawValue, 0)
        XCTAssertEqual(mapping[syms[1]]?.rawValue, 1)
    }

    // MARK: - isNominalSubtypeSymbol

    func testIsNominalSubtypeSymbolTransitive() {
        let ts = TypeSystem()
        let grandparent = SymbolID(rawValue: 0)
        let parent = SymbolID(rawValue: 1)
        let child = SymbolID(rawValue: 2)
        ts.setNominalDirectSupertypes([grandparent], for: parent)
        ts.setNominalDirectSupertypes([parent], for: child)

        XCTAssertTrue(ts.isNominalSubtypeSymbol(child, of: grandparent))
        XCTAssertFalse(ts.isNominalSubtypeSymbol(grandparent, of: child))
    }

    func testIsNominalSubtypeSymbolSelf() {
        let ts = TypeSystem()
        let sym = SymbolID(rawValue: 0)
        XCTAssertTrue(ts.isNominalSubtypeSymbol(sym, of: sym))
    }

    // MARK: - normalizedNominalVariances

    func testNormalizedNominalVariancesPadsWithInvariant() {
        let ts = TypeSystem()
        let sym = SymbolID(rawValue: 0)
        ts.setNominalTypeParameterVariances([.out], for: sym)
        let variances = ts.normalizedNominalVariances(for: sym, arity: 3)
        XCTAssertEqual(variances, [.out, .invariant, .invariant])
    }

    func testNormalizedNominalVariancesEmptyReturnsAllInvariant() {
        let ts = TypeSystem()
        let sym = SymbolID(rawValue: 0)
        let variances = ts.normalizedNominalVariances(for: sym, arity: 2)
        XCTAssertEqual(variances, [.invariant, .invariant])
    }

    func testNormalizedNominalVariancesTruncatesExcess() {
        let ts = TypeSystem()
        let sym = SymbolID(rawValue: 0)
        ts.setNominalTypeParameterVariances([.out, .in, .invariant], for: sym)
        let variances = ts.normalizedNominalVariances(for: sym, arity: 2)
        XCTAssertEqual(variances, [.out, .in])
    }

    // MARK: - Class Subtyping with type args

    func testClassSubtypingWithStarProjection() {
        let ts = TypeSystem()
        let parentSym = SymbolID(rawValue: 0)
        let childSym = SymbolID(rawValue: 1)
        ts.setNominalDirectSupertypes([parentSym], for: childSym)

        let intType = ts.make(.primitive(.int, .nonNull))
        let child = ts.make(.classType(ClassType(classSymbol: childSym, args: [.invariant(intType)])))
        let parentStar = ts.make(.classType(ClassType(classSymbol: parentSym, args: [.star])))
        XCTAssertTrue(ts.isSubtype(child, parentStar))
    }

    func testClassSubtypingSameSymbolDifferentArgCount() {
        let ts = TypeSystem()
        let sym = SymbolID(rawValue: 0)
        let intType = ts.make(.primitive(.int, .nonNull))
        let withArg = ts.make(.classType(ClassType(classSymbol: sym, args: [.invariant(intType)])))
        let withoutArg = ts.make(.classType(ClassType(classSymbol: sym, args: [])))
        XCTAssertFalse(ts.isSubtype(withArg, withoutArg))
    }

    // MARK: - Projection Subtyping

    func testProjectionSubtypeStarAcceptsAll() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        XCTAssertTrue(ts.isProjectionSubtype(.invariant(intType), .star))
        XCTAssertTrue(ts.isProjectionSubtype(.out(intType), .star))
        XCTAssertTrue(ts.isProjectionSubtype(.in(intType), .star))
    }

    func testProjectionSubtypeInvalidRejectsBoth() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        XCTAssertFalse(ts.isProjectionSubtype(.invalid, .invariant(intType)))
        XCTAssertFalse(ts.isProjectionSubtype(.invariant(intType), .invalid))
    }

    func testProjectionSubtypeStarIsNotSubtypeOfConcrete() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        XCTAssertFalse(ts.isProjectionSubtype(.star, .invariant(intType)))
    }

    func testComposedProjectionOutVariance() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        let result = ts.composedProjection(declarationVariance: .out, useSite: .invariant(intType))
        if case .out(let t) = result {
            XCTAssertEqual(t, intType)
        } else {
            XCTFail("Expected .out projection")
        }
    }

    func testComposedProjectionInVariance() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        let result = ts.composedProjection(declarationVariance: .in, useSite: .invariant(intType))
        if case .in(let t) = result {
            XCTAssertEqual(t, intType)
        } else {
            XCTFail("Expected .in projection")
        }
    }

    func testComposedProjectionOutWithInReturnsInvalid() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        let result = ts.composedProjection(declarationVariance: .out, useSite: .in(intType))
        if case .invalid = result {
            // Expected
        } else {
            XCTFail("Expected .invalid from out + in")
        }
    }

    func testComposedProjectionInWithOutReturnsInvalid() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        let result = ts.composedProjection(declarationVariance: .in, useSite: .out(intType))
        if case .invalid = result {
            // Expected
        } else {
            XCTFail("Expected .invalid from in + out")
        }
    }
}
