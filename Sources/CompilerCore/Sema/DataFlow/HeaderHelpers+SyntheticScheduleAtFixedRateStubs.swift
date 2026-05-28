import Foundation

/// Synthetic stdlib stubs for `kotlin.concurrent.scheduleAtFixedRate` (STDLIB-CONC-FN-006).
///
/// Registers both overloads of the `scheduleAtFixedRate` extension function on `java.util.Timer`:
///   - `Timer.scheduleAtFixedRate(delay: Long, period: Long, action: TimerTask.() -> Unit): TimerTask`
///   - `Timer.scheduleAtFixedRate(time: Date, period: Long, action: TimerTask.() -> Unit): TimerTask`
extension DataFlowSemaPhase {
    func registerSyntheticScheduleAtFixedRateStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let javaUtilPkg = ensurePackage(
            path: ["java", "util"],
            symbols: symbols,
            interner: interner
        )
        let javaUtilPkgSymbol = symbols.lookup(fqName: javaUtilPkg)
        let kotlinConcurrentPkg = ensurePackage(
            path: ["kotlin", "concurrent"],
            symbols: symbols,
            interner: interner
        )
        let kotlinConcurrentPkgSymbol = symbols.lookup(fqName: kotlinConcurrentPkg)

        // Register java.util.Timer
        let timerSymbol = ensureClassSymbol(
            named: "Timer",
            in: javaUtilPkg,
            symbols: symbols,
            interner: interner
        )
        if let javaUtilPkgSymbol {
            symbols.setParentSymbol(javaUtilPkgSymbol, for: timerSymbol)
        }
        let timerType = types.make(.classType(ClassType(
            classSymbol: timerSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(timerType, for: timerSymbol)

        // Register java.util.TimerTask
        let timerTaskSymbol = ensureClassSymbol(
            named: "TimerTask",
            in: javaUtilPkg,
            symbols: symbols,
            interner: interner
        )
        if let javaUtilPkgSymbol {
            symbols.setParentSymbol(javaUtilPkgSymbol, for: timerTaskSymbol)
        }
        let timerTaskType = types.make(.classType(ClassType(
            classSymbol: timerTaskSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(timerTaskType, for: timerTaskSymbol)

        // Register java.util.Date
        let dateSymbol = ensureClassSymbol(
            named: "Date",
            in: javaUtilPkg,
            symbols: symbols,
            interner: interner
        )
        if let javaUtilPkgSymbol {
            symbols.setParentSymbol(javaUtilPkgSymbol, for: dateSymbol)
        }
        let dateType = types.make(.classType(ClassType(
            classSymbol: dateSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(dateType, for: dateSymbol)

        // Register overload 1: Timer.scheduleAtFixedRate(delay: Long, period: Long, action: TimerTask.() -> Unit): TimerTask
        registerScheduleAtFixedRateDelayOverload(
            timerSymbol: timerSymbol,
            timerType: timerType,
            timerTaskType: timerTaskType,
            packageFQName: kotlinConcurrentPkg,
            packageSymbol: kotlinConcurrentPkgSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )

        // Register overload 2: Timer.scheduleAtFixedRate(time: Date, period: Long, action: TimerTask.() -> Unit): TimerTask
        registerScheduleAtFixedRateTimeOverload(
            timerSymbol: timerSymbol,
            timerType: timerType,
            timerTaskType: timerTaskType,
            dateType: dateType,
            packageFQName: kotlinConcurrentPkg,
            packageSymbol: kotlinConcurrentPkgSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    /// Overload 1: `Timer.scheduleAtFixedRate(delay: Long, period: Long, action: TimerTask.() -> Unit): TimerTask`
    private func registerScheduleAtFixedRateDelayOverload(
        timerSymbol: SymbolID,
        timerType: TypeID,
        timerTaskType: TypeID,
        packageFQName: [InternedString],
        packageSymbol: SymbolID?,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let functionName = interner.intern("scheduleAtFixedRate")
        let functionFQName = packageFQName + [functionName]

        let actionType = types.make(.functionType(FunctionType(
            receiver: timerTaskType,
            params: [],
            returnType: types.unitType
        )))

        // Check for existing overload with (Long, Long, action) parameters
        let existingOverload = symbols.lookupAll(fqName: functionFQName).first { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == timerType
                && signature.parameterTypes == [types.longType, types.longType, actionType]
                && signature.returnType == timerTaskType
        }
        if let existingOverload {
            symbols.setExternalLinkName("kk_timer_schedule_at_fixed_rate_delay", for: existingOverload)
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
        symbols.setExternalLinkName("kk_timer_schedule_at_fixed_rate_delay", for: functionSymbol)

        let paramSpecs: [(name: String, type: TypeID)] = [
            ("delay", types.longType),
            ("period", types.longType),
            ("action", actionType),
        ]
        var paramSymbols: [SymbolID] = []
        for spec in paramSpecs {
            let paramName = interner.intern(spec.name)
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: paramName,
                fqName: functionFQName + [paramName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(functionSymbol, for: paramSymbol)
            paramSymbols.append(paramSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: timerType,
                parameterTypes: paramSpecs.map { $0.type },
                returnType: timerTaskType,
                isSuspend: false,
                valueParameterSymbols: paramSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: paramSpecs.count),
                valueParameterIsVararg: Array(repeating: false, count: paramSpecs.count)
            ),
            for: functionSymbol
        )
    }

    /// Overload 2: `Timer.scheduleAtFixedRate(time: Date, period: Long, action: TimerTask.() -> Unit): TimerTask`
    private func registerScheduleAtFixedRateTimeOverload(
        timerSymbol: SymbolID,
        timerType: TypeID,
        timerTaskType: TypeID,
        dateType: TypeID,
        packageFQName: [InternedString],
        packageSymbol: SymbolID?,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let functionName = interner.intern("scheduleAtFixedRate")
        let functionFQName = packageFQName + [functionName]

        let actionType = types.make(.functionType(FunctionType(
            receiver: timerTaskType,
            params: [],
            returnType: types.unitType
        )))

        // Check for existing overload with (Date, Long, action) parameters
        let existingOverload = symbols.lookupAll(fqName: functionFQName).first { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == timerType
                && signature.parameterTypes == [dateType, types.longType, actionType]
                && signature.returnType == timerTaskType
        }
        if let existingOverload {
            symbols.setExternalLinkName("kk_timer_schedule_at_fixed_rate_time", for: existingOverload)
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
        symbols.setExternalLinkName("kk_timer_schedule_at_fixed_rate_time", for: functionSymbol)

        let paramSpecs: [(name: String, type: TypeID)] = [
            ("time", dateType),
            ("period", types.longType),
            ("action", actionType),
        ]
        var paramSymbols: [SymbolID] = []
        for spec in paramSpecs {
            let paramName = interner.intern(spec.name)
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: paramName,
                fqName: functionFQName + [paramName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(functionSymbol, for: paramSymbol)
            paramSymbols.append(paramSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: timerType,
                parameterTypes: paramSpecs.map { $0.type },
                returnType: timerTaskType,
                isSuspend: false,
                valueParameterSymbols: paramSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: paramSpecs.count),
                valueParameterIsVararg: Array(repeating: false, count: paramSpecs.count)
            ),
            for: functionSymbol
        )
    }
}
