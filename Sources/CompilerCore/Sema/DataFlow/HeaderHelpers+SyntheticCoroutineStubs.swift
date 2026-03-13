import Foundation

extension DataFlowSemaPhase {
    func registerSyntheticCoroutineStubs(
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

        let kotlinxPkg = ensureSyntheticPackage(
            [interner.intern("kotlinx")],
            symbols: symbols,
            interner: interner
        )
        let coroutinesPkg = ensureSyntheticPackage(
            kotlinxPkg + [interner.intern("coroutines")],
            symbols: symbols,
            interner: interner
        )
        let channelsPkg = ensureSyntheticPackage(
            coroutinesPkg + [interner.intern("channels")],
            symbols: symbols,
            interner: interner
        )
        let flowPkg = ensureSyntheticPackage(
            coroutinesPkg + [interner.intern("flow")],
            symbols: symbols,
            interner: interner
        )

        let exceptionSymbol = ensureClassSymbol(
            named: "Exception",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        let jobSymbol = ensureClassSymbol(
            named: "Job",
            in: coroutinesPkg,
            symbols: symbols,
            interner: interner
        )
        let deferredSymbol = ensureClassSymbol(
            named: "Deferred",
            in: coroutinesPkg,
            symbols: symbols,
            interner: interner
        )
        let dispatchersSymbol = ensureObjectSymbol(
            named: "Dispatchers",
            in: coroutinesPkg,
            symbols: symbols,
            interner: interner
        )
        let flowInterfaceSymbol = ensureInterfaceSymbol(
            named: "Flow",
            in: flowPkg,
            symbols: symbols,
            interner: interner
        )
        let dispatcherSymbol = ensureClassSymbol(
            named: "CoroutineDispatcher",
            in: coroutinesPkg,
            symbols: symbols,
            interner: interner
        )
        let channelSymbol = ensureClassSymbol(
            named: "Channel",
            in: channelsPkg,
            symbols: symbols,
            interner: interner
        )
        let cancellationSymbol = ensureClassSymbol(
            named: "CancellationException",
            in: coroutinesPkg,
            symbols: symbols,
            interner: interner
        )
        let rootCancellationSymbol: SymbolID = if let existing = symbols.lookup(fqName: [interner.intern("CancellationException")]) {
            existing
        } else {
            symbols.define(
                kind: .class,
                name: interner.intern("CancellationException"),
                fqName: [interner.intern("CancellationException")],
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }

        let jobType = types.make(.classType(ClassType(
            classSymbol: jobSymbol,
            args: [],
            nullability: .nonNull
        )))
        let deferredType = types.make(.classType(ClassType(
            classSymbol: deferredSymbol,
            args: [],
            nullability: .nonNull
        )))
        let dispatchersType = types.make(.classType(ClassType(
            classSymbol: dispatchersSymbol,
            args: [],
            nullability: .nonNull
        )))
        let flowRawType = types.make(.classType(ClassType(
            classSymbol: flowInterfaceSymbol,
            args: [],
            nullability: .nonNull
        )))
        let dispatcherType = types.make(.classType(ClassType(
            classSymbol: dispatcherSymbol,
            args: [],
            nullability: .nonNull
        )))
        let channelType = types.make(.classType(ClassType(
            classSymbol: channelSymbol,
            args: [],
            nullability: .nonNull
        )))
        let cancellationType = types.make(.classType(ClassType(
            classSymbol: cancellationSymbol,
            args: [],
            nullability: .nonNull
        )))
        let rootCancellationType = types.make(.classType(ClassType(
            classSymbol: rootCancellationSymbol,
            args: [],
            nullability: .nonNull
        )))

        symbols.setPropertyType(jobType, for: jobSymbol)
        symbols.setPropertyType(deferredType, for: deferredSymbol)
        symbols.setPropertyType(dispatchersType, for: dispatchersSymbol)
        symbols.setPropertyType(flowRawType, for: flowInterfaceSymbol)
        symbols.setPropertyType(dispatcherType, for: dispatcherSymbol)
        symbols.setPropertyType(channelType, for: channelSymbol)
        symbols.setPropertyType(cancellationType, for: cancellationSymbol)
        symbols.setPropertyType(rootCancellationType, for: rootCancellationSymbol)
        symbols.setDirectSupertypes([exceptionSymbol], for: cancellationSymbol)
        symbols.setDirectSupertypes([exceptionSymbol], for: rootCancellationSymbol)

        registerSyntheticCoroutineTopLevelFunction(
            named: "runBlocking",
            packageFQName: coroutinesPkg,
            parameterName: "block",
            parameterType: types.make(.functionType(FunctionType(
                params: [],
                returnType: types.anyType,
                isSuspend: true,
                nullability: .nonNull
            ))),
            returnType: types.anyType,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCoroutineTopLevelFunction(
            named: "launch",
            packageFQName: coroutinesPkg,
            parameterName: "block",
            parameterType: types.make(.functionType(FunctionType(
                params: [],
                returnType: types.unitType,
                isSuspend: true,
                nullability: .nonNull
            ))),
            returnType: jobType,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCoroutineTopLevelFunction(
            named: "async",
            packageFQName: coroutinesPkg,
            parameterName: "block",
            parameterType: types.make(.functionType(FunctionType(
                params: [],
                returnType: types.anyType,
                isSuspend: true,
                nullability: .nonNull
            ))),
            returnType: deferredType,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCoroutineTopLevelFunction(
            named: "delay",
            packageFQName: coroutinesPkg,
            parameterName: "timeMillis",
            parameterType: types.longType,
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCoroutineTopLevelFunction(
            named: "withContext",
            packageFQName: coroutinesPkg,
            parameters: [
                (name: "context", type: dispatcherType),
                (name: "block", type: types.make(.functionType(FunctionType(
                    params: [],
                    returnType: types.anyType,
                    isSuspend: true,
                    nullability: .nonNull
                )))),
            ],
            returnType: types.anyType,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCoroutineConstructor(
            ownerSymbol: channelSymbol,
            ownerType: channelType,
            externalLinkName: "kk_channel_create",
            parameters: [],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticChannelFactoryBridge(
            packageFQName: channelsPkg,
            channelSymbol: channelSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )

        registerSyntheticObjectProperty(
            ownerSymbol: dispatchersSymbol,
            ownerType: dispatchersType,
            name: "Default",
            propertyType: dispatcherType,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticObjectProperty(
            ownerSymbol: dispatchersSymbol,
            ownerType: dispatchersType,
            name: "IO",
            propertyType: dispatcherType,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticObjectProperty(
            ownerSymbol: dispatchersSymbol,
            ownerType: dispatchersType,
            name: "Main",
            propertyType: dispatcherType,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticCoroutineMember(
            ownerSymbol: jobSymbol,
            ownerType: jobType,
            name: "cancel",
            externalLinkName: "kk_job_cancel",
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCoroutineMember(
            ownerSymbol: jobSymbol,
            ownerType: jobType,
            name: "join",
            externalLinkName: "kk_job_join",
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCoroutineMember(
            ownerSymbol: deferredSymbol,
            ownerType: deferredType,
            name: "await",
            externalLinkName: "kk_kxmini_async_await",
            returnType: types.anyType,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCoroutineMember(
            ownerSymbol: channelSymbol,
            ownerType: channelType,
            name: "send",
            externalLinkName: "kk_channel_send",
            returnType: types.unitType,
            parameters: [(name: "value", type: types.anyType)],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCoroutineMember(
            ownerSymbol: channelSymbol,
            ownerType: channelType,
            name: "receive",
            externalLinkName: "kk_channel_receive",
            returnType: types.anyType,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCoroutineMember(
            ownerSymbol: channelSymbol,
            ownerType: channelType,
            name: "close",
            externalLinkName: "kk_channel_close",
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )
    }

    private func registerSyntheticCoroutineTopLevelFunction(
        named name: String,
        packageFQName: [InternedString],
        parameterName: String,
        parameterType: TypeID,
        returnType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        registerSyntheticCoroutineTopLevelFunction(
            named: name,
            packageFQName: packageFQName,
            parameters: [(name: parameterName, type: parameterType)],
            returnType: returnType,
            symbols: symbols,
            interner: interner
        )
    }

    private func registerSyntheticCoroutineTopLevelFunction(
        named name: String,
        packageFQName: [InternedString],
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        externalLinkName: String? = nil,
        syntheticTypeParameterNames: [String] = [],
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let functionName = interner.intern(name)
        let functionFQName = packageFQName + [functionName]
        guard symbols.lookup(fqName: functionFQName) == nil else {
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
        if let externalLinkName, !externalLinkName.isEmpty {
            symbols.setExternalLinkName(externalLinkName, for: functionSymbol)
        }
        var typeParameterSymbols: [SymbolID] = []
        if !syntheticTypeParameterNames.isEmpty {
            let localNamespaceFQName = functionFQName + [interner.intern("$synthetic")]
            for typeParamName in syntheticTypeParameterNames {
                let internedTypeParamName = interner.intern(typeParamName)
                let typeParamSymbol = symbols.define(
                    kind: .typeParameter,
                    name: internedTypeParamName,
                    fqName: localNamespaceFQName + [internedTypeParamName],
                    declSite: nil,
                    visibility: .private,
                    flags: [.synthetic]
                )
                typeParameterSymbols.append(typeParamSymbol)
            }
        }
        var valueParameterSymbols: [SymbolID] = []
        for parameter in parameters {
            let paramNameID = interner.intern(parameter.name)
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: paramNameID,
                fqName: functionFQName + [paramNameID],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(functionSymbol, for: paramSymbol)
            valueParameterSymbols.append(paramSymbol)
        }
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: parameters.map(\.type),
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count),
                typeParameterSymbols: typeParameterSymbols
            ),
            for: functionSymbol
        )
    }

    private func registerSyntheticCoroutineMember(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        name: String,
        externalLinkName: String,
        returnType: TypeID,
        parameters: [(name: String, type: TypeID)] = [],
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let memberName = interner.intern(name)
        let memberFQName = ownerInfo.fqName + [memberName]
        guard symbols.lookup(fqName: memberFQName) == nil else {
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

    private func registerSyntheticCoroutineConstructor(
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
        guard symbols.lookup(fqName: ctorFQName) == nil else {
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
                isSuspend: false,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
            ),
            for: ctorSymbol
        )
    }

    private func registerSyntheticObjectProperty(
        ownerSymbol: SymbolID,
        ownerType _: TypeID,
        name: String,
        propertyType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let propertyName = interner.intern(name)
        let propertyFQName = ownerInfo.fqName + [propertyName]
        guard symbols.lookup(fqName: propertyFQName) == nil else {
            return
        }
        let propertySymbol = symbols.define(
            kind: .property,
            name: propertyName,
            fqName: propertyFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: propertySymbol)
        symbols.setPropertyType(propertyType, for: propertySymbol)
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

    private func registerSyntheticChannelFactoryBridge(
        packageFQName: [InternedString],
        channelSymbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let functionName = interner.intern("Channel")
        let functionFQName = packageFQName + [functionName]
        guard symbols.lookup(fqName: functionFQName) == nil else {
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
        symbols.setExternalLinkName("kk_channel_create", for: functionSymbol)

        let typeParamName = interner.intern("T")
        let typeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: typeParamName,
            fqName: functionFQName + [interner.intern("$synthetic"), typeParamName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        let returnType = types.make(.classType(ClassType(
            classSymbol: channelSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [],
                returnType: returnType,
                typeParameterSymbols: [typeParamSymbol]
            ),
            for: functionSymbol
        )
    }

    private func ensureSyntheticPackage(
        _ fqName: [InternedString],
        symbols: SymbolTable,
        interner: StringInterner
    ) -> [InternedString] {
        if symbols.lookup(fqName: fqName) == nil {
            _ = symbols.define(
                kind: .package,
                name: fqName.last ?? interner.intern("_root_"),
                fqName: fqName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        return fqName
    }
}
