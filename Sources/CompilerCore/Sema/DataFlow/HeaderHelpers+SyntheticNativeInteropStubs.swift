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
        registerSyntheticNativeBitSetStubs(
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticCInteropStubs(
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticNativeVector128Stubs(
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticNativeIdentityHashCodeStub(
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticNativeStackTraceAddressStub(
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticNativeUnhandledExceptionHookStubs(
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticNativeByteArrayAccessorStubs(
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticNativeImmutableBlobStubs(
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
            appendMetadataAnnotations(
                [
                    MetadataAnnotationRecord(
                        annotationFQName: "kotlin.RequiresOptIn",
                        arguments: ["level=RequiresOptIn.Level.ERROR"]
                    ),
                ],
                to: symbol,
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

        let obsoleteNativeApiSymbol = ensureAnnotationClassSymbol(
            named: "ObsoleteNativeApi",
            in: nativePkg,
            symbols: symbols,
            interner: interner
        )
        if let nativePkgSymbol {
            symbols.setParentSymbol(nativePkgSymbol, for: obsoleteNativeApiSymbol)
        }
        appendStandardAnnotationMetadata(
            to: obsoleteNativeApiSymbol,
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
        var obsoleteAnnotations = symbols.annotations(for: obsoleteNativeApiSymbol)
        let obsoleteRequiresOptIn = MetadataAnnotationRecord(
            annotationFQName: "kotlin.RequiresOptIn",
            arguments: [
                "message=This API is obsolete and subject to removal in a future release.",
                "level=RequiresOptIn.Level.ERROR",
            ]
        )
        if !obsoleteAnnotations.contains(obsoleteRequiresOptIn) {
            obsoleteAnnotations.append(obsoleteRequiresOptIn)
            symbols.setAnnotations(obsoleteAnnotations, for: obsoleteNativeApiSymbol)
        }

        let eagerInitializationSymbol = ensureAnnotationClassSymbol(
            named: "EagerInitialization",
            in: nativePkg,
            symbols: symbols,
            interner: interner
        )
        if let nativePkgSymbol {
            symbols.setParentSymbol(nativePkgSymbol, for: eagerInitializationSymbol)
        }
        appendStandardAnnotationMetadata(
            to: eagerInitializationSymbol,
            targets: ["AnnotationTarget.PROPERTY"],
            retention: "AnnotationRetention.BINARY",
            symbols: symbols
        )
        var eagerInitializationAnnotations = symbols.annotations(for: eagerInitializationSymbol)
        let eagerInitializationMetaAnnotations = [
            MetadataAnnotationRecord(annotationFQName: "kotlin.ExperimentalStdlibApi"),
            MetadataAnnotationRecord(
                annotationFQName: "kotlin.Deprecated",
                arguments: [
                    "message = \"This annotation is a temporal migration assistance and may be removed in the future releases, please consider filing an issue about the case where it is needed\"",
                ]
            ),
        ]
        var didAppendEagerInitializationMetaAnnotation = false
        for record in eagerInitializationMetaAnnotations where !eagerInitializationAnnotations.contains(record) {
            eagerInitializationAnnotations.append(record)
            didAppendEagerInitializationMetaAnnotation = true
        }
        if didAppendEagerInitializationMetaAnnotation {
            symbols.setAnnotations(eagerInitializationAnnotations, for: eagerInitializationSymbol)
        }

        let hiddenFromObjCSymbol = ensureAnnotationClassSymbol(
            named: "HiddenFromObjC",
            in: nativePkg,
            symbols: symbols,
            interner: interner
        )
        if let nativePkgSymbol {
            symbols.setParentSymbol(nativePkgSymbol, for: hiddenFromObjCSymbol)
        }
        appendStandardAnnotationMetadata(
            to: hiddenFromObjCSymbol,
            targets: [
                "AnnotationTarget.PROPERTY",
                "AnnotationTarget.FUNCTION",
                "AnnotationTarget.CLASS",
            ],
            retention: "AnnotationRetention.BINARY",
            symbols: symbols
        )
        var hiddenFromObjCAnnotations = symbols.annotations(for: hiddenFromObjCSymbol)
        let hiddenFromObjCMetaAnnotations = [
            MetadataAnnotationRecord(annotationFQName: "kotlin.native.HidesFromObjC"),
            MetadataAnnotationRecord(annotationFQName: "kotlin.experimental.ExperimentalObjCRefinement"),
        ]
        var didAppendHiddenFromObjCMetaAnnotation = false
        for record in hiddenFromObjCMetaAnnotations where !hiddenFromObjCAnnotations.contains(record) {
            hiddenFromObjCAnnotations.append(record)
            didAppendHiddenFromObjCMetaAnnotation = true
        }
        if didAppendHiddenFromObjCMetaAnnotation {
            symbols.setAnnotations(hiddenFromObjCAnnotations, for: hiddenFromObjCSymbol)
        }

        let noInlineSymbol = ensureAnnotationClassSymbol(
            named: "NoInline",
            in: nativePkg,
            symbols: symbols,
            interner: interner
        )
        if let nativePkgSymbol {
            symbols.setParentSymbol(nativePkgSymbol, for: noInlineSymbol)
        }
        appendStandardAnnotationMetadata(
            to: noInlineSymbol,
            targets: [
                "AnnotationTarget.FUNCTION",
                "AnnotationTarget.PROPERTY",
            ],
            retention: "AnnotationRetention.BINARY",
            symbols: symbols
        )
        var noInlineAnnotations = symbols.annotations(for: noInlineSymbol)
        let experimentalNativeApiRecord = MetadataAnnotationRecord(
            annotationFQName: "kotlin.experimental.ExperimentalNativeApi"
        )
        if !noInlineAnnotations.contains(experimentalNativeApiRecord) {
            noInlineAnnotations.append(experimentalNativeApiRecord)
            symbols.setAnnotations(noInlineAnnotations, for: noInlineSymbol)
        }
    }

    private func registerSyntheticNativeBitSetStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let nativePkg = ensurePackage(
            path: ["kotlin", "native"],
            symbols: symbols,
            interner: interner
        )
        let nativePkgSymbol = symbols.lookup(fqName: nativePkg)
        let bitSetSymbol = ensureClassSymbol(
            named: "BitSet",
            in: nativePkg,
            symbols: symbols,
            interner: interner
        )
        if let nativePkgSymbol {
            symbols.setParentSymbol(nativePkgSymbol, for: bitSetSymbol)
        }

        let bitSetType = types.make(.classType(ClassType(
            classSymbol: bitSetSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(bitSetType, for: bitSetSymbol)

        var bitSetAnnotations = symbols.annotations(for: bitSetSymbol)
        let obsoleteNativeApiRecord = MetadataAnnotationRecord(annotationFQName: "kotlin.native.ObsoleteNativeApi")
        if !bitSetAnnotations.contains(obsoleteNativeApiRecord) {
            bitSetAnnotations.append(obsoleteNativeApiRecord)
            symbols.setAnnotations(bitSetAnnotations, for: bitSetSymbol)
        }

        let companionName = interner.intern("Companion")
        let companionFQName = nativePkg + [interner.intern("BitSet"), companionName]
        let companionSymbol: SymbolID
        if let existing = symbols.lookup(fqName: companionFQName), symbols.symbol(existing)?.kind == .object {
            companionSymbol = existing
        } else {
            companionSymbol = symbols.define(
                kind: .object,
                name: companionName,
                fqName: companionFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .static]
            )
        }
        symbols.setParentSymbol(bitSetSymbol, for: companionSymbol)
        let companionType = types.make(.classType(ClassType(
            classSymbol: companionSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(companionType, for: companionSymbol)

        let intRangeType = syntheticClassType(
            packagePath: ["kotlin", "ranges"],
            name: "IntRange",
            symbols: symbols,
            types: types,
            interner: interner
        )
        let initializerType = types.make(.functionType(FunctionType(
            params: [types.intType],
            returnType: types.booleanType
        )))

        registerSyntheticNativeBitSetConstructor(
            ownerSymbol: bitSetSymbol,
            ownerType: bitSetType,
            parameters: [(name: "size", type: types.intType)],
            defaultValues: [true],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeBitSetConstructor(
            ownerSymbol: bitSetSymbol,
            ownerType: bitSetType,
            parameters: [
                (name: "length", type: types.intType),
                (name: "initializer", type: initializerType),
            ],
            defaultValues: [false, false],
            symbols: symbols,
            interner: interner
        )

        registerSyntheticNativeBitSetProperty(
            named: "isEmpty",
            ownerSymbol: bitSetSymbol,
            propertyType: types.booleanType,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeBitSetProperty(
            named: "lastTrueIndex",
            ownerSymbol: bitSetSymbol,
            propertyType: types.intType,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeBitSetProperty(
            named: "size",
            ownerSymbol: bitSetSymbol,
            propertyType: types.intType,
            flags: [.synthetic, .mutable],
            symbols: symbols,
            interner: interner
        )

        for name in ["and", "andNot", "or", "xor"] {
            registerSyntheticNativeBitSetMemberFunction(
                named: name,
                ownerSymbol: bitSetSymbol,
                receiverType: bitSetType,
                parameters: [(name: "another", type: bitSetType)],
                returnType: types.unitType,
                symbols: symbols,
                interner: interner
            )
        }
        registerSyntheticNativeBitSetMemberFunction(
            named: "intersects",
            ownerSymbol: bitSetSymbol,
            receiverType: bitSetType,
            parameters: [(name: "another", type: bitSetType)],
            returnType: types.booleanType,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticNativeBitSetMemberFunction(
            named: "clear",
            ownerSymbol: bitSetSymbol,
            receiverType: bitSetType,
            parameters: [],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeBitSetMemberFunction(
            named: "clear",
            ownerSymbol: bitSetSymbol,
            receiverType: bitSetType,
            parameters: [(name: "index", type: types.intType)],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeBitSetMemberFunction(
            named: "clear",
            ownerSymbol: bitSetSymbol,
            receiverType: bitSetType,
            parameters: [(name: "range", type: intRangeType)],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeBitSetMemberFunction(
            named: "clear",
            ownerSymbol: bitSetSymbol,
            receiverType: bitSetType,
            parameters: [
                (name: "from", type: types.intType),
                (name: "to", type: types.intType),
            ],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticNativeBitSetMemberFunction(
            named: "flip",
            ownerSymbol: bitSetSymbol,
            receiverType: bitSetType,
            parameters: [(name: "index", type: types.intType)],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeBitSetMemberFunction(
            named: "flip",
            ownerSymbol: bitSetSymbol,
            receiverType: bitSetType,
            parameters: [(name: "range", type: intRangeType)],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeBitSetMemberFunction(
            named: "flip",
            ownerSymbol: bitSetSymbol,
            receiverType: bitSetType,
            parameters: [
                (name: "from", type: types.intType),
                (name: "to", type: types.intType),
            ],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticNativeBitSetMemberFunction(
            named: "get",
            ownerSymbol: bitSetSymbol,
            receiverType: bitSetType,
            parameters: [(name: "index", type: types.intType)],
            returnType: types.booleanType,
            flags: [.synthetic, .operatorFunction],
            symbols: symbols,
            interner: interner
        )

        registerSyntheticNativeBitSetMemberFunction(
            named: "set",
            ownerSymbol: bitSetSymbol,
            receiverType: bitSetType,
            parameters: [
                (name: "index", type: types.intType),
                (name: "value", type: types.booleanType),
            ],
            returnType: types.unitType,
            defaultValues: [false, true],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeBitSetMemberFunction(
            named: "set",
            ownerSymbol: bitSetSymbol,
            receiverType: bitSetType,
            parameters: [
                (name: "range", type: intRangeType),
                (name: "value", type: types.booleanType),
            ],
            returnType: types.unitType,
            defaultValues: [false, true],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeBitSetMemberFunction(
            named: "set",
            ownerSymbol: bitSetSymbol,
            receiverType: bitSetType,
            parameters: [
                (name: "from", type: types.intType),
                (name: "to", type: types.intType),
                (name: "value", type: types.booleanType),
            ],
            returnType: types.unitType,
            defaultValues: [false, false, true],
            symbols: symbols,
            interner: interner
        )

        for name in ["nextClearBit", "nextSetBit"] {
            registerSyntheticNativeBitSetMemberFunction(
                named: name,
                ownerSymbol: bitSetSymbol,
                receiverType: bitSetType,
                parameters: [(name: "startIndex", type: types.intType)],
                returnType: types.intType,
                defaultValues: [true],
                symbols: symbols,
                interner: interner
            )
        }
        registerSyntheticNativeBitSetMemberFunction(
            named: "previousBit",
            ownerSymbol: bitSetSymbol,
            receiverType: bitSetType,
            parameters: [
                (name: "startIndex", type: types.intType),
                (name: "lookFor", type: types.booleanType),
            ],
            returnType: types.intType,
            symbols: symbols,
            interner: interner
        )
        for name in ["previousClearBit", "previousSetBit"] {
            registerSyntheticNativeBitSetMemberFunction(
                named: name,
                ownerSymbol: bitSetSymbol,
                receiverType: bitSetType,
                parameters: [(name: "startIndex", type: types.intType)],
                returnType: types.intType,
                symbols: symbols,
                interner: interner
            )
        }

        registerSyntheticNativeBitSetMemberFunction(
            named: "equals",
            ownerSymbol: bitSetSymbol,
            receiverType: bitSetType,
            parameters: [(name: "other", type: types.makeNullable(types.anyType))],
            returnType: types.booleanType,
            flags: [.synthetic, .operatorFunction, .overrideMember],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeBitSetMemberFunction(
            named: "hashCode",
            ownerSymbol: bitSetSymbol,
            receiverType: bitSetType,
            parameters: [],
            returnType: types.intType,
            flags: [.synthetic, .overrideMember],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeBitSetMemberFunction(
            named: "toString",
            ownerSymbol: bitSetSymbol,
            receiverType: bitSetType,
            parameters: [],
            returnType: types.stringType,
            flags: [.synthetic, .overrideMember],
            symbols: symbols,
            interner: interner
        )
    }

    private func registerSyntheticNativeImmutableBlobStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let nativePkg = ensurePackage(
            path: ["kotlin", "native"],
            symbols: symbols,
            interner: interner
        )
        let nativePkgSymbol = symbols.lookup(fqName: nativePkg)
        let immutableBlobSymbol = ensureClassSymbol(
            named: "ImmutableBlob",
            in: nativePkg,
            symbols: symbols,
            interner: interner
        )
        if let nativePkgSymbol {
            symbols.setParentSymbol(nativePkgSymbol, for: immutableBlobSymbol)
        }

        let immutableBlobType = types.make(.classType(ClassType(
            classSymbol: immutableBlobSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(immutableBlobType, for: immutableBlobSymbol)
        appendDeprecatedImmutableBlobAnnotations(to: immutableBlobSymbol, symbols: symbols)

        let kotlinPkg = ensurePackage(
            path: ["kotlin"],
            symbols: symbols,
            interner: interner
        )
        let byteIteratorSymbol = ensureClassSymbol(
            named: "ByteIterator",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        if let kotlinPkgSymbol = symbols.lookup(fqName: kotlinPkg) {
            symbols.setParentSymbol(kotlinPkgSymbol, for: byteIteratorSymbol)
        }
        let byteIteratorType = types.make(.classType(ClassType(
            classSymbol: byteIteratorSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(byteIteratorType, for: byteIteratorSymbol)

        let byteArrayType = syntheticClassType(
            packagePath: ["kotlin"],
            name: "ByteArray",
            symbols: symbols,
            types: types,
            interner: interner
        )
        let uByteArrayType = syntheticClassType(
            packagePath: ["kotlin"],
            name: "UByteArray",
            symbols: symbols,
            types: types,
            interner: interner
        )
        let cPointerByteVarType = cPointerType(
            pointedTypeName: "ByteVar",
            symbols: symbols,
            types: types,
            interner: interner
        )
        let cPointerUByteVarType = cPointerType(
            pointedTypeName: "UByteVar",
            symbols: symbols,
            types: types,
            interner: interner
        )

        registerSyntheticNativeBitSetProperty(
            named: "size",
            ownerSymbol: immutableBlobSymbol,
            propertyType: types.intType,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeBitSetMemberFunction(
            named: "get",
            ownerSymbol: immutableBlobSymbol,
            receiverType: immutableBlobType,
            parameters: [(name: "index", type: types.intType)],
            returnType: types.intType,
            flags: [.synthetic, .operatorFunction],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeBitSetMemberFunction(
            named: "iterator",
            ownerSymbol: immutableBlobSymbol,
            receiverType: immutableBlobType,
            parameters: [],
            returnType: byteIteratorType,
            flags: [.synthetic, .operatorFunction],
            symbols: symbols,
            interner: interner
        )

        registerSyntheticNativeTopLevelFunction(
            named: "immutableBlobOf",
            packageFQName: nativePkg,
            receiverType: nil,
            parameters: [(name: "elements", type: types.intType)],
            returnType: immutableBlobType,
            defaultValues: [false],
            varargs: [true],
            annotations: deprecatedImmutableBlobFactoryAnnotations(),
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeTopLevelFunction(
            named: "toByteArray",
            packageFQName: nativePkg,
            receiverType: immutableBlobType,
            parameters: [
                (name: "startIndex", type: types.intType),
                (name: "endIndex", type: types.intType),
            ],
            returnType: byteArrayType,
            defaultValues: [true, true],
            annotations: deprecatedImmutableBlobAnnotations(),
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeTopLevelFunction(
            named: "toUByteArray",
            packageFQName: nativePkg,
            receiverType: immutableBlobType,
            parameters: [
                (name: "startIndex", type: types.intType),
                (name: "endIndex", type: types.intType),
            ],
            returnType: uByteArrayType,
            defaultValues: [true, true],
            annotations: deprecatedImmutableBlobAnnotations()
                + [MetadataAnnotationRecord(annotationFQName: "kotlin.ExperimentalUnsignedTypes")],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeTopLevelFunction(
            named: "asCPointer",
            packageFQName: nativePkg,
            receiverType: immutableBlobType,
            parameters: [(name: "offset", type: types.intType)],
            returnType: cPointerByteVarType,
            defaultValues: [true],
            annotations: deprecatedImmutableBlobPointerAnnotations(),
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeTopLevelFunction(
            named: "asUCPointer",
            packageFQName: nativePkg,
            receiverType: immutableBlobType,
            parameters: [(name: "offset", type: types.intType)],
            returnType: cPointerUByteVarType,
            defaultValues: [true],
            annotations: deprecatedImmutableBlobPointerAnnotations(),
            symbols: symbols,
            interner: interner
        )
    }

    private func registerSyntheticNativeVector128Stubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let nativePkg = ensurePackage(
            path: ["kotlin", "native"],
            symbols: symbols,
            interner: interner
        )
        let nativePkgSymbol = symbols.lookup(fqName: nativePkg)
        let cinteropPkg = ensurePackage(
            path: ["kotlinx", "cinterop"],
            symbols: symbols,
            interner: interner
        )
        guard let cinteropVector128Symbol = symbols.lookup(fqName: cinteropPkg + [interner.intern("Vector128")]) else {
            return
        }

        let cinteropVector128Type = types.make(.classType(ClassType(
            classSymbol: cinteropVector128Symbol,
            args: [],
            nullability: .nonNull
        )))
        let vector128Name = interner.intern("Vector128")
        let vector128AliasFQName = nativePkg + [vector128Name]
        let vector128AliasSymbol: SymbolID
        if let existing = symbols.lookup(fqName: vector128AliasFQName),
           symbols.symbol(existing)?.kind == .typeAlias
        {
            vector128AliasSymbol = existing
            symbols.insertFlags([.synthetic], for: existing)
        } else if symbols.lookup(fqName: vector128AliasFQName) == nil {
            vector128AliasSymbol = symbols.define(
                kind: .typeAlias,
                name: vector128Name,
                fqName: vector128AliasFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        } else {
            return
        }
        if let nativePkgSymbol {
            symbols.setParentSymbol(nativePkgSymbol, for: vector128AliasSymbol)
        }
        symbols.setTypeAliasUnderlyingType(cinteropVector128Type, for: vector128AliasSymbol)
        appendMetadataAnnotations(
            deprecatedNativeVector128TypeAliasAnnotations(),
            to: vector128AliasSymbol,
            symbols: symbols
        )

        let vectorOfAnnotations = deprecatedNativeVectorOfAnnotations()
        for parameterType in [types.floatType, types.intType] {
            registerSyntheticNativeTopLevelFunction(
                named: "vectorOf",
                packageFQName: nativePkg,
                receiverType: nil,
                parameters: [
                    (name: "f0", type: parameterType),
                    (name: "f1", type: parameterType),
                    (name: "f2", type: parameterType),
                    (name: "f3", type: parameterType),
                ],
                returnType: cinteropVector128Type,
                annotations: vectorOfAnnotations,
                symbols: symbols,
                interner: interner
            )
        }
    }

    private func registerSyntheticNativeByteArrayAccessorStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let nativePkg = ensurePackage(
            path: ["kotlin", "native"],
            symbols: symbols,
            interner: interner
        )
        let byteArrayType = syntheticClassType(
            packagePath: ["kotlin"],
            name: "ByteArray",
            symbols: symbols,
            types: types,
            interner: interner
        )

        let accessors: [(name: String, returnType: TypeID, externalLinkName: String, annotations: [MetadataAnnotationRecord])] = [
            ("getByteAt", types.intType, "kk_native_byteArray_getByteAt", experimentalNativeApiAnnotations()),
            ("getShortAt", types.intType, "kk_native_byteArray_getShortAt", experimentalNativeApiAnnotations()),
            ("getIntAt", types.intType, "kk_native_byteArray_getIntAt", experimentalNativeApiAnnotations()),
            ("getLongAt", types.longType, "kk_native_byteArray_getLongAt", experimentalNativeApiAnnotations()),
            ("getUByteAt", types.ubyteType, "kk_native_byteArray_getUByteAt", experimentalNativeUnsignedApiAnnotations()),
            ("getUShortAt", types.ushortType, "kk_native_byteArray_getUShortAt", experimentalNativeUnsignedApiAnnotations()),
            ("getUIntAt", types.uintType, "kk_native_byteArray_getUIntAt", experimentalNativeUnsignedApiAnnotations()),
            ("getULongAt", types.ulongType, "kk_native_byteArray_getULongAt", experimentalNativeUnsignedApiAnnotations()),
            ("getCharAt", types.charType, "kk_native_byteArray_getCharAt", experimentalNativeApiAnnotations()),
            ("getFloatAt", types.floatType, "kk_native_byteArray_getFloatAt", experimentalNativeApiAnnotations()),
            ("getDoubleAt", types.doubleType, "kk_native_byteArray_getDoubleAt", experimentalNativeApiAnnotations()),
        ]
        for accessor in accessors {
            registerSyntheticNativeTopLevelFunction(
                named: accessor.name,
                packageFQName: nativePkg,
                receiverType: byteArrayType,
                parameters: [(name: "index", type: types.intType)],
                returnType: accessor.returnType,
                annotations: accessor.annotations,
                externalLinkName: accessor.externalLinkName,
                symbols: symbols,
                interner: interner
            )
        }

        let setters: [(name: String, valueType: TypeID, externalLinkName: String, annotations: [MetadataAnnotationRecord])] = [
            ("setByteAt", types.intType, "kk_native_byteArray_setByteAt", experimentalNativeApiAnnotations()),
            ("setShortAt", types.intType, "kk_native_byteArray_setShortAt", experimentalNativeApiAnnotations()),
            ("setIntAt", types.intType, "kk_native_byteArray_setIntAt", experimentalNativeApiAnnotations()),
            ("setLongAt", types.longType, "kk_native_byteArray_setLongAt", experimentalNativeApiAnnotations()),
            ("setUByteAt", types.ubyteType, "kk_native_byteArray_setUByteAt", experimentalNativeUnsignedApiAnnotations()),
            ("setUShortAt", types.ushortType, "kk_native_byteArray_setUShortAt", experimentalNativeUnsignedApiAnnotations()),
            ("setUIntAt", types.uintType, "kk_native_byteArray_setUIntAt", experimentalNativeUnsignedApiAnnotations()),
            ("setULongAt", types.ulongType, "kk_native_byteArray_setULongAt", experimentalNativeUnsignedApiAnnotations()),
            ("setCharAt", types.charType, "kk_native_byteArray_setCharAt", experimentalNativeApiAnnotations()),
            ("setFloatAt", types.floatType, "kk_native_byteArray_setFloatAt", experimentalNativeApiAnnotations()),
            ("setDoubleAt", types.doubleType, "kk_native_byteArray_setDoubleAt", experimentalNativeApiAnnotations()),
        ]
        for setter in setters {
            registerSyntheticNativeTopLevelFunction(
                named: setter.name,
                packageFQName: nativePkg,
                receiverType: byteArrayType,
                parameters: [
                    (name: "index", type: types.intType),
                    (name: "value", type: setter.valueType),
                ],
                returnType: types.unitType,
                annotations: setter.annotations,
                externalLinkName: setter.externalLinkName,
                symbols: symbols,
                interner: interner
            )
        }
    }

    private func registerSyntheticNativeIdentityHashCodeStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let nativePkg = ensurePackage(
            path: ["kotlin", "native"],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeTopLevelFunction(
            named: "identityHashCode",
            packageFQName: nativePkg,
            receiverType: types.makeNullable(types.anyType),
            parameters: [],
            returnType: types.intType,
            annotations: experimentalNativeApiAnnotations(),
            externalLinkName: "kk_native_identityHashCode",
            symbols: symbols,
            interner: interner
        )
    }

    private func registerSyntheticNativeStackTraceAddressStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let nativePkg = ensurePackage(
            path: ["kotlin", "native"],
            symbols: symbols,
            interner: interner
        )
        let listLongType = syntheticListType(
            elementType: types.longType,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticNativeTopLevelFunction(
            named: "getStackTraceAddresses",
            packageFQName: nativePkg,
            receiverType: nil,
            parameters: [],
            returnType: listLongType,
            annotations: experimentalNativeApiAnnotations(),
            externalLinkName: "kk_native_getStackTraceAddresses",
            symbols: symbols,
            interner: interner
        )
    }

    private func registerSyntheticNativeUnhandledExceptionHookStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let nativePkg = ensurePackage(
            path: ["kotlin", "native"],
            symbols: symbols,
            interner: interner
        )
        let nativePkgSymbol = symbols.lookup(fqName: nativePkg)
        let throwableType = syntheticThrowableType(
            symbols: symbols,
            types: types,
            interner: interner
        )
        let hookType = types.make(.functionType(FunctionType(
            params: [throwableType],
            returnType: types.unitType
        )))
        let nullableHookType = types.makeNullable(hookType)

        let hookAliasName = interner.intern("ReportUnhandledExceptionHook")
        let hookAliasFQName = nativePkg + [hookAliasName]
        let hookAliasSymbol: SymbolID
        if let existing = symbols.lookup(fqName: hookAliasFQName),
           symbols.symbol(existing)?.kind == .typeAlias
        {
            hookAliasSymbol = existing
            symbols.insertFlags([.synthetic], for: existing)
        } else if symbols.lookup(fqName: hookAliasFQName) == nil {
            hookAliasSymbol = symbols.define(
                kind: .typeAlias,
                name: hookAliasName,
                fqName: hookAliasFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        } else {
            return
        }
        if let nativePkgSymbol {
            symbols.setParentSymbol(nativePkgSymbol, for: hookAliasSymbol)
        }
        symbols.setTypeAliasUnderlyingType(hookType, for: hookAliasSymbol)
        appendMetadataAnnotations(
            experimentalNativeApiAnnotations(),
            to: hookAliasSymbol,
            symbols: symbols
        )

        let annotations = experimentalNativeApiAnnotations()
        registerSyntheticNativeTopLevelFunction(
            named: "getUnhandledExceptionHook",
            packageFQName: nativePkg,
            receiverType: nil,
            parameters: [],
            returnType: nullableHookType,
            annotations: annotations,
            externalLinkName: "kk_native_getUnhandledExceptionHook",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeTopLevelFunction(
            named: "setUnhandledExceptionHook",
            packageFQName: nativePkg,
            receiverType: nil,
            parameters: [("hook", nullableHookType)],
            returnType: types.unitType,
            annotations: annotations,
            externalLinkName: "kk_native_setUnhandledExceptionHook",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeTopLevelFunction(
            named: "processUnhandledException",
            packageFQName: nativePkg,
            receiverType: nil,
            parameters: [("throwable", throwableType)],
            returnType: types.unitType,
            annotations: annotations,
            externalLinkName: "kk_native_processUnhandledException",
            canThrow: true,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeTopLevelFunction(
            named: "terminateWithUnhandledException",
            packageFQName: nativePkg,
            receiverType: nil,
            parameters: [("throwable", throwableType)],
            returnType: types.nothingType,
            annotations: annotations,
            externalLinkName: "kk_native_terminateWithUnhandledException",
            symbols: symbols,
            interner: interner
        )
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
            targets: [
                "AnnotationTarget.TYPEALIAS",
                "AnnotationTarget.FUNCTION",
                "AnnotationTarget.PROPERTY",
                "AnnotationTarget.ANNOTATION_CLASS",
                "AnnotationTarget.CLASS",
            ],
            retention: "AnnotationRetention.BINARY",
            symbols: symbols
        )
        appendMetadataAnnotations(
            [
                MetadataAnnotationRecord(
                    annotationFQName: "kotlin.RequiresOptIn",
                    arguments: ["level=RequiresOptIn.Level.WARNING"]
                ),
            ],
            to: betaInteropApiSymbol,
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
        let cVariableSymbol = ensureClassSymbol(
            named: "CVariable",
            in: cinteropPkg,
            symbols: symbols,
            interner: interner
        )
        let cVariableTypeSymbol = ensureClassSymbol(
            named: "Type",
            in: cinteropPkg + [interner.intern("CVariable")],
            symbols: symbols,
            interner: interner
        )
        let cPrimitiveVarSymbol = ensureClassSymbol(
            named: "CPrimitiveVar",
            in: cinteropPkg,
            symbols: symbols,
            interner: interner
        )
        let cPrimitiveVarTypeSymbol = ensureClassSymbol(
            named: "Type",
            in: cinteropPkg + [interner.intern("CPrimitiveVar")],
            symbols: symbols,
            interner: interner
        )
        let cStructVarSymbol = ensureClassSymbol(
            named: "CStructVar",
            in: cinteropPkg,
            symbols: symbols,
            interner: interner
        )
        let cStructVarTypeSymbol = ensureClassSymbol(
            named: "Type",
            in: cinteropPkg + [interner.intern("CStructVar")],
            symbols: symbols,
            interner: interner
        )
        let cEnumSymbol = ensureInterfaceSymbol(
            named: "CEnum",
            in: cinteropPkg,
            symbols: symbols,
            interner: interner
        )
        let cEnumVarSymbol = ensureClassSymbol(
            named: "CEnumVar",
            in: cinteropPkg,
            symbols: symbols,
            interner: interner
        )
        let cFunctionSymbol = ensureClassSymbol(
            named: "CFunction",
            in: cinteropPkg,
            symbols: symbols,
            interner: interner
        )
        let cOpaqueSymbol = ensureClassSymbol(
            named: "COpaque",
            in: cinteropPkg,
            symbols: symbols,
            interner: interner
        )
        let nativePtrSymbol = ensureClassSymbol(
            named: "NativePtr",
            in: cinteropPkg,
            symbols: symbols,
            interner: interner
        )
        let nativePlacementSymbol = ensureInterfaceSymbol(
            named: "NativePlacement",
            in: cinteropPkg,
            symbols: symbols,
            interner: interner
        )
        let nativeFreeablePlacementSymbol = ensureInterfaceSymbol(
            named: "NativeFreeablePlacement",
            in: cinteropPkg,
            symbols: symbols,
            interner: interner
        )
        let deferScopeSymbol = ensureClassSymbol(
            named: "DeferScope",
            in: cinteropPkg,
            symbols: symbols,
            interner: interner
        )
        let autofreeScopeSymbol = ensureClassSymbol(
            named: "AutofreeScope",
            in: cinteropPkg,
            symbols: symbols,
            interner: interner
        )
        let arenaBaseSymbol = ensureClassSymbol(
            named: "ArenaBase",
            in: cinteropPkg,
            symbols: symbols,
            interner: interner
        )
        let arenaSymbol = ensureClassSymbol(
            named: "Arena",
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
        let cValueSymbol = ensureClassSymbol(
            named: "CValue",
            in: cinteropPkg,
            symbols: symbols,
            interner: interner
        )
        let cValuesSymbol = ensureClassSymbol(
            named: "CValues",
            in: cinteropPkg,
            symbols: symbols,
            interner: interner
        )
        let stableRefSymbol = ensureClassSymbol(
            named: "StableRef",
            in: cinteropPkg,
            symbols: symbols,
            interner: interner
        )
        let pinnedSymbol = ensureClassSymbol(
            named: "Pinned",
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
        let cPointerVarSymbol = ensureSyntheticCInteropTypeAliasSymbol(
            named: "CPointerVar",
            in: cinteropPkg,
            packageSymbol: cinteropPkgSymbol,
            symbols: symbols,
            interner: interner
        ) ?? ensureClassSymbol(
            named: "CPointerVar",
            in: cinteropPkg,
            symbols: symbols,
            interner: interner
        )
        let cPointerVarOfSymbol = ensureClassSymbol(
            named: "CPointerVarOf",
            in: cinteropPkg,
            symbols: symbols,
            interner: interner
        )
        let booleanVarOfSymbol = ensureClassSymbol(
            named: "BooleanVarOf",
            in: cinteropPkg,
            symbols: symbols,
            interner: interner
        )
        let byteVarOfSymbol = ensureClassSymbol(
            named: "ByteVarOf",
            in: cinteropPkg,
            symbols: symbols,
            interner: interner
        )

        for symbol in [
            nativePointedSymbol,
            cPointedSymbol,
            cVariableSymbol,
            cPrimitiveVarSymbol,
            cStructVarSymbol,
            cEnumSymbol,
            cEnumVarSymbol,
            cFunctionSymbol,
            cOpaqueSymbol,
            nativePtrSymbol,
            nativePlacementSymbol,
            nativeFreeablePlacementSymbol,
            deferScopeSymbol,
            autofreeScopeSymbol,
            arenaBaseSymbol,
            arenaSymbol,
            memScopeSymbol,
            cValuesRefSymbol,
            cValueSymbol,
            cValuesSymbol,
            stableRefSymbol,
            pinnedSymbol,
            cPointerSymbol,
            cPointerVarSymbol,
            cPointerVarOfSymbol,
            booleanVarOfSymbol,
            byteVarOfSymbol,
        ] {
            if let cinteropPkgSymbol {
                symbols.setParentSymbol(cinteropPkgSymbol, for: symbol)
            }
        }
        symbols.setParentSymbol(cVariableSymbol, for: cVariableTypeSymbol)
        symbols.setParentSymbol(cPrimitiveVarSymbol, for: cPrimitiveVarTypeSymbol)
        symbols.setParentSymbol(cStructVarSymbol, for: cStructVarTypeSymbol)

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
        symbols.insertFlags([.abstractType], for: cPointedSymbol)
        symbols.setDirectSupertypes([nativePointedSymbol], for: cPointedSymbol)
        types.setNominalDirectSupertypes([nativePointedSymbol], for: cPointedSymbol)

        let cVariableType = types.make(.classType(ClassType(
            classSymbol: cVariableSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(cVariableType, for: cVariableSymbol)
        symbols.insertFlags([.abstractType], for: cVariableSymbol)
        symbols.setDirectSupertypes([cPointedSymbol], for: cVariableSymbol)
        types.setNominalDirectSupertypes([cPointedSymbol], for: cVariableSymbol)

        let cVariableTypeClassType = types.make(.classType(ClassType(
            classSymbol: cVariableTypeSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(cVariableTypeClassType, for: cVariableTypeSymbol)
        symbols.insertFlags([.openType], for: cVariableTypeSymbol)
        appendMetadataAnnotations(
            [
                MetadataAnnotationRecord(
                    annotationFQName: "kotlin.Deprecated",
                    arguments: ["message = \"Use sizeOf<T>() or alignOf<T>() instead.\""]
                ),
            ],
            to: cVariableTypeSymbol,
            symbols: symbols
        )

        let cPrimitiveVarType = types.make(.classType(ClassType(
            classSymbol: cPrimitiveVarSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(cPrimitiveVarType, for: cPrimitiveVarSymbol)
        symbols.insertFlags([.sealedType, .abstractType, .openType], for: cPrimitiveVarSymbol)
        symbols.setDirectSupertypes([cVariableSymbol], for: cPrimitiveVarSymbol)
        types.setNominalDirectSupertypes([cVariableSymbol], for: cPrimitiveVarSymbol)

        let cPrimitiveVarTypeClassType = types.make(.classType(ClassType(
            classSymbol: cPrimitiveVarTypeSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(cPrimitiveVarTypeClassType, for: cPrimitiveVarTypeSymbol)
        symbols.insertFlags([.openType], for: cPrimitiveVarTypeSymbol)
        symbols.setDirectSupertypes([cVariableTypeSymbol], for: cPrimitiveVarTypeSymbol)
        types.setNominalDirectSupertypes([cVariableTypeSymbol], for: cPrimitiveVarTypeSymbol)

        let cStructVarType = types.make(.classType(ClassType(
            classSymbol: cStructVarSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(cStructVarType, for: cStructVarSymbol)
        symbols.insertFlags([.abstractType, .openType], for: cStructVarSymbol)
        symbols.setDirectSupertypes([cVariableSymbol], for: cStructVarSymbol)
        types.setNominalDirectSupertypes([cVariableSymbol], for: cStructVarSymbol)

        let cStructVarTypeClassType = types.make(.classType(ClassType(
            classSymbol: cStructVarTypeSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(cStructVarTypeClassType, for: cStructVarTypeSymbol)
        symbols.insertFlags([.openType], for: cStructVarTypeSymbol)
        symbols.setDirectSupertypes([cVariableTypeSymbol], for: cStructVarTypeSymbol)
        types.setNominalDirectSupertypes([cVariableTypeSymbol], for: cStructVarTypeSymbol)

        let cEnumType = types.make(.classType(ClassType(
            classSymbol: cEnumSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(cEnumType, for: cEnumSymbol)
        appendMetadataAnnotations(deprecatedCEnumAnnotations(), to: cEnumSymbol, symbols: symbols)
        registerSyntheticNativeBitSetProperty(
            named: "value",
            ownerSymbol: cEnumSymbol,
            propertyType: types.anyType,
            flags: [.synthetic, .abstractType],
            symbols: symbols,
            interner: interner
        )

        let cEnumVarType = types.make(.classType(ClassType(
            classSymbol: cEnumVarSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(cEnumVarType, for: cEnumVarSymbol)
        symbols.insertFlags([.abstractType], for: cEnumVarSymbol)
        symbols.setDirectSupertypes([cPrimitiveVarSymbol], for: cEnumVarSymbol)
        types.setNominalDirectSupertypes([cPrimitiveVarSymbol], for: cEnumVarSymbol)

        let cOpaqueType = types.make(.classType(ClassType(
            classSymbol: cOpaqueSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(cOpaqueType, for: cOpaqueSymbol)
        symbols.insertFlags([.abstractType], for: cOpaqueSymbol)
        symbols.setDirectSupertypes([cPointedSymbol], for: cOpaqueSymbol)
        types.setNominalDirectSupertypes([cPointedSymbol], for: cOpaqueSymbol)

        let nativePtrType = types.make(.classType(ClassType(
            classSymbol: nativePtrSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(nativePtrType, for: nativePtrSymbol)

        registerSyntheticNativeBitSetConstructor(
            ownerSymbol: cPointedSymbol,
            ownerType: cPointedType,
            parameters: [(name: "rawPtr", type: nativePtrType)],
            defaultValues: [false],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeBitSetProperty(
            named: "rawPtr",
            ownerSymbol: cPointedSymbol,
            propertyType: nativePtrType,
            flags: [.synthetic, .mutable],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeBitSetConstructor(
            ownerSymbol: cVariableSymbol,
            ownerType: cVariableType,
            parameters: [(name: "rawPtr", type: nativePtrType)],
            defaultValues: [false],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeBitSetConstructor(
            ownerSymbol: cVariableTypeSymbol,
            ownerType: cVariableTypeClassType,
            parameters: [
                (name: "size", type: types.longType),
                (name: "align", type: types.intType),
            ],
            defaultValues: [false, false],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeBitSetProperty(
            named: "size",
            ownerSymbol: cVariableTypeSymbol,
            propertyType: types.longType,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeBitSetProperty(
            named: "align",
            ownerSymbol: cVariableTypeSymbol,
            propertyType: types.intType,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticNativeBitSetConstructor(
            ownerSymbol: cPrimitiveVarSymbol,
            ownerType: cPrimitiveVarType,
            parameters: [(name: "rawPtr", type: nativePtrType)],
            defaultValues: [false],
            visibility: .protected,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeBitSetConstructor(
            ownerSymbol: cPrimitiveVarTypeSymbol,
            ownerType: cPrimitiveVarTypeClassType,
            parameters: [(name: "size", type: types.intType)],
            defaultValues: [false],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeBitSetConstructor(
            ownerSymbol: cStructVarSymbol,
            ownerType: cStructVarType,
            parameters: [(name: "rawPtr", type: nativePtrType)],
            defaultValues: [false],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeBitSetConstructor(
            ownerSymbol: cStructVarTypeSymbol,
            ownerType: cStructVarTypeClassType,
            parameters: [
                (name: "size", type: types.longType),
                (name: "align", type: types.intType),
            ],
            defaultValues: [false, false],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeBitSetConstructor(
            ownerSymbol: cEnumVarSymbol,
            ownerType: cEnumVarType,
            parameters: [(name: "rawPtr", type: nativePtrType)],
            defaultValues: [false],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeBitSetConstructor(
            ownerSymbol: cOpaqueSymbol,
            ownerType: cOpaqueType,
            parameters: [(name: "rawPtr", type: nativePtrType)],
            defaultValues: [false],
            symbols: symbols,
            interner: interner
        )

        let nativePlacementType = types.make(.classType(ClassType(
            classSymbol: nativePlacementSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(nativePlacementType, for: nativePlacementSymbol)
        registerSyntheticNativeBitSetMemberFunction(
            named: "alloc",
            ownerSymbol: nativePlacementSymbol,
            receiverType: nativePlacementType,
            parameters: [
                (name: "size", type: types.longType),
                (name: "align", type: types.intType),
            ],
            returnType: nativePointedType,
            flags: [.synthetic, .abstractType],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeBitSetMemberFunction(
            named: "alloc",
            ownerSymbol: nativePlacementSymbol,
            receiverType: nativePlacementType,
            parameters: [
                (name: "size", type: types.intType),
                (name: "align", type: types.intType),
            ],
            returnType: nativePointedType,
            flags: [.synthetic, .openType],
            symbols: symbols,
            interner: interner
        )
        let nativePlacementAllocName = interner.intern("alloc")
        let nativePlacementAllocFQName = cinteropPkg + [nativePlacementAllocName]
        let nativePlacementAllocTypeParameterName = interner.intern("T")
        let nativePlacementAllocTypeParameterFQName = nativePlacementAllocFQName + [nativePlacementAllocTypeParameterName]
        let nativePlacementAllocTypeParameterSymbol: SymbolID = if let existing = symbols.lookup(
            fqName: nativePlacementAllocTypeParameterFQName
        ) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: nativePlacementAllocTypeParameterName,
                fqName: nativePlacementAllocTypeParameterFQName,
                declSite: nil,
                visibility: .private,
                flags: [.synthetic, .reifiedTypeParameter]
            )
        }
        symbols.insertFlags([.synthetic, .reifiedTypeParameter], for: nativePlacementAllocTypeParameterSymbol)
        symbols.setTypeParameterUpperBounds([cVariableType], for: nativePlacementAllocTypeParameterSymbol)
        let nativePlacementAllocTypeParameterType = types.make(.typeParam(TypeParamType(
            symbol: nativePlacementAllocTypeParameterSymbol,
            nullability: .nonNull
        )))
        registerSyntheticNativeTopLevelFunction(
            named: "alloc",
            packageFQName: cinteropPkg,
            receiverType: nativePlacementType,
            parameters: [],
            returnType: nativePlacementAllocTypeParameterType,
            typeParameterSymbols: [nativePlacementAllocTypeParameterSymbol],
            typeParameterUpperBoundsList: [[cVariableType]],
            reifiedTypeParameterIndices: [0],
            flags: [.synthetic, .inlineFunction],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativePlacementAllocArrayFunction(
            lengthType: types.longType,
            typeParameterDiscriminator: "$lengthLong",
            cVariableType: cVariableType,
            cPointerSymbol: cPointerSymbol,
            nativePlacementType: nativePlacementType,
            packageFQName: cinteropPkg,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticNativePlacementAllocArrayFunction(
            lengthType: types.intType,
            typeParameterDiscriminator: "$lengthInt",
            cVariableType: cVariableType,
            cPointerSymbol: cPointerSymbol,
            nativePlacementType: nativePlacementType,
            packageFQName: cinteropPkg,
            symbols: symbols,
            types: types,
            interner: interner
        )

        let nativeFreeablePlacementType = types.make(.classType(ClassType(
            classSymbol: nativeFreeablePlacementSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(nativeFreeablePlacementType, for: nativeFreeablePlacementSymbol)
        symbols.setDirectSupertypes([nativePlacementSymbol], for: nativeFreeablePlacementSymbol)
        types.setNominalDirectSupertypes([nativePlacementSymbol], for: nativeFreeablePlacementSymbol)

        registerSyntheticNativeTopLevelProperty(
            named: "nativeHeap",
            packageFQName: cinteropPkg,
            packageSymbol: cinteropPkgSymbol,
            propertyType: nativeFreeablePlacementType,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeTopLevelFunction(
            named: "free",
            packageFQName: cinteropPkg,
            receiverType: nativeFreeablePlacementType,
            parameters: [(name: "pointed", type: nativePointedType)],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )

        let deferScopeType = types.make(.classType(ClassType(
            classSymbol: deferScopeSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(deferScopeType, for: deferScopeSymbol)
        symbols.insertFlags([.openType], for: deferScopeSymbol)
        registerSyntheticNativeBitSetConstructor(
            ownerSymbol: deferScopeSymbol,
            ownerType: deferScopeType,
            parameters: [],
            defaultValues: [],
            symbols: symbols,
            interner: interner
        )
        let deferBlockType = types.make(.functionType(FunctionType(
            params: [],
            returnType: types.unitType
        )))
        registerSyntheticNativeBitSetMemberFunction(
            named: "defer",
            ownerSymbol: deferScopeSymbol,
            receiverType: deferScopeType,
            parameters: [(name: "block", type: deferBlockType)],
            returnType: types.unitType,
            flags: [.synthetic, .inlineFunction],
            symbols: symbols,
            interner: interner
        )

        let autofreeScopeType = types.make(.classType(ClassType(
            classSymbol: autofreeScopeSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(autofreeScopeType, for: autofreeScopeSymbol)
        symbols.insertFlags([.abstractType], for: autofreeScopeSymbol)
        symbols.setDirectSupertypes([deferScopeSymbol, nativePlacementSymbol], for: autofreeScopeSymbol)
        types.setNominalDirectSupertypes([deferScopeSymbol, nativePlacementSymbol], for: autofreeScopeSymbol)

        let arenaBaseType = types.make(.classType(ClassType(
            classSymbol: arenaBaseSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(arenaBaseType, for: arenaBaseSymbol)
        symbols.insertFlags([.openType], for: arenaBaseSymbol)
        symbols.setDirectSupertypes([autofreeScopeSymbol], for: arenaBaseSymbol)
        types.setNominalDirectSupertypes([autofreeScopeSymbol], for: arenaBaseSymbol)

        let arenaType = types.make(.classType(ClassType(
            classSymbol: arenaSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(arenaType, for: arenaSymbol)
        symbols.setDirectSupertypes([arenaBaseSymbol], for: arenaSymbol)
        types.setNominalDirectSupertypes([arenaBaseSymbol], for: arenaSymbol)

        let memScopeType = types.make(.classType(ClassType(
            classSymbol: memScopeSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(memScopeType, for: memScopeSymbol)
        symbols.setDirectSupertypes([arenaBaseSymbol], for: memScopeSymbol)
        types.setNominalDirectSupertypes([arenaBaseSymbol], for: memScopeSymbol)

        registerSyntheticNativeBitSetConstructor(
            ownerSymbol: arenaBaseSymbol,
            ownerType: arenaBaseType,
            parameters: [(name: "parent", type: nativeFreeablePlacementType)],
            defaultValues: [true],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeBitSetMemberFunction(
            named: "alloc",
            ownerSymbol: arenaBaseSymbol,
            receiverType: arenaBaseType,
            parameters: [
                (name: "size", type: types.longType),
                (name: "align", type: types.intType),
            ],
            returnType: nativePointedType,
            flags: [.synthetic, .overrideMember],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeBitSetMemberFunction(
            named: "alloc",
            ownerSymbol: arenaBaseSymbol,
            receiverType: arenaBaseType,
            parameters: [
                (name: "size", type: types.intType),
                (name: "align", type: types.intType),
            ],
            returnType: nativePointedType,
            flags: [.synthetic, .openType],
            symbols: symbols,
            interner: interner
        )

        registerSyntheticNativeBitSetConstructor(
            ownerSymbol: arenaSymbol,
            ownerType: arenaType,
            parameters: [(name: "parent", type: nativeFreeablePlacementType)],
            defaultValues: [true],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeBitSetMemberFunction(
            named: "alloc",
            ownerSymbol: arenaSymbol,
            receiverType: arenaType,
            parameters: [
                (name: "size", type: types.longType),
                (name: "align", type: types.intType),
            ],
            returnType: nativePointedType,
            flags: [.synthetic, .overrideMember],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeBitSetMemberFunction(
            named: "alloc",
            ownerSymbol: arenaSymbol,
            receiverType: arenaType,
            parameters: [
                (name: "size", type: types.intType),
                (name: "align", type: types.intType),
            ],
            returnType: nativePointedType,
            flags: [.synthetic, .openType],
            symbols: symbols,
            interner: interner
        )

        registerSyntheticNativeBitSetConstructor(
            ownerSymbol: autofreeScopeSymbol,
            ownerType: autofreeScopeType,
            parameters: [],
            defaultValues: [],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeBitSetMemberFunction(
            named: "alloc",
            ownerSymbol: autofreeScopeSymbol,
            receiverType: autofreeScopeType,
            parameters: [
                (name: "size", type: types.longType),
                (name: "align", type: types.intType),
            ],
            returnType: nativePointedType,
            flags: [.synthetic, .abstractType, .overrideMember],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeBitSetMemberFunction(
            named: "alloc",
            ownerSymbol: autofreeScopeSymbol,
            receiverType: autofreeScopeType,
            parameters: [
                (name: "size", type: types.intType),
                (name: "align", type: types.intType),
            ],
            returnType: nativePointedType,
            flags: [.synthetic, .openType],
            symbols: symbols,
            interner: interner
        )

        configureSingleTypeParameterNominal(
            ownerSymbol: cValuesRefSymbol,
            fqName: cinteropPkg + [interner.intern("CValuesRef")],
            parameterName: "T",
            supertype: nil,
            symbols: symbols,
            types: types,
            interner: interner
        )
        symbols.insertFlags([.abstractType], for: cValuesRefSymbol)
        if let cValuesRefTypeParameterSymbol = types.nominalTypeParameterSymbols(for: cValuesRefSymbol).first {
            symbols.setTypeParameterUpperBounds([cPointedType], for: cValuesRefTypeParameterSymbol)
            let cValuesRefTypeParameterType = types.make(.typeParam(TypeParamType(
                symbol: cValuesRefTypeParameterSymbol,
                nullability: .nonNull
            )))
            let cValuesRefType = types.make(.classType(ClassType(
                classSymbol: cValuesRefSymbol,
                args: [.invariant(cValuesRefTypeParameterType)],
                nullability: .nonNull
            )))
            let cPointerToCValuesRefTypeParameterType = types.make(.classType(ClassType(
                classSymbol: cPointerSymbol,
                args: [.invariant(cValuesRefTypeParameterType)],
                nullability: .nonNull
            )))
            registerSyntheticNativeBitSetConstructor(
                ownerSymbol: cValuesRefSymbol,
                ownerType: cValuesRefType,
                parameters: [],
                defaultValues: [],
                symbols: symbols,
                interner: interner
            )
            registerSyntheticNativeBitSetMemberFunction(
                named: "getPointer",
                ownerSymbol: cValuesRefSymbol,
                receiverType: cValuesRefType,
                parameters: [(name: "scope", type: autofreeScopeType)],
                returnType: cPointerToCValuesRefTypeParameterType,
                typeParameterSymbols: [cValuesRefTypeParameterSymbol],
                typeParameterUpperBoundsList: [[cPointedType]],
                classTypeParameterCount: 1,
                flags: [.synthetic, .abstractType],
                symbols: symbols,
                interner: interner
            )
        }
        configureSingleTypeParameterNominal(
            ownerSymbol: cValueSymbol,
            fqName: cinteropPkg + [interner.intern("CValue")],
            parameterName: "T",
            supertype: cValuesSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
        symbols.insertFlags([.abstractType], for: cValueSymbol)
        if let cValueTypeParameterSymbol = types.nominalTypeParameterSymbols(for: cValueSymbol).first {
            symbols.setTypeParameterUpperBounds([cVariableType], for: cValueTypeParameterSymbol)
            let cValueTypeParameterType = types.make(.typeParam(TypeParamType(
                symbol: cValueTypeParameterSymbol,
                nullability: .nonNull
            )))
            let cValueType = types.make(.classType(ClassType(
                classSymbol: cValueSymbol,
                args: [.invariant(cValueTypeParameterType)],
                nullability: .nonNull
            )))
            registerSyntheticNativeBitSetConstructor(
                ownerSymbol: cValueSymbol,
                ownerType: cValueType,
                parameters: [],
                defaultValues: [],
                symbols: symbols,
                interner: interner
            )
        }
        configureSingleTypeParameterNominal(
            ownerSymbol: cValuesSymbol,
            fqName: cinteropPkg + [interner.intern("CValues")],
            parameterName: "T",
            supertype: cValuesRefSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
        symbols.insertFlags([.abstractType], for: cValuesSymbol)
        if let cValuesTypeParameterSymbol = types.nominalTypeParameterSymbols(for: cValuesSymbol).first {
            symbols.setTypeParameterUpperBounds([cVariableType], for: cValuesTypeParameterSymbol)
            let cValuesTypeParameterType = types.make(.typeParam(TypeParamType(
                symbol: cValuesTypeParameterSymbol,
                nullability: .nonNull
            )))
            let cValuesType = types.make(.classType(ClassType(
                classSymbol: cValuesSymbol,
                args: [.invariant(cValuesTypeParameterType)],
                nullability: .nonNull
            )))
            let cPointerToCValuesTypeParameterType = types.make(.classType(ClassType(
                classSymbol: cPointerSymbol,
                args: [.invariant(cValuesTypeParameterType)],
                nullability: .nonNull
            )))
            registerSyntheticNativeBitSetConstructor(
                ownerSymbol: cValuesSymbol,
                ownerType: cValuesType,
                parameters: [],
                defaultValues: [],
                symbols: symbols,
                interner: interner
            )
            registerSyntheticNativeBitSetProperty(
                named: "align",
                ownerSymbol: cValuesSymbol,
                propertyType: types.intType,
                flags: [.synthetic, .abstractType],
                symbols: symbols,
                interner: interner
            )
            registerSyntheticNativeBitSetProperty(
                named: "size",
                ownerSymbol: cValuesSymbol,
                propertyType: types.intType,
                flags: [.synthetic, .abstractType],
                symbols: symbols,
                interner: interner
            )
            registerSyntheticNativeBitSetMemberFunction(
                named: "getPointer",
                ownerSymbol: cValuesSymbol,
                receiverType: cValuesType,
                parameters: [(name: "scope", type: autofreeScopeType)],
                returnType: cPointerToCValuesTypeParameterType,
                typeParameterSymbols: [cValuesTypeParameterSymbol],
                typeParameterUpperBoundsList: [[cVariableType]],
                classTypeParameterCount: 1,
                flags: [.synthetic, .openType, .overrideMember],
                symbols: symbols,
                interner: interner
            )
            registerSyntheticNativeBitSetMemberFunction(
                named: "place",
                ownerSymbol: cValuesSymbol,
                receiverType: cValuesType,
                parameters: [(name: "placement", type: cPointerToCValuesTypeParameterType)],
                returnType: cPointerToCValuesTypeParameterType,
                typeParameterSymbols: [cValuesTypeParameterSymbol],
                typeParameterUpperBoundsList: [[cVariableType]],
                classTypeParameterCount: 1,
                flags: [.synthetic, .abstractType],
                annotations: [MetadataAnnotationRecord(annotationFQName: "kotlin.IgnorableReturnValue")],
                symbols: symbols,
                interner: interner
            )
        }
        registerSyntheticCPointedReadFunction(
            named: "readValue",
            ownerSymbol: cPointedSymbol,
            ownerType: cPointedType,
            typeParameterUpperBound: cVariableType,
            returnClassSymbol: cValueSymbol,
            parameters: [
                (name: "size", type: types.longType),
                (name: "align", type: types.intType),
            ],
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticCPointedReadFunction(
            named: "readValues",
            ownerSymbol: cPointedSymbol,
            ownerType: cPointedType,
            typeParameterUpperBound: cVariableType,
            returnClassSymbol: cValuesSymbol,
            parameters: [
                (name: "size", type: types.intType),
                (name: "align", type: types.intType),
            ],
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
        if let cPointerTypeParameterSymbol = types.nominalTypeParameterSymbols(for: cPointerSymbol).first {
            symbols.setTypeParameterUpperBounds([cPointedType], for: cPointerTypeParameterSymbol)
            let cPointerTypeParameterType = types.make(.typeParam(TypeParamType(
                symbol: cPointerTypeParameterSymbol,
                nullability: .nonNull
            )))
            let cPointerType = types.make(.classType(ClassType(
                classSymbol: cPointerSymbol,
                args: [.invariant(cPointerTypeParameterType)],
                nullability: .nonNull
            )))
            registerSyntheticNativeBitSetMemberFunction(
                named: "getPointer",
                ownerSymbol: cPointerSymbol,
                receiverType: cPointerType,
                parameters: [(name: "scope", type: autofreeScopeType)],
                returnType: cPointerType,
                typeParameterSymbols: [cPointerTypeParameterSymbol],
                typeParameterUpperBoundsList: [[cPointedType]],
                classTypeParameterCount: 1,
                flags: [.synthetic, .openType, .overrideMember],
                symbols: symbols,
                interner: interner
            )
        }
        registerSyntheticCPointerPointedProperty(
            cPointerSymbol: cPointerSymbol,
            cPointedType: cPointedType,
            packageFQName: cinteropPkg,
            packageSymbol: cinteropPkgSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticNativeBitSetProperty(
            named: "rawValue",
            ownerSymbol: cPointerSymbol,
            propertyType: nativePtrType,
            symbols: symbols,
            interner: interner
        )
        // inline fun <reified T : CPointed> CPointer<*>.reinterpret(): CPointer<T>
        let reinterpretStarReceiverType = types.make(.classType(ClassType(
            classSymbol: cPointerSymbol,
            args: [.star],
            nullability: .nonNull
        )))
        let reinterpretFunctionName = interner.intern("reinterpret")
        let reinterpretFunctionFQName = cinteropPkg + [reinterpretFunctionName]
        let reinterpretTypeParameterName = interner.intern("T")
        let reinterpretTypeParameterFQName = reinterpretFunctionFQName + [reinterpretTypeParameterName]
        let reinterpretTypeParameterSymbol: SymbolID = if let existing = symbols.lookup(
            fqName: reinterpretTypeParameterFQName
        ) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: reinterpretTypeParameterName,
                fqName: reinterpretTypeParameterFQName,
                declSite: nil,
                visibility: .private,
                flags: [.synthetic, .reifiedTypeParameter]
            )
        }
        symbols.insertFlags([.synthetic, .reifiedTypeParameter], for: reinterpretTypeParameterSymbol)
        symbols.setTypeParameterUpperBounds([cPointedType], for: reinterpretTypeParameterSymbol)
        let reinterpretTypeParameterType = types.make(.typeParam(TypeParamType(
            symbol: reinterpretTypeParameterSymbol,
            nullability: .nonNull
        )))
        let reinterpretReturnType = types.make(.classType(ClassType(
            classSymbol: cPointerSymbol,
            args: [.invariant(reinterpretTypeParameterType)],
            nullability: .nonNull
        )))
        registerSyntheticNativeTopLevelFunction(
            named: "reinterpret",
            packageFQName: cinteropPkg,
            receiverType: reinterpretStarReceiverType,
            parameters: [],
            returnType: reinterpretReturnType,
            typeParameterSymbols: [reinterpretTypeParameterSymbol],
            typeParameterUpperBoundsList: [[cPointedType]],
            reifiedTypeParameterIndices: [0],
            flags: [.synthetic, .inlineFunction],
            symbols: symbols,
            interner: interner
        )
        // inline fun <T : CPointed> CPointer<T>?.toLong(): Long
        let pointerToLongFunctionName = interner.intern("toLong")
        let pointerToLongFunctionFQName = cinteropPkg + [pointerToLongFunctionName]
        let pointerToLongTypeParameterName = interner.intern("T")
        let pointerToLongTypeParameterFQName = pointerToLongFunctionFQName + [pointerToLongTypeParameterName]
        let pointerToLongTypeParameterSymbol: SymbolID = if let existing = symbols.lookup(
            fqName: pointerToLongTypeParameterFQName
        ) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: pointerToLongTypeParameterName,
                fqName: pointerToLongTypeParameterFQName,
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
        }
        symbols.insertFlags([.synthetic], for: pointerToLongTypeParameterSymbol)
        symbols.setTypeParameterUpperBounds([cPointedType], for: pointerToLongTypeParameterSymbol)
        let pointerToLongTypeParameterType = types.make(.typeParam(TypeParamType(
            symbol: pointerToLongTypeParameterSymbol,
            nullability: .nonNull
        )))
        let pointerToLongNullableReceiverType = types.make(.classType(ClassType(
            classSymbol: cPointerSymbol,
            args: [.invariant(pointerToLongTypeParameterType)],
            nullability: .nullable
        )))
        registerSyntheticNativeTopLevelFunction(
            named: "toLong",
            packageFQName: cinteropPkg,
            receiverType: pointerToLongNullableReceiverType,
            parameters: [],
            returnType: types.longType,
            typeParameterSymbols: [pointerToLongTypeParameterSymbol],
            typeParameterUpperBoundsList: [[cPointedType]],
            flags: [.synthetic, .inlineFunction],
            symbols: symbols,
            interner: interner
        )
        // inline fun <reified T : Any> unwrapKotlinObjectHolder(holder: COpaquePointer?): T
        let unwrapHolderFunctionName = interner.intern("unwrapKotlinObjectHolder")
        let unwrapHolderFunctionFQName = cinteropPkg + [unwrapHolderFunctionName]
        let unwrapHolderTypeParameterName = interner.intern("T")
        let unwrapHolderTypeParameterFQName = unwrapHolderFunctionFQName + [unwrapHolderTypeParameterName]
        let unwrapHolderTypeParameterSymbol: SymbolID = if let existing = symbols.lookup(
            fqName: unwrapHolderTypeParameterFQName
        ) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: unwrapHolderTypeParameterName,
                fqName: unwrapHolderTypeParameterFQName,
                declSite: nil,
                visibility: .private,
                flags: [.synthetic, .reifiedTypeParameter]
            )
        }
        symbols.insertFlags([.synthetic, .reifiedTypeParameter], for: unwrapHolderTypeParameterSymbol)
        symbols.setTypeParameterUpperBounds([types.anyType], for: unwrapHolderTypeParameterSymbol)
        let unwrapHolderTypeParameterType = types.make(.typeParam(TypeParamType(
            symbol: unwrapHolderTypeParameterSymbol,
            nullability: .nonNull
        )))
        let unwrapHolderHolderType: TypeID = if let cOpaquePointerSymbol = symbols.lookup(fqName: cinteropPkg + [interner.intern("COpaquePointer")]) {
            types.make(.classType(ClassType(
                classSymbol: cOpaquePointerSymbol,
                args: [],
                nullability: .nullable
            )))
        } else {
            types.make(.classType(ClassType(
                classSymbol: cPointerSymbol,
                args: [.star],
                nullability: .nullable
            )))
        }
        registerSyntheticNativeTopLevelFunction(
            named: "unwrapKotlinObjectHolder",
            packageFQName: cinteropPkg,
            receiverType: nil,
            parameters: [(name: "holder", type: unwrapHolderHolderType)],
            returnType: unwrapHolderTypeParameterType,
            typeParameterSymbols: [unwrapHolderTypeParameterSymbol],
            typeParameterUpperBoundsList: [[types.anyType]],
            reifiedTypeParameterIndices: [0],
            flags: [.synthetic, .inlineFunction],
            symbols: symbols,
            interner: interner
        )
        configureSingleTypeParameterNominal(
            ownerSymbol: cPointerVarOfSymbol,
            fqName: cinteropPkg + [interner.intern("CPointerVarOf")],
            parameterName: "T",
            supertype: cVariableSymbol,
            supertypeIsGeneric: false,
            symbols: symbols,
            types: types,
            interner: interner
        )
        if let cPointerVarOfTypeParameterSymbol = types.nominalTypeParameterSymbols(for: cPointerVarOfSymbol).first {
            symbols.setParentSymbol(cPointerVarOfSymbol, for: cPointerVarOfTypeParameterSymbol)
            let cPointerStarType = types.make(.classType(ClassType(
                classSymbol: cPointerSymbol,
                args: [.star],
                nullability: .nonNull
            )))
            symbols.setTypeParameterUpperBounds([cPointerStarType], for: cPointerVarOfTypeParameterSymbol)
            let cPointerVarOfTypeParameterType = types.make(.typeParam(TypeParamType(
                symbol: cPointerVarOfTypeParameterSymbol,
                nullability: .nonNull
            )))
            let cPointerVarOfType = types.make(.classType(ClassType(
                classSymbol: cPointerVarOfSymbol,
                args: [.invariant(cPointerVarOfTypeParameterType)],
                nullability: .nonNull
            )))
            registerSyntheticNativeBitSetConstructor(
                ownerSymbol: cPointerVarOfSymbol,
                ownerType: cPointerVarOfType,
                parameters: [(name: "rawPtr", type: nativePtrType)],
                defaultValues: [false],
                symbols: symbols,
                interner: interner
            )
        }
        let cPointerVarOfCompanionName = interner.intern("Companion")
        let cPointerVarOfCompanionFQName = cinteropPkg + [interner.intern("CPointerVarOf"), cPointerVarOfCompanionName]
        let cPointerVarOfCompanionSymbol: SymbolID
        if let existingCompanion = symbols.companionObjectSymbol(for: cPointerVarOfSymbol) {
            cPointerVarOfCompanionSymbol = existingCompanion
        } else if let existing = symbols.lookup(fqName: cPointerVarOfCompanionFQName),
                  symbols.symbol(existing)?.kind == .object
        {
            cPointerVarOfCompanionSymbol = existing
        } else {
            cPointerVarOfCompanionSymbol = symbols.define(
                kind: .object,
                name: cPointerVarOfCompanionName,
                fqName: cPointerVarOfCompanionFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .static]
            )
        }
        symbols.setParentSymbol(cPointerVarOfSymbol, for: cPointerVarOfCompanionSymbol)
        symbols.setCompanionObjectSymbol(cPointerVarOfCompanionSymbol, for: cPointerVarOfSymbol)
        let cPointerVarOfCompanionType = types.make(.classType(ClassType(
            classSymbol: cPointerVarOfCompanionSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(cPointerVarOfCompanionType, for: cPointerVarOfCompanionSymbol)
        symbols.setDirectSupertypes([cVariableTypeSymbol], for: cPointerVarOfCompanionSymbol)
        types.setNominalDirectSupertypes([cVariableTypeSymbol], for: cPointerVarOfCompanionSymbol)
        registerSyntheticCPointerVarTypeAlias(
            aliasSymbol: cPointerVarSymbol,
            aliasFQName: cinteropPkg + [interner.intern("CPointerVar")],
            typeParameterUpperBound: cPointedType,
            cPointerSymbol: cPointerSymbol,
            cPointerVarOfSymbol: cPointerVarOfSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
        configureSingleTypeParameterNominal(
            ownerSymbol: cFunctionSymbol,
            fqName: cinteropPkg + [interner.intern("CFunction")],
            parameterName: "T",
            supertype: cPointedSymbol,
            supertypeIsGeneric: false,
            symbols: symbols,
            types: types,
            interner: interner
        )
        if let cFunctionTypeParameterSymbol = types.nominalTypeParameterSymbols(for: cFunctionSymbol).first {
            symbols.setTypeParameterUpperBounds([types.anyType], for: cFunctionTypeParameterSymbol)
            let cFunctionTypeParameterType = types.make(.typeParam(TypeParamType(
                symbol: cFunctionTypeParameterSymbol,
                nullability: .nonNull
            )))
            let cFunctionType = types.make(.classType(ClassType(
                classSymbol: cFunctionSymbol,
                args: [.invariant(cFunctionTypeParameterType)],
                nullability: .nonNull
            )))
            registerNativeConcurrentConstructor(
                ownerSymbol: cFunctionSymbol,
                ownerType: cFunctionType,
                parameters: [(name: "rawPtr", type: nativePtrType)],
                defaultValues: [false],
                typeParameterSymbols: [cFunctionTypeParameterSymbol],
                classTypeParameterCount: 1,
                symbols: symbols,
                interner: interner
            )
        }
        configureSingleTypeParameterNominal(
            ownerSymbol: booleanVarOfSymbol,
            fqName: cinteropPkg + [interner.intern("BooleanVarOf")],
            parameterName: "T",
            supertype: cPrimitiveVarSymbol,
            supertypeIsGeneric: false,
            symbols: symbols,
            types: types,
            interner: interner
        )
        if let booleanVarOfTypeParameterSymbol = types.nominalTypeParameterSymbols(for: booleanVarOfSymbol).first {
            symbols.setTypeParameterUpperBounds([types.booleanType], for: booleanVarOfTypeParameterSymbol)
            let booleanVarOfTypeParameterType = types.make(.typeParam(TypeParamType(
                symbol: booleanVarOfTypeParameterSymbol,
                nullability: .nonNull
            )))
            let booleanVarOfType = types.make(.classType(ClassType(
                classSymbol: booleanVarOfSymbol,
                args: [.invariant(booleanVarOfTypeParameterType)],
                nullability: .nonNull
            )))
            registerNativeConcurrentConstructor(
                ownerSymbol: booleanVarOfSymbol,
                ownerType: booleanVarOfType,
                parameters: [(name: "rawPtr", type: nativePtrType)],
                defaultValues: [false],
                typeParameterSymbols: [booleanVarOfTypeParameterSymbol],
                classTypeParameterCount: 1,
                symbols: symbols,
                interner: interner
            )
            registerSyntheticNativeBitSetProperty(
                named: "value",
                ownerSymbol: booleanVarOfSymbol,
                propertyType: booleanVarOfTypeParameterType,
                symbols: symbols,
                interner: interner
            )
        }
        configureSingleTypeParameterNominal(
            ownerSymbol: byteVarOfSymbol,
            fqName: cinteropPkg + [interner.intern("ByteVarOf")],
            parameterName: "T",
            supertype: cPrimitiveVarSymbol,
            supertypeIsGeneric: false,
            symbols: symbols,
            types: types,
            interner: interner
        )
        if let byteVarOfTypeParameterSymbol = types.nominalTypeParameterSymbols(for: byteVarOfSymbol).first {
            symbols.setTypeParameterUpperBounds([types.intType], for: byteVarOfTypeParameterSymbol)
            let byteVarOfTypeParameterType = types.make(.typeParam(TypeParamType(
                symbol: byteVarOfTypeParameterSymbol,
                nullability: .nonNull
            )))
            let byteVarOfType = types.make(.classType(ClassType(
                classSymbol: byteVarOfSymbol,
                args: [.invariant(byteVarOfTypeParameterType)],
                nullability: .nonNull
            )))
            registerNativeConcurrentConstructor(
                ownerSymbol: byteVarOfSymbol,
                ownerType: byteVarOfType,
                parameters: [(name: "rawPtr", type: nativePtrType)],
                defaultValues: [false],
                typeParameterSymbols: [byteVarOfTypeParameterSymbol],
                classTypeParameterCount: 1,
                symbols: symbols,
                interner: interner
            )
            registerSyntheticNativeBitSetProperty(
                named: "value",
                ownerSymbol: byteVarOfSymbol,
                propertyType: byteVarOfTypeParameterType,
                symbols: symbols,
                interner: interner
            )
        }
        let booleanVarType = types.make(.classType(ClassType(
            classSymbol: booleanVarOfSymbol,
            args: [.invariant(types.booleanType)],
            nullability: .nonNull
        )))
        registerSyntheticCInteropTypeAlias(
            named: "BooleanVar",
            in: cinteropPkg,
            packageSymbol: cinteropPkgSymbol,
            underlyingType: booleanVarType,
            symbols: symbols,
            interner: interner
        )
        let byteVarType = types.make(.classType(ClassType(
            classSymbol: byteVarOfSymbol,
            args: [.invariant(types.intType)],
            nullability: .nonNull
        )))
        registerSyntheticCInteropTypeAlias(
            named: "ByteVar",
            in: cinteropPkg,
            packageSymbol: cinteropPkgSymbol,
            underlyingType: byteVarType,
            symbols: symbols,
            interner: interner
        )
        let cstrReturnType = types.make(.classType(ClassType(
            classSymbol: cValuesSymbol,
            args: [.invariant(byteVarType)],
            nullability: .nonNull
        )))
        registerSyntheticNativeExtensionProperty(
            named: "cstr",
            packageFQName: cinteropPkg,
            packageSymbol: cinteropPkgSymbol,
            receiverType: types.stringType,
            propertyType: cstrReturnType,
            symbols: symbols,
            interner: interner
        )
        // fun ByteArray.toCValues(): CValues<ByteVar>
        let byteArrayReceiverType = syntheticClassType(
            packagePath: ["kotlin"],
            name: "ByteArray",
            symbols: symbols,
            types: types,
            interner: interner
        )
        let byteArrayToCValuesReturnType = types.make(.classType(ClassType(
            classSymbol: cValuesSymbol,
            args: [.invariant(byteVarType)],
            nullability: .nonNull
        )))
        registerSyntheticNativeTopLevelFunction(
            named: "toCValues",
            packageFQName: cinteropPkg,
            receiverType: byteArrayReceiverType,
            parameters: [],
            returnType: byteArrayToCValuesReturnType,
            symbols: symbols,
            interner: interner
        )
        // fun ByteArray.toKString(startIndex: Int = 0, endIndex: Int = size, throwOnInvalidSequence: Boolean = false): String
        let byteArrayToKStringReceiverType = syntheticClassType(
            packagePath: ["kotlin"],
            name: "ByteArray",
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticNativeTopLevelFunction(
            named: "toKString",
            packageFQName: cinteropPkg,
            receiverType: byteArrayToKStringReceiverType,
            parameters: [
                (name: "startIndex", type: types.intType),
                (name: "endIndex", type: types.intType),
                (name: "throwOnInvalidSequence", type: types.booleanType),
            ],
            returnType: types.stringType,
            defaultValues: [true, true, true],
            symbols: symbols,
            interner: interner
        )
        let cOpaquePointerUnderlyingType = types.make(.classType(ClassType(
            classSymbol: cPointerSymbol,
            args: [.out(cPointedType)],
            nullability: .nonNull
        )))
        registerSyntheticCInteropTypeAlias(
            named: "COpaquePointer",
            in: cinteropPkg,
            packageSymbol: cinteropPkgSymbol,
            underlyingType: cOpaquePointerUnderlyingType,
            symbols: symbols,
            interner: interner
        )
        let pinnedFQName = cinteropPkg + [interner.intern("Pinned")]
        let pinnedTypeParameterName = interner.intern("T")
        let pinnedTypeParameterFQName = pinnedFQName + [pinnedTypeParameterName]
        let pinnedTypeParameterSymbol: SymbolID = if let existing = symbols.lookup(fqName: pinnedTypeParameterFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: pinnedTypeParameterName,
                fqName: pinnedTypeParameterFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        symbols.setTypeParameterUpperBounds([types.anyType], for: pinnedTypeParameterSymbol)
        let pinnedTypeParameterType = types.make(.typeParam(TypeParamType(
            symbol: pinnedTypeParameterSymbol,
            nullability: .nonNull
        )))
        let pinnedType = types.make(.classType(ClassType(
            classSymbol: pinnedSymbol,
            args: [.invariant(pinnedTypeParameterType)],
            nullability: .nonNull
        )))
        symbols.setPropertyType(pinnedType, for: pinnedSymbol)
        types.setNominalTypeParameterSymbols([pinnedTypeParameterSymbol], for: pinnedSymbol)
        types.setNominalTypeParameterVariances([.invariant], for: pinnedSymbol)

        let pinName = interner.intern("pin")
        let pinFQName = cinteropPkg + [pinName]
        let pinTypeParameterName = interner.intern("T")
        let pinTypeParameterFQName = pinFQName + [pinTypeParameterName]
        let pinTypeParameterSymbol: SymbolID = if let existing = symbols.lookup(fqName: pinTypeParameterFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: pinTypeParameterName,
                fqName: pinTypeParameterFQName,
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
        }
        symbols.setTypeParameterUpperBounds([types.anyType], for: pinTypeParameterSymbol)
        let pinTypeParameterType = types.make(.typeParam(TypeParamType(
            symbol: pinTypeParameterSymbol,
            nullability: .nonNull
        )))
        let pinReturnType = types.make(.classType(ClassType(
            classSymbol: pinnedSymbol,
            args: [.invariant(pinTypeParameterType)],
            nullability: .nonNull
        )))
        registerSyntheticNativeTopLevelFunction(
            named: "pin",
            packageFQName: cinteropPkg,
            receiverType: pinTypeParameterType,
            parameters: [],
            returnType: pinReturnType,
            typeParameterSymbols: [pinTypeParameterSymbol],
            typeParameterUpperBoundsList: [[types.anyType]],
            flags: [.synthetic, .inlineFunction],
            symbols: symbols,
            interner: interner
        )

        let stableRefFQName = cinteropPkg + [interner.intern("StableRef")]
        let stableRefTypeParameterName = interner.intern("T")
        let stableRefTypeParameterFQName = stableRefFQName + [stableRefTypeParameterName]
        let stableRefTypeParameterSymbol: SymbolID = if let existing = symbols.lookup(fqName: stableRefTypeParameterFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: stableRefTypeParameterName,
                fqName: stableRefTypeParameterFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        symbols.setTypeParameterUpperBounds([types.anyType], for: stableRefTypeParameterSymbol)
        let stableRefTypeParameterType = types.make(.typeParam(TypeParamType(
            symbol: stableRefTypeParameterSymbol,
            nullability: .nonNull
        )))
        let stableRefType = types.make(.classType(ClassType(
            classSymbol: stableRefSymbol,
            args: [.out(stableRefTypeParameterType)],
            nullability: .nonNull
        )))
        symbols.setPropertyType(stableRefType, for: stableRefSymbol)
        symbols.insertFlags([.valueType], for: stableRefSymbol)
        symbols.setValueClassUnderlyingType(cOpaquePointerUnderlyingType, for: stableRefSymbol)
        types.setNominalTypeParameterSymbols([stableRefTypeParameterSymbol], for: stableRefSymbol)
        types.setNominalTypeParameterVariances([.out], for: stableRefSymbol)
        registerSyntheticNativeBitSetConstructor(
            ownerSymbol: stableRefSymbol,
            ownerType: stableRefType,
            parameters: [(name: "source", type: cOpaquePointerUnderlyingType)],
            defaultValues: [false],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeBitSetMemberFunction(
            named: "asCPointer",
            ownerSymbol: stableRefSymbol,
            receiverType: stableRefType,
            parameters: [],
            returnType: cOpaquePointerUnderlyingType,
            typeParameterSymbols: [stableRefTypeParameterSymbol],
            typeParameterUpperBoundsList: [[types.anyType]],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeBitSetMemberFunction(
            named: "dispose",
            ownerSymbol: stableRefSymbol,
            receiverType: stableRefType,
            parameters: [],
            returnType: types.unitType,
            typeParameterSymbols: [stableRefTypeParameterSymbol],
            typeParameterUpperBoundsList: [[types.anyType]],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeBitSetMemberFunction(
            named: "get",
            ownerSymbol: stableRefSymbol,
            receiverType: stableRefType,
            parameters: [],
            returnType: stableRefTypeParameterType,
            typeParameterSymbols: [stableRefTypeParameterSymbol],
            typeParameterUpperBoundsList: [[types.anyType]],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )
        let stableRefCompanionName = interner.intern("Companion")
        let stableRefCompanionFQName = stableRefFQName + [stableRefCompanionName]
        let stableRefCompanionSymbol: SymbolID
        if let existingCompanion = symbols.companionObjectSymbol(for: stableRefSymbol) {
            stableRefCompanionSymbol = existingCompanion
        } else if let existing = symbols.lookup(fqName: stableRefCompanionFQName),
                  symbols.symbol(existing)?.kind == .object
        {
            stableRefCompanionSymbol = existing
        } else {
            stableRefCompanionSymbol = symbols.define(
                kind: .object,
                name: stableRefCompanionName,
                fqName: stableRefCompanionFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .static]
            )
        }
        symbols.setParentSymbol(stableRefSymbol, for: stableRefCompanionSymbol)
        symbols.setCompanionObjectSymbol(stableRefCompanionSymbol, for: stableRefSymbol)
        let stableRefCompanionType = types.make(.classType(ClassType(
            classSymbol: stableRefCompanionSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(stableRefCompanionType, for: stableRefCompanionSymbol)
        let createTypeParameterName = interner.intern("T")
        let createFunctionName = interner.intern("create")
        let createTypeParameterFQName = stableRefCompanionFQName + [createFunctionName, createTypeParameterName]
        let createTypeParameterSymbol: SymbolID = if let existing = symbols.lookup(fqName: createTypeParameterFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: createTypeParameterName,
                fqName: createTypeParameterFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        symbols.setTypeParameterUpperBounds([types.anyType], for: createTypeParameterSymbol)
        let createTypeParameterType = types.make(.typeParam(TypeParamType(
            symbol: createTypeParameterSymbol,
            nullability: .nonNull
        )))
        let createReturnType = types.make(.classType(ClassType(
            classSymbol: stableRefSymbol,
            args: [.out(createTypeParameterType)],
            nullability: .nonNull
        )))
        registerSyntheticNativeBitSetMemberFunction(
            named: "create",
            ownerSymbol: stableRefCompanionSymbol,
            receiverType: stableRefCompanionType,
            parameters: [(name: "any", type: createTypeParameterType)],
            returnType: createReturnType,
            typeParameterSymbols: [createTypeParameterSymbol],
            typeParameterUpperBoundsList: [[types.anyType]],
            flags: [.synthetic, .static],
            symbols: symbols,
            interner: interner
        )
        let asStableRefName = interner.intern("asStableRef")
        let asStableRefFQName = cinteropPkg + [asStableRefName]
        let asStableRefTypeParameterName = interner.intern("T")
        let asStableRefTypeParameterFQName = asStableRefFQName + [asStableRefTypeParameterName]
        let asStableRefTypeParameterSymbol: SymbolID = if let existing = symbols.lookup(
            fqName: asStableRefTypeParameterFQName
        ) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: asStableRefTypeParameterName,
                fqName: asStableRefTypeParameterFQName,
                declSite: nil,
                visibility: .private,
                flags: [.synthetic, .reifiedTypeParameter]
            )
        }
        symbols.insertFlags([.synthetic, .reifiedTypeParameter], for: asStableRefTypeParameterSymbol)
        symbols.setTypeParameterUpperBounds([types.anyType], for: asStableRefTypeParameterSymbol)
        let asStableRefTypeParameterType = types.make(.typeParam(TypeParamType(
            symbol: asStableRefTypeParameterSymbol,
            nullability: .nonNull
        )))
        let cPointerStarType = types.make(.classType(ClassType(
            classSymbol: cPointerSymbol,
            args: [.star],
            nullability: .nonNull
        )))
        let asStableRefReturnType = types.make(.classType(ClassType(
            classSymbol: stableRefSymbol,
            args: [.out(asStableRefTypeParameterType)],
            nullability: .nonNull
        )))
        registerSyntheticNativeTopLevelFunction(
            named: "asStableRef",
            packageFQName: cinteropPkg,
            receiverType: cPointerStarType,
            parameters: [],
            returnType: asStableRefReturnType,
            typeParameterSymbols: [asStableRefTypeParameterSymbol],
            typeParameterUpperBoundsList: [[types.anyType]],
            reifiedTypeParameterIndices: [0],
            flags: [.synthetic, .inlineFunction],
            symbols: symbols,
            interner: interner
        )
        let cOpaquePointerVarUnderlyingType = types.make(.classType(ClassType(
            classSymbol: cPointerVarOfSymbol,
            args: [.invariant(cOpaquePointerUnderlyingType)],
            nullability: .nonNull
        )))
        registerSyntheticCInteropTypeAlias(
            named: "COpaquePointerVar",
            in: cinteropPkg,
            packageSymbol: cinteropPkgSymbol,
            underlyingType: cOpaquePointerVarUnderlyingType,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCInteropSingleTypeParameterTypeAlias(
            named: "CArrayPointer",
            in: cinteropPkg,
            packageSymbol: cinteropPkgSymbol,
            parameterName: "T",
            targetSymbol: cPointerSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticCInteropSingleTypeParameterTypeAlias(
            named: "CArrayPointerVar",
            in: cinteropPkg,
            packageSymbol: cinteropPkgSymbol,
            parameterName: "T",
            targetSymbol: cPointerVarSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )

        for primitiveVar in [
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
        if let uShortVarSymbol = symbols.lookup(fqName: cinteropPkg + [interner.intern("UShortVar")]) {
            let uShortVarType = types.make(.classType(ClassType(
                classSymbol: uShortVarSymbol,
                args: [],
                nullability: .nonNull
            )))
            let wcstrReturnType = types.make(.classType(ClassType(
                classSymbol: cValuesSymbol,
                args: [.invariant(uShortVarType)],
                nullability: .nonNull
            )))
            registerSyntheticNativeExtensionProperty(
                named: "wcstr",
                packageFQName: cinteropPkg,
                packageSymbol: cinteropPkgSymbol,
                receiverType: types.stringType,
                propertyType: wcstrReturnType,
                symbols: symbols,
                interner: interner
            )
        }
        // fun UIntArray.toCValues(): CValues<UIntVar>
        if let uIntVarSymbol = symbols.lookup(fqName: cinteropPkg + [interner.intern("UIntVar")]) {
            let uIntVarType = types.make(.classType(ClassType(
                classSymbol: uIntVarSymbol,
                args: [],
                nullability: .nonNull
            )))
            let uIntArrayReceiverType = syntheticClassType(
                packagePath: ["kotlin"],
                name: "UIntArray",
                symbols: symbols,
                types: types,
                interner: interner
            )
            let uIntArrayToCValuesReturnType = types.make(.classType(ClassType(
                classSymbol: cValuesSymbol,
                args: [.invariant(uIntVarType)],
                nullability: .nonNull
            )))
            registerSyntheticNativeTopLevelFunction(
                named: "toCValues",
                packageFQName: cinteropPkg,
                receiverType: uIntArrayReceiverType,
                parameters: [],
                returnType: uIntArrayToCValuesReturnType,
                symbols: symbols,
                interner: interner
            )
        }

        // fun LongArray.toCValues(): CValues<LongVar>
        if let longVarSymbol = symbols.lookup(fqName: cinteropPkg + [interner.intern("LongVar")]) {
            let longVarType = types.make(.classType(ClassType(
                classSymbol: longVarSymbol,
                args: [],
                nullability: .nonNull
            )))
            let longArrayReceiverType = syntheticClassType(
                packagePath: ["kotlin"],
                name: "LongArray",
                symbols: symbols,
                types: types,
                interner: interner
            )
            let longArrayToCValuesReturnType = types.make(.classType(ClassType(
                classSymbol: cValuesSymbol,
                args: [.invariant(longVarType)],
                nullability: .nonNull
            )))
            registerSyntheticNativeTopLevelFunction(
                named: "toCValues",
                packageFQName: cinteropPkg,
                receiverType: longArrayReceiverType,
                parameters: [],
                returnType: longArrayToCValuesReturnType,
                symbols: symbols,
                interner: interner
            )
        }
        // fun FloatArray.toCValues(): CValues<FloatVar>
        if let floatVarSymbol = symbols.lookup(fqName: cinteropPkg + [interner.intern("FloatVar")]) {
            let floatVarType = types.make(.classType(ClassType(
                classSymbol: floatVarSymbol,
                args: [],
                nullability: .nonNull
            )))
            let floatArrayReceiverType = syntheticClassType(
                packagePath: ["kotlin"],
                name: "FloatArray",
                symbols: symbols,
                types: types,
                interner: interner
            )
            let floatArrayToCValuesReturnType = types.make(.classType(ClassType(
                classSymbol: cValuesSymbol,
                args: [.invariant(floatVarType)],
                nullability: .nonNull
            )))
            registerSyntheticNativeTopLevelFunction(
                named: "toCValues",
                packageFQName: cinteropPkg,
                receiverType: floatArrayReceiverType,
                parameters: [],
                returnType: floatArrayToCValuesReturnType,
                symbols: symbols,
                interner: interner
            )
        }
        // fun DoubleArray.toCValues(): CValues<DoubleVar>
        if let doubleVarSymbol = symbols.lookup(fqName: cinteropPkg + [interner.intern("DoubleVar")]) {
            let doubleVarType = types.make(.classType(ClassType(
                classSymbol: doubleVarSymbol,
                args: [],
                nullability: .nonNull
            )))
            let doubleArrayReceiverType = syntheticClassType(
                packagePath: ["kotlin"],
                name: "DoubleArray",
                symbols: symbols,
                types: types,
                interner: interner
            )
            let doubleArrayToCValuesReturnType = types.make(.classType(ClassType(
                classSymbol: cValuesSymbol,
                args: [.invariant(doubleVarType)],
                nullability: .nonNull
            )))
            registerSyntheticNativeTopLevelFunction(
                named: "toCValues",
                packageFQName: cinteropPkg,
                receiverType: doubleArrayReceiverType,
                parameters: [],
                returnType: doubleArrayToCValuesReturnType,
                symbols: symbols,
                interner: interner
            )
        }

        // fun ULongArray.toCValues(): CValues<ULongVar>
        if let uLongVarSymbol = symbols.lookup(fqName: cinteropPkg + [interner.intern("ULongVar")]) {
            let uLongVarType = types.make(.classType(ClassType(
                classSymbol: uLongVarSymbol,
                args: [],
                nullability: .nonNull
            )))
            let uLongArrayReceiverType = syntheticClassType(
                packagePath: ["kotlin"],
                name: "ULongArray",
                symbols: symbols,
                types: types,
                interner: interner
            )
            let uLongArrayToCValuesReturnType = types.make(.classType(ClassType(
                classSymbol: cValuesSymbol,
                args: [.invariant(uLongVarType)],
                nullability: .nonNull
            )))
            registerSyntheticNativeTopLevelFunction(
                named: "toCValues",
                packageFQName: cinteropPkg,
                receiverType: uLongArrayReceiverType,
                parameters: [],
                returnType: uLongArrayToCValuesReturnType,
                symbols: symbols,
                interner: interner
            )
        }
        // fun CPointer<IntVar>.toKStringFromUtf32(): String
        if let intVarSymbolForUtf32 = symbols.lookup(fqName: cinteropPkg + [interner.intern("IntVar")]) {
            let intVarTypeForUtf32 = types.make(.classType(ClassType(
                classSymbol: intVarSymbolForUtf32,
                args: [],
                nullability: .nonNull
            )))
            let toKStringFromUtf32ReceiverType = types.make(.classType(ClassType(
                classSymbol: cPointerSymbol,
                args: [.invariant(intVarTypeForUtf32)],
                nullability: .nonNull
            )))
            registerSyntheticNativeTopLevelFunction(
                named: "toKStringFromUtf32",
                packageFQName: cinteropPkg,
                receiverType: toKStringFromUtf32ReceiverType,
                parameters: [],
                returnType: types.stringType,
                symbols: symbols,
                interner: interner
            )
        }

        // fun CPointer<ShortVar>.toKString(): String
        if let shortVarSymbolForToKString = symbols.lookup(fqName: cinteropPkg + [interner.intern("ShortVar")]) {
            let shortVarTypeForToKString = types.make(.classType(ClassType(
                classSymbol: shortVarSymbolForToKString,
                args: [],
                nullability: .nonNull
            )))
            let toKStringShortVarReceiverType = types.make(.classType(ClassType(
                classSymbol: cPointerSymbol,
                args: [.invariant(shortVarTypeForToKString)],
                nullability: .nonNull
            )))
            registerSyntheticNativeTopLevelFunction(
                named: "toKString",
                packageFQName: cinteropPkg,
                receiverType: toKStringShortVarReceiverType,
                parameters: [],
                returnType: types.stringType,
                symbols: symbols,
                interner: interner
            )
        }

        // fun CPointer<UShortVar>.toKStringFromUtf16(): String
        if let uShortVarSymbolForUtf16 = symbols.lookup(fqName: cinteropPkg + [interner.intern("UShortVar")]) {
            let uShortVarTypeForUtf16 = types.make(.classType(ClassType(
                classSymbol: uShortVarSymbolForUtf16,
                args: [],
                nullability: .nonNull
            )))
            let toKStringFromUtf16UShortReceiverType = types.make(.classType(ClassType(
                classSymbol: cPointerSymbol,
                args: [.invariant(uShortVarTypeForUtf16)],
                nullability: .nonNull
            )))
            registerSyntheticNativeTopLevelFunction(
                named: "toKStringFromUtf16",
                packageFQName: cinteropPkg,
                receiverType: toKStringFromUtf16UShortReceiverType,
                parameters: [],
                returnType: types.stringType,
                symbols: symbols,
                interner: interner
            )
        }
        // fun UByteArray.toCValues(): CValues<UByteVar>
        if let uByteVarSymbol = symbols.lookup(fqName: cinteropPkg + [interner.intern("UByteVar")]) {
            let uByteVarType = types.make(.classType(ClassType(
                classSymbol: uByteVarSymbol,
                args: [],
                nullability: .nonNull
            )))
            let uByteArrayReceiverType = syntheticClassType(
                packagePath: ["kotlin"],
                name: "UByteArray",
                symbols: symbols,
                types: types,
                interner: interner
            )
            let uByteArrayToCValuesReturnType = types.make(.classType(ClassType(
                classSymbol: cValuesSymbol,
                args: [.invariant(uByteVarType)],
                nullability: .nonNull
            )))
            registerSyntheticNativeTopLevelFunction(
                named: "toCValues",
                packageFQName: cinteropPkg,
                receiverType: uByteArrayReceiverType,
                parameters: [],
                returnType: uByteArrayToCValuesReturnType,
                symbols: symbols,
                interner: interner
            )
        }

        // fun ShortArray.toCValues(): CValues<ShortVar>
        if let shortVarSymbol = symbols.lookup(fqName: cinteropPkg + [interner.intern("ShortVar")]) {
            let shortVarType = types.make(.classType(ClassType(
                classSymbol: shortVarSymbol,
                args: [],
                nullability: .nonNull
            )))
            let shortArrayReceiverType = syntheticClassType(
                packagePath: ["kotlin"],
                name: "ShortArray",
                symbols: symbols,
                types: types,
                interner: interner
            )
            let shortArrayToCValuesReturnType = types.make(.classType(ClassType(
                classSymbol: cValuesSymbol,
                args: [.invariant(shortVarType)],
                nullability: .nonNull
            )))
            registerSyntheticNativeTopLevelFunction(
                named: "toCValues",
                packageFQName: cinteropPkg,
                receiverType: shortArrayReceiverType,
                parameters: [],
                returnType: shortArrayToCValuesReturnType,
                symbols: symbols,
                interner: interner
            )
        }
        // fun UShortArray.toCValues(): CValues<UShortVar>
        if let uShortVarSymbol = symbols.lookup(fqName: cinteropPkg + [interner.intern("UShortVar")]) {
            let uShortVarType = types.make(.classType(ClassType(
                classSymbol: uShortVarSymbol,
                args: [],
                nullability: .nonNull
            )))
            let uShortArrayReceiverType = syntheticClassType(
                packagePath: ["kotlin"],
                name: "UShortArray",
                symbols: symbols,
                types: types,
                interner: interner
            )
            let uShortArrayToCValuesReturnType = types.make(.classType(ClassType(
                classSymbol: cValuesSymbol,
                args: [.invariant(uShortVarType)],
                nullability: .nonNull
            )))
            registerSyntheticNativeTopLevelFunction(
                named: "toCValues",
                packageFQName: cinteropPkg,
                receiverType: uShortArrayReceiverType,
                parameters: [],
                returnType: uShortArrayToCValuesReturnType,
                symbols: symbols,
                interner: interner
            )
        }
        registerSyntheticCInteropVector128Stubs(
            cinteropPkg: cinteropPkg,
            cinteropPkgSymbol: cinteropPkgSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func registerSyntheticCInteropVector128Stubs(
        cinteropPkg: [InternedString],
        cinteropPkgSymbol: SymbolID?,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let vector128Symbol = ensureClassSymbol(
            named: "Vector128",
            in: cinteropPkg,
            symbols: symbols,
            interner: interner
        )
        if let cinteropPkgSymbol {
            symbols.setParentSymbol(cinteropPkgSymbol, for: vector128Symbol)
        }
        let vector128Type = types.make(.classType(ClassType(
            classSymbol: vector128Symbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(vector128Type, for: vector128Symbol)
        appendMetadataAnnotations(
            [MetadataAnnotationRecord(annotationFQName: "kotlinx.cinterop.ExperimentalForeignApi")],
            to: vector128Symbol,
            symbols: symbols
        )

        let elementAccessors: [(name: String, returnType: TypeID)] = [
            ("getByteAt", types.intType),
            ("getIntAt", types.intType),
            ("getLongAt", types.longType),
            ("getFloatAt", types.floatType),
            ("getDoubleAt", types.doubleType),
            ("getUByteAt", types.ubyteType),
            ("getUIntAt", types.uintType),
            ("getULongAt", types.ulongType),
        ]
        for accessor in elementAccessors {
            registerSyntheticNativeBitSetMemberFunction(
                named: accessor.name,
                ownerSymbol: vector128Symbol,
                receiverType: vector128Type,
                parameters: [(name: "index", type: types.intType)],
                returnType: accessor.returnType,
                symbols: symbols,
                interner: interner
            )
        }
        registerSyntheticNativeBitSetMemberFunction(
            named: "equals",
            ownerSymbol: vector128Symbol,
            receiverType: vector128Type,
            parameters: [(name: "other", type: types.makeNullable(types.anyType))],
            returnType: types.booleanType,
            flags: [.synthetic, .operatorFunction, .overrideMember],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeBitSetMemberFunction(
            named: "hashCode",
            ownerSymbol: vector128Symbol,
            receiverType: vector128Type,
            parameters: [],
            returnType: types.intType,
            flags: [.synthetic, .overrideMember],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeBitSetMemberFunction(
            named: "toString",
            ownerSymbol: vector128Symbol,
            receiverType: vector128Type,
            parameters: [],
            returnType: types.stringType,
            flags: [.synthetic, .overrideMember],
            symbols: symbols,
            interner: interner
        )

        let experimentalForeignApiAnnotations = [
            MetadataAnnotationRecord(annotationFQName: "kotlinx.cinterop.ExperimentalForeignApi"),
        ]
        for parameterType in [types.floatType, types.intType] {
            registerSyntheticNativeTopLevelFunction(
                named: "vectorOf",
                packageFQName: cinteropPkg,
                receiverType: nil,
                parameters: [
                    (name: "f0", type: parameterType),
                    (name: "f1", type: parameterType),
                    (name: "f2", type: parameterType),
                    (name: "f3", type: parameterType),
                ],
                returnType: vector128Type,
                annotations: experimentalForeignApiAnnotations,
                symbols: symbols,
                interner: interner
            )
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

    private func appendMetadataAnnotations(
        _ records: [MetadataAnnotationRecord],
        to symbol: SymbolID,
        symbols: SymbolTable
    ) {
        var annotations = symbols.annotations(for: symbol)
        var didAppend = false
        for record in records where !annotations.contains(record) {
            annotations.append(record)
            didAppend = true
        }
        if didAppend {
            symbols.setAnnotations(annotations, for: symbol)
        }
    }

    private func syntheticClassType(
        packagePath: [String],
        name: String,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> TypeID {
        let packageFQName = packagePath.map { interner.intern($0) }
        let classFQName = packageFQName + [interner.intern(name)]
        guard let symbol = symbols.lookup(fqName: classFQName) else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: symbol,
            args: [],
            nullability: .nonNull
        )))
    }

    private func syntheticListType(
        elementType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> TypeID {
        let collectionsPkg = ensurePackage(
            path: ["kotlin", "collections"],
            symbols: symbols,
            interner: interner
        )
        let listFQName = collectionsPkg + [interner.intern("List")]
        guard let listSymbol = symbols.lookup(fqName: listFQName) else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: listSymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))
    }

    private func syntheticThrowableType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> TypeID {
        let kotlinPkg = ensurePackage(
            path: ["kotlin"],
            symbols: symbols,
            interner: interner
        )
        let throwableName = interner.intern("Throwable")
        let throwableFQName = kotlinPkg + [throwableName]
        let throwableSymbol: SymbolID
        if let existing = symbols.lookup(fqName: throwableFQName) {
            throwableSymbol = existing
        } else {
            throwableSymbol = symbols.define(
                kind: .class,
                name: throwableName,
                fqName: throwableFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            if let kotlinPkgSymbol = symbols.lookup(fqName: kotlinPkg) {
                symbols.setParentSymbol(kotlinPkgSymbol, for: throwableSymbol)
            }
        }
        return types.make(.classType(ClassType(
            classSymbol: throwableSymbol,
            args: [],
            nullability: .nonNull
        )))
    }

    private func cPointerType(
        pointedTypeName: String,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> TypeID {
        let cinteropPkg = ["kotlinx", "cinterop"].map { interner.intern($0) }
        guard let cPointerSymbol = symbols.lookup(fqName: cinteropPkg + [interner.intern("CPointer")]),
              let pointedSymbol = symbols.lookup(fqName: cinteropPkg + [interner.intern(pointedTypeName)])
        else {
            return types.anyType
        }

        let pointedType = types.make(.classType(ClassType(
            classSymbol: pointedSymbol,
            args: [],
            nullability: .nonNull
        )))
        return types.make(.classType(ClassType(
            classSymbol: cPointerSymbol,
            args: [.invariant(pointedType)],
            nullability: .nonNull
        )))
    }

    private func registerSyntheticCInteropTypeAlias(
        named aliasName: String,
        in packageFQName: [InternedString],
        packageSymbol: SymbolID?,
        underlyingType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let aliasSymbol = ensureSyntheticCInteropTypeAliasSymbol(
            named: aliasName,
            in: packageFQName,
            packageSymbol: packageSymbol,
            symbols: symbols,
            interner: interner
        ) else {
            return
        }
        symbols.setTypeAliasUnderlyingType(underlyingType, for: aliasSymbol)
    }

    private func registerSyntheticCInteropSingleTypeParameterTypeAlias(
        named aliasName: String,
        in packageFQName: [InternedString],
        packageSymbol: SymbolID?,
        parameterName: String,
        targetSymbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        guard let aliasSymbol = ensureSyntheticCInteropTypeAliasSymbol(
            named: aliasName,
            in: packageFQName,
            packageSymbol: packageSymbol,
            symbols: symbols,
            interner: interner
        ) else {
            return
        }

        let aliasFQName = packageFQName + [interner.intern(aliasName)]
        let parameterInternedName = interner.intern(parameterName)
        let typeParameterFQName = aliasFQName + [parameterInternedName]
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
        symbols.setTypeAliasTypeParameters([typeParameterSymbol], for: aliasSymbol)

        let typeParameterType = types.make(.typeParam(TypeParamType(
            symbol: typeParameterSymbol,
            nullability: .nonNull
        )))
        let underlyingType = types.make(.classType(ClassType(
            classSymbol: targetSymbol,
            args: [.invariant(typeParameterType)],
            nullability: .nonNull
        )))
        symbols.setTypeAliasUnderlyingType(underlyingType, for: aliasSymbol)
    }

    private func registerSyntheticCPointerVarTypeAlias(
        aliasSymbol: SymbolID,
        aliasFQName: [InternedString],
        typeParameterUpperBound: TypeID,
        cPointerSymbol: SymbolID,
        cPointerVarOfSymbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let parameterInternedName = interner.intern("T")
        let typeParameterFQName = aliasFQName + [parameterInternedName]
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
        symbols.setParentSymbol(aliasSymbol, for: typeParameterSymbol)
        symbols.setTypeAliasTypeParameters([typeParameterSymbol], for: aliasSymbol)
        symbols.setTypeParameterUpperBounds([typeParameterUpperBound], for: typeParameterSymbol)

        let typeParameterType = types.make(.typeParam(TypeParamType(
            symbol: typeParameterSymbol,
            nullability: .nonNull
        )))
        let pointerType = types.make(.classType(ClassType(
            classSymbol: cPointerSymbol,
            args: [.invariant(typeParameterType)],
            nullability: .nonNull
        )))
        let underlyingType = types.make(.classType(ClassType(
            classSymbol: cPointerVarOfSymbol,
            args: [.invariant(pointerType)],
            nullability: .nonNull
        )))
        symbols.setTypeAliasUnderlyingType(underlyingType, for: aliasSymbol)
    }

    private func ensureSyntheticCInteropTypeAliasSymbol(
        named aliasName: String,
        in packageFQName: [InternedString],
        packageSymbol: SymbolID?,
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID? {
        let aliasInternedName = interner.intern(aliasName)
        let aliasFQName = packageFQName + [aliasInternedName]
        let aliasSymbol: SymbolID
        if let existing = symbols.lookup(fqName: aliasFQName),
           symbols.symbol(existing)?.kind == .typeAlias
        {
            aliasSymbol = existing
            symbols.insertFlags([.synthetic], for: existing)
        } else if symbols.lookup(fqName: aliasFQName) == nil {
            aliasSymbol = symbols.define(
                kind: .typeAlias,
                name: aliasInternedName,
                fqName: aliasFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        } else {
            return nil
        }

        if let packageSymbol {
            symbols.setParentSymbol(packageSymbol, for: aliasSymbol)
        }
        return aliasSymbol
    }

    private func deprecatedImmutableBlobAnnotations() -> [MetadataAnnotationRecord] {
        [
            MetadataAnnotationRecord(
                annotationFQName: "kotlin.Deprecated",
                arguments: ["message = \"ImmutableBlob is deprecated. Use ByteArray instead.\""]
            ),
            MetadataAnnotationRecord(
                annotationFQName: "kotlin.DeprecatedSinceKotlin",
                arguments: [
                    "warningSince = \"1.9\"",
                    "errorSince = \"2.1\"",
                ]
            ),
        ]
    }

    private func deprecatedImmutableBlobFactoryAnnotations() -> [MetadataAnnotationRecord] {
        [
            MetadataAnnotationRecord(
                annotationFQName: "kotlin.Deprecated",
                arguments: [
                    "message = \"ImmutableBlob is deprecated. Use ByteArray instead.\"",
                    "replaceWith = ReplaceWith(\"byteArrayOf(*elements)\")",
                ]
            ),
            MetadataAnnotationRecord(
                annotationFQName: "kotlin.DeprecatedSinceKotlin",
                arguments: [
                    "warningSince = \"1.9\"",
                    "errorSince = \"2.1\"",
                ]
            ),
        ]
    }

    private func deprecatedImmutableBlobPointerAnnotations() -> [MetadataAnnotationRecord] {
        [
            MetadataAnnotationRecord(
                annotationFQName: "kotlin.Deprecated",
                arguments: [
                    "message = \"ImmutableBlob is deprecated. Use ByteArray instead. To get a stable C pointer to a `ByteArray`, pin it first.\"",
                ]
            ),
            MetadataAnnotationRecord(
                annotationFQName: "kotlin.DeprecatedSinceKotlin",
                arguments: [
                    "warningSince = \"1.9\"",
                    "errorSince = \"2.1\"",
                ]
            ),
        ]
    }

    private func deprecatedNativeVector128TypeAliasAnnotations() -> [MetadataAnnotationRecord] {
        [
            MetadataAnnotationRecord(
                annotationFQName: "kotlin.Deprecated",
                arguments: [
                    "message = \"Use kotlinx.cinterop.Vector128 instead.\"",
                    "replaceWith = ReplaceWith(\"kotlinx.cinterop.Vector128\")",
                ]
            ),
            MetadataAnnotationRecord(
                annotationFQName: "kotlin.DeprecatedSinceKotlin",
                arguments: [
                    "warningSince = \"1.9\"",
                    "errorSince = \"2.1\"",
                ]
            ),
            MetadataAnnotationRecord(annotationFQName: "kotlinx.cinterop.ExperimentalForeignApi"),
        ]
    }

    private func deprecatedCEnumAnnotations() -> [MetadataAnnotationRecord] {
        [
            MetadataAnnotationRecord(
                annotationFQName: "kotlin.Deprecated",
                arguments: ["message = \"Will be removed.\""]
            ),
        ]
    }

    private func deprecatedNativeVectorOfAnnotations() -> [MetadataAnnotationRecord] {
        [
            MetadataAnnotationRecord(
                annotationFQName: "kotlin.Deprecated",
                arguments: [
                    "message = \"Use kotlinx.cinterop.vectorOf instead.\"",
                    "replaceWith = ReplaceWith(\"kotlinx.cinterop.vectorOf(f0, f1, f2, f3)\")",
                ]
            ),
            MetadataAnnotationRecord(
                annotationFQName: "kotlin.DeprecatedSinceKotlin",
                arguments: [
                    "warningSince = \"1.9\"",
                    "errorSince = \"2.1\"",
                ]
            ),
            MetadataAnnotationRecord(annotationFQName: "kotlinx.cinterop.ExperimentalForeignApi"),
        ]
    }

    private func experimentalNativeApiAnnotations() -> [MetadataAnnotationRecord] {
        [MetadataAnnotationRecord(annotationFQName: "kotlin.experimental.ExperimentalNativeApi")]
    }

    private func experimentalNativeUnsignedApiAnnotations() -> [MetadataAnnotationRecord] {
        experimentalNativeApiAnnotations()
            + [MetadataAnnotationRecord(annotationFQName: "kotlin.ExperimentalUnsignedTypes")]
    }

    private func appendDeprecatedImmutableBlobAnnotations(to symbol: SymbolID, symbols: SymbolTable) {
        var annotations = symbols.annotations(for: symbol)
        var didAppend = false
        for record in deprecatedImmutableBlobAnnotations() where !annotations.contains(record) {
            annotations.append(record)
            didAppend = true
        }
        if didAppend {
            symbols.setAnnotations(annotations, for: symbol)
        }
    }

    private func registerSyntheticCPointedReadFunction(
        named name: String,
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        typeParameterUpperBound: TypeID,
        returnClassSymbol: SymbolID,
        parameters: [(name: String, type: TypeID)],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let functionName = interner.intern(name)
        let functionFQName = ownerInfo.fqName + [functionName]
        let typeParameterName = interner.intern("T")
        let typeParameterFQName = functionFQName + [typeParameterName]
        let typeParameterSymbol: SymbolID = if let existing = symbols.lookup(fqName: typeParameterFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: typeParameterName,
                fqName: typeParameterFQName,
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
        }
        symbols.setTypeParameterUpperBounds([typeParameterUpperBound], for: typeParameterSymbol)

        let typeParameterType = types.make(.typeParam(TypeParamType(
            symbol: typeParameterSymbol,
            nullability: .nonNull
        )))
        let returnType = types.make(.classType(ClassType(
            classSymbol: returnClassSymbol,
            args: [.invariant(typeParameterType)],
            nullability: .nonNull
        )))

        registerSyntheticNativeBitSetMemberFunction(
            named: name,
            ownerSymbol: ownerSymbol,
            receiverType: ownerType,
            parameters: parameters,
            returnType: returnType,
            typeParameterSymbols: [typeParameterSymbol],
            typeParameterUpperBoundsList: [[typeParameterUpperBound]],
            symbols: symbols,
            interner: interner
        )
    }

    private func registerSyntheticNativeBitSetConstructor(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        parameters: [(name: String, type: TypeID)],
        defaultValues: [Bool],
        visibility: Visibility = .public,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let initName = interner.intern("<init>")
        let constructorFQName = ownerInfo.fqName + [initName]
        let parameterTypes = parameters.map(\.type)
        let existing = symbols.lookupAll(fqName: constructorFQName).contains { symbolID in
            guard symbols.symbol(symbolID)?.kind == .constructor,
                  let signature = symbols.functionSignature(for: symbolID)
            else {
                return false
            }
            return signature.parameterTypes == parameterTypes
        }
        guard !existing else {
            return
        }

        let constructorSymbol = symbols.define(
            kind: .constructor,
            name: initName,
            fqName: constructorFQName,
            declSite: nil,
            visibility: visibility,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: constructorSymbol)

        let valueParameterSymbols = parameters.map { parameter in
            let parameterName = interner.intern(parameter.name)
            let parameterSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: constructorFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(constructorSymbol, for: parameterSymbol)
            symbols.setPropertyType(parameter.type, for: parameterSymbol)
            return parameterSymbol
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: parameterTypes,
                returnType: ownerType,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: defaultValues,
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
            ),
            for: constructorSymbol
        )
    }

    private func registerSyntheticNativeBitSetProperty(
        named name: String,
        ownerSymbol: SymbolID,
        propertyType: TypeID,
        flags: SymbolFlags = [.synthetic],
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let propertyName = interner.intern(name)
        let propertyFQName = ownerInfo.fqName + [propertyName]
        if let existing = symbols.lookup(fqName: propertyFQName) {
            symbols.setPropertyType(propertyType, for: existing)
            symbols.insertFlags(flags, for: existing)
            return
        }

        let propertySymbol = symbols.define(
            kind: .property,
            name: propertyName,
            fqName: propertyFQName,
            declSite: nil,
            visibility: .public,
            flags: flags
        )
        symbols.setParentSymbol(ownerSymbol, for: propertySymbol)
        symbols.setPropertyType(propertyType, for: propertySymbol)
    }

    private func registerSyntheticNativeTopLevelProperty(
        named name: String,
        packageFQName: [InternedString],
        packageSymbol: SymbolID?,
        propertyType: TypeID,
        flags: SymbolFlags = [.synthetic],
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let propertyName = interner.intern(name)
        let propertyFQName = packageFQName + [propertyName]
        if let existing = symbols.lookupAll(fqName: propertyFQName).first(where: { symbolID in
            symbols.symbol(symbolID)?.kind == .property
        }) {
            symbols.setPropertyType(propertyType, for: existing)
            symbols.insertFlags(flags, for: existing)
            return
        }

        let propertySymbol = symbols.define(
            kind: .property,
            name: propertyName,
            fqName: propertyFQName,
            declSite: nil,
            visibility: .public,
            flags: flags
        )
        if let packageSymbol {
            symbols.setParentSymbol(packageSymbol, for: propertySymbol)
        }
        symbols.setPropertyType(propertyType, for: propertySymbol)
    }

    private func registerSyntheticNativeBitSetMemberFunction(
        named name: String,
        ownerSymbol: SymbolID,
        receiverType: TypeID,
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        defaultValues: [Bool]? = nil,
        typeParameterSymbols: [SymbolID] = [],
        typeParameterUpperBoundsList: [[TypeID]] = [],
        classTypeParameterCount: Int = 0,
        flags: SymbolFlags = [.synthetic],
        annotations: [MetadataAnnotationRecord] = [],
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let functionName = interner.intern(name)
        let functionFQName = ownerInfo.fqName + [functionName]
        let parameterTypes = parameters.map(\.type)
        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == receiverType
                && signature.parameterTypes == parameterTypes
                && signature.returnType == returnType
                && signature.typeParameterSymbols == typeParameterSymbols
                && signature.classTypeParameterCount == classTypeParameterCount
        }) {
            symbols.insertFlags(flags, for: existing)
            appendMetadataAnnotations(annotations, to: existing, symbols: symbols)
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
        symbols.setParentSymbol(ownerSymbol, for: functionSymbol)
        for typeParameterSymbol in typeParameterSymbols {
            symbols.setParentSymbol(functionSymbol, for: typeParameterSymbol)
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

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: parameterTypes,
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: defaultValues ?? Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count),
                typeParameterSymbols: typeParameterSymbols,
                typeParameterUpperBoundsList: typeParameterUpperBoundsList,
                classTypeParameterCount: classTypeParameterCount
            ),
            for: functionSymbol
        )
        appendMetadataAnnotations(annotations, to: functionSymbol, symbols: symbols)
    }

    private func registerSyntheticCPointerPointedProperty(
        cPointerSymbol: SymbolID,
        cPointedType: TypeID,
        packageFQName: [InternedString],
        packageSymbol: SymbolID?,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let propertyName = interner.intern("pointed")
        let propertyFQName = packageFQName + [propertyName]
        let typeParameterName = interner.intern("T")
        let typeParameterFQName = propertyFQName + [typeParameterName]
        let typeParameterSymbol: SymbolID = if let existing = symbols.lookup(fqName: typeParameterFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: typeParameterName,
                fqName: typeParameterFQName,
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
        }
        symbols.setTypeParameterUpperBounds([cPointedType], for: typeParameterSymbol)

        let typeParameterType = types.make(.typeParam(TypeParamType(
            symbol: typeParameterSymbol,
            nullability: .nonNull
        )))
        let receiverType = types.make(.classType(ClassType(
            classSymbol: cPointerSymbol,
            args: [.invariant(typeParameterType)],
            nullability: .nonNull
        )))
        let getterSignature = FunctionSignature(
            receiverType: receiverType,
            parameterTypes: [],
            returnType: typeParameterType,
            typeParameterSymbols: [typeParameterSymbol],
            typeParameterUpperBoundsList: [[cPointedType]],
            classTypeParameterCount: 0
        )

        if let existing = symbols.lookupAll(fqName: propertyFQName).first(where: { symbolID in
            symbols.symbol(symbolID)?.kind == .property
                && symbols.extensionPropertyReceiverType(for: symbolID) == receiverType
        }) {
            symbols.setParentSymbol(existing, for: typeParameterSymbol)
            symbols.setPropertyType(typeParameterType, for: existing)
            symbols.setExtensionPropertyReceiverType(receiverType, for: existing)
            if let getterSymbol = symbols.extensionPropertyGetterAccessor(for: existing) {
                symbols.setFunctionSignature(getterSignature, for: getterSymbol)
            }
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
        if let packageSymbol {
            symbols.setParentSymbol(packageSymbol, for: propertySymbol)
        }
        symbols.setParentSymbol(propertySymbol, for: typeParameterSymbol)
        symbols.setPropertyType(typeParameterType, for: propertySymbol)
        symbols.setExtensionPropertyReceiverType(receiverType, for: propertySymbol)

        let getterSymbol = symbols.define(
            kind: .function,
            name: interner.intern("get"),
            fqName: propertyFQName + [interner.intern("$get")],
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(propertySymbol, for: getterSymbol)
        symbols.setFunctionSignature(getterSignature, for: getterSymbol)
        symbols.setExtensionPropertyGetterAccessor(getterSymbol, for: propertySymbol)
        symbols.setAccessorOwnerProperty(propertySymbol, for: getterSymbol)
    }

    private func registerSyntheticNativeExtensionProperty(
        named name: String,
        packageFQName: [InternedString],
        packageSymbol: SymbolID?,
        receiverType: TypeID,
        propertyType: TypeID,
        flags: SymbolFlags = [.synthetic],
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let propertyName = interner.intern(name)
        let propertyFQName = packageFQName + [propertyName]
        let getterSignature = FunctionSignature(
            receiverType: receiverType,
            parameterTypes: [],
            returnType: propertyType
        )

        if let existing = symbols.lookupAll(fqName: propertyFQName).first(where: { symbolID in
            symbols.symbol(symbolID)?.kind == .property
                && symbols.extensionPropertyReceiverType(for: symbolID) == receiverType
        }) {
            symbols.insertFlags(flags, for: existing)
            symbols.setPropertyType(propertyType, for: existing)
            symbols.setExtensionPropertyReceiverType(receiverType, for: existing)
            if let getterSymbol = symbols.extensionPropertyGetterAccessor(for: existing) {
                symbols.setFunctionSignature(getterSignature, for: getterSymbol)
            }
            return
        }

        let propertySymbol = symbols.define(
            kind: .property,
            name: propertyName,
            fqName: propertyFQName,
            declSite: nil,
            visibility: .public,
            flags: flags
        )
        if let packageSymbol {
            symbols.setParentSymbol(packageSymbol, for: propertySymbol)
        }
        symbols.setPropertyType(propertyType, for: propertySymbol)
        symbols.setExtensionPropertyReceiverType(receiverType, for: propertySymbol)

        let getterSymbol = symbols.define(
            kind: .function,
            name: interner.intern("get"),
            fqName: propertyFQName + [interner.intern("$get")],
            declSite: nil,
            visibility: .public,
            flags: flags
        )
        symbols.setParentSymbol(propertySymbol, for: getterSymbol)
        symbols.setFunctionSignature(getterSignature, for: getterSymbol)
        symbols.setExtensionPropertyGetterAccessor(getterSymbol, for: propertySymbol)
        symbols.setAccessorOwnerProperty(propertySymbol, for: getterSymbol)
    }

    private func registerSyntheticNativePlacementAllocArrayFunction(
        lengthType: TypeID,
        typeParameterDiscriminator: String,
        cVariableType: TypeID,
        cPointerSymbol: SymbolID,
        nativePlacementType: TypeID,
        packageFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let functionName = interner.intern("allocArray")
        let functionFQName = packageFQName + [functionName]
        let typeParameterName = interner.intern("T")
        let typeParameterFQName = functionFQName + [interner.intern(typeParameterDiscriminator), typeParameterName]
        let typeParameterSymbol: SymbolID = if let existing = symbols.lookup(fqName: typeParameterFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: typeParameterName,
                fqName: typeParameterFQName,
                declSite: nil,
                visibility: .private,
                flags: [.synthetic, .reifiedTypeParameter]
            )
        }
        symbols.insertFlags([.synthetic, .reifiedTypeParameter], for: typeParameterSymbol)
        symbols.setTypeParameterUpperBounds([cVariableType], for: typeParameterSymbol)

        let typeParameterType = types.make(.typeParam(TypeParamType(
            symbol: typeParameterSymbol,
            nullability: .nonNull
        )))
        let cArrayPointerReturnType = types.make(.classType(ClassType(
            classSymbol: cPointerSymbol,
            args: [.invariant(typeParameterType)],
            nullability: .nonNull
        )))
        registerSyntheticNativeTopLevelFunction(
            named: "allocArray",
            packageFQName: packageFQName,
            receiverType: nativePlacementType,
            parameters: [(name: "length", type: lengthType)],
            returnType: cArrayPointerReturnType,
            typeParameterSymbols: [typeParameterSymbol],
            typeParameterUpperBoundsList: [[cVariableType]],
            reifiedTypeParameterIndices: [0],
            flags: [.synthetic, .inlineFunction],
            symbols: symbols,
            interner: interner
        )
    }

    private func registerSyntheticNativeTopLevelFunction(
        named name: String,
        packageFQName: [InternedString],
        receiverType: TypeID?,
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        defaultValues: [Bool]? = nil,
        varargs: [Bool]? = nil,
        typeParameterSymbols: [SymbolID] = [],
        typeParameterUpperBoundsList: [[TypeID]] = [],
        reifiedTypeParameterIndices: Set<Int> = [],
        annotations: [MetadataAnnotationRecord] = [],
        externalLinkName: String? = nil,
        flags: SymbolFlags = [.synthetic],
        canThrow: Bool = false,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        var functionFlags = flags
        if canThrow {
            functionFlags.insert(.throwingFunction)
        }
        let functionName = interner.intern(name)
        let functionFQName = packageFQName + [functionName]
        let parameterTypes = parameters.map(\.type)
        let functionSymbol: SymbolID
        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == receiverType
                && signature.parameterTypes == parameterTypes
                && signature.returnType == returnType
                && signature.typeParameterSymbols == typeParameterSymbols
                && signature.typeParameterUpperBoundsList == typeParameterUpperBoundsList
                && signature.reifiedTypeParameterIndices == reifiedTypeParameterIndices
        }) {
            functionSymbol = existing
            symbols.insertFlags(functionFlags, for: existing)
            for typeParameterSymbol in typeParameterSymbols {
                symbols.setParentSymbol(existing, for: typeParameterSymbol)
            }
            if let externalLinkName {
                symbols.setExternalLinkName(externalLinkName, for: existing)
            }
        } else {
            functionSymbol = symbols.define(
                kind: .function,
                name: functionName,
                fqName: functionFQName,
                declSite: nil,
                visibility: .public,
                flags: functionFlags
            )
            if let packageSymbol = symbols.lookup(fqName: packageFQName) {
                symbols.setParentSymbol(packageSymbol, for: functionSymbol)
            }
            for typeParameterSymbol in typeParameterSymbols {
                symbols.setParentSymbol(functionSymbol, for: typeParameterSymbol)
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

            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: parameterTypes,
                    returnType: returnType,
                    isSuspend: false,
                    canThrow: canThrow,
                    valueParameterSymbols: valueParameterSymbols,
                    valueParameterHasDefaultValues: defaultValues ?? Array(repeating: false, count: valueParameterSymbols.count),
                    valueParameterIsVararg: varargs ?? Array(repeating: false, count: valueParameterSymbols.count),
                    typeParameterSymbols: typeParameterSymbols,
                    reifiedTypeParameterIndices: reifiedTypeParameterIndices,
                    typeParameterUpperBoundsList: typeParameterUpperBoundsList
                ),
                for: functionSymbol
            )
            if let externalLinkName {
                symbols.setExternalLinkName(externalLinkName, for: functionSymbol)
            }
        }

        if !annotations.isEmpty {
            var existingAnnotations = symbols.annotations(for: functionSymbol)
            var didAppend = false
            for record in annotations where !existingAnnotations.contains(record) {
                existingAnnotations.append(record)
                didAppend = true
            }
            if didAppend {
                symbols.setAnnotations(existingAnnotations, for: functionSymbol)
            }
        }
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
