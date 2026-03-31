import Foundation

/// Synthetic stdlib stubs for java.math.BigInteger (STDLIB-NUM-129).
/// Registers the BigInteger class, companion factory method (valueOf),
/// constructor (String), and instance methods (add, subtract, multiply,
/// divide, gcd, abs, pow, toInt, toLong, toString).
extension DataFlowSemaPhase {
    func registerSyntheticBigIntegerStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        // Ensure java.math package hierarchy
        let javaMathPkg = ensurePackage(
            path: ["java", "math"],
            symbols: symbols,
            interner: interner
        )
        let javaMathPkgSymbol = symbols.lookup(fqName: javaMathPkg)

        // --- BigInteger class symbol ---
        let bigIntegerSymbol = ensureClassSymbol(
            named: "BigInteger",
            in: javaMathPkg,
            symbols: symbols,
            interner: interner
        )
        if let javaMathPkgSymbol {
            symbols.setParentSymbol(javaMathPkgSymbol, for: bigIntegerSymbol)
        }

        let bigIntegerType = types.make(.classType(ClassType(
            classSymbol: bigIntegerSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(bigIntegerType, for: bigIntegerSymbol)

        let intType = types.intType
        let longType = types.longType
        let stringType = types.stringType

        // --- BigInteger(String) constructor ---
        // kk_biginteger_fromString accepts outThrown to signal NumberFormatException.
        registerBigIntegerConstructor(
            ownerSymbol: bigIntegerSymbol,
            ownerType: bigIntegerType,
            parameters: [("value", stringType)],
            externalLinkName: "kk_biginteger_fromString",
            canThrow: true,
            symbols: symbols,
            interner: interner
        )

        // --- Companion object for factory methods ---
        let companionFQName = ensureBigIntegerCompanionSymbol(
            ownerSymbol: bigIntegerSymbol,
            symbols: symbols,
            interner: interner
        )

        // --- BigInteger.valueOf(long) companion factory ---
        registerBigIntegerCompanionMethod(
            named: "valueOf",
            externalLinkName: "kk_biginteger_valueOf",
            returnType: bigIntegerType,
            parameters: [("value", longType)],
            companionFQName: companionFQName,
            symbols: symbols,
            interner: interner
        )

        // --- Instance methods ---

        // add(other: BigInteger) -> BigInteger
        registerBigIntegerInstanceMethod(
            named: "add",
            externalLinkName: "kk_biginteger_add",
            returnType: bigIntegerType,
            parameters: [("other", bigIntegerType)],
            ownerSymbol: bigIntegerSymbol,
            ownerType: bigIntegerType,
            symbols: symbols,
            interner: interner
        )

        // subtract(other: BigInteger) -> BigInteger
        registerBigIntegerInstanceMethod(
            named: "subtract",
            externalLinkName: "kk_biginteger_subtract",
            returnType: bigIntegerType,
            parameters: [("other", bigIntegerType)],
            ownerSymbol: bigIntegerSymbol,
            ownerType: bigIntegerType,
            symbols: symbols,
            interner: interner
        )

        // multiply(other: BigInteger) -> BigInteger
        registerBigIntegerInstanceMethod(
            named: "multiply",
            externalLinkName: "kk_biginteger_multiply",
            returnType: bigIntegerType,
            parameters: [("other", bigIntegerType)],
            ownerSymbol: bigIntegerSymbol,
            ownerType: bigIntegerType,
            symbols: symbols,
            interner: interner
        )

        // divide(other: BigInteger) -> BigInteger
        // kk_biginteger_divide accepts outThrown to signal ArithmeticException (/ by zero).
        registerBigIntegerInstanceMethod(
            named: "divide",
            externalLinkName: "kk_biginteger_divide",
            returnType: bigIntegerType,
            parameters: [("other", bigIntegerType)],
            canThrow: true,
            ownerSymbol: bigIntegerSymbol,
            ownerType: bigIntegerType,
            symbols: symbols,
            interner: interner
        )

        // gcd(other: BigInteger) -> BigInteger
        registerBigIntegerInstanceMethod(
            named: "gcd",
            externalLinkName: "kk_biginteger_gcd",
            returnType: bigIntegerType,
            parameters: [("other", bigIntegerType)],
            ownerSymbol: bigIntegerSymbol,
            ownerType: bigIntegerType,
            symbols: symbols,
            interner: interner
        )

        // abs() -> BigInteger
        registerBigIntegerInstanceMethod(
            named: "abs",
            externalLinkName: "kk_biginteger_abs",
            returnType: bigIntegerType,
            parameters: [],
            ownerSymbol: bigIntegerSymbol,
            ownerType: bigIntegerType,
            symbols: symbols,
            interner: interner
        )

        // pow(exponent: Int) -> BigInteger
        // kk_biginteger_pow accepts outThrown to signal ArithmeticException for negative exponents.
        registerBigIntegerInstanceMethod(
            named: "pow",
            externalLinkName: "kk_biginteger_pow",
            returnType: bigIntegerType,
            parameters: [("exponent", intType)],
            canThrow: true,
            ownerSymbol: bigIntegerSymbol,
            ownerType: bigIntegerType,
            symbols: symbols,
            interner: interner
        )

        // toInt() -> Int
        registerBigIntegerInstanceMethod(
            named: "toInt",
            externalLinkName: "kk_biginteger_toInt",
            returnType: intType,
            parameters: [],
            ownerSymbol: bigIntegerSymbol,
            ownerType: bigIntegerType,
            symbols: symbols,
            interner: interner
        )

        // toLong() -> Long
        registerBigIntegerInstanceMethod(
            named: "toLong",
            externalLinkName: "kk_biginteger_toLong",
            returnType: longType,
            parameters: [],
            ownerSymbol: bigIntegerSymbol,
            ownerType: bigIntegerType,
            symbols: symbols,
            interner: interner
        )

        // toString() -> String
        registerBigIntegerInstanceMethod(
            named: "toString",
            externalLinkName: "kk_biginteger_toString",
            returnType: stringType,
            parameters: [],
            ownerSymbol: bigIntegerSymbol,
            ownerType: bigIntegerType,
            symbols: symbols,
            interner: interner
        )
    }

    // MARK: - BigInteger Helpers

    private func ensureBigIntegerCompanionSymbol(
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

    private func registerBigIntegerCompanionMethod(
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
            flags: [.synthetic]
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
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
            ),
            for: memberSymbol
        )
    }

    private func registerBigIntegerConstructor(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        parameters: [(name: String, type: TypeID)],
        externalLinkName: String,
        canThrow: Bool = false,
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

        var flags: SymbolFlags = [.synthetic]
        if canThrow { flags.formUnion([.throwingFunction]) }
        let ctorSymbol = symbols.define(
            kind: .constructor,
            name: initName,
            fqName: ctorFQName,
            declSite: nil,
            visibility: .public,
            flags: flags
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

    private func registerBigIntegerInstanceMethod(
        named name: String,
        externalLinkName: String,
        returnType: TypeID,
        parameters: [(name: String, type: TypeID)],
        canThrow: Bool = false,
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let memberName = interner.intern(name)
        let memberFQName = ownerInfo.fqName + [memberName]
        if let existing = symbols.lookupAll(fqName: memberFQName).first(where: { symbolID in
            guard let existingSignature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return existingSignature.parameterTypes == parameters.map(\.type) &&
                existingSignature.returnType == returnType
        }) {
            symbols.setExternalLinkName(externalLinkName, for: existing)
            return
        }
        var flags: SymbolFlags = [.synthetic]
        if canThrow { flags.formUnion([.throwingFunction]) }
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
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
            ),
            for: memberSymbol
        )
    }
}
