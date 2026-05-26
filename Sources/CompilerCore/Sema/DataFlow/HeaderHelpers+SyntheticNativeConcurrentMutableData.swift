import Foundation

/// Synthetic stdlib stubs for `kotlin.native.concurrent`: MutableData class with append/copyInto/withBufferLocked/withPointerLocked.
///
/// Split out from `HeaderHelpers+SyntheticNativeConcurrentStubs.swift` to isolate
/// merge conflicts between parallel stdlib PRs adding new entries to this package.
extension DataFlowSemaPhase {

    // MARK: - MutableData

    func registerNativeConcurrentMutableData(
        packageFQName: [InternedString],
        pkgSymbol: SymbolID?,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let className = interner.intern("MutableData")
        let classFQName = packageFQName + [className]

        let classSymbol: SymbolID
        if let existing = symbols.lookup(fqName: classFQName), symbols.symbol(existing)?.kind == .class {
            classSymbol = existing
        } else {
            classSymbol = symbols.define(
                kind: .class,
                name: className,
                fqName: classFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        if let pkgSymbol {
            symbols.setParentSymbol(pkgSymbol, for: classSymbol)
        }

        let classType = types.make(.classType(ClassType(
            classSymbol: classSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(classType, for: classSymbol)
        appendNativeConcurrentMetadataAnnotations(
            [
                MetadataAnnotationRecord(
                    annotationFQName: "kotlin.Deprecated",
                    arguments: [
                        "message = \"Support for the legacy memory manager has been completely removed. Use any regular collection instead.\"",
                        "level = DeprecationLevel.ERROR",
                    ]
                ),
            ],
            to: classSymbol,
            symbols: symbols
        )

        let byteArrayType = nativeConcurrentClassType(
            packagePath: ["kotlin"],
            name: "ByteArray",
            symbols: symbols,
            types: types,
            interner: interner
        )
        let cOpaquePointerType = nativeConcurrentCOpaquePointerType(
            symbols: symbols,
            types: types,
            interner: interner
        )
        let nullableCOpaquePointerType = types.makeNullable(cOpaquePointerType)

        registerNativeConcurrentConstructor(
            ownerSymbol: classSymbol,
            ownerType: classType,
            parameters: [(name: "capacity", type: types.intType)],
            defaultValues: [true],
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentReadOnlyProperty(
            ownerSymbol: classSymbol,
            name: "size",
            propertyType: types.intType,
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentMemberFunction(
            ownerSymbol: classSymbol,
            ownerType: classType,
            name: "append",
            returnType: types.unitType,
            parameters: [(name: "data", type: classType)],
            defaultValues: [false],
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentMemberFunction(
            ownerSymbol: classSymbol,
            ownerType: classType,
            name: "append",
            returnType: types.unitType,
            parameters: [
                (name: "data", type: nullableCOpaquePointerType),
                (name: "count", type: types.intType),
            ],
            defaultValues: [false, false],
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentMemberFunction(
            ownerSymbol: classSymbol,
            ownerType: classType,
            name: "append",
            returnType: types.unitType,
            parameters: [
                (name: "data", type: byteArrayType),
                (name: "fromIndex", type: types.intType),
                (name: "toIndex", type: types.intType),
            ],
            defaultValues: [false, true, true],
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentMemberFunction(
            ownerSymbol: classSymbol,
            ownerType: classType,
            name: "copyInto",
            returnType: types.unitType,
            parameters: [
                (name: "output", type: byteArrayType),
                (name: "destinationIndex", type: types.intType),
                (name: "startIndex", type: types.intType),
                (name: "endIndex", type: types.intType),
            ],
            defaultValues: [false, false, false, false],
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentMemberFunction(
            ownerSymbol: classSymbol,
            ownerType: classType,
            name: "get",
            returnType: types.intType,
            parameters: [(name: "index", type: types.intType)],
            defaultValues: [false],
            flags: [.synthetic, .operatorFunction],
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentMemberFunction(
            ownerSymbol: classSymbol,
            ownerType: classType,
            name: "reset",
            returnType: types.unitType,
            parameters: [],
            defaultValues: [],
            symbols: symbols,
            interner: interner
        )

        registerNativeConcurrentMutableDataLockedMember(
            ownerSymbol: classSymbol,
            ownerType: classType,
            ownerFQName: classFQName,
            name: "withBufferLocked",
            blockParameterTypes: [byteArrayType, types.intType],
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerNativeConcurrentMutableDataLockedMember(
            ownerSymbol: classSymbol,
            ownerType: classType,
            ownerFQName: classFQName,
            name: "withPointerLocked",
            blockParameterTypes: [cOpaquePointerType, types.intType],
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func registerNativeConcurrentMutableDataLockedMember(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        ownerFQName: [InternedString],
        name: String,
        blockParameterTypes: [TypeID],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let typeParameterSymbol = nativeConcurrentSyntheticTypeParameter(
            named: "R",
            ownerFQName: ownerFQName + [interner.intern(name)],
            symbols: symbols,
            interner: interner
        )
        let typeParameterType = types.make(.typeParam(TypeParamType(
            symbol: typeParameterSymbol,
            nullability: .nonNull
        )))
        let blockType = types.make(.functionType(FunctionType(
            params: blockParameterTypes,
            returnType: typeParameterType
        )))
        registerNativeConcurrentMemberFunction(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            name: name,
            returnType: typeParameterType,
            parameters: [(name: "block", type: blockType)],
            defaultValues: [false],
            typeParameterSymbols: [typeParameterSymbol],
            symbols: symbols,
            interner: interner
        )
    }
}
