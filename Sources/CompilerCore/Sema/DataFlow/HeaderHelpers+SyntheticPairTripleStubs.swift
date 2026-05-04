import Foundation

/// Synthetic stdlib stubs split from `HeaderHelpers+SyntheticComparableAndCollectionStubs.swift`:
/// Pair<A,B> and Triple<A,B,C> classes plus the toList() return-type patch.
///
/// Split out to isolate merge conflicts between parallel stdlib PRs adding new
/// entries to this package.
extension DataFlowSemaPhase {

    func registerSyntheticPairStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let pairFQName: [InternedString] = [interner.intern("kotlin"), interner.intern("Pair")]
        let pairName = interner.intern("Pair")
        let pairSymbol: SymbolID = if let existing = symbols.lookup(fqName: pairFQName) {
            existing
        } else {
            symbols.define(
                kind: .class,
                name: pairName,
                fqName: pairFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }

        let firstName = interner.intern("A")
        let secondName = interner.intern("B")
        let firstSymbol = symbols.lookup(fqName: pairFQName + [firstName]) ?? symbols.define(
            kind: .typeParameter,
            name: firstName,
            fqName: pairFQName + [firstName],
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let secondSymbol = symbols.lookup(fqName: pairFQName + [secondName]) ?? symbols.define(
            kind: .typeParameter,
            name: secondName,
            fqName: pairFQName + [secondName],
            declSite: nil,
            visibility: .private,
            flags: []
        )
        types.setNominalTypeParameterSymbols([firstSymbol, secondSymbol], for: pairSymbol)
        types.setNominalTypeParameterVariances([.out, .out], for: pairSymbol)

        let firstType = types.make(.typeParam(TypeParamType(symbol: firstSymbol, nullability: .nonNull)))
        let secondType = types.make(.typeParam(TypeParamType(symbol: secondSymbol, nullability: .nonNull)))
        let pairType = types.make(.classType(ClassType(
            classSymbol: pairSymbol,
            args: [.out(firstType), .out(secondType)],
            nullability: .nonNull
        )))

        func registerFunctionMember(
            name: String,
            returnType: TypeID,
            externalLinkName: String,
            flags: SymbolFlags
        ) {
            let memberName = interner.intern(name)
            let memberFQName = pairFQName + [memberName]
            guard symbols.lookup(fqName: memberFQName) == nil else { return }
            let memberSymbol = symbols.define(
                kind: .function,
                name: memberName,
                fqName: memberFQName,
                declSite: nil,
                visibility: .public,
                flags: flags
            )
            symbols.setParentSymbol(pairSymbol, for: memberSymbol)
            symbols.setExternalLinkName(externalLinkName, for: memberSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: pairType,
                    parameterTypes: [],
                    returnType: returnType,
                    typeParameterSymbols: [firstSymbol, secondSymbol],
                    classTypeParameterCount: 2
                ),
                for: memberSymbol
            )
        }

        func registerPropertyMember(name: String, propertyType: TypeID, externalLinkName: String) {
            let memberName = interner.intern(name)
            let memberFQName = pairFQName + [memberName]
            guard symbols.lookup(fqName: memberFQName) == nil else { return }
            let memberSymbol = symbols.define(
                kind: .property,
                name: memberName,
                fqName: memberFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(pairSymbol, for: memberSymbol)
            symbols.setExternalLinkName(externalLinkName, for: memberSymbol)
            symbols.setPropertyType(propertyType, for: memberSymbol)
        }

        // Constructor: Pair(first: A, second: B) -> Pair<A, B>
        let initName = interner.intern("<init>")
        let initFQName = pairFQName + [initName]
        if symbols.lookup(fqName: initFQName) == nil {
            let initSymbol = symbols.define(
                kind: .constructor,
                name: initName,
                fqName: initFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(pairSymbol, for: initSymbol)
            symbols.setExternalLinkName("kk_pair_new", for: initSymbol)

            let firstParamName = interner.intern("first")
            let firstParamSymbol = symbols.define(
                kind: .valueParameter,
                name: firstParamName,
                fqName: initFQName + [firstParamName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(initSymbol, for: firstParamSymbol)

            let secondParamName = interner.intern("second")
            let secondParamSymbol = symbols.define(
                kind: .valueParameter,
                name: secondParamName,
                fqName: initFQName + [secondParamName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(initSymbol, for: secondParamSymbol)

            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: nil,
                    parameterTypes: [firstType, secondType],
                    returnType: pairType,
                    valueParameterSymbols: [firstParamSymbol, secondParamSymbol],
                    valueParameterHasDefaultValues: [false, false],
                    valueParameterIsVararg: [false, false],
                    typeParameterSymbols: [firstSymbol, secondSymbol],
                    classTypeParameterCount: 2
                ),
                for: initSymbol
            )
        }

        registerFunctionMember(
            name: "component1",
            returnType: firstType,
            externalLinkName: "kk_pair_first",
            flags: [.synthetic, .operatorFunction]
        )
        registerFunctionMember(
            name: "component2",
            returnType: secondType,
            externalLinkName: "kk_pair_second",
            flags: [.synthetic, .operatorFunction]
        )
        registerPropertyMember(name: "first", propertyType: firstType, externalLinkName: "kk_pair_first")
        registerPropertyMember(name: "second", propertyType: secondType, externalLinkName: "kk_pair_second")

        // Pair<A,B>.toString() → kk_pair_to_string
        registerFunctionMember(
            name: "toString",
            returnType: types.stringType,
            externalLinkName: "kk_pair_to_string",
            flags: [.synthetic]
        )

        // Pair<A,B>.toList() returns List<Any?> in Kotlin (elements can be nullable).
        // The List symbol is registered after Pair, so we initially use nullable anyType
        // as a placeholder; patchPairTripleToListReturnTypes() refines this to List<Any?>.
        registerFunctionMember(
            name: "toList",
            returnType: types.makeNullable(types.anyType),
            externalLinkName: "kk_pair_toList",
            flags: [.synthetic]
        )

    }

    func registerSyntheticTripleStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let tripleFQName: [InternedString] = [interner.intern("kotlin"), interner.intern("Triple")]
        let tripleName = interner.intern("Triple")
        let tripleSymbol: SymbolID = if let existing = symbols.lookup(fqName: tripleFQName) {
            existing
        } else {
            symbols.define(
                kind: .class, name: tripleName, fqName: tripleFQName,
                declSite: nil, visibility: .public, flags: [.synthetic]
            )
        }

        let aName = interner.intern("A")
        let bName = interner.intern("B")
        let cName = interner.intern("C")
        let aSymbol = symbols.lookup(fqName: tripleFQName + [aName]) ?? symbols.define(
            kind: .typeParameter, name: aName, fqName: tripleFQName + [aName],
            declSite: nil, visibility: .private, flags: []
        )
        let bSymbol = symbols.lookup(fqName: tripleFQName + [bName]) ?? symbols.define(
            kind: .typeParameter, name: bName, fqName: tripleFQName + [bName],
            declSite: nil, visibility: .private, flags: []
        )
        let cSymbol = symbols.lookup(fqName: tripleFQName + [cName]) ?? symbols.define(
            kind: .typeParameter, name: cName, fqName: tripleFQName + [cName],
            declSite: nil, visibility: .private, flags: []
        )
        types.setNominalTypeParameterSymbols([aSymbol, bSymbol, cSymbol], for: tripleSymbol)
        types.setNominalTypeParameterVariances([.out, .out, .out], for: tripleSymbol)

        let aType = types.make(.typeParam(TypeParamType(symbol: aSymbol, nullability: .nonNull)))
        let bType = types.make(.typeParam(TypeParamType(symbol: bSymbol, nullability: .nonNull)))
        let cType = types.make(.typeParam(TypeParamType(symbol: cSymbol, nullability: .nonNull)))
        let tripleType = types.make(.classType(ClassType(
            classSymbol: tripleSymbol,
            args: [.out(aType), .out(bType), .out(cType)],
            nullability: .nonNull
        )))

        func registerFunctionMember(
            name: String, returnType: TypeID, externalLinkName: String, flags: SymbolFlags
        ) {
            let memberName = interner.intern(name)
            let memberFQName = tripleFQName + [memberName]
            guard symbols.lookup(fqName: memberFQName) == nil else { return }
            let memberSymbol = symbols.define(
                kind: .function, name: memberName, fqName: memberFQName,
                declSite: nil, visibility: .public, flags: flags
            )
            symbols.setParentSymbol(tripleSymbol, for: memberSymbol)
            symbols.setExternalLinkName(externalLinkName, for: memberSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: tripleType, parameterTypes: [], returnType: returnType,
                    typeParameterSymbols: [aSymbol, bSymbol, cSymbol], classTypeParameterCount: 3
                ),
                for: memberSymbol
            )
        }

        func registerPropertyMember(name: String, propertyType: TypeID, externalLinkName: String) {
            let memberName = interner.intern(name)
            let memberFQName = tripleFQName + [memberName]
            guard symbols.lookup(fqName: memberFQName) == nil else { return }
            let memberSymbol = symbols.define(
                kind: .property, name: memberName, fqName: memberFQName,
                declSite: nil, visibility: .public, flags: [.synthetic]
            )
            symbols.setParentSymbol(tripleSymbol, for: memberSymbol)
            symbols.setExternalLinkName(externalLinkName, for: memberSymbol)
            symbols.setPropertyType(propertyType, for: memberSymbol)
        }

        // Constructor: Triple(first: A, second: B, third: C) -> Triple<A, B, C>
        let initName = interner.intern("<init>")
        let initFQName = tripleFQName + [initName]
        if symbols.lookup(fqName: initFQName) == nil {
            let initSymbol = symbols.define(
                kind: .constructor,
                name: initName,
                fqName: initFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(tripleSymbol, for: initSymbol)
            symbols.setExternalLinkName("kk_triple_new", for: initSymbol)

            let firstParamName = interner.intern("first")
            let firstParamSymbol = symbols.define(
                kind: .valueParameter,
                name: firstParamName,
                fqName: initFQName + [firstParamName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(initSymbol, for: firstParamSymbol)

            let secondParamName = interner.intern("second")
            let secondParamSymbol = symbols.define(
                kind: .valueParameter,
                name: secondParamName,
                fqName: initFQName + [secondParamName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(initSymbol, for: secondParamSymbol)

            let thirdParamName = interner.intern("third")
            let thirdParamSymbol = symbols.define(
                kind: .valueParameter,
                name: thirdParamName,
                fqName: initFQName + [thirdParamName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(initSymbol, for: thirdParamSymbol)

            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: nil,
                    parameterTypes: [aType, bType, cType],
                    returnType: tripleType,
                    valueParameterSymbols: [firstParamSymbol, secondParamSymbol, thirdParamSymbol],
                    valueParameterHasDefaultValues: [false, false, false],
                    valueParameterIsVararg: [false, false, false],
                    typeParameterSymbols: [aSymbol, bSymbol, cSymbol],
                    classTypeParameterCount: 3
                ),
                for: initSymbol
            )
        }

        registerFunctionMember(name: "component1", returnType: aType, externalLinkName: "kk_triple_first", flags: [.synthetic, .operatorFunction])
        registerFunctionMember(name: "component2", returnType: bType, externalLinkName: "kk_triple_second", flags: [.synthetic, .operatorFunction])
        registerFunctionMember(name: "component3", returnType: cType, externalLinkName: "kk_triple_third", flags: [.synthetic, .operatorFunction])
        registerPropertyMember(name: "first", propertyType: aType, externalLinkName: "kk_triple_first")
        registerPropertyMember(name: "second", propertyType: bType, externalLinkName: "kk_triple_second")
        registerPropertyMember(name: "third", propertyType: cType, externalLinkName: "kk_triple_third")

        // Triple<A,B,C>.toString() → kk_triple_to_string
        registerFunctionMember(name: "toString", returnType: types.stringType, externalLinkName: "kk_triple_to_string", flags: [.synthetic])

        // Triple<A,B,C>.toList() returns List<Any?> in Kotlin (elements can be nullable).
        // The List symbol is registered after Triple, so we initially use nullable anyType
        // as a placeholder; patchPairTripleToListReturnTypes() refines this to List<Any?>.
        registerFunctionMember(name: "toList", returnType: types.makeNullable(types.anyType), externalLinkName: "kk_triple_toList", flags: [.synthetic])

    }

    /// Patch the provisional `Any?` return types of `Pair.toList()` and `Triple.toList()`
    /// with the correct `List<Any?>` now that the List symbol is available.
    func patchPairTripleToListReturnTypes(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        listInterfaceSymbol: SymbolID
    ) {
        let nullableAnyType = types.makeNullable(types.anyType)
        let listOfNullableAny = types.make(.classType(ClassType(
            classSymbol: listInterfaceSymbol,
            args: [.out(nullableAnyType)],
            nullability: .nonNull
        )))

        // Patch Pair<A,B>.toList() -> List<Any?>
        let pairFQName: [InternedString] = [interner.intern("kotlin"), interner.intern("Pair")]
        let pairToListFQName = pairFQName + [interner.intern("toList")]
        if let pairToListSymbol = symbols.lookup(fqName: pairToListFQName) {
            if let existingSig = symbols.functionSignature(for: pairToListSymbol) {
                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: existingSig.receiverType,
                        parameterTypes: existingSig.parameterTypes,
                        returnType: listOfNullableAny,
                        typeParameterSymbols: existingSig.typeParameterSymbols,
                        classTypeParameterCount: existingSig.classTypeParameterCount
                    ),
                    for: pairToListSymbol
                )
            } else {
                assertionFailure("Pair.toList() symbol found but has no function signature; return type not patched")
            }
        } else {
            assertionFailure("Pair.toList() symbol not found in symbol table; return type not patched")
        }

        // Patch Triple<A,B,C>.toList() -> List<Any?>
        let tripleFQName: [InternedString] = [interner.intern("kotlin"), interner.intern("Triple")]
        let tripleToListFQName = tripleFQName + [interner.intern("toList")]
        if let tripleToListSymbol = symbols.lookup(fqName: tripleToListFQName) {
            if let existingSig = symbols.functionSignature(for: tripleToListSymbol) {
                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: existingSig.receiverType,
                        parameterTypes: existingSig.parameterTypes,
                        returnType: listOfNullableAny,
                        typeParameterSymbols: existingSig.typeParameterSymbols,
                        classTypeParameterCount: existingSig.classTypeParameterCount
                    ),
                    for: tripleToListSymbol
                )
            } else {
                assertionFailure("Triple.toList() symbol found but has no function signature; return type not patched")
            }
        } else {
            assertionFailure("Triple.toList() symbol not found in symbol table; return type not patched")
        }
    }
}
