import Foundation

/// Synthetic stdlib stubs for `java.util.Timer`, `java.util.TimerTask`, and
/// the `kotlin.concurrent.timer` top-level factory functions (STDLIB-CONC-FN-008)
/// and `kotlin.concurrent.schedule` extension functions (STDLIB-CONC-FN-005).
///
/// Kotlin's `kotlin.concurrent.timer(...)` is a convenience wrapper that creates
/// a `java.util.Timer` and schedules a repeating `TimerTask`.  Two overloads exist:
///
///   1. `timer(name, daemon, initialDelay, period, action)`
///      — starts after `initialDelay` milliseconds, then repeats every `period` ms.
///   2. `timer(name, daemon, startAt, period, action)`
///      — starts at the given `java.util.Date`, then repeats every `period` ms.
///
/// Both overloads return the underlying `java.util.Timer` so the caller can
/// cancel it later.
///
/// Kotlin's `kotlin.concurrent.schedule` is an extension function on `java.util.Timer`
/// that creates a `TimerTask` from a lambda and schedules it.  Two overloads exist:
///
///   1. `Timer.schedule(delay: Long, action: TimerTask.() -> Unit): TimerTask`
///      — runs once after `delay` milliseconds.
///   2. `Timer.schedule(delay: Long, period: Long, action: TimerTask.() -> Unit): TimerTask`
///      — runs after `delay` ms, then repeats every `period` ms.
extension DataFlowSemaPhase {
    func registerSyntheticTimerStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        // ── java.util package ────────────────────────────────────────────────
        let javaUtilPkg = ensurePackage(
            path: ["java", "util"],
            symbols: symbols,
            interner: interner
        )
        let javaUtilPkgSymbol = symbols.lookup(fqName: javaUtilPkg)

        // ── java.util.Timer ──────────────────────────────────────────────────
        let timerClassSymbol = ensureClassSymbol(
            named: "Timer",
            in: javaUtilPkg,
            symbols: symbols,
            interner: interner
        )
        if let javaUtilPkgSymbol {
            symbols.setParentSymbol(javaUtilPkgSymbol, for: timerClassSymbol)
        }
        let timerType = types.make(.classType(ClassType(
            classSymbol: timerClassSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(timerType, for: timerClassSymbol)

        // ── java.util.TimerTask ──────────────────────────────────────────────
        let timerTaskClassSymbol = ensureClassSymbol(
            named: "TimerTask",
            in: javaUtilPkg,
            symbols: symbols,
            interner: interner
        )
        if let javaUtilPkgSymbol {
            symbols.setParentSymbol(javaUtilPkgSymbol, for: timerTaskClassSymbol)
        }
        let timerTaskType = types.make(.classType(ClassType(
            classSymbol: timerTaskClassSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(timerTaskType, for: timerTaskClassSymbol)

        // ── java.util.Date ───────────────────────────────────────────────────
        // Needed by the second `timer(…, startAt: Date, …)` overload.
        let dateClassSymbol = ensureClassSymbol(
            named: "Date",
            in: javaUtilPkg,
            symbols: symbols,
            interner: interner
        )
        if let javaUtilPkgSymbol {
            symbols.setParentSymbol(javaUtilPkgSymbol, for: dateClassSymbol)
        }
        let dateType = types.make(.classType(ClassType(
            classSymbol: dateClassSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(dateType, for: dateClassSymbol)

        // ── kotlin.concurrent package ────────────────────────────────────────
        let concurrentPkg = ensurePackage(
            path: ["kotlin", "concurrent"],
            symbols: symbols,
            interner: interner
        )
        let concurrentPkgSymbol = symbols.lookup(fqName: concurrentPkg)

        // The lambda passed to `timer` is `TimerTask.() -> Unit`:
        // a function with `TimerTask` as receiver and `Unit` return.
        let actionType = types.make(.functionType(FunctionType(
            receiver: timerTaskType,
            params: [],
            returnType: types.unitType
        )))
        let nullableStringType = types.makeNullable(types.stringType)

        // ── Overload 1: timer(name, daemon, initialDelay, period, action) ────
        registerSyntheticTimerOverloadWithDelay(
            packageFQName: concurrentPkg,
            packageSymbol: concurrentPkgSymbol,
            timerType: timerType,
            actionType: actionType,
            nullableStringType: nullableStringType,
            symbols: symbols,
            types: types,
            interner: interner
        )

        // ── Overload 2: timer(name, daemon, startAt, period, action) ─────────
        registerSyntheticTimerOverloadWithDate(
            packageFQName: concurrentPkg,
            packageSymbol: concurrentPkgSymbol,
            timerType: timerType,
            dateType: dateType,
            actionType: actionType,
            nullableStringType: nullableStringType,
            symbols: symbols,
            types: types,
            interner: interner
        )

        // ── schedule overloads (STDLIB-CONC-FN-005) ──────────────────────────
        // Overload 1: Timer.schedule(delay: Long, action: TimerTask.() -> Unit): TimerTask
        registerSyntheticScheduleOverloadWithDelay(
            packageFQName: concurrentPkg,
            packageSymbol: concurrentPkgSymbol,
            timerType: timerType,
            timerTaskType: timerTaskType,
            actionType: actionType,
            symbols: symbols,
            types: types,
            interner: interner
        )

        // Overload 2: Timer.schedule(delay: Long, period: Long, action: TimerTask.() -> Unit): TimerTask
        registerSyntheticScheduleOverloadWithPeriod(
            packageFQName: concurrentPkg,
            packageSymbol: concurrentPkgSymbol,
            timerType: timerType,
            timerTaskType: timerTaskType,
            actionType: actionType,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    // MARK: - Private helpers

    /// `timer(name: String? = null, daemon: Boolean = false, initialDelay: Long = 0, period: Long, action: TimerTask.() -> Unit): Timer`
    private func registerSyntheticTimerOverloadWithDelay(
        packageFQName: [InternedString],
        packageSymbol: SymbolID?,
        timerType: TypeID,
        actionType: TypeID,
        nullableStringType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let functionName = interner.intern("timer")
        let functionFQName = packageFQName + [functionName]

        let parameterSpecs: [(name: String, type: TypeID, hasDefault: Bool)] = [
            ("name",         nullableStringType,   true),
            ("daemon",       types.booleanType,     true),
            ("initialDelay", types.longType,        true),
            ("period",       types.longType,        false),
            ("action",       actionType,            false),
        ]

        // Idempotency: if an existing symbol already matches, just stamp the link name.
        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let sig = symbols.functionSignature(for: symbolID) else { return false }
            return sig.receiverType == nil
                && sig.parameterTypes == parameterSpecs.map(\.type)
                && sig.returnType == timerType
        }) {
            symbols.setExternalLinkName("kk_timer_create_delay", for: existing)
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
        if let packageSymbol {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }
        symbols.setExternalLinkName("kk_timer_create_delay", for: functionSymbol)

        var paramSymbols: [SymbolID] = []
        for spec in parameterSpecs {
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
                parameterTypes: parameterSpecs.map(\.type),
                returnType: timerType,
                isSuspend: false,
                valueParameterSymbols: paramSymbols,
                valueParameterHasDefaultValues: parameterSpecs.map(\.hasDefault),
                valueParameterIsVararg: Array(repeating: false, count: paramSymbols.count)
            ),
            for: functionSymbol
        )
    }

    /// `timer(name: String? = null, daemon: Boolean = false, startAt: Date, period: Long, action: TimerTask.() -> Unit): Timer`
    private func registerSyntheticTimerOverloadWithDate(
        packageFQName: [InternedString],
        packageSymbol: SymbolID?,
        timerType: TypeID,
        dateType: TypeID,
        actionType: TypeID,
        nullableStringType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let functionName = interner.intern("timer")
        let functionFQName = packageFQName + [functionName]

        let parameterSpecs: [(name: String, type: TypeID, hasDefault: Bool)] = [
            ("name",    nullableStringType,  true),
            ("daemon",  types.booleanType,    true),
            ("startAt", dateType,             false),
            ("period",  types.longType,       false),
            ("action",  actionType,           false),
        ]

        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let sig = symbols.functionSignature(for: symbolID) else { return false }
            return sig.receiverType == nil
                && sig.parameterTypes == parameterSpecs.map(\.type)
                && sig.returnType == timerType
        }) {
            symbols.setExternalLinkName("kk_timer_create_date", for: existing)
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
        if let packageSymbol {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }
        symbols.setExternalLinkName("kk_timer_create_date", for: functionSymbol)

        var paramSymbols: [SymbolID] = []
        for spec in parameterSpecs {
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
                parameterTypes: parameterSpecs.map(\.type),
                returnType: timerType,
                isSuspend: false,
                valueParameterSymbols: paramSymbols,
                valueParameterHasDefaultValues: parameterSpecs.map(\.hasDefault),
                valueParameterIsVararg: Array(repeating: false, count: paramSymbols.count)
            ),
            for: functionSymbol
        )
    }

    // MARK: - schedule overloads

    /// `Timer.schedule(delay: Long, action: TimerTask.() -> Unit): TimerTask`
    private func registerSyntheticScheduleOverloadWithDelay(
        packageFQName: [InternedString],
        packageSymbol: SymbolID?,
        timerType: TypeID,
        timerTaskType: TypeID,
        actionType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let functionName = interner.intern("schedule")
        let functionFQName = packageFQName + [functionName]

        let parameterSpecs: [(name: String, type: TypeID, hasDefault: Bool)] = [
            ("delay",  types.longType, false),
            ("action", actionType,     false),
        ]

        // Idempotency: stamp the link name if an existing symbol already matches.
        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let sig = symbols.functionSignature(for: symbolID) else { return false }
            return sig.receiverType == timerType
                && sig.parameterTypes == parameterSpecs.map(\.type)
                && sig.returnType == timerTaskType
        }) {
            symbols.setExternalLinkName("kk_concurrent_schedule_delay", for: existing)
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
        if let packageSymbol {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }
        symbols.setExternalLinkName("kk_concurrent_schedule_delay", for: functionSymbol)

        var paramSymbols: [SymbolID] = []
        for spec in parameterSpecs {
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
                parameterTypes: parameterSpecs.map(\.type),
                returnType: timerTaskType,
                isSuspend: false,
                valueParameterSymbols: paramSymbols,
                valueParameterHasDefaultValues: parameterSpecs.map(\.hasDefault),
                valueParameterIsVararg: Array(repeating: false, count: paramSymbols.count)
            ),
            for: functionSymbol
        )
    }

    /// `Timer.schedule(delay: Long, period: Long, action: TimerTask.() -> Unit): TimerTask`
    private func registerSyntheticScheduleOverloadWithPeriod(
        packageFQName: [InternedString],
        packageSymbol: SymbolID?,
        timerType: TypeID,
        timerTaskType: TypeID,
        actionType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let functionName = interner.intern("schedule")
        let functionFQName = packageFQName + [functionName]

        let parameterSpecs: [(name: String, type: TypeID, hasDefault: Bool)] = [
            ("delay",  types.longType, false),
            ("period", types.longType, false),
            ("action", actionType,     false),
        ]

        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let sig = symbols.functionSignature(for: symbolID) else { return false }
            return sig.receiverType == timerType
                && sig.parameterTypes == parameterSpecs.map(\.type)
                && sig.returnType == timerTaskType
        }) {
            symbols.setExternalLinkName("kk_concurrent_schedule_period", for: existing)
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
        if let packageSymbol {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }
        symbols.setExternalLinkName("kk_concurrent_schedule_period", for: functionSymbol)

        var paramSymbols: [SymbolID] = []
        for spec in parameterSpecs {
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
                parameterTypes: parameterSpecs.map(\.type),
                returnType: timerTaskType,
                isSuspend: false,
                valueParameterSymbols: paramSymbols,
                valueParameterHasDefaultValues: parameterSpecs.map(\.hasDefault),
                valueParameterIsVararg: Array(repeating: false, count: paramSymbols.count)
            ),
            for: functionSymbol
        )
    }
}
