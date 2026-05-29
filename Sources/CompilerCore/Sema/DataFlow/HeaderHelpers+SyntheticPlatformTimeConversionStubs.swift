extension DataFlowSemaPhase {
    func registerSyntheticPlatformTimeConversionStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinTimePkg = ensurePackage(path: ["kotlin", "time"], symbols: symbols, interner: interner)

        let kotlinInstantSymbol = ensureClassSymbol(
            named: "Instant",
            in: kotlinTimePkg,
            symbols: symbols,
            interner: interner
        )
        let kotlinDurationSymbol = ensureClassSymbol(
            named: "Duration",
            in: kotlinTimePkg,
            symbols: symbols,
            interner: interner
        )

        let kotlinInstantType = types.make(.classType(ClassType(
            classSymbol: kotlinInstantSymbol,
            args: [],
            nullability: .nonNull
        )))
        let kotlinDurationType = types.make(.classType(ClassType(
            classSymbol: kotlinDurationSymbol,
            args: [],
            nullability: .nonNull
        )))
        let kotlinDurationUnitSymbol = ensureEnumClassSymbol(
            named: "DurationUnit",
            in: kotlinTimePkg,
            symbols: symbols,
            interner: interner
        )
        let kotlinDurationUnitType = types.make(.classType(ClassType(
            classSymbol: kotlinDurationUnitSymbol,
            args: [],
            nullability: .nonNull
        )))

        let javaTimePkg = ensurePackage(path: ["java", "time"], symbols: symbols, interner: interner)
        let javaTimePkgSymbol = symbols.lookup(fqName: javaTimePkg)
        let javaInstantSymbol = ensureClassSymbol(
            named: "Instant",
            in: javaTimePkg,
            symbols: symbols,
            interner: interner
        )
        let javaDurationSymbol = ensureClassSymbol(
            named: "Duration",
            in: javaTimePkg,
            symbols: symbols,
            interner: interner
        )
        if let javaTimePkgSymbol {
            symbols.setParentSymbol(javaTimePkgSymbol, for: javaInstantSymbol)
            symbols.setParentSymbol(javaTimePkgSymbol, for: javaDurationSymbol)
        }

        let javaInstantType = types.make(.classType(ClassType(
            classSymbol: javaInstantSymbol,
            args: [],
            nullability: .nonNull
        )))
        let javaDurationType = types.make(.classType(ClassType(
            classSymbol: javaDurationSymbol,
            args: [],
            nullability: .nonNull
        )))

        let javaUtilConcurrentPkg = ensurePackage(
            path: ["java", "util", "concurrent"],
            symbols: symbols,
            interner: interner
        )
        let javaUtilConcurrentPkgSymbol = symbols.lookup(fqName: javaUtilConcurrentPkg)
        let javaTimeUnitSymbol = ensureEnumClassSymbol(
            named: "TimeUnit",
            in: javaUtilConcurrentPkg,
            symbols: symbols,
            interner: interner
        )
        if let javaUtilConcurrentPkgSymbol {
            symbols.setParentSymbol(javaUtilConcurrentPkgSymbol, for: javaTimeUnitSymbol)
        }
        let javaTimeUnitType = types.make(.classType(ClassType(
            classSymbol: javaTimeUnitSymbol,
            args: [],
            nullability: .nonNull
        )))

        let kotlinJsPkg = ensurePackage(path: ["kotlin", "js"], symbols: symbols, interner: interner)
        let kotlinJsPkgSymbol = symbols.lookup(fqName: kotlinJsPkg)
        let jsDateSymbol = ensureClassSymbol(
            named: "Date",
            in: kotlinJsPkg,
            symbols: symbols,
            interner: interner
        )
        if let kotlinJsPkgSymbol {
            symbols.setParentSymbol(kotlinJsPkgSymbol, for: jsDateSymbol)
        }
        let jsDateType = types.make(.classType(ClassType(
            classSymbol: jsDateSymbol,
            args: [],
            nullability: .nonNull
        )))

        registerPlatformTimeExtensionFunction(
            named: "toJavaInstant",
            externalLinkName: "kk_instant_to_java_instant",
            receiverType: kotlinInstantType,
            returnType: javaInstantType,
            packageFQName: kotlinTimePkg,
            symbols: symbols,
            interner: interner
        )
        registerPlatformTimeExtensionFunction(
            named: "toKotlinInstant",
            externalLinkName: "kk_java_instant_to_kotlin_instant",
            receiverType: javaInstantType,
            returnType: kotlinInstantType,
            packageFQName: kotlinTimePkg,
            symbols: symbols,
            interner: interner
        )
        registerPlatformTimeExtensionFunction(
            named: "toJavaDuration",
            externalLinkName: "kk_duration_to_java_duration",
            receiverType: kotlinDurationType,
            returnType: javaDurationType,
            packageFQName: kotlinTimePkg,
            symbols: symbols,
            interner: interner
        )
        registerPlatformTimeExtensionFunction(
            named: "toKotlinDuration",
            externalLinkName: "kk_java_duration_to_kotlin_duration",
            receiverType: javaDurationType,
            returnType: kotlinDurationType,
            packageFQName: kotlinTimePkg,
            symbols: symbols,
            interner: interner
        )
        registerPlatformTimeExtensionFunction(
            named: "toJSDate",
            externalLinkName: "kk_instant_to_js_date",
            receiverType: kotlinInstantType,
            returnType: jsDateType,
            packageFQName: kotlinTimePkg,
            symbols: symbols,
            interner: interner
        )
        registerPlatformTimeExtensionFunction(
            named: "toKotlinInstant",
            externalLinkName: "kk_js_date_to_kotlin_instant",
            receiverType: jsDateType,
            returnType: kotlinInstantType,
            packageFQName: kotlinTimePkg,
            symbols: symbols,
            interner: interner
        )
        registerPlatformTimeExtensionFunction(
            named: "toDurationUnit",
            externalLinkName: "kk_time_unit_to_duration_unit",
            receiverType: javaTimeUnitType,
            returnType: kotlinDurationUnitType,
            packageFQName: kotlinTimePkg,
            symbols: symbols,
            interner: interner
        )
    }

    private func registerPlatformTimeExtensionFunction(
        named name: String,
        externalLinkName: String,
        receiverType: TypeID,
        returnType: TypeID,
        packageFQName: [InternedString],
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let functionName = interner.intern(name)
        let functionFQName = packageFQName + [functionName]
        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let existingSignature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return existingSignature.receiverType == receiverType
                && existingSignature.parameterTypes.isEmpty
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
                valueParameterSymbols: [],
                valueParameterHasDefaultValues: [],
                valueParameterIsVararg: []
            ),
            for: functionSymbol
        )
    }
}
