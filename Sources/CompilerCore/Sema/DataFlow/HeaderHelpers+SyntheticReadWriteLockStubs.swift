import Foundation

/// Synthetic stdlib stubs for java.util.concurrent.locks.ReentrantReadWriteLock
/// and kotlin.concurrent.read (STDLIB-CONC-001).
extension DataFlowSemaPhase {
    func registerSyntheticReadWriteLockStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let javaLocksPkg = ensurePackage(
            path: ["java", "util", "concurrent", "locks"],
            symbols: symbols,
            interner: interner
        )
        let javaLocksPkgSymbol = symbols.lookup(fqName: javaLocksPkg)
        let kotlinConcurrentPkg = ensurePackage(
            path: ["kotlin", "concurrent"],
            symbols: symbols,
            interner: interner
        )
        let kotlinConcurrentPkgSymbol = symbols.lookup(fqName: kotlinConcurrentPkg)

        let readWriteLockSymbol = ensureClassSymbol(
            named: "ReentrantReadWriteLock",
            in: javaLocksPkg,
            symbols: symbols,
            interner: interner
        )
        if let javaLocksPkgSymbol {
            symbols.setParentSymbol(javaLocksPkgSymbol, for: readWriteLockSymbol)
        }

        let readWriteLockType = types.make(.classType(ClassType(
            classSymbol: readWriteLockSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(readWriteLockType, for: readWriteLockSymbol)

        registerReadWriteLockConstructor(
            ownerSymbol: readWriteLockSymbol,
            ownerType: readWriteLockType,
            externalLinkName: "kk_reentrant_read_write_lock_new",
            symbols: symbols,
            interner: interner
        )
        registerReadWriteLockReadExtension(
            ownerSymbol: readWriteLockSymbol,
            ownerType: readWriteLockType,
            packageFQName: kotlinConcurrentPkg,
            packageSymbol: kotlinConcurrentPkgSymbol,
            symbols: symbols,
            interner: interner,
            types: types
        )
    }

    private func registerReadWriteLockConstructor(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        externalLinkName: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let initName = interner.intern("<init>")
        let ctorFQName = ownerInfo.fqName + [initName]
        if let existing = symbols.lookupAll(fqName: ctorFQName).first(where: { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.parameterTypes.isEmpty && signature.returnType == ownerType
        }) {
            symbols.setExternalLinkName(externalLinkName, for: existing)
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

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [],
                returnType: ownerType,
                valueParameterSymbols: [],
                valueParameterHasDefaultValues: [],
                valueParameterIsVararg: []
            ),
            for: ctorSymbol
        )
    }

    private func registerReadWriteLockReadExtension(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        packageFQName: [InternedString],
        packageSymbol: SymbolID?,
        symbols: SymbolTable,
        interner: StringInterner,
        types: TypeSystem
    ) {
        guard symbols.symbol(ownerSymbol) != nil else {
            return
        }

        let functionName = interner.intern("read")
        let functionFQName = packageFQName + [functionName]

        let typeParamName = interner.intern("T")
        let typeParamFQName = functionFQName + [typeParamName]
        let actionParamName = interner.intern("action")

        let typeParamSymbol: SymbolID
        let tType: TypeID
        let actionType: TypeID
        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            guard let receiverType = signature.receiverType,
                  receiverType == ownerType,
                  signature.parameterTypes.count == 1,
                  signature.typeParameterSymbols.count == 1
            else {
                return false
            }
            guard let existingTypeParam = signature.typeParameterSymbols.first else {
                return false
            }
            let existingTType = types.make(.typeParam(TypeParamType(
                symbol: existingTypeParam,
                nullability: .nonNull
            )))
            let existingActionType = types.make(.functionType(FunctionType(
                params: [],
                returnType: existingTType,
                isSuspend: false,
                nullability: .nonNull
            )))
            return signature.parameterTypes == [existingActionType] &&
                signature.returnType == existingTType
        }) {
            symbols.setExternalLinkName("kk_reentrant_read_write_lock_read", for: existing)
            return
        }

        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .inlineFunction, .throwingFunction]
        )
        if let packageSymbol {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }
        symbols.setExternalLinkName("kk_reentrant_read_write_lock_read", for: functionSymbol)

        typeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: typeParamName,
            fqName: typeParamFQName,
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(functionSymbol, for: typeParamSymbol)

        tType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        actionType = types.make(.functionType(FunctionType(
            params: [],
            returnType: tType,
            isSuspend: false,
            nullability: .nonNull
        )))

        let actionSymbol = symbols.define(
            kind: .valueParameter,
            name: actionParamName,
            fqName: functionFQName + [actionParamName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(functionSymbol, for: actionSymbol)

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: ownerType,
                parameterTypes: [actionType],
                returnType: tType,
                isSuspend: false,
                valueParameterSymbols: [actionSymbol],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [false],
                typeParameterSymbols: [typeParamSymbol],
                classTypeParameterCount: 0
            ),
            for: functionSymbol
        )
    }
}
