import Foundation

/// Synthetic stdlib stubs for `kotlin.native.concurrent`: shared helpers (symbol/type/property registration utilities) used across all native-concurrent topic files.
///
/// Split out from `HeaderHelpers+SyntheticNativeConcurrentStubs.swift` to isolate
/// merge conflicts between parallel stdlib PRs adding new entries to this package.
extension DataFlowSemaPhase {

    // MARK: - Helpers

    func ensureNativeConcurrentEnum(
        named name: String,
        entries: [String],
        in pkg: [InternedString],
        pkgSymbol: SymbolID?,
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID {
        let internedName = interner.intern(name)
        let fqName = pkg + [internedName]
        let enumSymbol: SymbolID
        if let existing = symbols.lookup(fqName: fqName) {
            enumSymbol = existing
        } else {
            enumSymbol = symbols.define(
                kind: .enumClass,
                name: internedName,
                fqName: fqName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            if let pkgSymbol {
                symbols.setParentSymbol(pkgSymbol, for: enumSymbol)
            }
        }
        for entry in entries {
            let entryName = interner.intern(entry)
            let entryFQName = fqName + [entryName]
            if symbols.lookup(fqName: entryFQName) != nil { continue }
            let entrySymbol = symbols.define(
                kind: .field,
                name: entryName,
                fqName: entryFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(enumSymbol, for: entrySymbol)
        }
        return enumSymbol
    }

    func setNativeConcurrentEnumEntryTypes(
        enumSymbol: SymbolID,
        enumType: TypeID,
        symbols: SymbolTable
    ) {
        guard let enumInfo = symbols.symbol(enumSymbol) else { return }
        for child in symbols.children(ofFQName: enumInfo.fqName) {
            guard let childInfo = symbols.symbol(child), childInfo.kind == .field else { continue }
            if symbols.propertyType(for: child) == nil {
                symbols.setPropertyType(enumType, for: child)
            }
        }
    }

    func registerNativeConcurrentMemberFunction(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        name: String,
        externalLinkName: String? = nil,
        returnType: TypeID,
        parameters: [(name: String, type: TypeID)],
        defaultValues: [Bool],
        typeParameterSymbols: [SymbolID] = [],
        classTypeParameterCount: Int = 0,
        flags: SymbolFlags = [.synthetic],
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else { return }
        let memberName = interner.intern(name)
        let memberFQName = ownerInfo.fqName + [memberName]
        guard symbols.lookupAll(fqName: memberFQName).first(where: { id in
            guard let sig = symbols.functionSignature(for: id) else { return false }
            return sig.parameterTypes == parameters.map(\.type) && sig.returnType == returnType
        }) == nil else { return }

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
            let paramName = interner.intern(parameter.name)
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: paramName,
                fqName: memberFQName + [paramName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(memberSymbol, for: paramSymbol)
            symbols.setPropertyType(parameter.type, for: paramSymbol)
            valueParameterSymbols.append(paramSymbol)
        }

        let defaults = defaultValues.isEmpty
            ? Array(repeating: false, count: parameters.count)
            : defaultValues
        let varargs = Array(repeating: false, count: parameters.count)

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: ownerType,
                parameterTypes: parameters.map(\.type),
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: defaults,
                valueParameterIsVararg: varargs,
                typeParameterSymbols: typeParameterSymbols,
                classTypeParameterCount: classTypeParameterCount
            ),
            for: memberSymbol
        )
    }

    func registerNativeConcurrentConstructor(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        externalLinkName: String? = nil,
        parameters: [(name: String, type: TypeID)],
        defaultValues: [Bool],
        typeParameterSymbols: [SymbolID] = [],
        classTypeParameterCount: Int = 0,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else { return }
        let initName = interner.intern("<init>")
        let constructorFQName = ownerInfo.fqName + [initName]
        let parameterTypes = parameters.map(\.type)
        guard symbols.lookupAll(fqName: constructorFQName).first(where: { id in
            guard symbols.symbol(id)?.kind == .constructor,
                  let sig = symbols.functionSignature(for: id)
            else {
                return false
            }
            return sig.parameterTypes == parameterTypes
        }) == nil else {
            return
        }

        let constructorSymbol = symbols.define(
            kind: .constructor,
            name: initName,
            fqName: constructorFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: constructorSymbol)
        if let externalLinkName {
            symbols.setExternalLinkName(externalLinkName, for: constructorSymbol)
        }

        let valueParameterSymbols = parameters.map { parameter in
            let paramName = interner.intern(parameter.name)
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: paramName,
                fqName: constructorFQName + [paramName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(constructorSymbol, for: paramSymbol)
            symbols.setPropertyType(parameter.type, for: paramSymbol)
            return paramSymbol
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: nil,
                parameterTypes: parameterTypes,
                returnType: ownerType,
                isSuspend: false,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: defaultValues,
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count),
                typeParameterSymbols: typeParameterSymbols,
                classTypeParameterCount: classTypeParameterCount
            ),
            for: constructorSymbol
        )
    }

    func nativeConcurrentClassType(
        packagePath: [String],
        name: String,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> TypeID {
        let classSymbol = nativeConcurrentClassSymbol(
            packagePath: packagePath,
            name: name,
            symbols: symbols,
            interner: interner
        )
        let classType = types.make(.classType(ClassType(
            classSymbol: classSymbol,
            args: [],
            nullability: .nonNull
        )))
        if symbols.propertyType(for: classSymbol) == nil {
            symbols.setPropertyType(classType, for: classSymbol)
        }
        return classType
    }

    func nativeConcurrentClassSymbol(
        packagePath: [String],
        name: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID {
        let packageFQName = ensurePackage(
            path: packagePath,
            symbols: symbols,
            interner: interner
        )
        let packageSymbol = symbols.lookup(fqName: packageFQName)
        let classSymbol = ensureClassSymbol(
            named: name,
            in: packageFQName,
            symbols: symbols,
            interner: interner
        )
        if let packageSymbol {
            symbols.setParentSymbol(packageSymbol, for: classSymbol)
        }
        return classSymbol
    }

    func nativeConcurrentSyntheticTypeParameter(
        named name: String,
        ownerFQName: [InternedString],
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID {
        let typeParamName = interner.intern(name)
        let typeParamFQName = ownerFQName + [typeParamName]
        if let existing = symbols.lookup(fqName: typeParamFQName) {
            return existing
        }
        return symbols.define(
            kind: .typeParameter,
            name: typeParamName,
            fqName: typeParamFQName,
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
    }

    func nativeConcurrentFutureType(
        elementType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> TypeID {
        let futureSymbol = nativeConcurrentClassSymbol(
            packagePath: ["kotlin", "native", "concurrent"],
            name: "Future",
            symbols: symbols,
            interner: interner
        )
        return types.make(.classType(ClassType(
            classSymbol: futureSymbol,
            args: [.invariant(elementType)],
            nullability: .nonNull
        )))
    }

    func nativeConcurrentCollectionType(
        named name: String,
        elementType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> TypeID {
        let collectionSymbol = nativeConcurrentClassSymbol(
            packagePath: ["kotlin", "collections"],
            name: name,
            symbols: symbols,
            interner: interner
        )
        return types.make(.classType(ClassType(
            classSymbol: collectionSymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))
    }

    func nativeConcurrentCPointerType(
        pointeeType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> TypeID {
        let cPointerSymbol = nativeConcurrentClassSymbol(
            packagePath: ["kotlinx", "cinterop"],
            name: "CPointer",
            symbols: symbols,
            interner: interner
        )
        return types.make(.classType(ClassType(
            classSymbol: cPointerSymbol,
            args: [.invariant(pointeeType)],
            nullability: .nonNull
        )))
    }

    func nativeConcurrentCFunctionType(
        functionType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> TypeID {
        let cinteropPkg = ensurePackage(
            path: ["kotlinx", "cinterop"],
            symbols: symbols,
            interner: interner
        )
        let cinteropPkgSymbol = symbols.lookup(fqName: cinteropPkg)
        let cFunctionSymbol = ensureClassSymbol(
            named: "CFunction",
            in: cinteropPkg,
            symbols: symbols,
            interner: interner
        )
        if let cinteropPkgSymbol {
            symbols.setParentSymbol(cinteropPkgSymbol, for: cFunctionSymbol)
        }

        let typeParameterName = interner.intern("T")
        let typeParameterFQName = cinteropPkg + [interner.intern("CFunction"), typeParameterName]
        let typeParameterSymbol: SymbolID
        if let existing = symbols.lookup(fqName: typeParameterFQName) {
            typeParameterSymbol = existing
        } else {
            typeParameterSymbol = symbols.define(
                kind: .typeParameter,
                name: typeParameterName,
                fqName: typeParameterFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
            symbols.setParentSymbol(cFunctionSymbol, for: typeParameterSymbol)
        }
        symbols.setTypeParameterUpperBounds([types.anyType], for: typeParameterSymbol)
        types.setNominalTypeParameterSymbols([typeParameterSymbol], for: cFunctionSymbol)
        types.setNominalTypeParameterVariances([.invariant], for: cFunctionSymbol)

        let typeParameterType = types.make(.typeParam(TypeParamType(
            symbol: typeParameterSymbol,
            nullability: .nonNull
        )))
        let cFunctionDeclarationType = types.make(.classType(ClassType(
            classSymbol: cFunctionSymbol,
            args: [.invariant(typeParameterType)],
            nullability: .nonNull
        )))
        symbols.setPropertyType(cFunctionDeclarationType, for: cFunctionSymbol)

        let cPointedSymbol = nativeConcurrentClassSymbol(
            packagePath: ["kotlinx", "cinterop"],
            name: "CPointed",
            symbols: symbols,
            interner: interner
        )
        if !symbols.directSupertypes(for: cFunctionSymbol).contains(cPointedSymbol) {
            symbols.setDirectSupertypes(
                symbols.directSupertypes(for: cFunctionSymbol) + [cPointedSymbol],
                for: cFunctionSymbol
            )
        }
        if !types.directNominalSupertypes(for: cFunctionSymbol).contains(cPointedSymbol) {
            types.setNominalDirectSupertypes(
                types.directNominalSupertypes(for: cFunctionSymbol) + [cPointedSymbol],
                for: cFunctionSymbol
            )
        }

        return types.make(.classType(ClassType(
            classSymbol: cFunctionSymbol,
            args: [.invariant(functionType)],
            nullability: .nonNull
        )))
    }

    func registerNativeConcurrentContinuationFunctionSupertype(
        ownerSymbol: SymbolID,
        functionArity: Int,
        functionArgumentTypes: [TypeID],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let functionSymbol = nativeConcurrentFunctionInterfaceSymbol(
            arity: functionArity,
            symbols: symbols,
            interner: interner
        )
        if !symbols.directSupertypes(for: ownerSymbol).contains(functionSymbol) {
            symbols.setDirectSupertypes(
                symbols.directSupertypes(for: ownerSymbol) + [functionSymbol],
                for: ownerSymbol
            )
        }
        if !types.directNominalSupertypes(for: ownerSymbol).contains(functionSymbol) {
            types.setNominalDirectSupertypes(
                types.directNominalSupertypes(for: ownerSymbol) + [functionSymbol],
                for: ownerSymbol
            )
        }

        let supertypeArgs: [TypeArg] = [.out(types.unitType)]
            + functionArgumentTypes.map { .in($0) }
        symbols.setSupertypeTypeArgs(supertypeArgs, for: ownerSymbol, supertype: functionSymbol)
        types.setNominalSupertypeTypeArgs(supertypeArgs, for: ownerSymbol, supertype: functionSymbol)
    }

    private func nativeConcurrentFunctionInterfaceSymbol(
        arity: Int,
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID {
        let functionPkg = ensurePackage(
            path: ["kotlin", "Function"],
            symbols: symbols,
            interner: interner
        )
        let functionPkgSymbol = symbols.lookup(fqName: functionPkg)
        let functionSymbol = ensureInterfaceSymbol(
            named: "Function\(arity)",
            in: functionPkg,
            symbols: symbols,
            interner: interner
        )
        if let functionPkgSymbol {
            symbols.setParentSymbol(functionPkgSymbol, for: functionSymbol)
        }
        return functionSymbol
    }

    func registerNativeConcurrentPackageFunction(
        named name: String,
        packageFQName: [InternedString],
        receiverType: TypeID?,
        returnType: TypeID,
        parameters: [(name: String, type: TypeID)],
        defaultValues: [Bool]? = nil,
        typeParameterSymbols: [SymbolID],
        annotations: [MetadataAnnotationRecord] = [],
        externalLinkName: String? = nil,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let functionName = interner.intern(name)
        let functionFQName = packageFQName + [functionName]
        let parameterTypes = parameters.map(\.type)
        guard symbols.lookupAll(fqName: functionFQName).first(where: { id in
            guard let signature = symbols.functionSignature(for: id) else { return false }
            return signature.receiverType == receiverType
                && signature.parameterTypes == parameterTypes
                && signature.returnType == returnType
                && signature.typeParameterSymbols == typeParameterSymbols
        }) == nil else {
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

        let valueParameterSymbols = parameters.map { parameter in
            let parameterName = interner.intern(parameter.name)
            let parameterSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: functionFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(functionSymbol, for: parameterSymbol)
            symbols.setPropertyType(parameter.type, for: parameterSymbol)
            return parameterSymbol
        }
        for typeParameterSymbol in typeParameterSymbols {
            symbols.setParentSymbol(functionSymbol, for: typeParameterSymbol)
        }
        if let externalLinkName {
            symbols.setExternalLinkName(externalLinkName, for: functionSymbol)
        }
        appendNativeConcurrentMetadataAnnotations(annotations, to: functionSymbol, symbols: symbols)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: parameterTypes,
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: defaultValues
                    ?? Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count),
                typeParameterSymbols: typeParameterSymbols,
                classTypeParameterCount: 0
            ),
            for: functionSymbol
        )
    }

    func nativeConcurrentLazyType(
        elementType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> TypeID {
        let kotlinPkg = ensurePackage(
            path: ["kotlin"],
            symbols: symbols,
            interner: interner
        )
        let lazySymbol = ensureInterfaceSymbol(
            named: "Lazy",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        if let packageSymbol = symbols.lookup(fqName: kotlinPkg) {
            symbols.setParentSymbol(packageSymbol, for: lazySymbol)
        }
        let lazyTypeParamName = interner.intern("T")
        let lazyTypeParamFQName = kotlinPkg + [interner.intern("Lazy"), lazyTypeParamName]
        let lazyTypeParamSymbol: SymbolID
        if let existing = symbols.lookup(fqName: lazyTypeParamFQName) {
            lazyTypeParamSymbol = existing
        } else {
            lazyTypeParamSymbol = symbols.define(
                kind: .typeParameter,
                name: lazyTypeParamName,
                fqName: lazyTypeParamFQName,
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(lazySymbol, for: lazyTypeParamSymbol)
        }
        types.setNominalTypeParameterSymbols([lazyTypeParamSymbol], for: lazySymbol)
        types.setNominalTypeParameterVariances([.out], for: lazySymbol)
        return types.make(.classType(ClassType(
            classSymbol: lazySymbol,
            args: [.invariant(elementType)],
            nullability: .nonNull
        )))
    }

    func appendNativeConcurrentMetadataAnnotations(
        _ records: [MetadataAnnotationRecord],
        to symbol: SymbolID,
        symbols: SymbolTable
    ) {
        appendSyntheticMetadataAnnotations(records, to: symbol, symbols: symbols)
    }

    func nativeConcurrentDeprecatedErrorAnnotation(
        message: String,
        replaceWith: String
    ) -> MetadataAnnotationRecord {
        MetadataAnnotationRecord(
            annotationFQName: "kotlin.Deprecated",
            arguments: [
                "message = \"\(message)\"",
                "replaceWith = ReplaceWith(\"\(replaceWith)\")",
                "level = DeprecationLevel.ERROR",
            ]
        )
    }

    func registerNativeConcurrentReadOnlyProperty(
        ownerSymbol: SymbolID,
        name: String,
        propertyType: TypeID,
        getterLinkName: String? = nil,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else { return }
        let propName = interner.intern(name)
        let propFQName = ownerInfo.fqName + [propName]
        if symbols.lookup(fqName: propFQName) != nil { return }

        let propSymbol = symbols.define(
            kind: .property,
            name: propName,
            fqName: propFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: propSymbol)
        symbols.setPropertyType(propertyType, for: propSymbol)
        if let getterLinkName {
            symbols.setExternalLinkName(getterLinkName, for: propSymbol)
        }
    }

    func registerNativeConcurrentMutableProperty(
        ownerSymbol: SymbolID,
        name: String,
        propertyType: TypeID,
        getterLinkName: String? = nil,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else { return }
        let propName = interner.intern(name)
        let propFQName = ownerInfo.fqName + [propName]
        if let existing = symbols.lookup(fqName: propFQName) {
            symbols.insertFlags([.synthetic, .mutable], for: existing)
            symbols.setPropertyType(propertyType, for: existing)
            if let getterLinkName {
                symbols.setExternalLinkName(getterLinkName, for: existing)
            }
            return
        }

        let propSymbol = symbols.define(
            kind: .property,
            name: propName,
            fqName: propFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .mutable]
        )
        symbols.setParentSymbol(ownerSymbol, for: propSymbol)
        symbols.setPropertyType(propertyType, for: propSymbol)
        if let getterLinkName {
            symbols.setExternalLinkName(getterLinkName, for: propSymbol)
        }
    }

    func appendNativeConcurrentAnnotationMetadata(
        to symbol: SymbolID,
        targets: [String],
        retention: String,
        symbols: SymbolTable
    ) {
        var annotations = symbols.annotations(for: symbol)
        let targetRecord = MetadataAnnotationRecord(
            annotationFQName: "kotlin.annotation.Target",
            arguments: targets
        )
        if !annotations.contains(targetRecord) {
            annotations.append(targetRecord)
        }
        let retentionRecord = MetadataAnnotationRecord(
            annotationFQName: "kotlin.annotation.Retention",
            arguments: [retention]
        )
        if !annotations.contains(retentionRecord) {
            annotations.append(retentionRecord)
        }
        symbols.setAnnotations(annotations, for: symbol)
    }
}
