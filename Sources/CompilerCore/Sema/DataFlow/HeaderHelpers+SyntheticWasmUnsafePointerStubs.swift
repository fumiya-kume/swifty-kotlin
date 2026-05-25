import Foundation

/// Synthetic `kotlin.wasm.unsafe.Pointer` surface.
extension DataFlowSemaPhase {
    func registerSyntheticWasmUnsafePointerStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let wasmUnsafePkg = ensurePackage(
            path: ["kotlin", "wasm", "unsafe"],
            symbols: symbols,
            interner: interner
        )
        let wasmUnsafePkgSymbol = symbols.lookup(fqName: wasmUnsafePkg)

        let pointerSymbol = ensureClassSymbol(
            named: "Pointer",
            in: wasmUnsafePkg,
            symbols: symbols,
            interner: interner
        )
        symbols.insertFlags([.synthetic, .valueType], for: pointerSymbol)
        symbols.setValueClassUnderlyingType(types.uintType, for: pointerSymbol)
        if let wasmUnsafePkgSymbol {
            symbols.setParentSymbol(wasmUnsafePkgSymbol, for: pointerSymbol)
        }

        let pointerType = types.make(.classType(ClassType(
            classSymbol: pointerSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(pointerType, for: pointerSymbol)

        registerWasmUnsafePointerAddressProperty(
            ownerSymbol: pointerSymbol,
            propertyType: types.uintType,
            symbols: symbols,
            interner: interner
        )
        registerWasmUnsafePointerConstructor(
            ownerSymbol: pointerSymbol,
            ownerType: pointerType,
            addressType: types.uintType,
            symbols: symbols,
            interner: interner
        )
        registerWasmUnsafePointerLoadMembers(
            ownerSymbol: pointerSymbol,
            ownerType: pointerType,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerWasmUnsafePointerStoreMembers(
            ownerSymbol: pointerSymbol,
            ownerType: pointerType,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerWasmUnsafePointerArithmeticMembers(
            ownerSymbol: pointerSymbol,
            ownerType: pointerType,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func registerWasmUnsafePointerAddressProperty(
        ownerSymbol: SymbolID,
        propertyType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let propertyName = interner.intern("address")
        let propertyFQName = ownerInfo.fqName + [propertyName]
        if let existing = symbols.lookupAll(fqName: propertyFQName).first(where: { symbolID in
            symbols.symbol(symbolID)?.kind == .property
        }) {
            symbols.setPropertyType(propertyType, for: existing)
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
    }

    private func registerWasmUnsafePointerConstructor(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        addressType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let initName = interner.intern("<init>")
        let constructorFQName = ownerInfo.fqName + [initName]
        if symbols.lookupAll(fqName: constructorFQName).contains(where: { symbolID in
            guard symbols.symbol(symbolID)?.kind == .constructor,
                  let signature = symbols.functionSignature(for: symbolID)
            else {
                return false
            }
            return signature.parameterTypes == [addressType]
        }) {
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

        let addressName = interner.intern("address")
        let addressParameter = symbols.define(
            kind: .valueParameter,
            name: addressName,
            fqName: constructorFQName + [addressName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(constructorSymbol, for: addressParameter)
        symbols.setPropertyType(addressType, for: addressParameter)

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: nil,
                parameterTypes: [addressType],
                returnType: ownerType,
                valueParameterSymbols: [addressParameter],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [false]
            ),
            for: constructorSymbol
        )
    }

    private func registerWasmUnsafePointerLoadMembers(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let loads: [(name: String, returnType: TypeID)] = [
            ("loadByte", types.intType),
            ("loadShort", types.intType),
            ("loadInt", types.intType),
            ("loadLong", types.longType),
        ]
        for load in loads {
            registerWasmUnsafePointerMemberFunction(
                named: load.name,
                ownerSymbol: ownerSymbol,
                ownerType: ownerType,
                parameters: [],
                returnType: load.returnType,
                symbols: symbols,
                interner: interner
            )
        }
    }

    private func registerWasmUnsafePointerStoreMembers(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let stores: [(name: String, parameterType: TypeID)] = [
            ("storeByte", types.intType),
            ("storeShort", types.intType),
            ("storeInt", types.intType),
            ("storeLong", types.longType),
        ]
        for store in stores {
            registerWasmUnsafePointerMemberFunction(
                named: store.name,
                ownerSymbol: ownerSymbol,
                ownerType: ownerType,
                parameters: [(name: "value", type: store.parameterType)],
                returnType: types.unitType,
                symbols: symbols,
                interner: interner
            )
        }
    }

    private func registerWasmUnsafePointerArithmeticMembers(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let parameters: [(name: String, type: TypeID)] = [
            ("other", types.intType),
            ("other", types.uintType),
        ]
        for parameter in parameters {
            for name in ["plus", "minus"] {
                registerWasmUnsafePointerMemberFunction(
                    named: name,
                    ownerSymbol: ownerSymbol,
                    ownerType: ownerType,
                    parameters: [parameter],
                    returnType: ownerType,
                    isOperator: true,
                    symbols: symbols,
                    interner: interner
                )
            }
        }
    }

    private func registerWasmUnsafePointerMemberFunction(
        named name: String,
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        isOperator: Bool = false,
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
            guard symbols.symbol(symbolID)?.kind == .function,
                  let signature = symbols.functionSignature(for: symbolID)
            else {
                return false
            }
            return signature.receiverType == ownerType && signature.parameterTypes == parameterTypes
        }) {
            var flags: SymbolFlags = [.synthetic]
            if isOperator {
                flags.insert(.operatorFunction)
            }
            symbols.insertFlags(flags, for: existing)
            if let signature = symbols.functionSignature(for: existing),
               signature.returnType != returnType
            {
                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: signature.receiverType,
                        parameterTypes: signature.parameterTypes,
                        returnType: returnType,
                        isSuspend: signature.isSuspend,
                        valueParameterSymbols: signature.valueParameterSymbols,
                        valueParameterHasDefaultValues: signature.valueParameterHasDefaultValues,
                        valueParameterIsVararg: signature.valueParameterIsVararg,
                        typeParameterSymbols: signature.typeParameterSymbols,
                        classTypeParameterCount: signature.classTypeParameterCount
                    ),
                    for: existing
                )
            }
            return
        }

        var flags: SymbolFlags = [.synthetic]
        if isOperator {
            flags.insert(.operatorFunction)
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

        let parameterNamespaceFQName = functionFQName + [interner.intern("$\(functionSymbol.rawValue)")]
        let parameterSymbols = parameters.map { parameter in
            let parameterName = interner.intern(parameter.name)
            let parameterSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: parameterNamespaceFQName + [parameterName],
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
                receiverType: ownerType,
                parameterTypes: parameterTypes,
                returnType: returnType,
                valueParameterSymbols: parameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: parameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: parameterSymbols.count)
            ),
            for: functionSymbol
        )
    }
}
