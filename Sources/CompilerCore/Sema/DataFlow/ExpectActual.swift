import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

// MPP-001: Validate expect/actual declarations.
// In Kotlin MPP, an `expect` declaration in common code must be implemented by a
// corresponding `actual` declaration for the current compilation target.

extension DataFlowSemaPhase {
    func validateExpectActualMatching(
        ast _: ASTModule,
        symbols: SymbolTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) {
        // Only validate source declarations; imported library symbols may contain
        // expect/actual markers without requiring local counterparts.
        let expects = symbols.allSymbols().filter { sym in
            sym.flags.contains(.expectDeclaration) && sym.declSite != nil
        }

        for expectSym in expects {
            let candidates = symbols.lookupAll(fqName: expectSym.fqName)
                .compactMap { symbols.symbol($0) }
                .filter { actual in
                    guard actual.flags.contains(.actualDeclaration) else {
                        return false
                    }
                    return actual.kind == expectSym.kind
                        || (expectSym.kind == .annotationClass && actual.kind == .typeAlias)
                }
                .sorted(by: { $0.id.rawValue < $1.id.rawValue })

            let compatibleCandidates = candidates.filter { actual in
                areExpectActualCompatible(expect: expectSym, actual: actual, symbols: symbols, types: types)
            }

            let rendered = expectSym.fqName
                .map { interner.resolve($0) }
                .joined(separator: ".")

            guard let actualSym = compatibleCandidates.first else {
                // Enhanced diagnostic with detailed failure information
                let candidateCount = candidates.count
                let compatibleCount = compatibleCandidates.count
                
                var diagnosticMessage = "Missing matching 'actual' declaration for expect symbol '\(rendered)'."
                if candidateCount == 0 {
                    diagnosticMessage += " No actual candidates found with same FQ name."
                } else if compatibleCount == 0 {
                    diagnosticMessage += " Found \(candidateCount) actual candidates but none were compatible."
                }
                
                // Add debug information about candidates
                if !candidates.isEmpty {
                    let candidateKinds = candidates.map { "\($0.kind)" }.joined(separator: ", ")
                    diagnosticMessage += " Candidate kinds: [\(candidateKinds)]."
                }
                
                diagnostics.error(
                    "KSWIFTK-MPP-UNRESOLVED",
                    diagnosticMessage,
                    range: expectSym.declSite
                )
                continue
            }

            if compatibleCandidates.count > 1 {
                diagnostics.error(
                    "KSWIFTK-MPP-AMBIGUOUS",
                    "Multiple matching 'actual' declarations found for expect symbol '\(rendered)'.",
                    range: expectSym.declSite
                )
                continue
            }

            symbols.setExpectActualLink(expect: expectSym.id, actual: actualSym.id)
        }
    }

    private func areExpectActualCompatible(
        expect: SemanticSymbol,
        actual: SemanticSymbol,
        symbols: SymbolTable,
        types: TypeSystem
    ) -> Bool {
        if expect.kind == .annotationClass, actual.kind == .typeAlias {
            // Check if the typealias's underlying type points to an annotation class
            // Use retry mechanism for robust resolution in concurrent environments
            let underlyingType = getTypeAliasUnderlyingTypeWithRetry(
                for: actual.id,
                symbols: symbols,
                maxRetries: 3,
                baseDelay: 0.001
            )
            
            guard let resolvedType = underlyingType else {
                return false
            }
            
            // The underlying type should be a class type pointing to an annotation class
            if case let .classType(classType) = types.kind(of: resolvedType) {
                guard classType.nullability == .nonNull,
                      let underlyingSymbol = symbols.symbol(classType.classSymbol)
                else {
                    return false
                }
                // The underlying symbol should be an annotation class
                return underlyingSymbol.kind == .annotationClass
            }
            return false
        }

        switch expect.kind {
        case .function, .constructor:
            guard let expectSig = symbols.functionSignature(for: expect.id),
                  let actualSig = symbols.functionSignature(for: actual.id)
            else {
                return false
            }
            return expectActualFunctionSignaturesMatch(
                expectSig: expectSig,
                expectSymbol: expect,
                actualSig: actualSig,
                actualSymbol: actual,
                symbols: symbols,
                types: types
            )

        case .property, .field:
            guard let expectType = symbols.propertyType(for: expect.id),
                  let actualType = symbols.propertyType(for: actual.id)
            else {
                return false
            }
            let typeParamMapping = makeOwnerTypeParameterMapping(
                expect: expect,
                actual: actual,
                symbols: symbols,
                types: types
            )
            return expect.flags.contains(.mutable) == actual.flags.contains(.mutable)
                && expectActualTypesMatch(
                    expectType,
                    actualType,
                    typeParamMapping: typeParamMapping,
                    symbols: symbols,
                    types: types
                )

        case .class, .interface, .object, .enumClass, .annotationClass:
            // Check type parameter count matches
            let expectTPs = types.nominalTypeParameterSymbols(for: expect.id)
            let actualTPs = types.nominalTypeParameterSymbols(for: actual.id)
            guard expectTPs.count == actualTPs.count else { return false }
            let typeParamMapping = Dictionary(uniqueKeysWithValues: zip(expectTPs, actualTPs))
            // Check each type parameter's variance and upper bounds match
            let expectVariances = types.nominalTypeParameterVariances(for: expect.id)
            let actualVariances = types.nominalTypeParameterVariances(for: actual.id)
            for (index, (eTP, aTP)) in zip(expectTPs, actualTPs).enumerated() {
                let eVar = index < expectVariances.count ? expectVariances[index] : TypeVariance.invariant
                let aVar = index < actualVariances.count ? actualVariances[index] : TypeVariance.invariant
                guard eVar == aVar else { return false }
                guard expectActualTypeListsMatch(
                    symbols.typeParameterUpperBounds(for: eTP),
                    symbols.typeParameterUpperBounds(for: aTP),
                    typeParamMapping: typeParamMapping,
                    symbols: symbols,
                    types: types
                ) else {
                    return false
                }
            }
            let expectSupertypes = symbols.directSupertypes(for: expect.id)
            let actualSupertypes = symbols.directSupertypes(for: actual.id)
            guard expectSupertypes.count == actualSupertypes.count else {
                return false
            }
            for (expectSuper, actualSuper) in zip(expectSupertypes, actualSupertypes) {
                guard expectActualNominalSymbolsMatch(expectSuper, actualSuper, symbols: symbols) else {
                    return false
                }
                let expectArgs = types.nominalSupertypeTypeArgs(for: expect.id, supertype: expectSuper)
                let actualArgs = types.nominalSupertypeTypeArgs(for: actual.id, supertype: actualSuper)
                guard expectActualTypeArgsMatch(
                    expectArgs,
                    actualArgs,
                    typeParamMapping: typeParamMapping,
                    symbols: symbols,
                    types: types
                ) else {
                    return false
                }
            }
            return expect.flags.contains(.valueType) == actual.flags.contains(.valueType)

        case .typeAlias:
            // Check underlying types match
            let expectTPs = symbols.typeAliasTypeParameters(for: expect.id)
            let actualTPs = symbols.typeAliasTypeParameters(for: actual.id)
            guard expectTPs.count == actualTPs.count else {
                return false
            }
            let typeParamMapping = Dictionary(uniqueKeysWithValues: zip(expectTPs, actualTPs))
            guard expectActualTypeBoundListsMatch(
                expectTPs.map { symbols.typeParameterUpperBounds(for: $0) },
                actualTPs.map { symbols.typeParameterUpperBounds(for: $0) },
                typeParamMapping: typeParamMapping,
                symbols: symbols,
                types: types
            ) else {
                return false
            }
            guard let expectUnderlying = symbols.typeAliasUnderlyingType(for: expect.id),
                  let actualUnderlying = symbols.typeAliasUnderlyingType(for: actual.id)
            else {
                return false
            }
            return expectActualTypesMatch(
                expectUnderlying,
                actualUnderlying,
                typeParamMapping: typeParamMapping,
                symbols: symbols,
                types: types
            )

        case .package:
            return true

        case .typeParameter:
            return false

        case .backingField, .valueParameter, .local, .label:
            // These symbol kinds are not meaningful as expect/actual declarations.
            return false
        }
    }

    private func expectActualFunctionSignaturesMatch(
        expectSig: FunctionSignature,
        expectSymbol: SemanticSymbol,
        actualSig: FunctionSignature,
        actualSymbol: SemanticSymbol,
        symbols: SymbolTable,
        types: TypeSystem
    ) -> Bool {
        guard expectSig.parameterTypes.count == actualSig.parameterTypes.count,
              expectSig.isSuspend == actualSig.isSuspend,
              expectSig.valueParameterIsVararg == actualSig.valueParameterIsVararg,
              expectSig.reifiedTypeParameterIndices == actualSig.reifiedTypeParameterIndices,
              expectSig.classTypeParameterCount == actualSig.classTypeParameterCount
        else {
            return false
        }

        var typeParamMapping = makeOwnerTypeParameterMapping(
            expect: expectSymbol,
            actual: actualSymbol,
            symbols: symbols,
            types: types
        )

        guard expectSig.typeParameterSymbols.count == actualSig.typeParameterSymbols.count else {
            return false
        }
        for (expectTP, actualTP) in zip(expectSig.typeParameterSymbols, actualSig.typeParameterSymbols) {
            typeParamMapping[expectTP] = actualTP
        }

        guard expectActualOptionalTypeListsMatch(
            expectSig.typeParameterUpperBounds,
            actualSig.typeParameterUpperBounds,
            typeParamMapping: typeParamMapping,
            symbols: symbols,
            types: types
        ), expectActualTypeBoundListsMatch(
            expectSig.typeParameterUpperBoundsList,
            actualSig.typeParameterUpperBoundsList,
            typeParamMapping: typeParamMapping,
            symbols: symbols,
            types: types
        ) else {
            return false
        }

        guard expectActualOptionalTypeMatch(
            expectSig.receiverType,
            actualSig.receiverType,
            typeParamMapping: typeParamMapping,
            symbols: symbols,
            types: types
        ), expectActualTypeListsMatch(
            expectSig.parameterTypes,
            actualSig.parameterTypes,
            typeParamMapping: typeParamMapping,
            symbols: symbols,
            types: types
        ) else {
            return false
        }

        return expectActualTypesMatch(
            expectSig.returnType,
            actualSig.returnType,
            typeParamMapping: typeParamMapping,
            symbols: symbols,
            types: types
        )
    }

    private func makeOwnerTypeParameterMapping(
        expect: SemanticSymbol,
        actual: SemanticSymbol,
        symbols: SymbolTable,
        types: TypeSystem
    ) -> [SymbolID: SymbolID] {
        guard let expectOwner = symbols.parentSymbol(for: expect.id),
              let actualOwner = symbols.parentSymbol(for: actual.id),
              expectActualNominalSymbolsMatch(expectOwner, actualOwner, symbols: symbols)
        else {
            return [:]
        }

        let expectParams = types.nominalTypeParameterSymbols(for: expectOwner)
        let actualParams = types.nominalTypeParameterSymbols(for: actualOwner)
        guard expectParams.count == actualParams.count else {
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: zip(expectParams, actualParams))
    }

    private func expectActualTypeListsMatch(
        _ expectTypes: [TypeID],
        _ actualTypes: [TypeID],
        typeParamMapping: [SymbolID: SymbolID],
        symbols: SymbolTable,
        types: TypeSystem
    ) -> Bool {
        guard expectTypes.count == actualTypes.count else {
            return false
        }
        for (expectType, actualType) in zip(expectTypes, actualTypes) {
            guard expectActualTypesMatch(
                expectType,
                actualType,
                typeParamMapping: typeParamMapping,
                symbols: symbols,
                types: types
            ) else {
                return false
            }
        }
        return true
    }

    private func expectActualTypeBoundListsMatch(
        _ expectBounds: [[TypeID]],
        _ actualBounds: [[TypeID]],
        typeParamMapping: [SymbolID: SymbolID],
        symbols: SymbolTable,
        types: TypeSystem
    ) -> Bool {
        guard expectBounds.count == actualBounds.count else {
            return false
        }
        for (expectList, actualList) in zip(expectBounds, actualBounds) {
            guard expectActualTypeListsMatch(
                expectList,
                actualList,
                typeParamMapping: typeParamMapping,
                symbols: symbols,
                types: types
            ) else {
                return false
            }
        }
        return true
    }

    private func expectActualOptionalTypeListsMatch(
        _ expectTypes: [TypeID?],
        _ actualTypes: [TypeID?],
        typeParamMapping: [SymbolID: SymbolID],
        symbols: SymbolTable,
        types: TypeSystem
    ) -> Bool {
        guard expectTypes.count == actualTypes.count else {
            return false
        }
        for (expectType, actualType) in zip(expectTypes, actualTypes) {
            guard expectActualOptionalTypeMatch(
                expectType,
                actualType,
                typeParamMapping: typeParamMapping,
                symbols: symbols,
                types: types
            ) else {
                return false
            }
        }
        return true
    }

    private func expectActualOptionalTypeMatch(
        _ expectType: TypeID?,
        _ actualType: TypeID?,
        typeParamMapping: [SymbolID: SymbolID],
        symbols: SymbolTable,
        types: TypeSystem
    ) -> Bool {
        switch (expectType, actualType) {
        case (.none, .none):
            true
        case let (.some(expectType), .some(actualType)):
            expectActualTypesMatch(
                expectType,
                actualType,
                typeParamMapping: typeParamMapping,
                symbols: symbols,
                types: types
            )
        default:
            false
        }
    }

    private func expectActualTypeArgsMatch(
        _ expectArgs: [TypeArg],
        _ actualArgs: [TypeArg],
        typeParamMapping: [SymbolID: SymbolID],
        symbols: SymbolTable,
        types: TypeSystem
    ) -> Bool {
        guard expectArgs.count == actualArgs.count else {
            return false
        }

        for (expectArg, actualArg) in zip(expectArgs, actualArgs) {
            switch (expectArg, actualArg) {
            case (.star, .star):
                continue
            case let (.invariant(expectType), .invariant(actualType)),
                 let (.out(expectType), .out(actualType)),
                 let (.in(expectType), .in(actualType)):
                guard expectActualTypesMatch(
                    expectType,
                    actualType,
                    typeParamMapping: typeParamMapping,
                    symbols: symbols,
                    types: types
                ) else {
                    return false
                }
            default:
                return false
            }
        }

        return true
    }

    private func expectActualTypesMatch(
        _ expectType: TypeID,
        _ actualType: TypeID,
        typeParamMapping: [SymbolID: SymbolID],
        symbols: SymbolTable,
        types: TypeSystem
    ) -> Bool {
        switch (types.kind(of: expectType), types.kind(of: actualType)) {
        case (.error, .error), (.unit, .unit):
            return true

        case let (.nothing(expectNullability), .nothing(actualNullability)):
            return expectNullability == actualNullability

        case let (.any(expectNullability), .any(actualNullability)):
            return expectNullability == actualNullability

        case let (.primitive(expectPrimitive, expectNullability), .primitive(actualPrimitive, actualNullability)):
            return expectPrimitive == actualPrimitive && expectNullability == actualNullability

        case let (.typeParam(expectParam), .typeParam(actualParam)):
            let mapped = typeParamMapping[expectParam.symbol] ?? expectParam.symbol
            return mapped == actualParam.symbol && expectParam.nullability == actualParam.nullability

        case let (.classType(expectClass), .classType(actualClass)):
            return expectClass.nullability == actualClass.nullability
                && expectActualNominalSymbolsMatch(expectClass.classSymbol, actualClass.classSymbol, symbols: symbols)
                && expectActualTypeArgsMatch(
                    expectClass.args,
                    actualClass.args,
                    typeParamMapping: typeParamMapping,
                    symbols: symbols,
                    types: types
                )

        case let (.functionType(expectFunction), .functionType(actualFunction)):
            return expectFunction.isSuspend == actualFunction.isSuspend
                && expectFunction.nullability == actualFunction.nullability
                && expectActualTypeListsMatch(
                    expectFunction.contextReceivers,
                    actualFunction.contextReceivers,
                    typeParamMapping: typeParamMapping,
                    symbols: symbols,
                    types: types
                )
                && expectActualOptionalTypeMatch(
                    expectFunction.receiver,
                    actualFunction.receiver,
                    typeParamMapping: typeParamMapping,
                    symbols: symbols,
                    types: types
                )
                && expectActualTypeListsMatch(
                    expectFunction.params,
                    actualFunction.params,
                    typeParamMapping: typeParamMapping,
                    symbols: symbols,
                    types: types
                )
                && expectActualTypesMatch(
                    expectFunction.returnType,
                    actualFunction.returnType,
                    typeParamMapping: typeParamMapping,
                    symbols: symbols,
                    types: types
                )

        case let (.kClassType(expectKClass), .kClassType(actualKClass)):
            return expectKClass.nullability == actualKClass.nullability
                && expectActualTypesMatch(
                    expectKClass.argument,
                    actualKClass.argument,
                    typeParamMapping: typeParamMapping,
                    symbols: symbols,
                    types: types
                )

        case let (.intersection(expectParts), .intersection(actualParts)):
            return expectActualTypeListsMatch(
                expectParts,
                actualParts,
                typeParamMapping: typeParamMapping,
                symbols: symbols,
                types: types
            )

        default:
            return false
        }
    }
    
    /// Retry mechanism for getting typealias underlying type with exponential backoff
    private func getTypeAliasUnderlyingTypeWithRetry(
        for symbol: SymbolID,
        symbols: SymbolTable,
        maxRetries: Int,
        baseDelay: TimeInterval
    ) -> TypeID? {
        for attempt in 0..<maxRetries {
            if let underlyingType = symbols.typeAliasUnderlyingType(for: symbol) {
                return underlyingType
            }
            
            // In CI environments, use shorter delays to avoid timing issues
            if attempt < maxRetries - 1 {
                // Minimal delay for CI environments with exponential backoff
                let delay = baseDelay * pow(2.0, Double(attempt))
                Thread.sleep(forTimeInterval: delay)
            }
        }
        return nil
    }

    private func expectActualNominalSymbolsMatch(
        _ expectSymbolID: SymbolID,
        _ actualSymbolID: SymbolID,
        symbols: SymbolTable
    ) -> Bool {
        guard let expectSymbol = symbols.symbol(expectSymbolID),
              let actualSymbol = symbols.symbol(actualSymbolID)
        else {
            return false
        }
        return expectSymbol.kind == actualSymbol.kind && expectSymbol.fqName == actualSymbol.fqName
    }
}
