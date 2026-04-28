/// Synthetic stdlib stubs for Closeable / AutoCloseable and the .use {} extension (STDLIB-520).
///
/// Kotlin defines:
///   interface Closeable { fun close(): Unit }
///   typealias AutoCloseable = Closeable          // on Kotlin/JVM they are identical
///   fun AutoCloseable(closeAction: () -> Unit): AutoCloseable
///   inline fun <T : AutoCloseable?, R> T.use(block: (T) -> R): R
///   inline fun <T : Closeable?, R> T.use(block: (T) -> R): R
///
/// The .use extension is inline-expanded by CallLowerer: no runtime call is needed.
extension DataFlowSemaPhase {
    func registerSyntheticCloseableStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        // Ensure "kotlin" and "kotlin.io" packages exist.
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
        let kotlinIOPkg: [InternedString] = [interner.intern("kotlin"), interner.intern("io")]
        if symbols.lookup(fqName: kotlinIOPkg) == nil {
            _ = symbols.define(
                kind: .package,
                name: interner.intern("io"),
                fqName: kotlinIOPkg,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }

        // --- Closeable interface ---
        let closeableName = interner.intern("Closeable")
        let closeableFQName = kotlinIOPkg + [closeableName]
        let closeableSymbol: SymbolID = if let existing = symbols.lookup(fqName: closeableFQName) {
            existing
        } else {
            symbols.define(
                kind: .interface,
                name: closeableName,
                fqName: closeableFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }

        // Store in TypeSystem so type checking can recognise Closeable receivers.
        types.closeableInterfaceSymbol = closeableSymbol

        let closeableType = types.make(.classType(ClassType(
            classSymbol: closeableSymbol, args: [], nullability: .nonNull
        )))
        types.closeableTypeID = closeableType

        // Register `fun close(): Unit` on Closeable.
        let closeName = interner.intern("close")
        let closeFQName = closeableFQName + [closeName]
        if symbols.lookup(fqName: closeFQName) == nil {
            let closeSymbol = symbols.define(
                kind: .function,
                name: closeName,
                fqName: closeFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(closeableSymbol, for: closeSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: closeableType,
                    parameterTypes: [],
                    returnType: types.unitType
                ),
                for: closeSymbol
            )
        }

        // --- AutoCloseable type alias (points to the same symbol) ---
        let autoCloseableName = interner.intern("AutoCloseable")
        let autoCloseableFQName = kotlinPkg + [autoCloseableName]
        if symbols.lookup(fqName: autoCloseableFQName) == nil {
            let aliasSymbol = symbols.define(
                kind: .typeAlias,
                name: autoCloseableName,
                fqName: autoCloseableFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setTypeAliasUnderlyingType(closeableType, for: aliasSymbol)
        }
        if symbols.lookupAll(fqName: autoCloseableFQName).allSatisfy({ symbols.symbol($0)?.kind != .function }) {
            let closeActionType = types.make(.functionType(FunctionType(
                params: [],
                returnType: types.unitType,
                isSuspend: false,
                nullability: .nonNull
            )))
            let closeActionParamName = interner.intern("closeAction")
            let closeActionParamSymbol = symbols.define(
                kind: .valueParameter,
                name: closeActionParamName,
                fqName: autoCloseableFQName + [closeActionParamName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            let factorySymbol = symbols.define(
                kind: .function,
                name: autoCloseableName,
                fqName: autoCloseableFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .inlineFunction]
            )
            if let packageSymbol = symbols.lookup(fqName: kotlinPkg) {
                symbols.setParentSymbol(packageSymbol, for: factorySymbol)
            }
            symbols.setParentSymbol(factorySymbol, for: closeActionParamSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: nil,
                    parameterTypes: [closeActionType],
                    returnType: closeableType,
                    isSuspend: false,
                    valueParameterSymbols: [closeActionParamSymbol],
                    valueParameterHasDefaultValues: [false],
                    valueParameterIsVararg: [false],
                    typeParameterSymbols: []
                ),
                for: factorySymbol
            )
            symbols.setExternalLinkName("kk_auto_closeable_create", for: factorySymbol)
        }

        // --- java.io.Closeable interface (mirrors kotlin.io.Closeable) ---
        // On Kotlin/JVM java.io.Closeable is the canonical type; kswiftc maps it
        // to the synthetic kotlin.io.Closeable so that `import java.io.Closeable`
        // works in user code.
        let javaPkg: [InternedString] = [interner.intern("java")]
        if symbols.lookup(fqName: javaPkg) == nil {
            _ = symbols.define(
                kind: .package,
                name: interner.intern("java"),
                fqName: javaPkg,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        let javaIOPkg: [InternedString] = javaPkg + [interner.intern("io")]
        if symbols.lookup(fqName: javaIOPkg) == nil {
            _ = symbols.define(
                kind: .package,
                name: interner.intern("io"),
                fqName: javaIOPkg,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        let javaCloseableFQName = javaIOPkg + [closeableName]
        if symbols.lookup(fqName: javaCloseableFQName) == nil {
            let javaCloseableSymbol = symbols.define(
                kind: .interface,
                name: closeableName,
                fqName: javaCloseableFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            // Register java.io.Closeable → kotlin.io.Closeable supertype chain
            // so that isNominalSubtypeSymbol traversal finds kotlin.io.Closeable.
            symbols.setDirectSupertypes([closeableSymbol], for: javaCloseableSymbol)
            types.setNominalDirectSupertypes([closeableSymbol], for: javaCloseableSymbol)
        }

        // --- T.use(block: (T) -> R): R ---
        // Kotlin 2.0 common exposes `kotlin.use` for AutoCloseable?, while
        // kotlin.io.use remains available for java.io.Closeable compatibility.
        let useName = interner.intern("use")
        let nullableCloseableType = types.makeNullable(closeableType)

        func registerUseFunction(in packageFQName: [InternedString]) {
            let useFQName = packageFQName + [useName]
            if symbols.lookup(fqName: useFQName) != nil {
                return
            }

            let tName = interner.intern("T")
            let rName = interner.intern("R")
            let tFQName = useFQName + [tName]
            let rFQName = useFQName + [rName]

            let tSymbol = symbols.define(
                kind: .typeParameter,
                name: tName,
                fqName: tFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
            let rSymbol = symbols.define(
                kind: .typeParameter,
                name: rName,
                fqName: rFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )

            symbols.setTypeParameterUpperBounds([nullableCloseableType], for: tSymbol)

            let tType = types.make(.typeParam(TypeParamType(symbol: tSymbol, nullability: .nonNull)))
            let rType = types.make(.typeParam(TypeParamType(symbol: rSymbol, nullability: .nonNull)))

            let blockType = types.make(.functionType(FunctionType(
                params: [tType],
                returnType: rType,
                isSuspend: false,
                nullability: .nonNull
            )))

            let blockParamName = interner.intern("block")
            let blockParamSymbol = symbols.define(
                kind: .valueParameter,
                name: blockParamName,
                fqName: useFQName + [blockParamName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )

            let useSymbol = symbols.define(
                kind: .function,
                name: useName,
                fqName: useFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .inlineFunction]
            )
            if let packageSymbol = symbols.lookup(fqName: packageFQName) {
                symbols.setParentSymbol(packageSymbol, for: useSymbol)
            }
            symbols.setParentSymbol(useSymbol, for: tSymbol)
            symbols.setParentSymbol(useSymbol, for: rSymbol)
            symbols.setParentSymbol(useSymbol, for: blockParamSymbol)

            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: tType,
                    parameterTypes: [blockType],
                    returnType: rType,
                    isSuspend: false,
                    valueParameterSymbols: [blockParamSymbol],
                    valueParameterHasDefaultValues: [false],
                    valueParameterIsVararg: [false],
                    typeParameterSymbols: [tSymbol, rSymbol],
                    typeParameterUpperBoundsList: [[nullableCloseableType], []],
                    classTypeParameterCount: 0
                ),
                for: useSymbol
            )
        }

        registerUseFunction(in: kotlinPkg)
        registerUseFunction(in: kotlinIOPkg)
    }
}
