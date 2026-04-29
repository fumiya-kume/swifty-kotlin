import Foundation

/// Synthetic Kotlin/Native metaprogramming and C interop stubs.
extension DataFlowSemaPhase {
    func registerSyntheticNativeInteropStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        registerSyntheticNativeExperimentalAnnotations(
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeObjCAnnotations(
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCInteropStubs(
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func registerSyntheticNativeExperimentalAnnotations(
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let experimentalPkg = ensurePackage(
            path: ["kotlin", "experimental"],
            symbols: symbols,
            interner: interner
        )
        let experimentalPkgSymbol = symbols.lookup(fqName: experimentalPkg)

        let annotations: [(String, [String], String)] = [
            (
                "ExperimentalNativeApi",
                [
                    "AnnotationTarget.CLASS",
                    "AnnotationTarget.ANNOTATION_CLASS",
                    "AnnotationTarget.PROPERTY",
                    "AnnotationTarget.FIELD",
                    "AnnotationTarget.LOCAL_VARIABLE",
                    "AnnotationTarget.VALUE_PARAMETER",
                    "AnnotationTarget.CONSTRUCTOR",
                    "AnnotationTarget.FUNCTION",
                    "AnnotationTarget.PROPERTY_GETTER",
                    "AnnotationTarget.PROPERTY_SETTER",
                    "AnnotationTarget.TYPEALIAS",
                ],
                "AnnotationRetention.BINARY"
            ),
            (
                "ExperimentalObjCName",
                ["AnnotationTarget.ANNOTATION_CLASS"],
                "AnnotationRetention.BINARY"
            ),
            (
                "ExperimentalObjCRefinement",
                ["AnnotationTarget.ANNOTATION_CLASS"],
                "AnnotationRetention.BINARY"
            ),
            (
                "ExperimentalObjCEnum",
                ["AnnotationTarget.ANNOTATION_CLASS"],
                "AnnotationRetention.BINARY"
            ),
        ]

        for (name, targets, retention) in annotations {
            let symbol = ensureAnnotationClassSymbol(
                named: name,
                in: experimentalPkg,
                symbols: symbols,
                interner: interner
            )
            if let experimentalPkgSymbol {
                symbols.setParentSymbol(experimentalPkgSymbol, for: symbol)
            }
            appendStandardAnnotationMetadata(
                to: symbol,
                targets: targets,
                retention: retention,
                symbols: symbols
            )
        }
    }

    private func registerSyntheticNativeObjCAnnotations(
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let nativePkg = ensurePackage(
            path: ["kotlin", "native"],
            symbols: symbols,
            interner: interner
        )
        let nativePkgSymbol = symbols.lookup(fqName: nativePkg)

        let annotations: [(String, [String], String)] = [
            (
                "ObjCName",
                [
                    "AnnotationTarget.CLASS",
                    "AnnotationTarget.PROPERTY",
                    "AnnotationTarget.VALUE_PARAMETER",
                    "AnnotationTarget.FUNCTION",
                ],
                "AnnotationRetention.BINARY"
            ),
            (
                "CName",
                [
                    "AnnotationTarget.FUNCTION",
                    "AnnotationTarget.CLASS",
                ],
                "AnnotationRetention.BINARY"
            ),
            (
                "ObjCSignatureOverride",
                ["AnnotationTarget.FUNCTION"],
                "AnnotationRetention.BINARY"
            ),
            (
                "HidesFromObjC",
                [
                    "AnnotationTarget.CLASS",
                    "AnnotationTarget.FUNCTION",
                    "AnnotationTarget.PROPERTY",
                ],
                "AnnotationRetention.BINARY"
            ),
            (
                "ShouldRefineInSwift",
                [
                    "AnnotationTarget.CLASS",
                    "AnnotationTarget.FUNCTION",
                    "AnnotationTarget.PROPERTY",
                ],
                "AnnotationRetention.BINARY"
            ),
            (
                "RefinesInSwift",
                ["AnnotationTarget.ANNOTATION_CLASS"],
                "AnnotationRetention.BINARY"
            ),
        ]

        for (name, targets, retention) in annotations {
            let symbol = ensureAnnotationClassSymbol(
                named: name,
                in: nativePkg,
                symbols: symbols,
                interner: interner
            )
            if let nativePkgSymbol {
                symbols.setParentSymbol(nativePkgSymbol, for: symbol)
            }
            appendStandardAnnotationMetadata(
                to: symbol,
                targets: targets,
                retention: retention,
                symbols: symbols
            )
        }

        let freezingIsDeprecatedSymbol = ensureAnnotationClassSymbol(
            named: "FreezingIsDeprecated",
            in: nativePkg,
            symbols: symbols,
            interner: interner
        )
        if let nativePkgSymbol {
            symbols.setParentSymbol(nativePkgSymbol, for: freezingIsDeprecatedSymbol)
        }
        appendStandardAnnotationMetadata(
            to: freezingIsDeprecatedSymbol,
            targets: [
                "AnnotationTarget.CLASS",
                "AnnotationTarget.ANNOTATION_CLASS",
                "AnnotationTarget.PROPERTY",
                "AnnotationTarget.FIELD",
                "AnnotationTarget.LOCAL_VARIABLE",
                "AnnotationTarget.VALUE_PARAMETER",
                "AnnotationTarget.CONSTRUCTOR",
                "AnnotationTarget.FUNCTION",
                "AnnotationTarget.PROPERTY_GETTER",
                "AnnotationTarget.PROPERTY_SETTER",
                "AnnotationTarget.TYPEALIAS",
            ],
            retention: "AnnotationRetention.BINARY",
            symbols: symbols
        )
        var freezingAnnotations = symbols.annotations(for: freezingIsDeprecatedSymbol)
        let freezingRequiresOptIn = MetadataAnnotationRecord(
            annotationFQName: "kotlin.RequiresOptIn",
            arguments: [
                "message=Freezing API is deprecated since 1.7.20. See https://kotlinlang.org/docs/native-migration-guide.html for details",
                "level=RequiresOptIn.Level.WARNING",
            ]
        )
        if !freezingAnnotations.contains(freezingRequiresOptIn) {
            freezingAnnotations.append(freezingRequiresOptIn)
            symbols.setAnnotations(freezingAnnotations, for: freezingIsDeprecatedSymbol)
        }
    }

    private func registerSyntheticCInteropStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let cinteropPkg = ensurePackage(
            path: ["kotlinx", "cinterop"],
            symbols: symbols,
            interner: interner
        )
        let cinteropPkgSymbol = symbols.lookup(fqName: cinteropPkg)

        let experimentalForeignApiSymbol = ensureAnnotationClassSymbol(
            named: "ExperimentalForeignApi",
            in: cinteropPkg,
            symbols: symbols,
            interner: interner
        )
        if let cinteropPkgSymbol {
            symbols.setParentSymbol(cinteropPkgSymbol, for: experimentalForeignApiSymbol)
        }
        appendStandardAnnotationMetadata(
            to: experimentalForeignApiSymbol,
            targets: [
                "AnnotationTarget.CLASS",
                "AnnotationTarget.ANNOTATION_CLASS",
                "AnnotationTarget.PROPERTY",
                "AnnotationTarget.FIELD",
                "AnnotationTarget.LOCAL_VARIABLE",
                "AnnotationTarget.VALUE_PARAMETER",
                "AnnotationTarget.CONSTRUCTOR",
                "AnnotationTarget.FUNCTION",
                "AnnotationTarget.PROPERTY_GETTER",
                "AnnotationTarget.PROPERTY_SETTER",
                "AnnotationTarget.TYPEALIAS",
            ],
            retention: "AnnotationRetention.BINARY",
            symbols: symbols
        )

        let betaInteropApiSymbol = ensureAnnotationClassSymbol(
            named: "BetaInteropApi",
            in: cinteropPkg,
            symbols: symbols,
            interner: interner
        )
        if let cinteropPkgSymbol {
            symbols.setParentSymbol(cinteropPkgSymbol, for: betaInteropApiSymbol)
        }
        appendStandardAnnotationMetadata(
            to: betaInteropApiSymbol,
            targets: ["AnnotationTarget.ANNOTATION_CLASS"],
            retention: "AnnotationRetention.BINARY",
            symbols: symbols
        )

        let nativePointedSymbol = ensureClassSymbol(
            named: "NativePointed",
            in: cinteropPkg,
            symbols: symbols,
            interner: interner
        )
        let cPointedSymbol = ensureClassSymbol(
            named: "CPointed",
            in: cinteropPkg,
            symbols: symbols,
            interner: interner
        )
        let cOpaquePointerSymbol = ensureClassSymbol(
            named: "COpaquePointer",
            in: cinteropPkg,
            symbols: symbols,
            interner: interner
        )
        let nativePlacementSymbol = ensureClassSymbol(
            named: "NativePlacement",
            in: cinteropPkg,
            symbols: symbols,
            interner: interner
        )
        let memScopeSymbol = ensureClassSymbol(
            named: "MemScope",
            in: cinteropPkg,
            symbols: symbols,
            interner: interner
        )
        let cValuesRefSymbol = ensureClassSymbol(
            named: "CValuesRef",
            in: cinteropPkg,
            symbols: symbols,
            interner: interner
        )
        let cPointerSymbol = ensureClassSymbol(
            named: "CPointer",
            in: cinteropPkg,
            symbols: symbols,
            interner: interner
        )
        let cPointerVarSymbol = ensureClassSymbol(
            named: "CPointerVar",
            in: cinteropPkg,
            symbols: symbols,
            interner: interner
        )

        for symbol in [
            nativePointedSymbol,
            cPointedSymbol,
            cOpaquePointerSymbol,
            nativePlacementSymbol,
            memScopeSymbol,
            cValuesRefSymbol,
            cPointerSymbol,
            cPointerVarSymbol,
        ] {
            if let cinteropPkgSymbol {
                symbols.setParentSymbol(cinteropPkgSymbol, for: symbol)
            }
        }

        let nativePointedType = types.make(.classType(ClassType(
            classSymbol: nativePointedSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(nativePointedType, for: nativePointedSymbol)

        let cPointedType = types.make(.classType(ClassType(
            classSymbol: cPointedSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(cPointedType, for: cPointedSymbol)
        symbols.setDirectSupertypes([nativePointedSymbol], for: cPointedSymbol)
        types.setNominalDirectSupertypes([nativePointedSymbol], for: cPointedSymbol)

        let cOpaquePointerType = types.make(.classType(ClassType(
            classSymbol: cOpaquePointerSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(cOpaquePointerType, for: cOpaquePointerSymbol)
        symbols.setDirectSupertypes([nativePointedSymbol], for: cOpaquePointerSymbol)
        types.setNominalDirectSupertypes([nativePointedSymbol], for: cOpaquePointerSymbol)

        let nativePlacementType = types.make(.classType(ClassType(
            classSymbol: nativePlacementSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(nativePlacementType, for: nativePlacementSymbol)

        let memScopeType = types.make(.classType(ClassType(
            classSymbol: memScopeSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(memScopeType, for: memScopeSymbol)
        symbols.setDirectSupertypes([nativePlacementSymbol], for: memScopeSymbol)
        types.setNominalDirectSupertypes([nativePlacementSymbol], for: memScopeSymbol)

        configureSingleTypeParameterNominal(
            ownerSymbol: cValuesRefSymbol,
            fqName: cinteropPkg + [interner.intern("CValuesRef")],
            parameterName: "T",
            supertype: nil,
            symbols: symbols,
            types: types,
            interner: interner
        )
        configureSingleTypeParameterNominal(
            ownerSymbol: cPointerSymbol,
            fqName: cinteropPkg + [interner.intern("CPointer")],
            parameterName: "T",
            supertype: cValuesRefSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
        configureSingleTypeParameterNominal(
            ownerSymbol: cPointerVarSymbol,
            fqName: cinteropPkg + [interner.intern("CPointerVar")],
            parameterName: "T",
            supertype: cPointedSymbol,
            supertypeIsGeneric: false,
            symbols: symbols,
            types: types,
            interner: interner
        )

        for primitiveVar in [
            "ByteVar",
            "UByteVar",
            "ShortVar",
            "UShortVar",
            "IntVar",
            "UIntVar",
            "LongVar",
            "ULongVar",
            "FloatVar",
            "DoubleVar",
        ] {
            let symbol = ensureClassSymbol(
                named: primitiveVar,
                in: cinteropPkg,
                symbols: symbols,
                interner: interner
            )
            if let cinteropPkgSymbol {
                symbols.setParentSymbol(cinteropPkgSymbol, for: symbol)
            }
            let type = types.make(.classType(ClassType(
                classSymbol: symbol,
                args: [],
                nullability: .nonNull
            )))
            symbols.setPropertyType(type, for: symbol)
            symbols.setDirectSupertypes([cPointedSymbol], for: symbol)
            types.setNominalDirectSupertypes([cPointedSymbol], for: symbol)
        }
    }

    private func appendStandardAnnotationMetadata(
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

    private func configureSingleTypeParameterNominal(
        ownerSymbol: SymbolID,
        fqName: [InternedString],
        parameterName: String,
        supertype: SymbolID?,
        supertypeIsGeneric: Bool = true,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let parameterInternedName = interner.intern(parameterName)
        let typeParameterFQName = fqName + [parameterInternedName]
        let typeParameterSymbol: SymbolID = if let existing = symbols.lookup(fqName: typeParameterFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: parameterInternedName,
                fqName: typeParameterFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }

        let parameterType = types.make(.typeParam(TypeParamType(
            symbol: typeParameterSymbol,
            nullability: .nonNull
        )))
        let ownerType = types.make(.classType(ClassType(
            classSymbol: ownerSymbol,
            args: [.invariant(parameterType)],
            nullability: .nonNull
        )))
        symbols.setPropertyType(ownerType, for: ownerSymbol)
        types.setNominalTypeParameterSymbols([typeParameterSymbol], for: ownerSymbol)
        types.setNominalTypeParameterVariances([.invariant], for: ownerSymbol)

        if let supertype {
            let supertypeTypeArgs: [TypeArg] = supertypeIsGeneric ? [.invariant(parameterType)] : []
            symbols.setDirectSupertypes([supertype], for: ownerSymbol)
            types.setNominalDirectSupertypes([supertype], for: ownerSymbol)
            symbols.setSupertypeTypeArgs(supertypeTypeArgs, for: ownerSymbol, supertype: supertype)
            types.setNominalSupertypeTypeArgs(supertypeTypeArgs, for: ownerSymbol, supertype: supertype)
        }
    }
}
