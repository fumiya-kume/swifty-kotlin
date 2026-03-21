import Foundation

/// Synthetic stdlib stubs for kotlin.random.Random (STDLIB-165, STDLIB-514, STDLIB-515, STDLIB-516).
/// Registers the Random class, its constructor, and nextInt/nextLong/nextFloat/nextDouble/nextBoolean methods.
extension DataFlowSemaPhase {
    func registerSyntheticRandomStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinPkg: [InternedString] = [interner.intern("kotlin")]
        if symbols.lookup(fqName: kotlinPkg) == nil {
            _ = symbols.define(
                kind: .package,
                name: interner.intern("kotlin"),
                fqName: kotlinPkg,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }

        let kotlinRandomPkg = ensureSyntheticPackage(
            path: [interner.intern("kotlin"), interner.intern("random")],
            symbols: symbols
        )

        let randomSymbol = ensureObjectSymbol(
            named: "Random",
            in: kotlinRandomPkg,
            symbols: symbols,
            interner: interner
        )

        let randomType = types.make(.classType(ClassType(
            classSymbol: randomSymbol,
            args: [],
            nullability: .nonNull
        )))

        symbols.setPropertyType(randomType, for: randomSymbol)

        let intType = types.intType
        let longType = types.longType
        let floatType = types.floatType
        let doubleType = types.doubleType
        let boolType = types.make(.primitive(.boolean, .nonNull))

        // Random(seed: Int) constructor (STDLIB-516)
        // In Kotlin, Random(seed) is a top-level factory function, but from
        // the user perspective it looks like a constructor call.  We register
        // it as a constructor on the Random symbol so that the call resolver
        // can find it when the user writes `Random(42)`.
        registerSyntheticRandomConstructor(
            ownerSymbol: randomSymbol,
            ownerType: randomType,
            externalLinkName: "kk_random_create_seeded",
            parameters: [(name: "seed", type: intType)],
            symbols: symbols,
            interner: interner
        )

        registerSyntheticRandomMember(
            ownerSymbol: randomSymbol,
            ownerType: randomType,
            name: "nextInt",
            externalLinkName: "kk_random_nextInt",
            returnType: intType,
            parameters: [],
            symbols: symbols,
            interner: interner
        )

        registerSyntheticRandomMember(
            ownerSymbol: randomSymbol,
            ownerType: randomType,
            name: "nextInt",
            externalLinkName: "kk_random_nextInt_until",
            returnType: intType,
            parameters: [(name: "until", type: intType)],
            symbols: symbols,
            interner: interner
        )

        registerSyntheticRandomMember(
            ownerSymbol: randomSymbol,
            ownerType: randomType,
            name: "nextInt",
            externalLinkName: "kk_random_nextInt_range",
            returnType: intType,
            parameters: [
                (name: "from", type: intType),
                (name: "until", type: intType),
            ],
            symbols: symbols,
            interner: interner
        )

        registerSyntheticRandomMember(
            ownerSymbol: randomSymbol,
            ownerType: randomType,
            name: "nextLong",
            externalLinkName: "kk_random_nextLong",
            returnType: longType,
            parameters: [],
            symbols: symbols,
            interner: interner
        )

        registerSyntheticRandomMember(
            ownerSymbol: randomSymbol,
            ownerType: randomType,
            name: "nextLong",
            externalLinkName: "kk_random_nextLong_until",
            returnType: longType,
            parameters: [(name: "until", type: longType)],
            symbols: symbols,
            interner: interner
        )

        registerSyntheticRandomMember(
            ownerSymbol: randomSymbol,
            ownerType: randomType,
            name: "nextLong",
            externalLinkName: "kk_random_nextLong_range",
            returnType: longType,
            parameters: [
                (name: "from", type: longType),
                (name: "until", type: longType),
            ],
            symbols: symbols,
            interner: interner
        )

        registerSyntheticRandomMember(
            ownerSymbol: randomSymbol,
            ownerType: randomType,
            name: "nextFloat",
            externalLinkName: "kk_random_nextFloat",
            returnType: floatType,
            parameters: [],
            symbols: symbols,
            interner: interner
        )

        registerSyntheticRandomMember(
            ownerSymbol: randomSymbol,
            ownerType: randomType,
            name: "nextDouble",
            externalLinkName: "kk_random_nextDouble",
            returnType: doubleType,
            parameters: [],
            symbols: symbols,
            interner: interner
        )

        registerSyntheticRandomMember(
            ownerSymbol: randomSymbol,
            ownerType: randomType,
            name: "nextBoolean",
            externalLinkName: "kk_random_nextBoolean",
            returnType: boolType,
            parameters: [],
            symbols: symbols,
            interner: interner
        )
    }

    private func ensureObjectSymbol(
        named name: String,
        in pkg: [InternedString],
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID {
        let internedName = interner.intern(name)
        let fqName = pkg + [internedName]
        if let existing = symbols.lookup(fqName: fqName) {
            return existing
        }
        return symbols.define(
            kind: .object,
            name: internedName,
            fqName: fqName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
    }

    /// Registers a constructor on the Random symbol (STDLIB-516).
    private func registerSyntheticRandomConstructor(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        externalLinkName: String,
        parameters: [(name: String, type: TypeID)],
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let initName = interner.intern("<init>")
        let ctorFQName = ownerInfo.fqName + [initName]
        let hasMatchingConstructor = symbols.lookupAll(fqName: ctorFQName).contains { symbolID in
            guard let symbol = symbols.symbol(symbolID),
                  symbol.kind == .constructor,
                  let signature = symbols.functionSignature(for: symbolID)
            else {
                return false
            }
            return signature.parameterTypes == parameters.map(\.type)
        }
        guard !hasMatchingConstructor else {
            return
        }

        let ctorSymbol = symbols.define(
            kind: .constructor,
            name: initName,
            fqName: ctorFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: ctorSymbol)
        symbols.setExternalLinkName(externalLinkName, for: ctorSymbol)

        var valueParameterSymbols: [SymbolID] = []
        for parameter in parameters {
            let parameterName = interner.intern(parameter.name)
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: ctorFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(ctorSymbol, for: paramSymbol)
            valueParameterSymbols.append(paramSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: parameters.map(\.type),
                returnType: ownerType,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
            ),
            for: ctorSymbol
        )
    }

    private func registerSyntheticRandomMember(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        name: String,
        externalLinkName: String,
        returnType: TypeID,
        parameters: [(name: String, type: TypeID)],
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let memberName = interner.intern(name)
        let memberFQName = ownerInfo.fqName + [memberName]
        guard symbols.lookupAll(fqName: memberFQName).first(where: { symbolID in
            guard let existingSignature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return existingSignature.parameterTypes == parameters.map(\.type) &&
                existingSignature.returnType == returnType
        }) == nil else {
            return
        }
        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: memberSymbol)
        symbols.setExternalLinkName(externalLinkName, for: memberSymbol)
        var valueParameterSymbols: [SymbolID] = []
        for parameter in parameters {
            let parameterName = interner.intern(parameter.name)
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: memberFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(memberSymbol, for: paramSymbol)
            valueParameterSymbols.append(paramSymbol)
        }
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: ownerType,
                parameterTypes: parameters.map(\.type),
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
            ),
            for: memberSymbol
        )
    }

    private func ensureSyntheticPackage(
        path: [InternedString],
        symbols: SymbolTable
    ) -> [InternedString] {
        var fqName: [InternedString] = []
        for part in path {
            fqName.append(part)
            if symbols.lookup(fqName: fqName) == nil {
                _ = symbols.define(
                    kind: .package,
                    name: part,
                    fqName: fqName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
            }
        }
        return fqName
    }
}
