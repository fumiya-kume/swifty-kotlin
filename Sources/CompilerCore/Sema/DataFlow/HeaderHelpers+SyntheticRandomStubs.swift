import Foundation

/// Synthetic stdlib stubs for kotlin.random.Random
/// (STDLIB-165, STDLIB-514, STDLIB-515, STDLIB-516, STDLIB-653, STDLIB-654, STDLIB-655).
/// Registers the Random object, seeded constructor-style factory, and
/// nextInt/nextLong/nextFloat/nextDouble/nextBoolean/nextBytes methods.
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

        let randomSymbol = ensureSyntheticObjectSymbol(
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

        registerSyntheticRandomAsKotlinRandom(
            packageFQName: kotlinRandomPkg,
            returnType: randomType,
            symbols: symbols,
            types: types,
            interner: interner
        )

        registerSyntheticRandomProperty(
            ownerSymbol: randomSymbol,
            name: "Default",
            externalLinkName: "kk_random_default",
            propertyType: randomType,
            symbols: symbols,
            interner: interner
        )

        let intType = types.intType
        let longType = types.longType
        let ulongType = types.ulongType
        let floatType = types.floatType
        let doubleType = types.doubleType
        let uintType = types.uintType
        let boolType = types.make(.primitive(.boolean, .nonNull))
        let ulongRangeType = makeRangeType(
            named: "ULongRange",
            symbols: symbols,
            types: types,
            interner: interner
        )
        let longRangeType = makeRangeType(
            named: "LongRange",
            symbols: symbols,
            types: types,
            interner: interner
        )
        let intRangeType = makeRangeType(
            named: "IntRange",
            symbols: symbols,
            types: types,
            interner: interner
        )

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
        registerSyntheticRandomConstructor(
            ownerSymbol: randomSymbol,
            ownerType: randomType,
            externalLinkName: "kk_random_create_seeded",
            parameters: [(name: "seed", type: longType)],
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
            name: "nextInt",
            externalLinkName: "kk_random_nextInt_rangeObject",
            returnType: intType,
            parameters: [(name: "range", type: intRangeType)],
            canThrow: true,
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
            externalLinkName: "kk_random_nextLong_rangeObject",
            returnType: longType,
            parameters: [(name: "range", type: longRangeType)],
            canThrow: true,
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
            name: "nextULong",
            externalLinkName: "kk_random_nextULong",
            returnType: ulongType,
            parameters: [],
            symbols: symbols,
            interner: interner
        )

        registerSyntheticRandomMember(
            ownerSymbol: randomSymbol,
            ownerType: randomType,
            name: "nextUInt",
            externalLinkName: "kk_random_nextUInt",
            returnType: uintType,
            parameters: [],
            symbols: symbols,
            interner: interner
        )

        registerSyntheticRandomMember(
            ownerSymbol: randomSymbol,
            ownerType: randomType,
            name: "nextULong",
            externalLinkName: "kk_random_nextULong_until",
            returnType: ulongType,
            parameters: [(name: "until", type: ulongType)],
            canThrow: true,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticRandomMember(
            ownerSymbol: randomSymbol,
            ownerType: randomType,
            name: "nextUInt",
            externalLinkName: "kk_random_nextUInt_until",
            returnType: uintType,
            parameters: [(name: "until", type: uintType)],
            canThrow: true,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticRandomMember(
            ownerSymbol: randomSymbol,
            ownerType: randomType,
            name: "nextULong",
            externalLinkName: "kk_random_nextULong_range",
            returnType: ulongType,
            parameters: [
                (name: "from", type: ulongType),
                (name: "until", type: ulongType),
            ],
            canThrow: true,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticRandomMember(
            ownerSymbol: randomSymbol,
            ownerType: randomType,
            name: "nextUInt",
            externalLinkName: "kk_random_nextUInt_range",
            returnType: uintType,
            parameters: [
                (name: "from", type: uintType),
                (name: "until", type: uintType),
            ],
            canThrow: true,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticRandomMember(
            ownerSymbol: randomSymbol,
            ownerType: randomType,
            name: "nextULong",
            externalLinkName: "kk_random_nextULong_ulongRange",
            returnType: ulongType,
            parameters: [(name: "range", type: ulongRangeType)],
            canThrow: true,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticRandomMember(
            ownerSymbol: randomSymbol,
            ownerType: randomType,
            name: "nextUInt",
            externalLinkName: "kk_random_nextUInt_uintRange",
            returnType: uintType,
            parameters: [(
                name: "range",
                type: makeRangeType(named: "UIntRange", symbols: symbols, types: types, interner: interner)
            )],
            canThrow: true,
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
            name: "nextFloat",
            externalLinkName: "kk_random_nextFloat_until",
            returnType: floatType,
            parameters: [(name: "until", type: floatType)],
            symbols: symbols,
            interner: interner
        )

        // STDLIB-655: nextFloat(from, until)
        registerSyntheticRandomMember(
            ownerSymbol: randomSymbol,
            ownerType: randomType,
            name: "nextFloat",
            externalLinkName: "kk_random_nextFloat_range",
            returnType: floatType,
            parameters: [
                (name: "from", type: floatType),
                (name: "until", type: floatType),
            ],
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
            name: "nextDouble",
            externalLinkName: "kk_random_nextDouble_until",
            returnType: doubleType,
            parameters: [(name: "until", type: doubleType)],
            symbols: symbols,
            interner: interner
        )

        registerSyntheticRandomMember(
            ownerSymbol: randomSymbol,
            ownerType: randomType,
            name: "nextDouble",
            externalLinkName: "kk_random_nextDouble_range",
            returnType: doubleType,
            parameters: [
                (name: "from", type: doubleType),
                (name: "until", type: doubleType),
            ],
            symbols: symbols,
            interner: interner
        )

        // STDLIB-653: nextBytes(array: ByteArray): ByteArray
        let byteArrayType = makeListIntType(
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticRandomMember(
            ownerSymbol: randomSymbol,
            ownerType: randomType,
            name: "nextBytes",
            externalLinkName: "kk_random_nextBytes",
            returnType: byteArrayType,
            parameters: [(name: "array", type: byteArrayType)],
            symbols: symbols,
            interner: interner
        )

        let uByteArrayType = makePrimitiveArrayType(
            named: "UByteArray",
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticRandomMember(
            ownerSymbol: randomSymbol,
            ownerType: randomType,
            name: "nextUBytes",
            externalLinkName: "kk_random_nextUBytes_size",
            returnType: uByteArrayType,
            parameters: [(name: "size", type: intType)],
            canThrow: true,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticRandomMember(
            ownerSymbol: randomSymbol,
            ownerType: randomType,
            name: "nextUBytes",
            externalLinkName: "kk_random_nextUBytes",
            returnType: uByteArrayType,
            parameters: [(name: "array", type: uByteArrayType)],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticRandomMember(
            ownerSymbol: randomSymbol,
            ownerType: randomType,
            name: "nextUBytes",
            externalLinkName: "kk_random_nextUBytes_range",
            returnType: uByteArrayType,
            parameters: [
                (name: "array", type: uByteArrayType),
                (name: "fromIndex", type: intType),
                (name: "toIndex", type: intType),
            ],
            canThrow: true,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticRandomMember(
            ownerSymbol: randomSymbol,
            ownerType: randomType,
            name: "nextBytes",
            externalLinkName: "kk_random_nextBytes_size",
            returnType: byteArrayType,
            parameters: [(name: "size", type: intType)],
            canThrow: true,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticRandomMember(
            ownerSymbol: randomSymbol,
            ownerType: randomType,
            name: "nextBytes",
            externalLinkName: "kk_random_nextBytes_range",
            returnType: byteArrayType,
            parameters: [
                (name: "array", type: byteArrayType),
                (name: "fromIndex", type: intType),
                (name: "toIndex", type: intType),
            ],
            canThrow: true,
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

        registerSyntheticRandomMember(
            ownerSymbol: randomSymbol,
            ownerType: randomType,
            name: "nextBits",
            externalLinkName: "kk_random_nextBits",
            returnType: intType,
            parameters: [(name: "bitCount", type: intType)],
            canThrow: true,
            symbols: symbols,
            interner: interner
        )

        // SecureRandom basic support
        let secureRandomSymbol = ensureClassSymbol(
            named: "SecureRandom",
            in: kotlinRandomPkg,
            symbols: symbols,
            interner: interner
        )
        let secureRandomType = types.make(.classType(ClassType(
            classSymbol: secureRandomSymbol,
            args: [],
            nullability: .nonNull
        )))

        let secureCompanionFQName = ensureRandomCompanionSymbol(
            ownerSymbol: secureRandomSymbol,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticRandomCompanionMethod(
            named: "getInstance",
            externalLinkName: "kk_secure_random_get_instance",
            returnType: secureRandomType,
            parameters: [],
            companionFQName: secureCompanionFQName,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticRandomMember(
            ownerSymbol: secureRandomSymbol,
            ownerType: secureRandomType,
            name: "setSeed",
            externalLinkName: "kk_secure_random_set_seed",
            returnType: secureRandomType,
            parameters: [(name: "seed", type: intType)],
            symbols: symbols,
            interner: interner
        )

        registerSyntheticRandomMember(
            ownerSymbol: secureRandomSymbol,
            ownerType: secureRandomType,
            name: "generateSeed",
            externalLinkName: "kk_secure_random_generate_seed",
            returnType: byteArrayType,
            parameters: [(name: "size", type: intType)],
            symbols: symbols,
            interner: interner
        )

        registerSyntheticRandomMember(
            ownerSymbol: secureRandomSymbol,
            ownerType: secureRandomType,
            name: "nextBytes",
            externalLinkName: "kk_secure_random_next_bytes",
            returnType: byteArrayType,
            parameters: [(name: "array", type: byteArrayType)],
            symbols: symbols,
            interner: interner
        )
    }

    private func ensureRandomCompanionSymbol(
        ownerSymbol: SymbolID,
        symbols: SymbolTable,
        interner: StringInterner
    ) -> [InternedString] {
        if let existingCompanion = symbols.companionObjectSymbol(for: ownerSymbol),
           let companionInfo = symbols.symbol(existingCompanion)
        {
            return companionInfo.fqName
        }

        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return []
        }
        let companionName = interner.intern("Companion")
        let companionFQName = ownerInfo.fqName + [companionName]
        let companionSymbol = symbols.define(
            kind: .object,
            name: companionName,
            fqName: companionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .static]
        )
        symbols.setParentSymbol(ownerSymbol, for: companionSymbol)
        symbols.setCompanionObjectSymbol(companionSymbol, for: ownerSymbol)
        return companionFQName
    }

    private func registerSyntheticRandomCompanionMethod(
        named name: String,
        externalLinkName: String,
        returnType: TypeID,
        parameters: [(name: String, type: TypeID)],
        companionFQName: [InternedString],
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let memberName = interner.intern(name)
        let memberFQName = companionFQName + [memberName]
        guard symbols.lookupAll(fqName: memberFQName).first(where: { symbolID in
            guard let existingSignature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return existingSignature.parameterTypes == parameters.map(\.type) &&
                existingSignature.returnType == returnType
        }) == nil else {
            return
        }

        guard let companionSymbol = symbols.lookup(fqName: companionFQName) else {
            return
        }
        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .static]
        )
        symbols.setParentSymbol(companionSymbol, for: memberSymbol)
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

    private func registerSyntheticRandomAsKotlinRandom(
        packageFQName: [InternedString],
        returnType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let javaRandomType = ensureSyntheticJavaRandomType(
            symbols: symbols,
            types: types,
            interner: interner
        )

        registerSyntheticRandomExtensionFunction(
            packageFQName: packageFQName,
            name: "asKotlinRandom",
            externalLinkName: "kk_random_asKotlinRandom",
            receiverType: javaRandomType,
            returnType: returnType,
            symbols: symbols,
            interner: interner
        )
    }

    private func ensureSyntheticJavaRandomType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> TypeID {
        let javaUtilPkg = ensurePackage(
            path: ["java", "util"],
            symbols: symbols,
            interner: interner
        )
        let javaRandomSymbol = ensureClassSymbol(
            named: "Random",
            in: javaUtilPkg,
            symbols: symbols,
            interner: interner
        )
        if let packageSymbol = symbols.lookup(fqName: javaUtilPkg) {
            symbols.setParentSymbol(packageSymbol, for: javaRandomSymbol)
        }

        let javaRandomType = types.make(.classType(ClassType(
            classSymbol: javaRandomSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(javaRandomType, for: javaRandomSymbol)

        registerSyntheticJavaRandomConstructor(
            ownerSymbol: javaRandomSymbol,
            ownerType: javaRandomType,
            externalLinkName: "kk_java_random_new",
            parameters: [],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticJavaRandomConstructor(
            ownerSymbol: javaRandomSymbol,
            ownerType: javaRandomType,
            externalLinkName: "kk_java_random_new_seed",
            parameters: [(name: "seed", type: types.intType)],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticJavaRandomConstructor(
            ownerSymbol: javaRandomSymbol,
            ownerType: javaRandomType,
            externalLinkName: "kk_java_random_new_seed",
            parameters: [(name: "seed", type: types.longType)],
            symbols: symbols,
            interner: interner
        )

        return javaRandomType
    }

    private func registerSyntheticRandomExtensionFunction(
        packageFQName: [InternedString],
        name: String,
        externalLinkName: String,
        receiverType: TypeID,
        returnType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let functionName = interner.intern(name)
        let functionFQName = packageFQName + [functionName]
        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == receiverType
                && signature.parameterTypes.isEmpty
                && signature.returnType == returnType
        }) {
            symbols.setExternalLinkName(externalLinkName, for: existing)
            return
        }

        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }
        symbols.setExternalLinkName(externalLinkName, for: functionSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [],
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: [],
                valueParameterHasDefaultValues: [],
                valueParameterIsVararg: []
            ),
            for: functionSymbol
        )
    }

    private func registerSyntheticJavaRandomConstructor(
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
        let initFQName = ownerInfo.fqName + [initName]
        if let existing = symbols.lookupAll(fqName: initFQName).first(where: { symbolID in
            symbols.functionSignature(for: symbolID)?.parameterTypes == parameters.map(\.type)
        }) {
            symbols.setExternalLinkName(externalLinkName, for: existing)
            return
        }

        let constructorSymbol = symbols.define(
            kind: .constructor,
            name: initName,
            fqName: initFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: constructorSymbol)
        symbols.setExternalLinkName(externalLinkName, for: constructorSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: nil,
                parameterTypes: parameters.map(\.type),
                returnType: ownerType,
                isSuspend: false,
                valueParameterSymbols: [],
                valueParameterHasDefaultValues: Array(repeating: false, count: parameters.count),
                valueParameterIsVararg: Array(repeating: false, count: parameters.count)
            ),
            for: constructorSymbol
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
        canThrow: Bool = false,
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
        var flags: SymbolFlags = [.synthetic]
        if canThrow {
            flags.insert(.throwingFunction)
        }
        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: flags
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
                canThrow: canThrow,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
            ),
            for: memberSymbol
        )
    }

    private func registerSyntheticRandomProperty(
        ownerSymbol: SymbolID,
        name: String,
        externalLinkName: String,
        propertyType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let propertyName = interner.intern(name)
        let propertyFQName = ownerInfo.fqName + [propertyName]
        let propertySymbol = symbols.lookup(fqName: propertyFQName) ?? symbols.define(
            kind: .property,
            name: propertyName,
            fqName: propertyFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: propertySymbol)
        symbols.setExternalLinkName(externalLinkName, for: propertySymbol)
        symbols.setPropertyType(propertyType, for: propertySymbol)
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

    private func makePrimitiveArrayType(
        named name: String,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> TypeID {
        let kotlinPkg: [InternedString] = [interner.intern("kotlin")]
        let symbol = ensureClassSymbol(
            named: name,
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        return types.make(.classType(ClassType(
            classSymbol: symbol,
            args: [],
            nullability: .nonNull
        )))
    }

    private func makeRangeType(
        named name: String,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> TypeID {
        let rangesPkg = ensureSyntheticPackage(
            path: [interner.intern("kotlin"), interner.intern("ranges")],
            symbols: symbols
        )
        let symbol = ensureClassSymbol(
            named: name,
            in: rangesPkg,
            symbols: symbols,
            interner: interner
        )
        return types.make(.classType(ClassType(
            classSymbol: symbol,
            args: [],
            nullability: .nonNull
        )))
    }

    /// Build a `List<Int>` type, which is the internal representation of ByteArray.
    private func makeListIntType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> TypeID {
        let listFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("List"),
        ]
        guard let listSymbol = symbols.lookup(fqName: listFQName) else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: listSymbol,
            args: [.out(types.intType)],
            nullability: .nonNull
        )))
    }

}
