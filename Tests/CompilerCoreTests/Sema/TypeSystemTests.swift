@testable import CompilerCore
import XCTest

final class TypeSystemTests: XCTestCase {
    // MARK: - Built-in Types

    func testBuiltInTypesArePreInitialized() {
        let ts = TypeSystem()
        XCTAssertEqual(ts.kind(of: ts.errorType), .error)
        XCTAssertEqual(ts.kind(of: ts.unitType), .unit)
        XCTAssertEqual(ts.kind(of: ts.nothingType), .nothing(.nonNull))
        XCTAssertEqual(ts.kind(of: ts.nullableNothingType), .nothing(.nullable))
        XCTAssertEqual(ts.kind(of: ts.anyType), .any(.nonNull))
        XCTAssertEqual(ts.kind(of: ts.nullableAnyType), .any(.nullable))
        // makeNullable / makeNonNullable round-trip for Nothing
        XCTAssertEqual(ts.makeNullable(ts.nothingType), ts.nullableNothingType)
        XCTAssertEqual(ts.makeNonNullable(ts.nullableNothingType), ts.nothingType)
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
        if case let .classType(ct) = ts.kind(of: id) {
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
        if case let .typeParam(result) = ts.kind(of: id) {
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
        if case let .functionType(result) = ts.kind(of: id) {
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
        if case let .intersection(parts) = ts.kind(of: id) {
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
        if case let .intersection(parts) = ts.kind(of: result) {
            XCTAssertEqual(parts.count, 2)
        } else {
            XCTFail("Expected intersection type from glb")
        }
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

    // MARK: - Platform Type (T!)

    func testPlatformTypeMakeAndKind() {
        let ts = TypeSystem()
        let platformInt = ts.make(.primitive(.int, .platformType))
        XCTAssertEqual(ts.kind(of: platformInt), .primitive(.int, .platformType))
    }

    func testPlatformTypeNullabilityOf() {
        let ts = TypeSystem()
        let platformInt = ts.make(.primitive(.int, .platformType))
        XCTAssertEqual(ts.nullability(of: platformInt), .platformType)
    }

    func testPlatformTypeIsSubtypeOfNonNull() {
        let ts = TypeSystem()
        let platformInt = ts.make(.primitive(.int, .platformType))
        let nonNullInt = ts.make(.primitive(.int, .nonNull))
        XCTAssertTrue(ts.isSubtype(platformInt, nonNullInt))
    }

    func testPlatformTypeIsSubtypeOfNullable() {
        let ts = TypeSystem()
        let platformInt = ts.make(.primitive(.int, .platformType))
        let nullableInt = ts.make(.primitive(.int, .nullable))
        XCTAssertTrue(ts.isSubtype(platformInt, nullableInt))
    }

    func testNonNullIsSubtypeOfPlatformType() {
        let ts = TypeSystem()
        let nonNullInt = ts.make(.primitive(.int, .nonNull))
        let platformInt = ts.make(.primitive(.int, .platformType))
        XCTAssertTrue(ts.isSubtype(nonNullInt, platformInt))
    }

    func testNullableIsSubtypeOfPlatformType() {
        let ts = TypeSystem()
        let nullableInt = ts.make(.primitive(.int, .nullable))
        let platformInt = ts.make(.primitive(.int, .platformType))
        XCTAssertTrue(ts.isSubtype(nullableInt, platformInt))
    }

    func testPlatformTypeIsNotDefinitelyNonNull() {
        let ts = TypeSystem()
        let platformInt = ts.make(.primitive(.int, .platformType))
        XCTAssertFalse(ts.isDefinitelyNonNull(platformInt))
    }

    func testWithNullabilityPlatformType() {
        let ts = TypeSystem()
        let platformAny = ts.withNullability(.platformType, for: ts.anyType)
        XCTAssertEqual(ts.nullability(of: platformAny), .platformType)
    }

    func testMakeNullableOnPlatformType() {
        let ts = TypeSystem()
        let platformInt = ts.make(.primitive(.int, .platformType))
        let nullableInt = ts.makeNullable(platformInt)
        XCTAssertEqual(ts.nullability(of: nullableInt), .nullable)
    }
}
