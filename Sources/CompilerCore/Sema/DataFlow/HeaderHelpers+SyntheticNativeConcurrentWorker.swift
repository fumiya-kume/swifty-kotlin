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

        // Worker.execute(mode: TransferMode, producer: () -> T1, job: (T1) -> T2): Future<T2>
        let executeName = interner.intern("execute")
        let executeFQName = workerFQName + [executeName]
        let executeT1Symbol = nativeConcurrentSyntheticTypeParameter(
            named: "T1",
            ownerFQName: executeFQName,
            symbols: symbols,
            interner: interner
        )
        let executeT2Symbol = nativeConcurrentSyntheticTypeParameter(
            named: "T2",
            ownerFQName: executeFQName,
            symbols: symbols,
            interner: interner
        )
        let executeT1Type = types.make(.typeParam(TypeParamType(
            symbol: executeT1Symbol,
            nullability: .nonNull
        )))
        let executeT2Type = types.make(.typeParam(TypeParamType(
            symbol: executeT2Symbol,
            nullability: .nonNull
        )))
        let executeProducerType = types.make(.functionType(FunctionType(
            params: [],
            returnType: executeT1Type
        )))
        let executeJobType = types.make(.functionType(FunctionType(
            params: [executeT1Type],
            returnType: executeT2Type
        )))
        registerNativeConcurrentMemberFunction(
            ownerSymbol: workerSymbol,
            ownerType: workerType,
            name: "execute",
            externalLinkName: "kk_worker_execute",
            returnType: nativeConcurrentFutureType(
                elementType: executeT2Type,
                symbols: symbols,
                types: types,
                interner: interner
            ),
            parameters: [
                (name: "mode", type: transferModeType),
                (name: "producer", type: executeProducerType),
                (name: "job", type: executeJobType),
            ],
            defaultValues: [false, false, false],
            typeParameterSymbols: [executeT1Symbol, executeT2Symbol],
            symbols: symbols,
            interner: interner
        )

        // Worker.requestTermination(processScheduled: Boolean = true): Future<Boolean>
        registerNativeConcurrentMemberFunction(
            ownerSymbol: workerSymbol,
            ownerType: workerType,
            name: "requestTermination",
            externalLinkName: "kk_worker_request_termination",
            returnType: nativeConcurrentFutureType(
                elementType: types.booleanType,
                symbols: symbols,
                types: types,
                interner: interner
            ),
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
