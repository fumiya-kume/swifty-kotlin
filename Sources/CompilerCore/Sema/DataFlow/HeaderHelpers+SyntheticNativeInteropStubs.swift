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
        let cPrimitiveVarSymbol = ensureClassSymbol(
            named: "CPrimitiveVar",
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
        let nativePtrSymbol = ensureClassSymbol(
            named: "NativePtr",
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
        let booleanVarOfSymbol = ensureClassSymbol(
            named: "BooleanVarOf",
            in: cinteropPkg,
            symbols: symbols,
            interner: interner
        )

        for symbol in [
            nativePointedSymbol,
            cPointedSymbol,
            cVariableSymbol,
            cPrimitiveVarSymbol,
            cOpaquePointerSymbol,
            nativePtrSymbol,
            nativePlacementSymbol,
            nativeFreeablePlacementSymbol,
            deferScopeSymbol,
            autofreeScopeSymbol,
            arenaBaseSymbol,
            arenaSymbol,
            memScopeSymbol,
            cValuesRefSymbol,
            cPointerSymbol,
            cPointerVarSymbol,
            booleanVarOfSymbol,
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

        let cVariableType = types.make(.classType(ClassType(
            classSymbol: cVariableSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(cVariableType, for: cVariableSymbol)
        symbols.setDirectSupertypes([cPointedSymbol], for: cVariableSymbol)
        types.setNominalDirectSupertypes([cPointedSymbol], for: cVariableSymbol)

        let cPrimitiveVarType = types.make(.classType(ClassType(
            classSymbol: cPrimitiveVarSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(cPrimitiveVarType, for: cPrimitiveVarSymbol)
        symbols.setDirectSupertypes([cVariableSymbol], for: cPrimitiveVarSymbol)
        types.setNominalDirectSupertypes([cVariableSymbol], for: cPrimitiveVarSymbol)

        let cOpaquePointerType = types.make(.classType(ClassType(
            classSymbol: cOpaquePointerSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(cOpaquePointerType, for: cOpaquePointerSymbol)
        symbols.setDirectSupertypes([nativePointedSymbol], for: cOpaquePointerSymbol)
        types.setNominalDirectSupertypes([nativePointedSymbol], for: cOpaquePointerSymbol)

        let nativePtrType = types.make(.classType(ClassType(
            classSymbol: nativePtrSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(nativePtrType, for: nativePtrSymbol)

        let nativePlacementType = types.make(.classType(ClassType(
            classSymbol: nativePlacementSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(nativePlacementType, for: nativePlacementSymbol)

        let nativeFreeablePlacementType = types.make(.classType(ClassType(
            classSymbol: nativeFreeablePlacementSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(nativeFreeablePlacementType, for: nativeFreeablePlacementSymbol)
        symbols.setDirectSupertypes([nativePlacementSymbol], for: nativeFreeablePlacementSymbol)
        types.setNominalDirectSupertypes([nativePlacementSymbol], for: nativeFreeablePlacementSymbol)

        let deferScopeType = types.make(.classType(ClassType(
            classSymbol: deferScopeSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(deferScopeType, for: deferScopeSymbol)
        symbols.insertFlags([.openType], for: deferScopeSymbol)

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
        let booleanVarType = types.make(.classType(ClassType(
            classSymbol: booleanVarOfSymbol,
            args: [.invariant(types.booleanType)],
            nullability: .nonNull
        )))
        let booleanVarAliasName = interner.intern("BooleanVar")
        let booleanVarAliasFQName = cinteropPkg + [booleanVarAliasName]
        let booleanVarAliasSymbol: SymbolID
        if let existing = symbols.lookup(fqName: booleanVarAliasFQName),
           symbols.symbol(existing)?.kind == .typeAlias
        {
            booleanVarAliasSymbol = existing
            symbols.insertFlags([.synthetic], for: existing)
        } else if symbols.lookup(fqName: booleanVarAliasFQName) == nil {
            booleanVarAliasSymbol = symbols.define(
                kind: .typeAlias,
                name: booleanVarAliasName,
                fqName: booleanVarAliasFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        } else {
            booleanVarAliasSymbol = .invalid
        }
        if booleanVarAliasSymbol.rawValue >= 0 {
            if let cinteropPkgSymbol {
                symbols.setParentSymbol(cinteropPkgSymbol, for: booleanVarAliasSymbol)
            }
            symbols.setTypeAliasUnderlyingType(booleanVarType, for: booleanVarAliasSymbol)
        }

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

    private func registerSyntheticNativeBitSetConstructor(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        parameters: [(name: String, type: TypeID)],
        defaultValues: [Bool],
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
            visibility: .public,
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

    private func registerSyntheticNativeBitSetMemberFunction(
        named name: String,
        ownerSymbol: SymbolID,
        receiverType: TypeID,
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        defaultValues: [Bool]? = nil,
        flags: SymbolFlags = [.synthetic],
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
        }) {
            symbols.insertFlags(flags, for: existing)
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
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
            ),
            for: functionSymbol
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
        }) {
            functionSymbol = existing
            symbols.insertFlags(functionFlags, for: existing)
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
                    valueParameterIsVararg: varargs ?? Array(repeating: false, count: valueParameterSymbols.count)
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
