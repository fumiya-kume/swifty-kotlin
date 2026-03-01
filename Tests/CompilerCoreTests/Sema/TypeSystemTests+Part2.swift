@testable import CompilerCore
import XCTest

extension TypeSystemTests {
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

    func testSubstituteTypeParameterReplacesMatching() throws {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        let tpSym = SymbolID(rawValue: 0)
        let tp = ts.make(.typeParam(TypeParamType(symbol: tpSym)))

        let varMap = ts.makeTypeVarBySymbol([tpSym])
        let tv = try XCTUnwrap(varMap[tpSym])
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

    func testSubstituteInClassTypeArgs() throws {
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
        let tv = try XCTUnwrap(varMap[tpSym])
        let result = ts.substituteTypeParameters(
            in: classWithT,
            substitution: [tv: intType],
            typeVarBySymbol: varMap
        )

        if case let .classType(ct) = ts.kind(of: result) {
            XCTAssertEqual(ct.args.count, 1)
            if case let .invariant(inner) = ct.args[0] {
                XCTAssertEqual(inner, intType)
            } else {
                XCTFail("Expected invariant type arg")
            }
        } else {
            XCTFail("Expected classType after substitution")
        }
    }

    func testSubstituteInFunctionType() throws {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        let tpSym = SymbolID(rawValue: 0)
        let tp = ts.make(.typeParam(TypeParamType(symbol: tpSym)))

        let ft = ts.make(.functionType(FunctionType(params: [tp], returnType: tp)))
        let varMap = ts.makeTypeVarBySymbol([tpSym])
        let tv = try XCTUnwrap(varMap[tpSym])
        let result = ts.substituteTypeParameters(
            in: ft,
            substitution: [tv: intType],
            typeVarBySymbol: varMap
        )

        if case let .functionType(resultFt) = ts.kind(of: result) {
            XCTAssertEqual(resultFt.params, [intType])
            XCTAssertEqual(resultFt.returnType, intType)
        } else {
            XCTFail("Expected functionType after substitution")
        }
    }

    func testSubstituteInIntersectionType() throws {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        let tpSym = SymbolID(rawValue: 0)
        let tp = ts.make(.typeParam(TypeParamType(symbol: tpSym)))

        let inter = ts.make(.intersection([tp, ts.anyType]))
        let varMap = ts.makeTypeVarBySymbol([tpSym])
        let tv = try XCTUnwrap(varMap[tpSym])
        let result = ts.substituteTypeParameters(
            in: inter,
            substitution: [tv: intType],
            typeVarBySymbol: varMap
        )

        if case let .intersection(parts) = ts.kind(of: result) {
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
        if case let .out(t) = result {
            XCTAssertEqual(t, intType)
        } else {
            XCTFail("Expected .out projection")
        }
    }

    func testComposedProjectionInVariance() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        let result = ts.composedProjection(declarationVariance: .in, useSite: .invariant(intType))
        if case let .in(t) = result {
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
