import Foundation

/// Synthetic stdlib stubs for `kotlin.native.concurrent`: Worker class with Companion.start, member functions, and properties.
///
/// Split out from `HeaderHelpers+SyntheticNativeConcurrentStubs.swift` to isolate
/// merge conflicts between parallel stdlib PRs adding new entries to this package.
extension DataFlowSemaPhase {

    // MARK: - Worker

    func registerNativeConcurrentWorker(
        packageFQName: [InternedString],
        pkgSymbol: SymbolID?,
        transferModeType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let workerName = interner.intern("Worker")
        let workerFQName = packageFQName + [workerName]

        let workerSymbol: SymbolID
        if let existing = symbols.lookup(fqName: workerFQName), symbols.symbol(existing)?.kind == .class {
            workerSymbol = existing
        } else {
            workerSymbol = symbols.define(
                kind: .class,
                name: workerName,
                fqName: workerFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        if let pkgSymbol {
            symbols.setParentSymbol(pkgSymbol, for: workerSymbol)
        }
        let workerType = types.make(.classType(ClassType(
            classSymbol: workerSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(workerType, for: workerSymbol)

        // Worker companion: start(name: String? = null): Worker
        let companionName = interner.intern("Companion")
        let companionFQName = workerFQName + [companionName]
        let companionSymbol: SymbolID
        if let existing = symbols.lookup(fqName: companionFQName) {
            companionSymbol = existing
        } else {
            companionSymbol = symbols.define(
                kind: .object,
                name: companionName,
                fqName: companionFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        symbols.setParentSymbol(workerSymbol, for: companionSymbol)
        let companionType = types.make(.classType(ClassType(
            classSymbol: companionSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(companionType, for: companionSymbol)

        // Worker.Companion.start(name: String? = null): Worker
        registerNativeConcurrentMemberFunction(
            ownerSymbol: companionSymbol,
            ownerType: companionType,
            name: "start",
            externalLinkName: "kk_worker_new",
            returnType: workerType,
            parameters: [(name: "name", type: types.makeNullable(types.stringType))],
            defaultValues: [true],
            symbols: symbols,
            interner: interner
        )

        // Worker.execute(mode: TransferMode, producer: () -> T): Future<T>
        // Since Future<T> is registered later (no type param yet), register a simpler version
        // returning Any for now (the full generic version requires Future to exist first).
        // We register the execute signature with the intType placeholder in tests.
        // Instead, omit the full generic execute and register the simpler transfer-mode-free version.

        // Worker.requestTermination(processScheduled: Boolean = true): Future<Boolean>
        // Simplified: returns unitType (we do not have Future yet here)
        registerNativeConcurrentMemberFunction(
            ownerSymbol: workerSymbol,
            ownerType: workerType,
            name: "requestTermination",
            externalLinkName: "kk_worker_request_termination",
            returnType: types.unitType,
            parameters: [(name: "processScheduled", type: types.booleanType)],
            defaultValues: [true],
            symbols: symbols,
            interner: interner
        )

        // Worker.isTerminated: Boolean (property)
        registerNativeConcurrentReadOnlyProperty(
            ownerSymbol: workerSymbol,
            name: "isTerminated",
            propertyType: types.booleanType,
            getterLinkName: "kk_worker_is_terminated",
            symbols: symbols,
            interner: interner
        )

        // Worker.name: String (property)
        registerNativeConcurrentReadOnlyProperty(
            ownerSymbol: workerSymbol,
            name: "name",
            propertyType: types.stringType,
            getterLinkName: "kk_worker_name",
            symbols: symbols,
            interner: interner
        )
    }
}
