// swiftlint:disable file_length

private enum SyntheticAnnotationAPISurfaceForHelpers {
    static let targetEntries = [
        "CLASS", "ANNOTATION_CLASS", "TYPE_PARAMETER", "PROPERTY", "FIELD",
        "LOCAL_VARIABLE", "VALUE_PARAMETER", "CONSTRUCTOR", "FUNCTION",
        "PROPERTY_GETTER", "PROPERTY_SETTER", "TYPE", "EXPRESSION", "FILE",
        "TYPEALIAS",
    ]
    static let retentionEntries = ["SOURCE", "BINARY", "RUNTIME"]
}

/// Helpers used by the synthetic Metaprog stub registration:
/// annotation class registration, JVM annotation registration,
/// AnnotationTarget / Retention / DeprecationLevel / RequiresOptInLevel
/// enums, the throws-exception-classes property/constructor, and
/// generic String / Boolean / Int annotation property/constructor
/// registration helpers.
///
/// Split out from `HeaderHelpers+SyntheticMetaprogStubs.swift`.
extension DataFlowSemaPhase {
    func registerSyntheticParameterNameMembers(
        ownerSymbol: SymbolID,
        ownerFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let stringType = types.stringType
        let ownerType = types.make(.classType(ClassType(
            classSymbol: ownerSymbol,
            args: [],
            nullability: .nonNull
        )))

        let name = interner.intern("name")
        let propertyFQName = ownerFQName + [name]
        let propertySymbol: SymbolID
        if let existing = symbols.lookup(fqName: propertyFQName) {
            propertySymbol = existing
        } else {
            propertySymbol = symbols.define(
                kind: .property,
                name: name,
                fqName: propertyFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        symbols.setParentSymbol(ownerSymbol, for: propertySymbol)
        symbols.setPropertyType(stringType, for: propertySymbol)

        let initName = interner.intern("<init>")
        let ctorFQName = ownerFQName + [initName]
        let ctorSymbol: SymbolID
        if let existing = symbols.lookupAll(fqName: ctorFQName).first(where: {
            symbols.symbol($0)?.kind == .constructor
        }) {
            ctorSymbol = existing
        } else {
            ctorSymbol = symbols.define(
                kind: .constructor,
                name: initName,
                fqName: ctorFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        symbols.setParentSymbol(ownerSymbol, for: ctorSymbol)

        let parameterFQName = ctorFQName + [name]
        let parameterSymbol: SymbolID
        if let existing = symbols.lookup(fqName: parameterFQName) {
            parameterSymbol = existing
        } else {
            parameterSymbol = symbols.define(
                kind: .valueParameter,
                name: name,
                fqName: parameterFQName,
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
        }
        symbols.setParentSymbol(ctorSymbol, for: parameterSymbol)
        symbols.setPropertyType(stringType, for: parameterSymbol)

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: ownerType,
                parameterTypes: [stringType],
                returnType: ownerType,
                valueParameterSymbols: [parameterSymbol],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [false]
            ),
            for: ctorSymbol
        )
    }

    func attachAnnotationIfNeeded(
        _ annotation: MetadataAnnotationRecord,
        to symbolFQName: [InternedString],
        symbols: SymbolTable
    ) {
        guard let symbol = symbols.lookup(fqName: symbolFQName) else {
            return
        }
        var annotations = symbols.annotations(for: symbol)
        if !annotations.contains(annotation) {
            annotations.append(annotation)
            symbols.setAnnotations(annotations, for: symbol)
        }
    }

    func registerSyntheticJvmAnnotationClass(
        named name: String,
        packageFQName: [InternedString],
        packageSymbol: SymbolID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let className = interner.intern(name)
        let classFQName = packageFQName + [className]
        if let existing = symbols.lookup(fqName: classFQName) {
            if packageSymbol != .invalid {
                symbols.setParentSymbol(packageSymbol, for: existing)
            }
            return
        }

        let classSymbol = symbols.define(
            kind: .annotationClass,
            name: className,
            fqName: classFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        if packageSymbol != .invalid {
            symbols.setParentSymbol(packageSymbol, for: classSymbol)
        }
    }

    func registerSyntheticContextFunctionTypeParamsAnnotation(
        packageFQName: [InternedString],
        packageSymbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let className = interner.intern(KnownCompilerAnnotation.contextFunctionTypeParams.simpleName)
        let classFQName = packageFQName + [className]
        let classSymbol: SymbolID
        if let existing = symbols.lookup(fqName: classFQName) {
            classSymbol = existing
        } else {
            classSymbol = symbols.define(
                kind: .annotationClass,
                name: className,
                fqName: classFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        if packageSymbol != .invalid {
            symbols.setParentSymbol(packageSymbol, for: classSymbol)
        }

        appendSyntheticAnnotation(
            MetadataAnnotationRecord(
                annotationFQName: KnownCompilerAnnotation.target.qualifiedName,
                arguments: ["AnnotationTarget.TYPE"]
            ),
            to: classSymbol,
            symbols: symbols
        )

        let classType = types.make(.classType(ClassType(
            classSymbol: classSymbol,
            args: [],
            nullability: .nonNull
        )))
        registerSyntheticAnnotationIntProperty(
            named: "count",
            ownerSymbol: classSymbol,
            ownerFQName: classFQName,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticAnnotationIntConstructor(
            ownerSymbol: classSymbol,
            ownerFQName: classFQName,
            ownerType: classType,
            parameterName: "count",
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    func registerSyntheticAnnotationIntProperty(
        named name: String,
        ownerSymbol: SymbolID,
        ownerFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let valueName = interner.intern(name)
        let valueFQName = ownerFQName + [valueName]
        let valueSymbol: SymbolID
        if let existing = symbols.lookup(fqName: valueFQName) {
            valueSymbol = existing
        } else {
            valueSymbol = symbols.define(
                kind: .property,
                name: valueName,
                fqName: valueFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }

        symbols.setParentSymbol(ownerSymbol, for: valueSymbol)
        symbols.setPropertyType(types.intType, for: valueSymbol)
    }

    func registerSyntheticAnnotationIntConstructor(
        ownerSymbol: SymbolID,
        ownerFQName: [InternedString],
        ownerType: TypeID,
        parameterName: String,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let initName = interner.intern("<init>")
        let initFQName = ownerFQName + [initName]
        let parameterTypes = [types.intType]
        if symbols.lookupAll(fqName: initFQName).contains(where: {
            symbols.functionSignature(for: $0)?.parameterTypes == parameterTypes
        }) {
            return
        }

        let initSymbol = symbols.define(
            kind: .constructor,
            name: initName,
            fqName: initFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: initSymbol)

        let paramName = interner.intern(parameterName)
        let paramSymbol = symbols.define(
            kind: .valueParameter,
            name: paramName,
            fqName: initFQName + [paramName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(initSymbol, for: paramSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: parameterTypes,
                returnType: ownerType,
                valueParameterSymbols: [paramSymbol],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [false]
            ),
            for: initSymbol
        )
    }

    func registerSyntheticAnnotationTargetEnum(
        packageFQName: [InternedString],
        packageSymbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let enumName = interner.intern("AnnotationTarget")
        let enumFQName = packageFQName + [enumName]
        let enumSymbol: SymbolID
        if let existing = symbols.lookup(fqName: enumFQName) {
            enumSymbol = existing
            if packageSymbol != .invalid {
                symbols.setParentSymbol(packageSymbol, for: existing)
            }
        } else {
            enumSymbol = symbols.define(
                kind: .enumClass,
                name: enumName,
                fqName: enumFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            if packageSymbol != .invalid {
                symbols.setParentSymbol(packageSymbol, for: enumSymbol)
            }
        }

        let enumType = types.make(.classType(ClassType(
            classSymbol: enumSymbol,
            args: [],
            nullability: .nonNull
        )))

        for entryName in SyntheticAnnotationAPISurfaceForHelpers.targetEntries {
            let entry = interner.intern(entryName)
            let entryFQName = enumFQName + [entry]
            let entrySymbol: SymbolID
            if let existing = symbols.lookup(fqName: entryFQName) {
                entrySymbol = existing
            } else {
                entrySymbol = symbols.define(
                    kind: .field,
                    name: entry,
                    fqName: entryFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
            }
            symbols.setParentSymbol(enumSymbol, for: entrySymbol)
            if symbols.propertyType(for: entrySymbol) == nil {
                symbols.setPropertyType(enumType, for: entrySymbol)
            }
        }
    }

    func registerSyntheticDeprecationLevelEnum(
        packageFQName: [InternedString],
        packageSymbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let enumName = interner.intern("DeprecationLevel")
        let enumFQName = packageFQName + [enumName]
        let enumSymbol: SymbolID
        if let existing = symbols.lookup(fqName: enumFQName) {
            enumSymbol = existing
            if packageSymbol != .invalid {
                symbols.setParentSymbol(packageSymbol, for: existing)
            }
        } else {
            enumSymbol = symbols.define(
                kind: .enumClass,
                name: enumName,
                fqName: enumFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            if packageSymbol != .invalid {
                symbols.setParentSymbol(packageSymbol, for: enumSymbol)
            }
        }

        let enumType = types.make(.classType(ClassType(
            classSymbol: enumSymbol,
            args: [],
            nullability: .nonNull
        )))

        for entryName in ["WARNING", "ERROR", "HIDDEN"] {
            let entry = interner.intern(entryName)
            let entryFQName = enumFQName + [entry]
            let entrySymbol: SymbolID
            if let existing = symbols.lookup(fqName: entryFQName) {
                entrySymbol = existing
            } else {
                entrySymbol = symbols.define(
                    kind: .field,
                    name: entry,
                    fqName: entryFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
            }
            symbols.setParentSymbol(enumSymbol, for: entrySymbol)
            if symbols.propertyType(for: entrySymbol) == nil {
                symbols.setPropertyType(enumType, for: entrySymbol)
            }
        }
    }

    func registerSyntheticDeprecatedSinceKotlinMembers(
        ownerSymbol: SymbolID,
        ownerFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        appendSyntheticAnnotation(
            MetadataAnnotationRecord(
                annotationFQName: KnownCompilerAnnotation.target.qualifiedName,
                arguments: [
                    "AnnotationTarget.CLASS",
                    "AnnotationTarget.FUNCTION",
                    "AnnotationTarget.PROPERTY",
                    "AnnotationTarget.ANNOTATION_CLASS",
                    "AnnotationTarget.CONSTRUCTOR",
                    "AnnotationTarget.PROPERTY_SETTER",
                    "AnnotationTarget.PROPERTY_GETTER",
                    "AnnotationTarget.TYPEALIAS",
                ]
            ),
            to: ownerSymbol,
            symbols: symbols
        )

        let stringType = types.stringType
        let ownerType = types.make(.classType(ClassType(
            classSymbol: ownerSymbol,
            args: [],
            nullability: .nonNull
        )))
        let propertyNames = ["warningSince", "errorSince", "hiddenSince"].map { interner.intern($0) }
        for propertyName in propertyNames {
            let propertyFQName = ownerFQName + [propertyName]
            let propertySymbol: SymbolID
            if let existing = symbols.lookup(fqName: propertyFQName) {
                propertySymbol = existing
            } else {
                propertySymbol = symbols.define(
                    kind: .property,
                    name: propertyName,
                    fqName: propertyFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
            }
            symbols.setParentSymbol(ownerSymbol, for: propertySymbol)
            symbols.setPropertyType(stringType, for: propertySymbol)
        }

        let initName = interner.intern("<init>")
        let ctorFQName = ownerFQName + [initName]
        let ctorSymbol: SymbolID
        if let existing = symbols.lookupAll(fqName: ctorFQName).first(where: {
            symbols.symbol($0)?.kind == .constructor
        }) {
            ctorSymbol = existing
        } else {
            ctorSymbol = symbols.define(
                kind: .constructor,
                name: initName,
                fqName: ctorFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        symbols.setParentSymbol(ownerSymbol, for: ctorSymbol)

        let valueParameterSymbols = propertyNames.map { parameterName -> SymbolID in
            let parameterFQName = ctorFQName + [parameterName]
            let parameterSymbol: SymbolID
            if let existing = symbols.lookup(fqName: parameterFQName) {
                parameterSymbol = existing
            } else {
                parameterSymbol = symbols.define(
                    kind: .valueParameter,
                    name: parameterName,
                    fqName: parameterFQName,
                    declSite: nil,
                    visibility: .private,
                    flags: [.synthetic]
                )
            }
            symbols.setParentSymbol(ctorSymbol, for: parameterSymbol)
            symbols.setPropertyType(stringType, for: parameterSymbol)
            return parameterSymbol
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: ownerType,
                parameterTypes: Array(repeating: stringType, count: valueParameterSymbols.count),
                returnType: ownerType,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: true, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
            ),
            for: ctorSymbol
        )
    }

    func registerSyntheticAnnotationRetentionEnum(
        packageFQName: [InternedString],
        packageSymbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let enumName = interner.intern("AnnotationRetention")
        let enumFQName = packageFQName + [enumName]
        let enumSymbol: SymbolID
        if let existing = symbols.lookup(fqName: enumFQName) {
            enumSymbol = existing
            if packageSymbol != .invalid {
                symbols.setParentSymbol(packageSymbol, for: existing)
            }
        } else {
            enumSymbol = symbols.define(
                kind: .enumClass,
                name: enumName,
                fqName: enumFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            if packageSymbol != .invalid {
                symbols.setParentSymbol(packageSymbol, for: enumSymbol)
            }
        }

        let enumType = types.make(.classType(ClassType(
            classSymbol: enumSymbol,
            args: [],
            nullability: .nonNull
        )))

        for entryName in SyntheticAnnotationAPISurfaceForHelpers.retentionEntries {
            let entry = interner.intern(entryName)
            let entryFQName = enumFQName + [entry]
            let entrySymbol: SymbolID
            if let existing = symbols.lookup(fqName: entryFQName) {
                entrySymbol = existing
            } else {
                entrySymbol = symbols.define(
                    kind: .field,
                    name: entry,
                    fqName: entryFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
            }
            symbols.setParentSymbol(enumSymbol, for: entrySymbol)
            if symbols.propertyType(for: entrySymbol) == nil {
                symbols.setPropertyType(enumType, for: entrySymbol)
            }
        }
    }

    func registerSyntheticRequiresOptInLevelEnum(
        ownerSymbol: SymbolID,
        ownerFQName: [InternedString],
        packageSymbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let levelName = interner.intern("Level")
        let levelFQName = ownerFQName + [levelName]
        let levelSymbol: SymbolID
        if let existing = symbols.lookup(fqName: levelFQName) {
            levelSymbol = existing
        } else {
            levelSymbol = symbols.define(
                kind: .enumClass,
                name: levelName,
                fqName: levelFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        symbols.setParentSymbol(ownerSymbol, for: levelSymbol)
        if packageSymbol != .invalid {
            symbols.setSourceFileID(symbols.sourceFileID(for: packageSymbol) ?? FileID(rawValue: 0), for: levelSymbol)
        }

        let levelType = types.make(.classType(ClassType(
            classSymbol: levelSymbol,
            args: [],
            nullability: .nonNull
        )))

        for entryName in ["WARNING", "ERROR"] {
            let entry = interner.intern(entryName)
            let entryFQName = levelFQName + [entry]
            let entrySymbol: SymbolID
            if let existing = symbols.lookup(fqName: entryFQName) {
                entrySymbol = existing
            } else {
                entrySymbol = symbols.define(
                    kind: .field,
                    name: entry,
                    fqName: entryFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
            }
            symbols.setParentSymbol(levelSymbol, for: entrySymbol)
            symbols.setPropertyType(levelType, for: entrySymbol)
        }
    }

    func registerSyntheticSubclassOptInRequiredMarkerClassProperty(
        ownerSymbol: SymbolID,
        ownerFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let valueName = interner.intern("markerClass")
        let valueFQName = ownerFQName + [valueName]
        let valueSymbol: SymbolID
        if let existing = symbols.lookup(fqName: valueFQName) {
            valueSymbol = existing
        } else {
            valueSymbol = symbols.define(
                kind: .property,
                name: valueName,
                fqName: valueFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }

        symbols.setParentSymbol(ownerSymbol, for: valueSymbol)

        let annotationFQName = [interner.intern("kotlin"), interner.intern("Annotation")]
        let annotationType: TypeID
        if let annotationSymbol = symbols.lookup(fqName: annotationFQName) {
            annotationType = types.make(.classType(ClassType(
                classSymbol: annotationSymbol,
                args: [],
                nullability: .nonNull
            )))
        } else {
            annotationType = types.anyType
        }
        symbols.setPropertyType(types.makeKClassType(argument: annotationType), for: valueSymbol)
    }

    func registerSyntheticThrowsExceptionClassesPropertyAndConstructor(
        ownerSymbol: SymbolID,
        ownerFQName: [InternedString],
        kotlinPkg: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let exceptionClassesName = interner.intern("exceptionClasses")
        let exceptionClassesFQName = ownerFQName + [exceptionClassesName]
        let exceptionClassesSymbol: SymbolID
        if let existing = symbols.lookup(fqName: exceptionClassesFQName) {
            exceptionClassesSymbol = existing
        } else {
            exceptionClassesSymbol = symbols.define(
                kind: .property,
                name: exceptionClassesName,
                fqName: exceptionClassesFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        symbols.setParentSymbol(ownerSymbol, for: exceptionClassesSymbol)

        let throwableType = makeSyntheticThrowsThrowableType(
            kotlinPkg: kotlinPkg,
            symbols: symbols,
            types: types,
            interner: interner
        )
        let exceptionKClassType = types.makeKClassType(argument: throwableType)
        let exceptionClassesType = makeSyntheticThrowsExceptionClassesArrayType(
            elementType: exceptionKClassType,
            kotlinPkg: kotlinPkg,
            symbols: symbols,
            types: types,
            interner: interner
        )
        symbols.setPropertyType(exceptionClassesType, for: exceptionClassesSymbol)

        let initName = interner.intern("<init>")
        let constructorFQName = ownerFQName + [initName]
        let hasMatchingConstructor = symbols.lookupAll(fqName: constructorFQName).contains { symbolID in
            guard let symbol = symbols.symbol(symbolID),
                  symbol.kind == .constructor,
                  let signature = symbols.functionSignature(for: symbolID)
            else {
                return false
            }
            return signature.parameterTypes == [exceptionKClassType]
                && signature.valueParameterIsVararg == [true]
        }
        guard !hasMatchingConstructor else {
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

        let parameterSymbol = symbols.define(
            kind: .valueParameter,
            name: exceptionClassesName,
            fqName: constructorFQName + [exceptionClassesName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(constructorSymbol, for: parameterSymbol)

        let ownerType = types.make(.classType(ClassType(
            classSymbol: ownerSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [exceptionKClassType],
                returnType: ownerType,
                valueParameterSymbols: [parameterSymbol],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [true]
            ),
            for: constructorSymbol
        )
    }

    func makeSyntheticThrowsThrowableType(
        kotlinPkg: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> TypeID {
        let throwableFQName = kotlinPkg + [interner.intern("Throwable")]
        guard let throwableSymbol = symbols.lookup(fqName: throwableFQName) else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: throwableSymbol,
            args: [],
            nullability: .nonNull
        )))
    }

    func makeSyntheticThrowsExceptionClassesArrayType(
        elementType: TypeID,
        kotlinPkg: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> TypeID {
        let arrayFQName = kotlinPkg + [interner.intern("Array")]
        guard let arraySymbol = symbols.lookup(fqName: arrayFQName) else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: arraySymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))
    }

    func registerSyntheticStringAnnotationPropertyAndConstructor(
        ownerSymbol: SymbolID,
        ownerFQName: [InternedString],
        propertyName: String,
        parameterHasDefaultValue: Bool = false,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let property = interner.intern(propertyName)
        let propertyFQName = ownerFQName + [property]
        let propertySymbol: SymbolID
        if let existing = symbols.lookup(fqName: propertyFQName) {
            propertySymbol = existing
        } else {
            propertySymbol = symbols.define(
                kind: .property,
                name: property,
                fqName: propertyFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        symbols.setParentSymbol(ownerSymbol, for: propertySymbol)
        symbols.setPropertyType(types.stringType, for: propertySymbol)

        let initName = interner.intern("<init>")
        let constructorFQName = ownerFQName + [initName]
        let hasMatchingConstructor = symbols.lookupAll(fqName: constructorFQName).contains { symbolID in
            guard let symbol = symbols.symbol(symbolID),
                  symbol.kind == .constructor,
                  let signature = symbols.functionSignature(for: symbolID)
            else {
                return false
            }
            return signature.parameterTypes == [types.stringType]
        }
        guard !hasMatchingConstructor else {
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

        let parameterSymbol = symbols.define(
            kind: .valueParameter,
            name: property,
            fqName: constructorFQName + [property],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(constructorSymbol, for: parameterSymbol)

        let ownerType = types.make(.classType(ClassType(
            classSymbol: ownerSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [types.stringType],
                returnType: ownerType,
                valueParameterSymbols: [parameterSymbol],
                valueParameterHasDefaultValues: [parameterHasDefaultValue],
                valueParameterIsVararg: [false]
            ),
            for: constructorSymbol
        )
    }

    func registerSyntheticBooleanAnnotationPropertyAndConstructor(
        ownerSymbol: SymbolID,
        ownerFQName: [InternedString],
        propertyName: String,
        hasDefaultValue: Bool,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let property = interner.intern(propertyName)
        let propertyFQName = ownerFQName + [property]
        let propertySymbol: SymbolID
        if let existing = symbols.lookup(fqName: propertyFQName) {
            propertySymbol = existing
        } else {
            propertySymbol = symbols.define(
                kind: .property,
                name: property,
                fqName: propertyFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        symbols.setParentSymbol(ownerSymbol, for: propertySymbol)
        symbols.setPropertyType(types.booleanType, for: propertySymbol)

        let initName = interner.intern("<init>")
        let constructorFQName = ownerFQName + [initName]
        let hasMatchingConstructor = symbols.lookupAll(fqName: constructorFQName).contains { symbolID in
            guard let symbol = symbols.symbol(symbolID),
                  symbol.kind == .constructor,
                  let signature = symbols.functionSignature(for: symbolID)
            else {
                return false
            }
            return signature.parameterTypes == [types.booleanType]
        }
        guard !hasMatchingConstructor else {
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

        let parameterSymbol = symbols.define(
            kind: .valueParameter,
            name: property,
            fqName: constructorFQName + [property],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(constructorSymbol, for: parameterSymbol)

        let ownerType = types.make(.classType(ClassType(
            classSymbol: ownerSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [types.booleanType],
                returnType: ownerType,
                valueParameterSymbols: [parameterSymbol],
                valueParameterHasDefaultValues: [hasDefaultValue],
                valueParameterIsVararg: [false]
            ),
            for: constructorSymbol
        )
    }

    func appendSyntheticAnnotation(
        _ annotation: MetadataAnnotationRecord,
        to symbol: SymbolID,
        symbols: SymbolTable
    ) {
        var annotations = symbols.annotations(for: symbol)
        if !annotations.contains(annotation) {
            annotations.append(annotation)
            symbols.setAnnotations(annotations, for: symbol)
        }
    }
}
