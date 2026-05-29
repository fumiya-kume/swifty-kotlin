import Foundation

/// Synthetic stdlib stubs for `java.lang.Thread` and `kotlin.concurrent`.
extension DataFlowSemaPhase {
    func registerSyntheticConcurrencyStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let javaLangPkg = ensurePackage(
            path: ["java", "lang"],
            symbols: symbols,
            interner: interner
        )
        let javaUtilPkg = ensurePackage(
            path: ["java", "util"],
            symbols: symbols,
            interner: interner
        )
        let concurrentPkg = ensurePackage(
            path: ["kotlin", "concurrent"],
            symbols: symbols,
            interner: interner
        )
        let concurrentPkgSymbol = symbols.lookup(fqName: concurrentPkg)

        let classLoaderSymbol = symbols.lookup(fqName: javaLangPkg + [interner.intern("ClassLoader")])
        let classLoaderType: TypeID = if let classLoaderSymbol {
            types.make(.classType(ClassType(
                classSymbol: classLoaderSymbol,
                args: [],
                nullability: .nonNull
            )))
        } else {
            types.anyType
        }
        let nullableClassLoaderType = types.makeNullable(classLoaderType)
        let nullableStringType = types.makeNullable(types.stringType)

        let threadSymbol = ensureClassSymbol(
            named: "Thread",
            in: javaLangPkg,
            symbols: symbols,
            interner: interner
        )
        if let javaLangPkgSymbol = symbols.lookup(fqName: javaLangPkg) {
            symbols.setParentSymbol(javaLangPkgSymbol, for: threadSymbol)
        }
        let threadType = types.make(.classType(ClassType(
            classSymbol: threadSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(threadType, for: threadSymbol)
        registerSyntheticThreadClassMembers(
            ownerSymbol: threadSymbol,
            ownerType: threadType,
            symbols: symbols,
            types: types,
            interner: interner
        )

        let timerSymbol = ensureClassSymbol(
            named: "Timer",
            in: javaUtilPkg,
            symbols: symbols,
            interner: interner
        )
        if let javaUtilPkgSymbol = symbols.lookup(fqName: javaUtilPkg) {
            symbols.setParentSymbol(javaUtilPkgSymbol, for: timerSymbol)
        }
        let timerType = types.make(.classType(ClassType(
            classSymbol: timerSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(timerType, for: timerSymbol)

        let timerTaskSymbol = ensureClassSymbol(
            named: "TimerTask",
            in: javaUtilPkg,
            symbols: symbols,
            interner: interner
        )
        if let javaUtilPkgSymbol = symbols.lookup(fqName: javaUtilPkg) {
            symbols.setParentSymbol(javaUtilPkgSymbol, for: timerTaskSymbol)
        }
        let timerTaskType = types.make(.classType(ClassType(
            classSymbol: timerTaskSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(timerTaskType, for: timerTaskSymbol)

        let javaUtilDateSymbol = ensureClassSymbol(
            named: "Date",
            in: javaUtilPkg,
            symbols: symbols,
            interner: interner
        )
        if let javaUtilPkgSymbol = symbols.lookup(fqName: javaUtilPkg) {
            symbols.setParentSymbol(javaUtilPkgSymbol, for: javaUtilDateSymbol)
        }
        let javaUtilDateType = types.make(.classType(ClassType(
            classSymbol: javaUtilDateSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(javaUtilDateType, for: javaUtilDateSymbol)

        registerSyntheticThreadTopLevelFunction(
            packageFQName: concurrentPkg,
            packageSymbol: concurrentPkgSymbol,
            threadType: threadType,
            classLoaderType: nullableClassLoaderType,
            nullableStringType: nullableStringType,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticVolatileAnnotation(
            packageFQName: concurrentPkg,
            packageSymbol: concurrentPkgSymbol,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticFixedRateTimerWithInitialDelay(
            packageFQName: concurrentPkg,
            packageSymbol: concurrentPkgSymbol,
            timerType: timerType,
            timerTaskType: timerTaskType,
            nullableStringType: nullableStringType,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticFixedRateTimerWithStartAt(
            packageFQName: concurrentPkg,
            packageSymbol: concurrentPkgSymbol,
            timerType: timerType,
            timerTaskType: timerTaskType,
            javaUtilDateType: javaUtilDateType,
            nullableStringType: nullableStringType,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func registerSyntheticVolatileAnnotation(
        packageFQName: [InternedString],
        packageSymbol: SymbolID?,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let volatileSymbol = ensureAnnotationClassSymbol(
            named: "Volatile",
            in: packageFQName,
            symbols: symbols,
            interner: interner
        )
        if let packageSymbol {
            symbols.setParentSymbol(packageSymbol, for: volatileSymbol)
        }

        let targetRecord = MetadataAnnotationRecord(
            annotationFQName: "kotlin.annotation.Target",
            arguments: ["AnnotationTarget.FIELD"]
        )
        var annotations = symbols.annotations(for: volatileSymbol)
        if !annotations.contains(targetRecord) {
            annotations.append(targetRecord)
            symbols.setAnnotations(annotations, for: volatileSymbol)
        }
    }

    private func registerSyntheticThreadTopLevelFunction(
        packageFQName: [InternedString],
        packageSymbol: SymbolID?,
        threadType: TypeID,
        classLoaderType: TypeID,
        nullableStringType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let functionName = interner.intern("thread")
        let functionFQName = packageFQName + [functionName]

        let existingSymbol = symbols.lookupAll(fqName: functionFQName).first { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            let defaultFunctionType = types.make(.functionType(FunctionType(
                params: [],
                returnType: types.unitType
            )))
            return signature.receiverType == nil
                && signature.parameterTypes == [
                    types.booleanType,
                    types.booleanType,
                    classLoaderType,
                    nullableStringType,
                    types.intType,
                    defaultFunctionType,
                ]
                && signature.returnType == threadType
        }
        if let existingSymbol {
            symbols.setExternalLinkName("kk_thread_create", for: existingSymbol)
            return
        }

        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .inlineFunction]
        )
        if let packageSymbol {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }
        symbols.setExternalLinkName("kk_thread_create", for: functionSymbol)

        let parameterSpecs: [(name: String, type: TypeID, hasDefault: Bool)] = [
            ("start", types.booleanType, true),
            ("isDaemon", types.booleanType, true),
            ("contextClassLoader", classLoaderType, true),
            ("name", nullableStringType, true),
            ("priority", types.intType, true),
            ("block", types.make(.functionType(FunctionType(
                params: [],
                returnType: types.unitType
            ))), false),
        ]

        var valueParameterSymbols: [SymbolID] = []
        valueParameterSymbols.reserveCapacity(parameterSpecs.count)
        for spec in parameterSpecs {
            let parameterName = interner.intern(spec.name)
            let parameterSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: functionFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(functionSymbol, for: parameterSymbol)
            valueParameterSymbols.append(parameterSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: parameterSpecs.map { $0.type },
                returnType: threadType,
                isSuspend: false,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: parameterSpecs.map { $0.hasDefault },
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
            ),
            for: functionSymbol
        )
    }

    private func registerSyntheticThreadClassMembers(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        registerSyntheticThreadStaticFunction(
            named: "sleep",
            externalLinkName: "kk_thread_sleep",
            ownerSymbol: ownerSymbol,
            parameters: [("millis", types.longType)],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticThreadStaticFunction(
            named: "currentThread",
            externalLinkName: "kk_thread_currentThread",
            ownerSymbol: ownerSymbol,
            parameters: [],
            returnType: ownerType,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticThreadMemberFunction(
            named: "join",
            externalLinkName: "kk_thread_join",
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            parameters: [],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )
    }

    private func registerSyntheticThreadStaticFunction(
        named name: String,
        externalLinkName: String,
        ownerSymbol: SymbolID,
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else { return }
        let memberName = interner.intern(name)
        let memberFQName = ownerInfo.fqName + [memberName]
        guard symbols.lookupAll(fqName: memberFQName).first(where: { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == nil
                && signature.parameterTypes == parameters.map(\.type)
                && signature.returnType == returnType
        }) == nil else {
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
        symbols.setParentSymbol(ownerSymbol, for: memberSymbol)
        symbols.setExternalLinkName(externalLinkName, for: memberSymbol)

        let parameterSymbols = parameters.map { parameter -> SymbolID in
            let parameterName = interner.intern(parameter.name)
            let parameterSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: memberFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(memberSymbol, for: parameterSymbol)
            return parameterSymbol
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: parameters.map(\.type),
                returnType: returnType,
                valueParameterSymbols: parameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: parameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: parameterSymbols.count)
            ),
            for: memberSymbol
        )
    }

    private func registerSyntheticThreadMemberFunction(
        named name: String,
        externalLinkName: String,
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else { return }
        let memberName = interner.intern(name)
        let memberFQName = ownerInfo.fqName + [memberName]
        guard symbols.lookupAll(fqName: memberFQName).first(where: { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == ownerType
                && signature.parameterTypes == parameters.map(\.type)
                && signature.returnType == returnType
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

        let parameterSymbols = parameters.map { parameter -> SymbolID in
            let parameterName = interner.intern(parameter.name)
            let parameterSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: memberFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(memberSymbol, for: parameterSymbol)
            return parameterSymbol
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: ownerType,
                parameterTypes: parameters.map(\.type),
                returnType: returnType,
                valueParameterSymbols: parameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: parameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: parameterSymbols.count)
            ),
            for: memberSymbol
        )
    }

    /// Registers `kotlin.concurrent.fixedRateTimer(name, daemon, initialDelay, period, action)`.
    ///
    /// Kotlin signature:
    /// ```kotlin
    /// fun fixedRateTimer(
    ///     name: String? = null,
    ///     daemon: Boolean = false,
    ///     initialDelay: Long = 0L,
    ///     period: Long,
    ///     action: TimerTask.() -> Unit
    /// ): Timer
    /// ```
    private func registerSyntheticFixedRateTimerWithInitialDelay(
        packageFQName: [InternedString],
        packageSymbol: SymbolID?,
        timerType: TypeID,
        timerTaskType: TypeID,
        nullableStringType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let functionName = interner.intern("fixedRateTimer")
        let functionFQName = packageFQName + [functionName]

        let actionType = types.make(.functionType(FunctionType(
            receiver: timerTaskType,
            params: [],
            returnType: types.unitType
        )))

        let alreadyDefined = symbols.lookupAll(fqName: functionFQName).contains { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == nil
                && signature.parameterTypes.count == 5
                && signature.parameterTypes[0] == nullableStringType
                && signature.parameterTypes[1] == types.booleanType
                && signature.parameterTypes[2] == types.longType
                && signature.parameterTypes[3] == types.longType
                && signature.parameterTypes[4] == actionType
                && signature.returnType == timerType
        }
        if alreadyDefined {
            return
        }

        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .inlineFunction]
        )
        if let packageSymbol {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }
        symbols.setExternalLinkName("kk_fixed_rate_timer_delay", for: functionSymbol)

        let parameterSpecs: [(name: String, type: TypeID, hasDefault: Bool)] = [
            ("name", nullableStringType, true),
            ("daemon", types.booleanType, true),
            ("initialDelay", types.longType, true),
            ("period", types.longType, false),
            ("action", actionType, false),
        ]

        var valueParameterSymbols: [SymbolID] = []
        valueParameterSymbols.reserveCapacity(parameterSpecs.count)
        for spec in parameterSpecs {
            let parameterName = interner.intern(spec.name)
            let parameterSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: functionFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(functionSymbol, for: parameterSymbol)
            valueParameterSymbols.append(parameterSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: parameterSpecs.map { $0.type },
                returnType: timerType,
                isSuspend: false,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: parameterSpecs.map { $0.hasDefault },
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
            ),
            for: functionSymbol
        )
    }

    /// Registers `kotlin.concurrent.fixedRateTimer(name, daemon, startAt, period, action)`.
    ///
    /// Kotlin signature:
    /// ```kotlin
    /// fun fixedRateTimer(
    ///     name: String? = null,
    ///     daemon: Boolean = false,
    ///     startAt: Date,
    ///     period: Long,
    ///     action: TimerTask.() -> Unit
    /// ): Timer
    /// ```
    private func registerSyntheticFixedRateTimerWithStartAt(
        packageFQName: [InternedString],
        packageSymbol: SymbolID?,
        timerType: TypeID,
        timerTaskType: TypeID,
        javaUtilDateType: TypeID,
        nullableStringType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let functionName = interner.intern("fixedRateTimer")
        let functionFQName = packageFQName + [functionName]

        let actionType = types.make(.functionType(FunctionType(
            receiver: timerTaskType,
            params: [],
            returnType: types.unitType
        )))

        let alreadyDefined = symbols.lookupAll(fqName: functionFQName).contains { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == nil
                && signature.parameterTypes.count == 5
                && signature.parameterTypes[0] == nullableStringType
                && signature.parameterTypes[1] == types.booleanType
                && signature.parameterTypes[2] == javaUtilDateType
                && signature.parameterTypes[3] == types.longType
                && signature.parameterTypes[4] == actionType
                && signature.returnType == timerType
        }
        if alreadyDefined {
            return
        }

        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .inlineFunction]
        )
        if let packageSymbol {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }
        symbols.setExternalLinkName("kk_fixed_rate_timer_start_at", for: functionSymbol)

        let parameterSpecs: [(name: String, type: TypeID, hasDefault: Bool)] = [
            ("name", nullableStringType, true),
            ("daemon", types.booleanType, true),
            ("startAt", javaUtilDateType, false),
            ("period", types.longType, false),
            ("action", actionType, false),
        ]

        var valueParameterSymbols: [SymbolID] = []
        valueParameterSymbols.reserveCapacity(parameterSpecs.count)
        for spec in parameterSpecs {
            let parameterName = interner.intern(spec.name)
            let parameterSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: functionFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(functionSymbol, for: parameterSymbol)
            valueParameterSymbols.append(parameterSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: parameterSpecs.map { $0.type },
                returnType: timerType,
                isSuspend: false,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: parameterSpecs.map { $0.hasDefault },
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
            ),
            for: functionSymbol
        )
    }
}
