// jscpd:ignore-start
/// `registerSyntheticCoroutineCancellationStubs` and the private
/// helpers used by the synthetic Coroutine stub registration
/// (top-level functions, extension functions, members, constructors,
/// channel factory bridges, intrinsics stubs, annotation attachment).
///
/// Split out from `HeaderHelpers+SyntheticCoroutineStubs.swift`.
extension DataFlowSemaPhase {
    func registerSyntheticCoroutineCancellationStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let jobFQName: [InternedString] = [interner.intern("kotlinx"), interner.intern("coroutines"), interner.intern("Job")]
        guard let jobSymbol = symbols.lookup(fqName: jobFQName) else {
            return
        }
        let jobType = types.make(.classType(ClassType(
            classSymbol: jobSymbol,
            args: [],
            nullability: .nonNull
        )))
        let cancellationPkg = ensureSyntheticCoroutinePackage(
            ensurePackage(
                path: ["kotlin", "coroutines", "cancellation"],
                symbols: symbols,
                interner: interner
            ),
            symbols: symbols,
            interner: interner
        )

        registerSyntheticCoroutineExtensionFunction(
            named: "cancel",
            packageFQName: cancellationPkg,
            receiverType: jobType,
            externalLinkName: "kk_job_cancel",
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )
    }

    func registerSyntheticCoroutineTopLevelFunction(
        named name: String,
        packageFQName: [InternedString],
        parameterName: String,
        parameterType: TypeID,
        returnType: TypeID,
        flags: SymbolFlags = [.synthetic],
        isSuspend: Bool = false,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        registerSyntheticCoroutineTopLevelFunction(
            named: name,
            packageFQName: packageFQName,
            parameters: [(name: parameterName, type: parameterType)],
            returnType: returnType,
            isSuspend: isSuspend,
            flags: flags,
            symbols: symbols,
            interner: interner
        )
    }

    func registerSyntheticCoroutineExtensionFunction(
        named name: String,
        packageFQName: [InternedString],
        receiverType: TypeID,
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        externalLinkName: String? = nil,
        flags: SymbolFlags = [.synthetic],
        typeParameterSymbols: [SymbolID] = [],
        classTypeParameterCount: Int = 0,
        syntheticTypeParameterNames: [String] = [],
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let functionName = interner.intern(name)
        let functionFQName = packageFQName + [functionName]
        let existingSymbols = symbols.lookupAll(fqName: functionFQName)
        let hasExistingFunctionWithSameSignature = existingSymbols.contains { id in
            guard let sym = symbols.symbol(id),
                  sym.kind == .function,
                  let sig = symbols.functionSignature(for: id)
            else {
                return false
            }
            return sig.receiverType == receiverType
                && sig.parameterTypes == parameters.map(\.type)
                && sig.returnType == returnType
        }
        guard !hasExistingFunctionWithSameSignature else {
            return
        }

        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: flags
        )
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }
        if let externalLinkName, !externalLinkName.isEmpty {
            symbols.setExternalLinkName(externalLinkName, for: functionSymbol)
        }

        var functionTypeParameterSymbols = typeParameterSymbols
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
                functionTypeParameterSymbols.append(typeParamSymbol)
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
                receiverType: receiverType,
                parameterTypes: parameters.map(\.type),
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count),
                typeParameterSymbols: functionTypeParameterSymbols,
                classTypeParameterCount: classTypeParameterCount
            ),
            for: functionSymbol
        )
    }

    func registerSyntheticCoroutineTopLevelFunction(
        named name: String,
        packageFQName: [InternedString],
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        externalLinkName: String? = nil,
        isSuspend: Bool = false,
        syntheticTypeParameterNames: [String] = [],
        flags: SymbolFlags = [.synthetic],
        explicitTypeParameterSymbols: [SymbolID]? = nil,
        syntheticVarargParameterIndices: Set<Int> = [],
        valueParameterFQNameSuffixes: [String]? = nil,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let functionName = interner.intern(name)
        let functionFQName = packageFQName + [functionName]
        // Skip only true duplicate function signatures. Allow overloads with the
        // same arity but different parameter types, and allow nominal types to
        // share the same FQName with factory-style functions.
        let existingSymbols = symbols.lookupAll(fqName: functionFQName)
        let hasExistingFunctionWithSameSignature = existingSymbols.contains { id in
            guard let sym = symbols.symbol(id),
                  sym.kind == .function,
                  let sig = symbols.functionSignature(for: id)
            else {
                return false
            }
            return sig.receiverType == nil
                && sig.parameterTypes == parameters.map(\.type)
                && sig.returnType == returnType
        }
        guard !hasExistingFunctionWithSameSignature else {
            return
        }
        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: flags
        )
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }
        if let externalLinkName, !externalLinkName.isEmpty {
            symbols.setExternalLinkName(externalLinkName, for: functionSymbol)
        }
        var typeParameterSymbols: [SymbolID] = []
        if let explicitTypeParameterSymbols {
            typeParameterSymbols = explicitTypeParameterSymbols
            for typeParameterSymbol in explicitTypeParameterSymbols {
                symbols.setParentSymbol(functionSymbol, for: typeParameterSymbol)
            }
        } else if !syntheticTypeParameterNames.isEmpty {
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
                symbols.setParentSymbol(functionSymbol, for: typeParamSymbol)
                typeParameterSymbols.append(typeParamSymbol)
            }
        }
        var valueParameterSymbols: [SymbolID] = []
        for (index, parameter) in parameters.enumerated() {
            let paramNameID = interner.intern(parameter.name)
            let paramFQNameSuffix = if let valueParameterFQNameSuffixes,
                                       valueParameterFQNameSuffixes.indices.contains(index) {
                interner.intern(valueParameterFQNameSuffixes[index])
            } else {
                paramNameID
            }
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: paramNameID,
                fqName: functionFQName + [paramFQNameSuffix],
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
                isSuspend: isSuspend,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: parameters.indices.map { syntheticVarargParameterIndices.contains($0) },
                typeParameterSymbols: typeParameterSymbols
            ),
            for: functionSymbol
        )
    }

    func registerSyntheticCoroutineTopLevelProperty(
        named name: String,
        packageFQName: [InternedString],
        returnType: TypeID,
        externalLinkName: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let propertyName = interner.intern(name)
        let propertyFQName = packageFQName + [propertyName]
        if let existing = symbols.lookupAll(fqName: propertyFQName).first(where: { symbolID in
            symbols.symbol(symbolID)?.kind == .property
        }) {
            symbols.setExternalLinkName(externalLinkName, for: existing)
            symbols.setPropertyType(returnType, for: existing)
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
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: propertySymbol)
        }
        symbols.setExternalLinkName(externalLinkName, for: propertySymbol)
        symbols.setPropertyType(returnType, for: propertySymbol)
    }

    func registerSyntheticCoroutineExtensionFunction(
        named name: String,
        packageFQName: [InternedString],
        receiverType: TypeID,
        externalLinkName: String,
        returnType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let functionName = interner.intern(name)
        let functionFQName = packageFQName + [functionName]
        let existingSymbols = symbols.lookupAll(fqName: functionFQName)
        if let existing = existingSymbols.first(where: { symbolID in
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
                returnType: returnType
            ),
            for: functionSymbol
        )
    }

    func registerSyntheticCoroutineMember(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        name: String,
        externalLinkName: String? = nil,
        returnType: TypeID,
        parameters: [(name: String, type: TypeID)] = [],
        flags: SymbolFlags = [.synthetic],
        typeParameterSymbols: [SymbolID] = [],
        classTypeParameterCount: Int = 0,
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
            flags: flags
        )
        symbols.setParentSymbol(ownerSymbol, for: memberSymbol)
        if let externalLinkName {
            symbols.setExternalLinkName(externalLinkName, for: memberSymbol)
        }
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
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count),
                typeParameterSymbols: typeParameterSymbols,
                classTypeParameterCount: classTypeParameterCount
            ),
            for: memberSymbol
        )
    }

    func registerSyntheticCoroutineExtensionFunction(
        named name: String,
        packageFQName: [InternedString],
        receiverType: TypeID,
        externalLinkName: String,
        returnType: TypeID,
        parameters: [(name: String, type: TypeID)] = [],
        flags: SymbolFlags = [.synthetic],
        classTypeParameterCount: Int = 0,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let functionName = interner.intern(name)
        let functionFQName = packageFQName + [functionName]
        let existingSymbols = symbols.lookupAll(fqName: functionFQName)
        let hasExistingFunctionWithSameSignature = existingSymbols.contains { id in
            guard let sym = symbols.symbol(id),
                  sym.kind == .function,
                  let sig = symbols.functionSignature(for: id)
            else {
                return false
            }
            return sig.receiverType == receiverType
                && sig.parameterTypes == parameters.map(\.type)
                && sig.returnType == returnType
        }
        guard !hasExistingFunctionWithSameSignature else {
            return
        }
        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: flags
        )
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }
        symbols.setExternalLinkName(externalLinkName, for: functionSymbol)
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
                receiverType: receiverType,
                parameterTypes: parameters.map(\.type),
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count),
                classTypeParameterCount: classTypeParameterCount
            ),
            for: functionSymbol
        )
    }

    func registerSyntheticCoroutineConstructor(
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

    func registerSyntheticObjectProperty(
        ownerSymbol: SymbolID,
        ownerType _: TypeID,
        name: String,
        propertyType: TypeID,
        externalLinkName: String? = nil,
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
        if let externalLinkName {
            symbols.setExternalLinkName(externalLinkName, for: propertySymbol)
        }
    }

    func registerSyntheticChannelFactoryBridge(
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

    /// Registers a synthetic `Channel(capacity: Int)` factory function that maps
    /// to `kk_channel_create` for buffered channel construction.
    func registerSyntheticChannelFactoryBridgeWithCapacity(
        packageFQName: [InternedString],
        channelSymbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let functionName = interner.intern("Channel")
        // Use a unique synthetic suffix to distinguish from the no-arg overload.
        let overloadFQName = packageFQName + [interner.intern("Channel$capacity")]
        guard symbols.lookup(fqName: overloadFQName) == nil else {
            return
        }

        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: overloadFQName,
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
            fqName: overloadFQName + [interner.intern("$synthetic"), typeParamName],
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
        let capacityParamName = interner.intern("capacity")
        let capacityParamSymbol = symbols.define(
            kind: .valueParameter,
            name: capacityParamName,
            fqName: overloadFQName + [capacityParamName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(functionSymbol, for: capacityParamSymbol)

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [types.intType],
                returnType: returnType,
                valueParameterSymbols: [capacityParamSymbol],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [false],
                typeParameterSymbols: [typeParamSymbol]
            ),
            for: functionSymbol
        )
    }

    func ensureSyntheticCoroutinePackage(
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

    func registerSyntheticCoroutineIntrinsicsStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinPkg: [InternedString] = [interner.intern("kotlin")]
        let kotlinCoroutinesPkg = ensureSyntheticCoroutinePackage(
            kotlinPkg + [interner.intern("coroutines")],
            symbols: symbols,
            interner: interner
        )
        let intrinsicsPkg = ensureSyntheticCoroutinePackage(
            kotlinCoroutinesPkg + [interner.intern("intrinsics")],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCoroutineTopLevelProperty(
            named: "COROUTINE_SUSPENDED",
            packageFQName: intrinsicsPkg,
            returnType: types.nullableAnyType,
            externalLinkName: "kk_coroutine_suspended",
            symbols: symbols,
            interner: interner
        )
    }

    func attachRestrictsSuspensionAnnotationMetadata(
        to symbol: SymbolID,
        symbols: SymbolTable
    ) {
        let targetRecord = MetadataAnnotationRecord(
            annotationFQName: "kotlin.annotation.Target",
            arguments: ["AnnotationTarget.CLASS"]
        )
        var annotations = symbols.annotations(for: symbol)
        if !annotations.contains(targetRecord) {
            annotations.append(targetRecord)
        }
        symbols.setAnnotations(annotations, for: symbol)
    }

    func attachCoroutineExperimentalStdlibApiAnnotation(
        to symbol: SymbolID,
        symbols: SymbolTable
    ) {
        let record = MetadataAnnotationRecord(annotationFQName: "kotlin.ExperimentalStdlibApi")
        var annotations = symbols.annotations(for: symbol)
        if !annotations.contains(record) {
            annotations.append(record)
        }
        symbols.setAnnotations(annotations, for: symbol)
    }
}
// jscpd:ignore-end
