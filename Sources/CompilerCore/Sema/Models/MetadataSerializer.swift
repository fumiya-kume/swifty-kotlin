import Foundation

package enum MetadataModality: String {
    case final
    case open
    case abstract
}

// MARK: - Shared Metadata Record

/// Unified metadata record used by both export (MetadataEncoder) and import (MetadataDecoder).
/// This is the single source of truth for what information survives the metadata round-trip.
package struct MetadataRecord {
    package let kind: SymbolKind
    let mangledName: String
    package let fqName: String
    package let arity: Int
    package let isSuspend: Bool
    package let isInline: Bool
    package let isOperator: Bool
    /// Whether the member overrides a supertype member (`override` keyword).
    package let isOverride: Bool
    let typeSignature: String?
    /// Upper-bound type signatures for callable type parameters, in declaration order.
    /// Empty entries preserve alignment when only a later type parameter is bounded.
    package let typeParameterUpperBoundsSignatures: [[String]]
    /// Per-parameter vararg flags for function/constructor signatures.
    package let valueParameterIsVararg: [Bool]
    /// Per-parameter flags indicating whether a function-type argument may
    /// contain a non-local return when the callable is inline-expanded.
    package let valueParameterAllowsNonLocalReturn: [Bool]
    /// Per-parameter default-value flags for function/constructor signatures.
    package let valueParameterHasDefaultValues: [Bool]
    /// Whether the function/constructor is declared `throws`.
    package let canThrow: Bool
    /// Resolved names of value parameters, in declaration order, used for
    /// named-argument resolution on imported functions.
    package let valueParameterNames: [String]
    /// Indices of reified type parameters, in declaration order, so that
    /// call sites append the correct runtime type-token arguments for inline
    /// functions imported from a precompiled stdlib artifact.
    package let reifiedTypeParameterIndices: Set<Int>
    /// Link name of the precompiled default-argument stub (e.g. `foo$default`).
    let defaultStubExternalLinkName: String?
    let externalLinkName: String?
    package let declaredFieldCount: Int?
    package let declaredInstanceSizeWords: Int?
    let declaredVtableSize: Int?
    let declaredItableSize: Int?
    package let superFQName: String?
    package let companionObjectFQName: String?
    let fieldOffsets: String?
    let vtableSlots: String?
    let itableSlots: String?
    /// Link name of the precompiled top-level object initializer (e.g. `__object_init_*`).
    let objectInitializerLinkName: String?
    /// Link name of the precompiled companion object initializer (e.g. `__companion_init_*`).
    let companionInitializerLinkName: String?
    /// Link name of the precompiled enum static initializer (e.g. `__enum_static_init_*`).
    package let enumStaticInitLinkName: String?

    // P5-74: data class flag
    package let isDataClass: Bool

    /// Whether a nominal declaration is explicitly open and may be subclassed.
    /// This must survive library metadata import; Kotlin classes are final by default.
    package let isOpenClass: Bool
    /// Declaration modality for classes and members. Final is omitted from the
    /// wire format so older artifacts remain compact and decode as final.
    package let modality: MetadataModality

    // P5-74: sealed class flag
    package let isSealedClass: Bool

    // STDLIB-SHARED-003: fun interface flag for SAM-constructor resolution
    package let isFunInterface: Bool

    // P5-86: annotation metadata
    let annotations: [MetadataAnnotationRecord]

    // P5-75: value class flag
    package let isValueClass: Bool

    // P5-75: value class underlying type signature (e.g. "I" for Int)
    let valueClassUnderlyingTypeSig: String?

    // P5-78: sealed subclass FQ names for cross-module exhaustiveness
    let sealedSubclassFQNames: [String]

    // MPP-001: expect/actual declaration flags
    let isExpect: Bool
    let isActual: Bool

    /// Receiver type signature for extension properties; nil for non-extension properties.
    let propertyReceiverTypeSignature: String?
    /// Link name of the precompiled getter accessor for extension properties.
    let propertyGetterExternalLinkName: String?
    /// ABI return type signature for functions whose compiled return type differs
    /// from the source-level signature (e.g. raw `Int` string handles).
    let abiReturnTypeSignature: String?
    /// ABI return type signature for extension property getters when it differs
    /// from the property's source type.
    let propertyGetterAbiReturnTypeSignature: String?
    /// True for `var` properties/fields.
    package let isMutable: Bool
    /// Self type signature of a generic nominal declaration, carrying its type
    /// parameters and their declared variance (e.g.
    /// `Lkotlinx.coroutines.flow.SharedFlow<O<T8150>>;`).
    let nominalTypeParametersSignature: String?
    /// Type signatures of the generic direct supertypes of a nominal
    /// declaration, with the child's type parameters substituted in (e.g.
    /// `Lkotlinx.coroutines.flow.SharedFlow<T8154>;`).
    let nominalSupertypeSignatures: [String]
    /// Encoded compile-time constant value of a `const val` property, so
    /// consumers can inline it instead of reading an uninitialized global slot
    /// (a precompiled library has no `main` to run top-level initializers).
    let constValueLiteral: String?
    /// Declaration-order type parameters of a nominal type, encoded as
    /// `<typeSignature>:<variance>` pairs (e.g. `T5023:i`), so consumers can
    /// restore the generic arity used by constructor/member resolution.
    let nominalTypeParameters: String?

    init(
        kind: SymbolKind,
        mangledName: String = "",
        fqName: String = "",
        arity: Int = 0,
        isSuspend: Bool = false,
        isInline: Bool = false,
        isOperator: Bool = false,
        isOverride: Bool = false,
        typeSignature: String? = nil,
        typeParameterUpperBoundsSignatures: [[String]] = [],
        valueParameterIsVararg: [Bool] = [],
        valueParameterAllowsNonLocalReturn: [Bool] = [],
        valueParameterHasDefaultValues: [Bool] = [],
        canThrow: Bool = false,
        valueParameterNames: [String] = [],
        reifiedTypeParameterIndices: Set<Int> = [],
        defaultStubExternalLinkName: String? = nil,
        externalLinkName: String? = nil,
        declaredFieldCount: Int? = nil,
        declaredInstanceSizeWords: Int? = nil,
        declaredVtableSize: Int? = nil,
        declaredItableSize: Int? = nil,
        superFQName: String? = nil,
        companionObjectFQName: String? = nil,
        fieldOffsets: String? = nil,
        vtableSlots: String? = nil,
        itableSlots: String? = nil,
        objectInitializerLinkName: String? = nil,
        companionInitializerLinkName: String? = nil,
        enumStaticInitLinkName: String? = nil,
        isDataClass: Bool = false,
        isOpenClass: Bool = false,
        modality: MetadataModality = .final,
        isSealedClass: Bool = false,
        isFunInterface: Bool = false,
        annotations: [MetadataAnnotationRecord] = [],
        isValueClass: Bool = false,
        valueClassUnderlyingTypeSig: String? = nil,
        sealedSubclassFQNames: [String] = [],
        isExpect: Bool = false,
        isActual: Bool = false,
        propertyReceiverTypeSignature: String? = nil,
        propertyGetterExternalLinkName: String? = nil,
        abiReturnTypeSignature: String? = nil,
        propertyGetterAbiReturnTypeSignature: String? = nil,
        isMutable: Bool = false,
        nominalTypeParametersSignature: String? = nil,
        nominalSupertypeSignatures: [String] = [],
        constValueLiteral: String? = nil,
        nominalTypeParameters: String? = nil
    ) {
        self.kind = kind
        self.mangledName = mangledName
        self.fqName = fqName
        self.arity = arity
        self.isSuspend = isSuspend
        self.isInline = isInline
        self.isOperator = isOperator
        self.isOverride = isOverride
        self.typeSignature = typeSignature
        self.typeParameterUpperBoundsSignatures = typeParameterUpperBoundsSignatures
        self.valueParameterIsVararg = valueParameterIsVararg
        self.valueParameterAllowsNonLocalReturn = valueParameterAllowsNonLocalReturn
        self.valueParameterHasDefaultValues = valueParameterHasDefaultValues
        self.canThrow = canThrow
        self.valueParameterNames = valueParameterNames
        self.reifiedTypeParameterIndices = reifiedTypeParameterIndices
        self.defaultStubExternalLinkName = defaultStubExternalLinkName
        self.externalLinkName = externalLinkName
        self.declaredFieldCount = declaredFieldCount
        self.declaredInstanceSizeWords = declaredInstanceSizeWords
        self.declaredVtableSize = declaredVtableSize
        self.declaredItableSize = declaredItableSize
        self.superFQName = superFQName
        self.companionObjectFQName = companionObjectFQName
        self.fieldOffsets = fieldOffsets
        self.vtableSlots = vtableSlots
        self.itableSlots = itableSlots
        self.objectInitializerLinkName = objectInitializerLinkName
        self.companionInitializerLinkName = companionInitializerLinkName
        self.enumStaticInitLinkName = enumStaticInitLinkName
        self.isDataClass = isDataClass
        self.isOpenClass = isOpenClass
        self.modality = modality
        self.isSealedClass = isSealedClass
        self.isFunInterface = isFunInterface
        self.annotations = annotations
        self.isValueClass = isValueClass
        self.valueClassUnderlyingTypeSig = valueClassUnderlyingTypeSig
        self.sealedSubclassFQNames = sealedSubclassFQNames
        self.isExpect = isExpect
        self.isActual = isActual
        self.propertyReceiverTypeSignature = propertyReceiverTypeSignature
        self.propertyGetterExternalLinkName = propertyGetterExternalLinkName
        self.abiReturnTypeSignature = abiReturnTypeSignature
        self.propertyGetterAbiReturnTypeSignature = propertyGetterAbiReturnTypeSignature
        self.isMutable = isMutable
        self.nominalTypeParametersSignature = nominalTypeParametersSignature
        self.nominalSupertypeSignatures = nominalSupertypeSignatures
        self.constValueLiteral = constValueLiteral
        self.nominalTypeParameters = nominalTypeParameters
    }
}

/// Annotation metadata that survives the export/import round-trip (P5-86).
public struct MetadataAnnotationRecord: Equatable {
    /// Fully-qualified name of the annotation class (e.g. "kotlin.Deprecated").
    public let annotationFQName: String
    /// Serialized argument values.
    public let arguments: [String]
    /// Optional use-site target (get, set, field, param, etc.).
    public let useSiteTarget: String?

    public init(
        annotationFQName: String,
        arguments: [String] = [],
        useSiteTarget: String? = nil
    ) {
        self.annotationFQName = annotationFQName
        self.arguments = arguments
        self.useSiteTarget = useSiteTarget
    }
}

// MARK: - MetadataEncoder (Export)

/// Encodes compiler symbols into `[MetadataRecord]` and serializes them to the text-based
/// metadata format consumed by `MetadataDecoder`.
package final class MetadataEncoder {
    package init() {}

    /// Build metadata records from the compiler's semantic state.
    package func buildRecords(
        symbols: SymbolTable,
        types: TypeSystem,
        moduleName: String,
        interner: StringInterner,
        functionLinkNames: [SymbolID: String],
        inlineFunctionSymbols: Set<SymbolID> = [],
        includeNonPublic: Bool = false,
        includeSynthetic: Bool = true,
        includeSyntheticNominalAnchors: Bool = false,
        excludeSourceFileIDs: Set<Int32> = [],
        runtimeCallbackRawReturnSymbolIDs: Set<SymbolID> = [],
        objectInitializerLinkNames: [SymbolID: String] = [:],
        companionInitializerLinkNames: [SymbolID: String] = [:],
        enumStaticInitLinkNames: [SymbolID: String] = [:]
    ) -> [MetadataRecord] {
        let exported = symbols.allSymbols()
            .filter { symbol in
                if !includeNonPublic && symbol.visibility != .public {
                    return false
                }
                // KSP-626: `componentN`/`copy`/`equals`/`hashCode`/`toString` of a
                // source-backed data class are synthesized symbols, but they are part of
                // the class's public surface and are compiled into the artifact. Without
                // them consumers cannot destructure or compare an imported data class.
                let keepAsDataClassMember = !includeSynthetic
                    && Self.isSourceBackedDataClassMember(
                        symbol.id,
                        symbols: symbols,
                        excludedSourceFileIDs: excludeSourceFileIDs
                    )
                let keepAsEnumClassMember = !includeSynthetic
                    && Self.isSourceBackedEnumClassMember(
                        symbol.id,
                        symbols: symbols,
                        excludedSourceFileIDs: excludeSourceFileIDs
                    )
                if !includeSynthetic && symbol.flags.contains(.synthetic) && !keepAsDataClassMember && !keepAsEnumClassMember {
                    let keepAsSyntheticNominalAnchor = includeSyntheticNominalAnchors && Self.nominalKinds.contains(symbol.kind)
                    let keepAsSyntheticTypeAlias = includeSyntheticNominalAnchors && symbol.kind == .typeAlias
                    if !(keepAsSyntheticNominalAnchor || keepAsSyntheticTypeAlias) {
                        return false
                    }
                    // STDLIB-SHARED-012: Top-level synthetic classes generated during
                    // lowering (e.g. SAM wrappers like `kk_sam_wrapper_*`) are not part
                    // of the stdlib surface and must not survive into the artifact.
                    if keepAsSyntheticNominalAnchor, symbol.fqName.count <= 1 {
                        return false
                    }
                }
                // STDLIB-SHARED-011: When synthetic functions are excluded, their child
                // type/value parameters must also be excluded. Otherwise metadata leaks
                // orphaned records like `List.toMap.K` that become spurious package
                // symbols on the consumer side and block synthetic member re-registration.
                // Source-backed declarations (e.g. bundled stdlib functions under a
                // synthetic package stub) are still exported; only synthesized helpers
                // without a source declSite are pruned by parent synthetics.
                if !includeSynthetic, symbol.declSite == nil, !keepAsDataClassMember, !keepAsEnumClassMember {
                    var parentID = symbols.parentSymbol(for: symbol.id)
                    while let p = parentID, let parent = symbols.symbol(p) {
                        if parent.flags.contains(.synthetic) {
                            let keepAsSyntheticNominalAnchor = includeSyntheticNominalAnchors && Self.nominalKinds.contains(parent.kind)
                            let keepAsSyntheticTypeAlias = includeSyntheticNominalAnchors && parent.kind == .typeAlias
                            if !(keepAsSyntheticNominalAnchor || keepAsSyntheticTypeAlias) {
                                return false
                            }
                        }
                        parentID = symbols.parentSymbol(for: p)
                    }
                }
                if symbol.kind == .package {
                    return !symbols.annotations(for: symbol.id).isEmpty
                }
                // KSP-911: ULongArray(LongArray) is an internal storage
                // constructor. Keep it in the stdlib object for source-backed
                // implementation calls, but do not export it to consumers.
                if includeNonPublic,
                   symbol.kind == .function,
                   symbol.fqName.map({ interner.resolve($0) }) == ["kotlin", "ULongArray"],
                   symbols.functionSignature(for: symbol.id)?.parameterTypes.count == 1
                {
                    return false
                }
                // KSP-908: UIntArray(IntArray) is an internal storage
                // constructor. It must remain in the stdlib object for
                // source-backed implementation calls, but must not be
                // imported as a public overload by consumer modules.
                if includeNonPublic,
                   symbol.kind == .function,
                   symbol.fqName.map({ interner.resolve($0) }) == ["kotlin", "UIntArray"],
                   symbols.functionSignature(for: symbol.id)?.parameterTypes.count == 1
                {
                    return false
                }
                // STDLIB-SHARED-016: Compiler-generated enum static helpers
                // (values/valueOf/entries) for non-public enum classes are not part
                // of the stdlib surface and cannot be resolved on the consumer side.
                if isNonPublicEnumStaticHelper(symbolID: symbol.id, symbols: symbols, interner: interner) {
                    return false
                }
                // Exclude symbols declared in bundled stdlib virtual files (e.g. __bundled_*.kt).
                // These are compiler internals and are always re-injected on every compilation.
                // Source-backed nominal types that reuse a synthetic shell carry a sourceFileID
                // but leave declSite nil, so also filter by the tracked source file ID.
                if let declSite = symbol.declSite, excludeSourceFileIDs.contains(declSite.start.file.rawValue) {
                    return false
                }
                if let sourceFileID = symbols.sourceFileID(for: symbol.id), excludeSourceFileIDs.contains(sourceFileID.rawValue) {
                    return false
                }
                return true
            }
            .sorted { lhs, rhs in
                if lhs.fqName.count != rhs.fqName.count {
                    return lhs.fqName.count < rhs.fqName.count
                }
                let lhsResolved = lhs.fqName.map { interner.resolve($0) }
                let rhsResolved = rhs.fqName.map { interner.resolve($0) }
                if lhsResolved != rhsResolved {
                    return lhsResolved.lexicographicallyPrecedes(rhsResolved)
                }
                return lhs.id.rawValue < rhs.id.rawValue
            }

        let exportedSymbolIDs = Set(exported.map(\.id))
        var records: [MetadataRecord] = []
        for symbol in exported {
            let isSyntheticNominalAnchor = !includeSynthetic
                && includeSyntheticNominalAnchors
                && symbol.flags.contains(.synthetic)
                && Self.nominalKinds.contains(symbol.kind)
            let built = buildRecord(
                for: symbol,
                symbols: symbols,
                types: types,
                moduleName: moduleName,
                interner: interner,
                functionLinkNames: functionLinkNames,
                inlineFunctionSymbols: inlineFunctionSymbols,
                metadataAnchorOnly: isSyntheticNominalAnchor,
                runtimeCallbackRawReturnSymbolIDs: runtimeCallbackRawReturnSymbolIDs,
                includedSymbolIDs: exportedSymbolIDs,
                objectInitializerLinkNames: objectInitializerLinkNames,
                companionInitializerLinkNames: companionInitializerLinkNames,
                enumStaticInitLinkNames: enumStaticInitLinkNames
            )
            records.append(built)
        }
        return records
    }

    /// Encodes the generic shape of a nominal declaration so consumers can
    /// rebuild it: the declaration's own type parameters (with declared
    /// variance) and the type arguments it passes to each generic direct
    /// supertype. Without these, an imported `class Sub<T> : Base<T>` looks
    /// like a raw `Sub` / `Base` pair and `Sub<Int>` no longer lifts to
    /// `Base<Int>`.
    private func nominalGenericSignatures(
        symbol: SemanticSymbol,
        symbols: SymbolTable,
        types: TypeSystem,
        mangler: NameMangler,
        interner: StringInterner
    ) -> (selfSignature: String?, supertypeSignatures: [String]) {
        let encode: ([TypeArg], SymbolID) -> String = { args, classSymbol in
            self.metadataTypeSignature(
                types.make(.classType(ClassType(classSymbol: classSymbol, args: args, nullability: .nonNull))),
                symbols: symbols,
                types: types,
                mangler: mangler,
                nameResolver: { interner.resolve($0) }
            )
        }
        let typeParameterSymbols = types.nominalTypeParameterSymbols(for: symbol.id)
        let selfSignature: String?
        if !typeParameterSymbols.isEmpty {
            let variances = types.nominalTypeParameterVariances(for: symbol.id)
            let selfArgs: [TypeArg] = typeParameterSymbols.enumerated().map { index, parameterSymbol in
                let parameterType = types.make(.typeParam(TypeParamType(symbol: parameterSymbol, nullability: .nonNull)))
                switch index < variances.count ? variances[index] : .invariant {
                case .out: return .out(parameterType)
                case .in: return .in(parameterType)
                case .invariant: return .invariant(parameterType)
                }
            }
            selfSignature = encode(selfArgs, symbol.id)
        } else {
            selfSignature = nil
        }
        let supertypeSignatures: [String] = symbols.directSupertypes(for: symbol.id).compactMap { superSymbol in
            let superArgs = types.nominalSupertypeTypeArgs(for: symbol.id, supertype: superSymbol)
            guard !superArgs.isEmpty else { return nil }
            return encode(superArgs, superSymbol)
        }
        return (selfSignature, supertypeSignatures)
    }

    private func metadataTypeSignature(
        _ type: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        mangler: NameMangler,
        nameResolver: ((InternedString) -> String)?
    ) -> String {
        let expandedType = expandMetadataTypeAliases(
            in: type,
            symbols: symbols,
            types: types
        )
        return mangler.encodeType(
            expandedType,
            symbols: symbols,
            types: types,
            nameResolver: nameResolver,
            unboxValueClasses: false
        )
    }

    private func expandMetadataTypeAliases(
        in type: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        seenAliases: Set<SymbolID> = []
    ) -> TypeID {
        switch types.kind(of: type) {
        case let .classType(classType):
            guard let symbol = symbols.symbol(classType.classSymbol),
                  symbol.kind == .typeAlias,
                  !seenAliases.contains(classType.classSymbol),
                  let underlying = symbols.typeAliasUnderlyingType(for: classType.classSymbol)
            else {
                let expandedArgs = classType.args.map {
                    expandMetadataTypeAliasArg($0, symbols: symbols, types: types, seenAliases: seenAliases)
                }
                if expandedArgs == classType.args {
                    return type
                }
                return types.make(.classType(ClassType(
                    classSymbol: classType.classSymbol,
                    args: expandedArgs,
                    nullability: classType.nullability
                )))
            }

            let aliasTypeParams = symbols.typeAliasTypeParameters(for: classType.classSymbol)
            let typeVarBySymbol = types.makeTypeVarBySymbol(aliasTypeParams)
            var substitution: [TypeVarID: TypeID] = [:]
            for (index, typeParamSymbol) in aliasTypeParams.enumerated() {
                guard index < classType.args.count,
                      let typeVar = typeVarBySymbol[typeParamSymbol]
                else {
                    continue
                }
                substitution[typeVar] = expandMetadataTypeAliasValue(
                    classType.args[index],
                    symbols: symbols,
                    types: types,
                    seenAliases: seenAliases
                )
            }

            let substituted = types.substituteTypeParameters(
                in: underlying,
                substitution: substitution,
                typeVarBySymbol: typeVarBySymbol
            )
            let expandedUnderlying = expandMetadataTypeAliases(
                in: substituted,
                symbols: symbols,
                types: types,
                seenAliases: seenAliases.union([classType.classSymbol])
            )
            if classType.nullability == .nullable {
                return types.makeNullable(expandedUnderlying)
            }
            return expandedUnderlying

        case let .functionType(functionType):
            let newContextReceivers = functionType.contextReceivers.map {
                expandMetadataTypeAliases(in: $0, symbols: symbols, types: types, seenAliases: seenAliases)
            }
            let newReceiver = functionType.receiver.map {
                expandMetadataTypeAliases(in: $0, symbols: symbols, types: types, seenAliases: seenAliases)
            }
            let newParams = functionType.params.map {
                expandMetadataTypeAliases(in: $0, symbols: symbols, types: types, seenAliases: seenAliases)
            }
            let newReturn = expandMetadataTypeAliases(
                in: functionType.returnType,
                symbols: symbols,
                types: types,
                seenAliases: seenAliases
            )
            if newContextReceivers == functionType.contextReceivers,
               newReceiver == functionType.receiver,
               newParams == functionType.params,
               newReturn == functionType.returnType
            {
                return type
            }
            return types.make(.functionType(FunctionType(
                contextReceivers: newContextReceivers,
                receiver: newReceiver,
                params: newParams,
                returnType: newReturn,
                isSuspend: functionType.isSuspend,
                nullability: functionType.nullability
            )))

        case let .intersection(parts):
            let expandedParts = parts.map {
                expandMetadataTypeAliases(in: $0, symbols: symbols, types: types, seenAliases: seenAliases)
            }
            if expandedParts == parts {
                return type
            }
            return types.make(.intersection(expandedParts))

        case let .kClassType(kClassType):
            let expandedArgument = expandMetadataTypeAliases(
                in: kClassType.argument,
                symbols: symbols,
                types: types,
                seenAliases: seenAliases
            )
            if expandedArgument == kClassType.argument {
                return type
            }
            return types.make(.kClassType(KClassType(
                argument: expandedArgument,
                nullability: kClassType.nullability
            )))

        case .typeParam, .stringStruct, .primitive, .any, .unit, .nothing, .error:
            return type
        }
    }

    private func expandMetadataTypeAliasArg(
        _ arg: TypeArg,
        symbols: SymbolTable,
        types: TypeSystem,
        seenAliases: Set<SymbolID>
    ) -> TypeArg {
        switch arg {
        case let .invariant(inner):
            .invariant(expandMetadataTypeAliases(in: inner, symbols: symbols, types: types, seenAliases: seenAliases))
        case let .out(inner):
            .out(expandMetadataTypeAliases(in: inner, symbols: symbols, types: types, seenAliases: seenAliases))
        case let .in(inner):
            .in(expandMetadataTypeAliases(in: inner, symbols: symbols, types: types, seenAliases: seenAliases))
        case .star:
            .star
        }
    }

    private func expandMetadataTypeAliasValue(
        _ arg: TypeArg,
        symbols: SymbolTable,
        types: TypeSystem,
        seenAliases: Set<SymbolID>
    ) -> TypeID {
        switch arg {
        case let .invariant(inner):
            expandMetadataTypeAliases(in: inner, symbols: symbols, types: types, seenAliases: seenAliases)
        case let .out(inner):
            expandMetadataTypeAliases(in: inner, symbols: symbols, types: types, seenAliases: seenAliases)
        case let .in(inner):
            expandMetadataTypeAliases(in: inner, symbols: symbols, types: types, seenAliases: seenAliases)
        case .star:
            types.nullableAnyType
        }
    }

    func buildRecord(
        for symbol: SemanticSymbol,
        symbols: SymbolTable,
        types: TypeSystem,
        moduleName: String,
        interner: StringInterner,
        functionLinkNames: [SymbolID: String] = [:],
        inlineFunctionSymbols: Set<SymbolID> = [],
        metadataAnchorOnly: Bool = false,
        runtimeCallbackRawReturnSymbolIDs: Set<SymbolID> = [],
        includedSymbolIDs: Set<SymbolID>? = nil,
        objectInitializerLinkNames: [SymbolID: String] = [:],
        companionInitializerLinkNames: [SymbolID: String] = [:],
        enumStaticInitLinkNames: [SymbolID: String] = [:]
    ) -> MetadataRecord {
        let mangler = NameMangler()
        let mangled = mangler.mangle(
            moduleName: moduleName,
            symbol: symbol,
            symbols: symbols,
            types: types,
            nameResolver: { interner.resolve($0) }
        )
        let fqName = symbol.fqName.map { interner.resolve($0) }.joined(separator: ".")

        // STDLIB-SHARED-014: Direct supertype FQ names are needed even for
        // synthetic nominal anchors (e.g. List, Iterable) so that consumers
        // can walk the type hierarchy during member-call fallback resolution.
        let computedSuperFQName: String? = {
            guard Self.nominalKinds.contains(symbol.kind) else { return nil }
            let directSupertypeSymbols = symbols.directSupertypes(for: symbol.id)
            let superFQNames = directSupertypeSymbols.compactMap { superSymbolID in
                symbols.symbol(superSymbolID)?.fqName.map { interner.resolve($0) }.joined(separator: ".")
            }
            return superFQNames.isEmpty ? nil : superFQNames.joined(separator: ",")
        }()

        let valueClassUnderlyingTypeSig: String?
        if symbol.flags.contains(.valueType),
           let underlyingType = symbols.valueClassUnderlyingType(for: symbol.id)
        {
            valueClassUnderlyingTypeSig = mangler.encodeType(
                underlyingType,
                symbols: symbols,
                types: types,
                nameResolver: { interner.resolve($0) }
            )
        } else {
            valueClassUnderlyingTypeSig = nil
        }

        if metadataAnchorOnly {
            // Synthetic nominal anchors need their declared layout sizes as
            // consumer-side synthesis hints. Do not serialize partial slot maps:
            // their synthetic members are intentionally not exported and are
            // re-registered by the consumer. Keeping only an inherited itable
            // entry would install an incomplete layout and prevent synthesis from
            // assigning slots to those re-registered members.
            if Self.nominalKinds.contains(symbol.kind), let layout = symbols.nominalLayout(for: symbol.id) {
                return MetadataRecord(
                    kind: symbol.kind,
                    mangledName: mangled,
                    fqName: fqName,
                    declaredFieldCount: layout.instanceFieldCount,
                    declaredInstanceSizeWords: layout.instanceSizeWords,
                    declaredVtableSize: layout.vtableSize,
                    declaredItableSize: layout.itableSize,
                    superFQName: computedSuperFQName,
                    isDataClass: symbol.flags.contains(.dataType),
                    isOpenClass: symbol.flags.contains(.openType),
                    modality: symbol.flags.contains(.abstractType)
                        ? .abstract
                        : (symbol.flags.contains(.openType) ? .open : .final),
                    isSealedClass: symbol.flags.contains(.sealedType),
                    isFunInterface: symbol.flags.contains(.funInterface),
                    isValueClass: symbol.flags.contains(.valueType),
                    valueClassUnderlyingTypeSig: valueClassUnderlyingTypeSig,
                    isExpect: symbol.flags.contains(.expectDeclaration),
                    isActual: symbol.flags.contains(.actualDeclaration)
                )
            }
            return MetadataRecord(
                kind: symbol.kind,
                mangledName: mangled,
                fqName: fqName,
                superFQName: computedSuperFQName,
                isDataClass: symbol.flags.contains(.dataType),
                isOpenClass: symbol.flags.contains(.openType),
                modality: symbol.flags.contains(.abstractType)
                    ? .abstract
                    : (symbol.flags.contains(.openType) ? .open : .final),
                isSealedClass: symbol.flags.contains(.sealedType),
                isFunInterface: symbol.flags.contains(.funInterface),
                isValueClass: symbol.flags.contains(.valueType),
                valueClassUnderlyingTypeSig: valueClassUnderlyingTypeSig,
                isExpect: symbol.flags.contains(.expectDeclaration),
                isActual: symbol.flags.contains(.actualDeclaration)
            )
        }

        var arity = 0
        var isSuspend = false
        var isInline = false
        var isOperator = false
        var isOverride = false
        var typeSignature: String?
        var typeParameterUpperBoundsSignatures: [[String]] = []
        var valueParameterIsVararg: [Bool] = []
        var valueParameterAllowsNonLocalReturn: [Bool] = []
        var valueParameterHasDefaultValues: [Bool] = []
        var canThrow = false
        var valueParameterNames: [String] = []
        var reifiedTypeParameterIndices: Set<Int> = []
        var defaultStubExternalLinkName: String?
        var externalLinkName: String?
        var abiReturnTypeSignature: String?

        if symbol.kind == .function || symbol.kind == .constructor, let signature = symbols.functionSignature(for: symbol.id) {
            arity = signature.parameterTypes.count
            isSuspend = signature.isSuspend
            // Only mark a record as inline when an actual inline KIR body was emitted.
            // Source flags may be set for runtime-backed synthetic functions that have
            // no KIR body, and those must not try to load a missing inline-kir file.
            isInline = inlineFunctionSymbols.contains(symbol.id)
            isOperator = symbol.flags.contains(.operatorFunction)
            isOverride = symbol.flags.contains(.overrideMember)
            valueParameterIsVararg = signature.valueParameterIsVararg
            valueParameterAllowsNonLocalReturn = signature.valueParameterAllowsNonLocalReturn
            valueParameterHasDefaultValues = signature.valueParameterHasDefaultValues
            canThrow = signature.canThrow
            valueParameterNames = signature.valueParameterSymbols.compactMap { paramSymbol in
                symbols.symbol(paramSymbol).map { interner.resolve($0.name) }
            }
            reifiedTypeParameterIndices = signature.reifiedTypeParameterIndices
            typeSignature = mangler.mangledSignature(
                for: symbol,
                symbols: symbols,
                types: types,
                nameResolver: { interner.resolve($0) },
                unboxValueClasses: false
            )
            typeParameterUpperBoundsSignatures = signature.typeParameterUpperBoundsList.map { bounds in
                bounds.map {
                    metadataTypeSignature(
                        $0,
                        symbols: symbols,
                        types: types,
                        mangler: mangler,
                        nameResolver: { interner.resolve($0) }
                    )
                }
            }
            externalLinkName = functionLinkNames[symbol.id] ?? symbols.externalLinkName(for: symbol.id)
            if signature.valueParameterHasDefaultValues.contains(true) {
                let stubSymbol = SyntheticSymbolScheme.defaultStubSymbol(for: symbol.id)
                defaultStubExternalLinkName = functionLinkNames[stubSymbol] ?? symbols.externalLinkName(for: stubSymbol)
            }
            if runtimeCallbackRawReturnSymbolIDs.contains(symbol.id),
               symbols.functionABIReturnType(for: symbol.id) == nil
            {
                abiReturnTypeSignature = metadataTypeSignature(
                    types.intType,
                    symbols: symbols,
                    types: types,
                    mangler: mangler,
                    nameResolver: { interner.resolve($0) }
                )
            }
            if let abiReturnType = symbols.functionABIReturnType(for: symbol.id) {
                abiReturnTypeSignature = metadataTypeSignature(
                    abiReturnType,
                    symbols: symbols,
                    types: types,
                    mangler: mangler,
                    nameResolver: { interner.resolve($0) }
                )
            }
        }

        var propertyReceiverTypeSignature: String?
        var propertyGetterExternalLinkName: String?
        var propertyGetterAbiReturnTypeSignature: String?
        var isMutable = false
        var constValueLiteral: String?
        if symbol.kind == .property || symbol.kind == .field,
           symbols.propertyType(for: symbol.id) != nil
        {
            typeSignature = symbols.propertyType(for: symbol.id).map { propertyType in
                metadataTypeSignature(
                    propertyType,
                    symbols: symbols,
                    types: types,
                    mangler: mangler,
                    nameResolver: { interner.resolve($0) }
                )
            }
            propertyReceiverTypeSignature = symbols.extensionPropertyReceiverType(for: symbol.id).map { receiverType in
                metadataTypeSignature(
                    receiverType,
                    symbols: symbols,
                    types: types,
                    mangler: mangler,
                    nameResolver: { interner.resolve($0) }
                )
            }
            // Properties with custom getters are lowered as accessor functions in
            // the artifact objects. Record that function's link name so consumers
            // can call the precompiled getter directly.
            // Enum `entries` is a compiler-synthesized property whose getter
            // is emitted as `entries$get`, rather than through the ordinary
            // property-accessor naming scheme. Preserve that getter link in a
            // precompiled artifact so consumers do not materialize an
            // unresolved global slot for the property itself.
            let enumEntriesGetterSymbol: SymbolID? = {
                guard symbol.name == interner.intern("entries"),
                      let companionID = symbols.parentSymbol(for: symbol.id),
                      let companion = symbols.symbol(companionID),
                      companion.kind == .object,
                      let enumID = symbols.parentSymbol(for: companionID),
                      let enumSymbol = symbols.symbol(enumID),
                      enumSymbol.kind == .enumClass,
                      symbols.companionObjectSymbol(for: enumID) == companionID
                else {
                    return nil
                }
                let getterFQName = companion.fqName + [interner.intern("entries$get")]
                return symbols.lookupAll(fqName: getterFQName).first { candidate in
                    symbols.symbol(candidate)?.kind == .function
                }
            }()
            let getterSymbol = enumEntriesGetterSymbol
                ?? symbols.extensionPropertyGetterAccessor(for: symbol.id)
                ?? SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: symbol.id)
            let hasCustomGetter = symbols.propertyHasCustomGetter(for: symbol.id)
                || symbols.extensionPropertyGetterAccessor(for: symbol.id) != nil
                || enumEntriesGetterSymbol != nil
            // Runtime-backed properties can be declared in bundled source
            // without a Kotlin getter body (for example Collection.size). The
            // property symbol's external link must still cross the library
            // boundary as a synthetic getter link; otherwise consumers restore
            // the property as an itable getter and runtime collection boxes
            // cannot satisfy the dispatch.
            if !hasCustomGetter,
               let propertyLink = symbols.externalLinkName(for: symbol.id),
               !propertyLink.isEmpty
            {
                propertyGetterExternalLinkName = propertyLink
            }
            if hasCustomGetter,
               let linkName = functionLinkNames[getterSymbol] ?? symbols.externalLinkName(for: getterSymbol),
               !linkName.isEmpty {
                propertyGetterExternalLinkName = linkName
                if runtimeCallbackRawReturnSymbolIDs.contains(getterSymbol) {
                    propertyGetterAbiReturnTypeSignature = metadataTypeSignature(
                        types.intType,
                        symbols: symbols,
                        types: types,
                        mangler: mangler,
                        nameResolver: { interner.resolve($0) }
                    )
                }
            }
            isMutable = symbol.flags.contains(.mutable)
            if !isMutable, let constValue = symbols.constValueExprKind(for: symbol.id) {
                constValueLiteral = MetadataConstValueCoder.encode(constValue) { interner.resolve($0) }
            }
        }

        if symbol.kind == .typeAlias,
           symbols.typeAliasUnderlyingType(for: symbol.id) != nil
        {
            typeSignature = symbols.typeAliasUnderlyingType(for: symbol.id).map { underlyingType in
                metadataTypeSignature(
                    underlyingType,
                    symbols: symbols,
                    types: types,
                    mangler: mangler,
                    nameResolver: { interner.resolve($0) }
                )
            }
        }

        var declaredFieldCount: Int?
        var declaredInstanceSizeWords: Int?
        var declaredVtableSize: Int?
        var declaredItableSize: Int?
        var superFQName: String?
        var companionObjectFQName: String?
        var fieldOffsetsStr: String?
        var vtableSlotsStr: String?
        var itableSlotsStr: String?
        var objectInitializerLinkName: String?
        var companionInitializerLinkName: String?
        var enumStaticInitLinkName: String?
        var nominalTypeParametersSignature: String?
        var nominalSupertypeSignatures: [String] = []
        var nominalTypeParameters: String?

        if Self.nominalKinds.contains(symbol.kind) {
            superFQName = computedSuperFQName
            let generics = nominalGenericSignatures(
                symbol: symbol,
                symbols: symbols,
                types: types,
                mangler: mangler,
                interner: interner
            )
            nominalTypeParameters = serializeNominalTypeParameters(
                for: symbol.id,
                symbols: symbols,
                types: types,
                mangler: mangler,
                interner: interner
            )
            nominalTypeParametersSignature = generics.selfSignature
            nominalSupertypeSignatures = generics.supertypeSignatures
            if let layout = symbols.nominalLayout(for: symbol.id) {
                declaredInstanceSizeWords = layout.instanceSizeWords
                declaredFieldCount = layout.instanceFieldCount
                declaredVtableSize = layout.vtableSize
                declaredItableSize = layout.itableSize

                let serializedFieldOffsets = serializeFieldOffsets(layout.fieldOffsets, symbols: symbols, interner: interner, includedSymbolIDs: includedSymbolIDs)
                if !serializedFieldOffsets.isEmpty {
                    fieldOffsetsStr = serializedFieldOffsets
                }
                let serializedVTableSlots = serializeVTableSlots(layout.vtableSlots, symbols: symbols, interner: interner, includedSymbolIDs: includedSymbolIDs, mangler: mangler, types: types)
                if !serializedVTableSlots.isEmpty {
                    vtableSlotsStr = serializedVTableSlots
                }
                let serializedITableSlots = serializeITableSlots(layout.itableSlots, symbols: symbols, interner: interner, includedSymbolIDs: includedSymbolIDs)
                if !serializedITableSlots.isEmpty {
                    itableSlotsStr = serializedITableSlots
                }
            }
            if let companionSymbolID = symbols.companionObjectSymbol(for: symbol.id),
               let includedSymbolIDs = includedSymbolIDs,
               includedSymbolIDs.contains(companionSymbolID),
               let companionSymbol = symbols.symbol(companionSymbolID)
            {
                companionObjectFQName = companionSymbol.fqName.map { interner.resolve($0) }.joined(separator: ".")
            }
            if symbol.kind == .object {
                objectInitializerLinkName = objectInitializerLinkNames[symbol.id]
            }
            companionInitializerLinkName = companionInitializerLinkNames[symbol.id]
            if symbol.kind == .enumClass {
                enumStaticInitLinkName = enumStaticInitLinkNames[symbol.id]
            }
        }

        let isDataClass = symbol.flags.contains(.dataType)
        let isOpenClass = symbol.flags.contains(.openType)
        let modality: MetadataModality = if symbol.flags.contains(.abstractType) {
            .abstract
        } else if symbol.flags.contains(.openType) {
            .open
        } else {
            .final
        }
        let isSealedClass = symbol.flags.contains(.sealedType)
        let isFunInterface = symbol.flags.contains(.funInterface)
        let isExpect = symbol.flags.contains(.expectDeclaration)
        let isActual = symbol.flags.contains(.actualDeclaration)
        // Serialize isValueClass independently of whether the underlying type was found.
        // Even if underlying type extraction fails, mark it as a value class so importers
        // can identify it correctly; valueClassUnderlyingTypeSig may be nil in that case.
        let isValueClass = symbol.flags.contains(.valueType)

        let annotationEntries = symbols.annotations(for: symbol.id)

        // P5-78: collect sealed subclass FQ names for cross-module exhaustiveness
        var sealedSubclassFQNames: [String] = []
        if isSealedClass {
            let directSubs = symbols.sealedSubclasses(for: symbol.id) ?? symbols.directSubtypes(of: symbol.id)
            sealedSubclassFQNames = directSubs.compactMap { subID in
                guard let subSymbol = symbols.symbol(subID) else { return nil }
                let subFQ = subSymbol.fqName.map { interner.resolve($0) }.joined(separator: ".")
                return subFQ.isEmpty ? nil : subFQ
            }.sorted()
        }

        return MetadataRecord(
            kind: symbol.kind,
            mangledName: mangled,
            fqName: fqName,
            arity: arity,
            isSuspend: isSuspend,
            isInline: isInline,
            isOperator: isOperator,
            isOverride: isOverride,
            typeSignature: typeSignature,
            typeParameterUpperBoundsSignatures: typeParameterUpperBoundsSignatures,
            valueParameterIsVararg: valueParameterIsVararg,
            valueParameterAllowsNonLocalReturn: valueParameterAllowsNonLocalReturn,
            valueParameterHasDefaultValues: valueParameterHasDefaultValues,
            canThrow: canThrow,
            valueParameterNames: valueParameterNames,
            reifiedTypeParameterIndices: reifiedTypeParameterIndices,
            defaultStubExternalLinkName: defaultStubExternalLinkName,
            externalLinkName: externalLinkName,
            declaredFieldCount: declaredFieldCount,
            declaredInstanceSizeWords: declaredInstanceSizeWords,
            declaredVtableSize: declaredVtableSize,
            declaredItableSize: declaredItableSize,
            superFQName: superFQName,
            companionObjectFQName: companionObjectFQName,
            fieldOffsets: fieldOffsetsStr,
            vtableSlots: vtableSlotsStr,
            itableSlots: itableSlotsStr,
            objectInitializerLinkName: objectInitializerLinkName,
            companionInitializerLinkName: companionInitializerLinkName,
            enumStaticInitLinkName: enumStaticInitLinkName,
            isDataClass: isDataClass,
            isOpenClass: isOpenClass,
            modality: modality,
            isSealedClass: isSealedClass,
            isFunInterface: isFunInterface,
            annotations: annotationEntries,
            isValueClass: isValueClass,
            valueClassUnderlyingTypeSig: valueClassUnderlyingTypeSig,
            sealedSubclassFQNames: sealedSubclassFQNames,
            isExpect: isExpect,
            isActual: isActual,
            propertyReceiverTypeSignature: propertyReceiverTypeSignature,
            propertyGetterExternalLinkName: propertyGetterExternalLinkName,
            abiReturnTypeSignature: abiReturnTypeSignature,
            propertyGetterAbiReturnTypeSignature: propertyGetterAbiReturnTypeSignature,
            isMutable: isMutable,
            nominalTypeParametersSignature: nominalTypeParametersSignature,
            nominalSupertypeSignatures: nominalSupertypeSignatures,
            constValueLiteral: constValueLiteral,
            nominalTypeParameters: nominalTypeParameters
        )
    }

    /// Encodes a nominal type's declaration-order type parameters as
    /// `<typeSignature>:<variance>` pairs so importers can restore the generic
    /// arity (constructor/member type-argument resolution needs it).
    private func serializeNominalTypeParameters(
        for symbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        mangler: NameMangler,
        interner: StringInterner
    ) -> String? {
        let typeParameterSymbols = types.nominalTypeParameterSymbols(for: symbol)
        guard !typeParameterSymbols.isEmpty else {
            return nil
        }
        let variances = types.nominalTypeParameterVariances(for: symbol)
        let entries: [String] = typeParameterSymbols.enumerated().map { index, typeParameterSymbol in
            let encoded = mangler.encodeType(
                types.make(.typeParam(TypeParamType(symbol: typeParameterSymbol, nullability: .nonNull))),
                symbols: symbols,
                types: types,
                nameResolver: { interner.resolve($0) }
            )
            let variance: String = switch index < variances.count ? variances[index] : .invariant {
            case .invariant: "i"
            case .out: "o"
            case .in: "n"
            }
            return "\(encoded):\(variance)"
        }
        return entries.joined(separator: ",")
    }

    /// Nominal kinds that carry layout information in metadata.
    private static let nominalKinds: Set<SymbolKind> = [.class, .interface, .object, .enumClass, .annotationClass]

    /// True when `symbolID` is (or belongs to) a compiler-generated member of a
    /// source-backed data class (KSP-626).
    private static func isSourceBackedDataClassMember(
        _ symbolID: SymbolID,
        symbols: SymbolTable,
        excludedSourceFileIDs: Set<Int32>
    ) -> Bool {
        var currentID = symbols.parentSymbol(for: symbolID)
        while let parentID = currentID, let parent = symbols.symbol(parentID) {
            if nominalKinds.contains(parent.kind) {
                guard parent.flags.contains(.dataType),
                      !parent.flags.contains(.synthetic),
                      parent.declSite != nil
                else {
                    return false
                }
                if let sourceFileID = symbols.sourceFileID(for: parent.id),
                   excludedSourceFileIDs.contains(sourceFileID.rawValue)
                {
                    return false
                }
                return true
            }
            currentID = symbols.parentSymbol(for: parentID)
        }
        return false
    }

    /// True when `symbolID` is a compiler-generated member of a source-backed enum
    /// class (name, ordinal, values) or its companion (valueOf, entries). These
    /// symbols are synthesized by HeaderCollection but are part of the public
    /// surface of an enum class, so consumers that import the class from a
    /// precompiled artifact must be able to resolve them.
    private static func isSourceBackedEnumClassMember(
        _ symbolID: SymbolID,
        symbols: SymbolTable,
        excludedSourceFileIDs: Set<Int32>
    ) -> Bool {
        var currentID = symbols.parentSymbol(for: symbolID)
        while let parentID = currentID, let parent = symbols.symbol(parentID) {
            if Self.nominalKinds.contains(parent.kind) {
                if parent.kind == .enumClass,
                   !parent.flags.contains(.synthetic),
                   parent.declSite != nil {
                    if let sourceFileID = symbols.sourceFileID(for: parent.id),
                       excludedSourceFileIDs.contains(sourceFileID.rawValue)
                    {
                        return false
                    }
                    return true
                }
                // Synthetic companions / nested anchors may sit between the
                // member and the owning enum class; keep walking.
                if parent.flags.contains(.synthetic) {
                    currentID = symbols.parentSymbol(for: parentID)
                    continue
                }
                // valueOf / entries are synthesized on the companion object,
                // which may be a user-declared (non-synthetic) companion. Walk
                // through it to reach the owning enum class.
                if parent.kind == .object,
                   let grandparentID = symbols.parentSymbol(for: parentID),
                   symbols.companionObjectSymbol(for: grandparentID) == parentID
                {
                    currentID = grandparentID
                    continue
                }
                return false
            }
            currentID = symbols.parentSymbol(for: parentID)
        }
        return false
    }

    func metadataAnnotationRecord(for record: MetadataRecord) -> MetadataAnnotationRecord {
        MetadataAnnotationRecord(
            annotationFQName: KnownCompilerAnnotation.metadata.qualifiedName,
            arguments: [serialize([record])]
        )
    }

    /// Serialize records to the text-based metadata format.
    package func serialize(_ records: [MetadataRecord]) -> String {
        var lines = ["symbols=\(records.count)"]
        for record in records {
            var fields: [String] = [
                "\(record.kind)",
                record.mangledName,
                "fq=\(record.fqName)",
                "schema=v1",
            ]
            if record.kind == .function || record.kind == .constructor {
                fields.append("arity=\(record.arity)")
                fields.append("suspend=\(record.isSuspend ? 1 : 0)")
                fields.append("inline=\(record.isInline ? 1 : 0)")
                fields.append("operator=\(record.isOperator ? 1 : 0)")
                if record.isOverride {
                    fields.append("override=1")
                }
                if !record.valueParameterIsVararg.isEmpty {
                    let mask = record.valueParameterIsVararg.map { $0 ? "1" : "0" }.joined()
                    fields.append("vararg=\(mask)")
                }
                if !record.valueParameterAllowsNonLocalReturn.isEmpty {
                    let mask = record.valueParameterAllowsNonLocalReturn.map { $0 ? "1" : "0" }.joined()
                    fields.append("nonLocal=\(mask)")
                }
                if !record.valueParameterHasDefaultValues.isEmpty {
                    let mask = record.valueParameterHasDefaultValues.map { $0 ? "1" : "0" }.joined()
                    fields.append("default=\(mask)")
                }
                if record.canThrow {
                    fields.append("canThrow=1")
                }
                if !record.valueParameterNames.isEmpty {
                    fields.append("paramNames=\(record.valueParameterNames.joined(separator: ","))")
                }
                if !record.reifiedTypeParameterIndices.isEmpty {
                    let indices = record.reifiedTypeParameterIndices.sorted().map(String.init).joined(separator: ",")
                    fields.append("reified=\(indices)")
                }
                if let sig = record.typeSignature {
                    fields.append("sig=\(sig)")
                }
                if record.typeParameterUpperBoundsSignatures.contains(where: { !$0.isEmpty }),
                   let encodedBounds = encodeMetadataTypeParameterUpperBounds(record.typeParameterUpperBoundsSignatures)
                {
                    fields.append("typeBounds=\(encodedBounds)")
                }
                if let linkName = record.defaultStubExternalLinkName, !linkName.isEmpty {
                    fields.append("defaultLink=\(linkName)")
                }
                if let linkName = record.externalLinkName, !linkName.isEmpty {
                    fields.append("link=\(linkName)")
                }
                if let abiSig = record.abiReturnTypeSignature {
                    fields.append("abiSig=\(abiSig)")
                }
            }
            if record.kind == .property || record.kind == .field {
                if let sig = record.typeSignature {
                    fields.append("sig=\(sig)")
                }
                if let recv = record.propertyReceiverTypeSignature {
                    fields.append("recv=\(recv)")
                }
                if let getterLink = record.propertyGetterExternalLinkName, !getterLink.isEmpty {
                    fields.append("getterLink=\(getterLink)")
                }
                if let getterAbiSig = record.propertyGetterAbiReturnTypeSignature {
                    fields.append("getterAbiSig=\(getterAbiSig)")
                }
                if record.isMutable {
                    fields.append("mutable=1")
                }
                if let constValue = record.constValueLiteral, !constValue.isEmpty {
                    fields.append("const=\(constValue)")
                }
            }
            if record.kind == .typeAlias {
                if let sig = record.typeSignature {
                    fields.append("sig=\(sig)")
                }
            }
            if Self.nominalKinds.contains(record.kind) {
                if let layoutWords = record.declaredInstanceSizeWords {
                    fields.append("layoutWords=\(layoutWords)")
                }
                if let fieldCount = record.declaredFieldCount {
                    fields.append("fields=\(fieldCount)")
                }
                if let vtableSize = record.declaredVtableSize {
                    fields.append("vtable=\(vtableSize)")
                }
                if let itableSize = record.declaredItableSize {
                    fields.append("itable=\(itableSize)")
                }
                if let fo = record.fieldOffsets {
                    fields.append("fieldOffsets=\(fo)")
                }
                if let vs = record.vtableSlots {
                    fields.append("vtableSlots=\(vs)")
                }
                if let is_ = record.itableSlots {
                    fields.append("itableSlots=\(is_)")
                }
                if let superFq = record.superFQName {
                    fields.append("superFq=\(superFq)")
                }
                if let typeParamsSig = record.nominalTypeParametersSignature {
                    fields.append("typeParamsSig=\(typeParamsSig)")
                }
                if !record.nominalSupertypeSignatures.isEmpty {
                    fields.append("superSigs=\(record.nominalSupertypeSignatures.joined(separator: "|"))")
                }
                if let companionFq = record.companionObjectFQName {
                    fields.append("companionFq=\(companionFq)")
                }
                if let objectInitLink = record.objectInitializerLinkName, !objectInitLink.isEmpty {
                    fields.append("objectInitLink=\(objectInitLink)")
                }
                if let companionInitLink = record.companionInitializerLinkName, !companionInitLink.isEmpty {
                    fields.append("companionInitLink=\(companionInitLink)")
                }
                if let enumStaticInitLink = record.enumStaticInitLinkName, !enumStaticInitLink.isEmpty {
                    fields.append("enumStaticInitLink=\(enumStaticInitLink)")
                }
                if let typeParams = record.nominalTypeParameters, !typeParams.isEmpty {
                    fields.append("typeParams=\(typeParams)")
                }
            }
            if record.isDataClass {
                fields.append("dataClass=1")
            }
            if record.isOpenClass {
                fields.append("openClass=1")
            }
            if record.modality != .final {
                fields.append("modality=\(record.modality.rawValue)")
            }
            if record.isSealedClass {
                fields.append("sealedClass=1")
            }
            if record.isFunInterface {
                fields.append("funInterface=1")
            }
            if record.isValueClass {
                fields.append("valueClass=1")
                if let vSig = record.valueClassUnderlyingTypeSig {
                    fields.append("valueUnderlying=\(vSig)")
                }
            }
            if !record.sealedSubclassFQNames.isEmpty {
                fields.append("sealedSubs=\(record.sealedSubclassFQNames.joined(separator: ","))")
            }
            if record.isExpect {
                fields.append("expect=1")
            }
            if record.isActual {
                fields.append("actual=1")
            }
            if !record.annotations.isEmpty {
                fields.append("annotations=\(encodeAnnotations(record.annotations))")
            }
            lines.append(fields.joined(separator: " "))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    func serializeFieldOffsets(
        _ offsets: [SymbolID: Int],
        symbols: SymbolTable,
        interner: StringInterner,
        includedSymbolIDs: Set<SymbolID>? = nil
    ) -> String {
        let pairs: [(String, Int)] = offsets.compactMap { symbolID, offset in
            guard let symbol = symbols.symbol(symbolID) else {
                return nil
            }
            if let includedSymbolIDs, !includedSymbolIDs.contains(symbolID) {
                return nil
            }
            let fqName = symbol.fqName.map { interner.resolve($0) }.joined(separator: ".")
            guard !fqName.isEmpty else {
                return nil
            }
            return (fqName, offset)
        }
        let sorted = pairs.sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
            return lhs.0 < rhs.0
        }
        return sorted.map { "\($0.0)@\($0.1)" }.joined(separator: ",")
    }

    /// True for compiler-generated enum static helpers (`values`, `valueOf`,
    /// `entries`) that belong to a non-public enum class.  These slots are not
    /// reachable from consumer code and cannot be resolved on import, so they
    /// should be omitted from serialized vtable/itable layouts.
    private func isNonPublicEnumStaticHelper(
        symbolID: SymbolID,
        symbols: SymbolTable,
        interner: StringInterner
    ) -> Bool {
        guard let symbol = symbols.symbol(symbolID),
              symbol.kind == .function
        else {
            return false
        }
        let name = interner.resolve(symbol.name)
        guard name == "values" || name == "valueOf" || name == "entries" else {
            return false
        }
        var ancestorID = symbols.parentSymbol(for: symbol.id)
        while let ancestor = ancestorID, let ancestorSymbol = symbols.symbol(ancestor) {
            if ancestorSymbol.kind == .enumClass {
                return ancestorSymbol.visibility != .public
            }
            ancestorID = symbols.parentSymbol(for: ancestor)
        }
        return false
    }

    func serializeVTableSlots(
        _ slots: [SymbolID: Int],
        symbols: SymbolTable,
        interner: StringInterner,
        includedSymbolIDs: Set<SymbolID>? = nil,
        mangler: NameMangler? = nil,
        types: TypeSystem? = nil
    ) -> String {
        let pairs: [(String, Int)] = slots.compactMap { symbolID, slot in
            if let decoded = SyntheticSymbolScheme.decodedPropertyAccessor(symbolID),
               let property = symbols.symbol(decoded.property)
            {
                let fqName = property.fqName.map { interner.resolve($0) }.joined(separator: ".")
                guard !fqName.isEmpty else { return nil }
                let prefix = decoded.kind == .getter ? "pget:" : "pset:"
                return ("\(prefix)\(fqName)", slot)
            }
            if let property = symbols.symbol(symbolID), property.kind == .property {
                let fqName = property.fqName.map { interner.resolve($0) }.joined(separator: ".")
                guard !fqName.isEmpty else { return nil }
                return ("pget:\(fqName)", slot)
            }
            guard let symbol = symbols.symbol(symbolID), symbol.kind == .function else {
                return nil
            }
            // Vtable layout must survive the round-trip even for methods that are
            // private or synthetic (e.g. Any.toString/hashCode/equals, internal
            // helpers like Random.stepXorWow).  The consumer resolves each entry
            // by FQ name/arity/type-signature so that overloaded methods with the
            // same arity map to the correct slot.
            if isNonPublicEnumStaticHelper(symbolID: symbolID, symbols: symbols, interner: interner) {
                return nil
            }
            if let includedSymbolIDs, !includedSymbolIDs.contains(symbolID) {
                return nil
            }
            let fqName = symbol.fqName.map { interner.resolve($0) }.joined(separator: ".")
            guard !fqName.isEmpty else {
                return nil
            }
            let signature = symbols.functionSignature(for: symbolID)
            let arity = signature?.parameterTypes.count ?? 0
            let isSuspend = signature?.isSuspend ?? false
            let typeSignature: String? = if let mangler, let types {
                mangler.mangledSignature(
                    for: symbol,
                    symbols: symbols,
                    types: types,
                    nameResolver: { interner.resolve($0) }
                )
            } else {
                nil
            }
            let key: String
            if let typeSignature, !typeSignature.isEmpty {
                key = "\(fqName)#\(arity)#\(isSuspend ? 1 : 0)#\(typeSignature)"
            } else {
                key = "\(fqName)#\(arity)#\(isSuspend ? 1 : 0)"
            }
            return (key, slot)
        }
        let sorted = pairs.sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
            return lhs.0 < rhs.0
        }
        // Use `|` as the entry separator because the type-signature component
        // of each key may contain commas (e.g. function parameter lists).
        // Prefix with `v2:` so single-entry tokens are distinguishable from the
        // legacy comma-separated format.
        let body = sorted.map { "\($0.0)@\($0.1)" }.joined(separator: "|")
        return "v2:\(body)"
    }

    func serializeITableSlots(
        _ slots: [SymbolID: Int],
        symbols: SymbolTable,
        interner: StringInterner,
        includedSymbolIDs: Set<SymbolID>? = nil
    ) -> String {
        let pairs: [(String, Int)] = slots.compactMap { symbolID, slot in
            guard let symbol = symbols.symbol(symbolID) else {
                return nil
            }
            if isNonPublicEnumStaticHelper(symbolID: symbolID, symbols: symbols, interner: interner) {
                return nil
            }
            // ITable slot layout is part of the nominal type shape and must round-trip
            // completely, even for synthetic or non-public interface supertypes.
            if let includedSymbolIDs, !includedSymbolIDs.contains(symbolID) {
                return nil
            }
            let fqName = symbol.fqName.map { interner.resolve($0) }.joined(separator: ".")
            guard !fqName.isEmpty else {
                return nil
            }
            return (fqName, slot)
        }
        let sorted = pairs.sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
            return lhs.0 < rhs.0
        }
        return sorted.map { "\($0.0)@\($0.1)" }.joined(separator: ",")
    }

    // MARK: - Annotation Encoding

    private func encodeAnnotations(_ annotations: [MetadataAnnotationRecord]) -> String {
        annotations.map { encodeAnnotation($0) }.joined(separator: ";")
    }

    private func encodeAnnotation(_ annotation: MetadataAnnotationRecord) -> String {
        var parts = [annotation.annotationFQName]
        if let target = annotation.useSiteTarget {
            parts.append("target:\(target)")
        }
        if !annotation.arguments.isEmpty {
            let argsB64 = annotation.arguments.map { Data($0.utf8).base64EncodedString() }
            parts.append("args:\(argsB64.joined(separator: ","))")
        }
        return parts.joined(separator: "|")
    }
}

private func encodeMetadataTypeParameterUpperBounds(_ bounds: [[String]]) -> String? {
    let encodedGroups = bounds.map { group in
        group.map { Data($0.utf8).base64EncodedString() }.joined(separator: ",")
    }
    return encodedGroups.isEmpty ? nil : encodedGroups.joined(separator: "|")
}

private func decodeMetadataTypeParameterUpperBounds(_ value: String) -> [[String]] {
    value.split(separator: "|", omittingEmptySubsequences: false).map { group in
        guard !group.isEmpty else { return [] }
        return group.split(separator: ",", omittingEmptySubsequences: false).compactMap { encoded in
            guard let data = Data(base64Encoded: String(encoded)),
                  let decoded = String(data: data, encoding: .utf8)
            else {
                return nil
            }
            return decoded
        }
    }
}

// MARK: - MetadataDecoder (Import)

/// Decodes the text-based metadata format into `[MetadataRecord]`.
/// This replaces the ad-hoc parsing previously done in DataFlow/LibraryMetadataParsing.swift.
final class MetadataDecoder {
    init() {}

    /// Parse text content into metadata records.
    func decode(_ content: String) -> [MetadataRecord] {
        var records: [MetadataRecord] = []
        for rawLine in content.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("symbols=") {
                continue
            }
            let parts = line.split(separator: " ").map(String.init)
            guard let kindToken = parts.first,
                  let kind = symbolKindFromMetadata(kindToken)
            else {
                continue
            }
            let mangledName = parts.count > 1 ? parts[1] : ""

            var rec = MutableMetadataRecord()

            for part in parts.dropFirst() {
                guard let separatorIndex = part.firstIndex(of: "=") else {
                    continue
                }
                let key = String(part[..<separatorIndex])
                let value = String(part[part.index(after: separatorIndex)...])
                applyKeyValuePart(key: key, value: value, into: &rec)
            }

            // Backward-compatible schema gate:
            // - records without schema are treated as legacy v1
            // - only explicitly non-v1 schema versions are rejected
            guard !rec.fqName.isEmpty else {
                continue
            }
            if let schemaVersion = rec.schemaVersion, schemaVersion != "v1" {
                continue
            }

            records.append(MetadataRecord(
                kind: kind,
                mangledName: mangledName,
                fqName: rec.fqName,
                arity: rec.arity,
                isSuspend: rec.isSuspend,
                isInline: rec.isInline,
                isOperator: rec.isOperator,
                isOverride: rec.isOverride,
                typeSignature: rec.typeSignature,
                typeParameterUpperBoundsSignatures: rec.typeParameterUpperBoundsSignatures,
                valueParameterIsVararg: rec.valueParameterIsVararg,
                valueParameterAllowsNonLocalReturn: rec.valueParameterAllowsNonLocalReturn,
                valueParameterHasDefaultValues: rec.valueParameterHasDefaultValues,
                canThrow: rec.canThrow,
                valueParameterNames: rec.valueParameterNames,
                reifiedTypeParameterIndices: rec.reifiedTypeParameterIndices,
                defaultStubExternalLinkName: rec.defaultStubExternalLinkName,
                externalLinkName: rec.externalLinkName,
                declaredFieldCount: rec.declaredFieldCount,
                declaredInstanceSizeWords: rec.declaredInstanceSizeWords,
                declaredVtableSize: rec.declaredVtableSize,
                declaredItableSize: rec.declaredItableSize,
                superFQName: rec.superFQName,
                companionObjectFQName: rec.companionObjectFQName,
                fieldOffsets: rec.fieldOffsets,
                vtableSlots: rec.vtableSlots,
                itableSlots: rec.itableSlots,
                objectInitializerLinkName: rec.objectInitializerLinkName,
                companionInitializerLinkName: rec.companionInitializerLinkName,
                enumStaticInitLinkName: rec.enumStaticInitLinkName,
                isDataClass: rec.isDataClass,
                isOpenClass: rec.isOpenClass,
                modality: rec.modality,
                isSealedClass: rec.isSealedClass,
                isFunInterface: rec.isFunInterface,
                annotations: rec.annotations,
                isValueClass: rec.isValueClass,
                valueClassUnderlyingTypeSig: rec.valueClassUnderlyingTypeSig,
                sealedSubclassFQNames: rec.sealedSubclassFQNames,
                isExpect: rec.isExpect,
                isActual: rec.isActual,
                propertyReceiverTypeSignature: rec.propertyReceiverTypeSignature,
                propertyGetterExternalLinkName: rec.propertyGetterExternalLinkName,
                abiReturnTypeSignature: rec.abiReturnTypeSignature,
                propertyGetterAbiReturnTypeSignature: rec.propertyGetterAbiReturnTypeSignature,
                isMutable: rec.isMutable,
                nominalTypeParametersSignature: rec.nominalTypeParametersSignature,
                nominalSupertypeSignatures: rec.nominalSupertypeSignatures,
                constValueLiteral: rec.constValueLiteral,
                nominalTypeParameters: rec.nominalTypeParameters
            ))
        }
        return records
    }

    // MARK: - Key-Value Parsing

    /// Mutable accumulator used while parsing a single metadata line.
    private struct MutableMetadataRecord {
        var fqName: String = ""
        var arity: Int = 0
        var isSuspend: Bool = false
        var isInline: Bool = false
        var isOperator: Bool = false
        var isOverride: Bool = false
        var typeSignature: String?
        var valueParameterIsVararg: [Bool] = []
        var valueParameterAllowsNonLocalReturn: [Bool] = []
        var valueParameterHasDefaultValues: [Bool] = []
        var canThrow: Bool = false
        var valueParameterNames: [String] = []
        var reifiedTypeParameterIndices: Set<Int> = []
        var defaultStubExternalLinkName: String?
        var externalLinkName: String?
        var declaredFieldCount: Int?
        var declaredInstanceSizeWords: Int?
        var declaredVtableSize: Int?
        var declaredItableSize: Int?
        var superFQName: String?
        var companionObjectFQName: String?
        var fieldOffsets: String?
        var vtableSlots: String?
        var itableSlots: String?
        var objectInitializerLinkName: String?
        var companionInitializerLinkName: String?
        var enumStaticInitLinkName: String?
        var isDataClass: Bool = false
        var isOpenClass: Bool = false
        var modality: MetadataModality = .final
        var isSealedClass: Bool = false
        var isFunInterface: Bool = false
        var isValueClass: Bool = false
        var valueClassUnderlyingTypeSig: String?
        var annotations: [MetadataAnnotationRecord] = []
        var sealedSubclassFQNames: [String] = []
        var isExpect: Bool = false
        var isActual: Bool = false
        var propertyReceiverTypeSignature: String?
        var propertyGetterExternalLinkName: String?
        var abiReturnTypeSignature: String?
        var propertyGetterAbiReturnTypeSignature: String?
        var isMutable: Bool = false
        var nominalTypeParametersSignature: String?
        var nominalSupertypeSignatures: [String] = []
        var constValueLiteral: String?
        var nominalTypeParameters: String?
        var typeParameterUpperBoundsSignatures: [[String]] = []
        var schemaVersion: String?
    }

    private func applyKeyValuePart(key: String, value: String, into record: inout MutableMetadataRecord) {
        switch key {
        case "fq":
            record.fqName = value
        case "arity":
            record.arity = Int(value) ?? 0
        case "suspend":
            record.isSuspend = value == "1" || value == "true"
        case "inline":
            record.isInline = value == "1" || value == "true"
        case "operator":
            record.isOperator = value == "1" || value == "true"
        case "override":
            record.isOverride = value == "1" || value == "true"
        case "vararg":
            record.valueParameterIsVararg = value.map { $0 == "1" }
        case "nonLocal":
            record.valueParameterAllowsNonLocalReturn = value.map { $0 == "1" }
        case "default":
            record.valueParameterHasDefaultValues = value.map { $0 == "1" }
        case "canThrow":
            record.canThrow = value == "1" || value == "true"
        case "paramNames":
            record.valueParameterNames = value.split(separator: ",").map(String.init)
        case "reified":
            record.reifiedTypeParameterIndices = Set(
                value.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            )
        case "defaultLink":
            record.defaultStubExternalLinkName = value.isEmpty ? nil : value
        case "sig":
            record.typeSignature = value.isEmpty ? nil : value
        case "typeBounds":
            record.typeParameterUpperBoundsSignatures = decodeMetadataTypeParameterUpperBounds(value)
        case "link":
            record.externalLinkName = value.isEmpty ? nil : value
        case "fields":
            record.declaredFieldCount = Int(value)
        case "layoutWords":
            record.declaredInstanceSizeWords = Int(value)
        case "vtable":
            record.declaredVtableSize = Int(value)
        case "itable":
            record.declaredItableSize = Int(value)
        case "superFq":
            record.superFQName = value.isEmpty ? nil : value
        case "typeParamsSig":
            record.nominalTypeParametersSignature = value.isEmpty ? nil : value
        case "superSigs":
            record.nominalSupertypeSignatures = value.split(separator: "|").map(String.init)
        case "companionFq":
            record.companionObjectFQName = value.isEmpty ? nil : value
        case "fieldOffsets":
            record.fieldOffsets = value.isEmpty ? nil : value
        case "vtableSlots":
            record.vtableSlots = value.isEmpty ? nil : value
        case "itableSlots":
            record.itableSlots = value.isEmpty ? nil : value
        case "typeParams":
            record.nominalTypeParameters = value.isEmpty ? nil : value
        case "objectInitLink":
            record.objectInitializerLinkName = value.isEmpty ? nil : value
        case "companionInitLink":
            record.companionInitializerLinkName = value.isEmpty ? nil : value
        case "enumStaticInitLink":
            record.enumStaticInitLinkName = value.isEmpty ? nil : value
        case "dataClass":
            record.isDataClass = value == "1" || value == "true"
        case "openClass":
            record.isOpenClass = value == "1" || value == "true"
        case "modality":
            record.modality = MetadataModality(rawValue: value) ?? .final
        case "sealedClass":
            record.isSealedClass = value == "1" || value == "true"
        case "funInterface":
            record.isFunInterface = value == "1" || value == "true"
        case "valueClass":
            record.isValueClass = value == "1" || value == "true"
        case "valueUnderlying":
            record.valueClassUnderlyingTypeSig = value.isEmpty ? nil : value
        case "sealedSubs":
            record.sealedSubclassFQNames = value.split(separator: ",").map(String.init).filter { !$0.isEmpty }
        case "annotations":
            record.annotations = decodeAnnotations(value)
        case "expect":
            record.isExpect = value == "1" || value == "true"
        case "actual":
            record.isActual = value == "1" || value == "true"
        case "recv":
            record.propertyReceiverTypeSignature = value.isEmpty ? nil : value
        case "getterLink":
            record.propertyGetterExternalLinkName = value.isEmpty ? nil : value
        case "getterAbiSig":
            record.propertyGetterAbiReturnTypeSignature = value.isEmpty ? nil : value
        case "mutable":
            record.isMutable = value == "1" || value == "true"
        case "const":
            record.constValueLiteral = value.isEmpty ? nil : value
        case "abiSig":
            record.abiReturnTypeSignature = value.isEmpty ? nil : value
        case "schema":
            record.schemaVersion = value
        default:
            break
        }
    }

    // MARK: - Annotation Decoding

    private func decodeAnnotations(_ value: String) -> [MetadataAnnotationRecord] {
        guard !value.isEmpty else {
            return []
        }
        return value.split(separator: ";", omittingEmptySubsequences: true).compactMap { entry in
            decodeAnnotation(String(entry))
        }
    }

    private func decodeAnnotation(_ entry: String) -> MetadataAnnotationRecord? {
        let parts = entry.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard let annotationFQName = parts.first, !annotationFQName.isEmpty else {
            return nil
        }
        var useSiteTarget: String?
        var arguments: [String] = []
        for part in parts.dropFirst() {
            if part.hasPrefix("target:") {
                useSiteTarget = String(part.dropFirst("target:".count))
            } else if part.hasPrefix("args:") {
                let argsStr = String(part.dropFirst("args:".count))
                arguments = argsStr.split(separator: ",", omittingEmptySubsequences: false).compactMap { b64 in
                    guard let data = Data(base64Encoded: String(b64)) else {
                        return nil
                    }
                    return String(data: data, encoding: .utf8)
                }
            }
        }
        return MetadataAnnotationRecord(
            annotationFQName: annotationFQName,
            arguments: arguments,
            useSiteTarget: useSiteTarget
        )
    }

    // MARK: - Symbol Kind Mapping

    func symbolKindFromMetadata(_ token: String) -> SymbolKind? {
        symbolKindFromMetadataToken(token)
    }
}

// MARK: - Inline KIR Filename Helpers

extension String {
    /// FNV-1a 64-bit hash used to derive a stable, filesystem-safe filename
    /// from an arbitrary mangled name.
    package var fnv1a64Hash: UInt64 {
        let offset: UInt64 = 14695981039346656037
        let prime: UInt64 = 1099511628211
        var hash = offset
        for byte in self.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }
        return hash
    }
}

extension MetadataEncoder {
    /// Returns the inline-KIR filename for a mangled symbol name.
    /// Short, filesystem-safe names are preserved; long or non-alphanumeric
    /// mangled names are hashed to avoid exceeding filesystem path limits.
    package static func inlineKIRFileName(for mangledName: String) -> String {
        let safePattern = "^[A-Za-z0-9_-]+$"
        let isSafe = mangledName.range(of: safePattern, options: .regularExpression) != nil
        if isSafe && mangledName.count <= 64 {
            return "\(mangledName).kirbin"
        }
        return "\(mangledName.fnv1a64Hash).kirbin"
    }
}
