/// Synthetic stubs for kotlin.Function0..N type hierarchy and the
/// `andThen`/`compose`/`curried` extension family used to register
/// the function-as-type surface.
///
/// Split out from `HeaderHelpers+SyntheticTODOAndIOStubs.swift` to keep
/// each header-helpers file scoped to a single responsibility.
extension DataFlowSemaPhase {
    func registerSyntheticFunctionTypes(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        // kotlin.Function パッケージ階層の確立
        let kotlinFunctionPkg = ensureSyntheticPackageHierarchy(
            fqName: [interner.intern("kotlin"), interner.intern("Function")],
            symbols: symbols
        )

        // Function0-22 のインターフェースを登録
        for arity in 0...22 {
            registerSyntheticFunctionInterface(
                arity: arity,
                packageFQName: kotlinFunctionPkg,
                symbols: symbols,
                types: types,
                interner: interner
            )
        }

        // 関数型の合成とカリー化拡張関数を登録
        registerSyntheticFunctionCompositionExtensions(
            packageFQName: kotlinFunctionPkg,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    func registerSyntheticFunctionInterface(
        arity: Int,
        packageFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let interfaceName = interner.intern("Function\(arity)")
        let interfaceFQName = packageFQName + [interfaceName]

        // 既に存在する場合はスキップ
        if symbols.lookup(fqName: interfaceFQName) != nil {
            return
        }

        let interfaceSymbol = symbols.define(
            kind: .interface,
            name: interfaceName,
            fqName: interfaceFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )

        // 型パラメータの定義
        var typeParamSymbols: [SymbolID] = []
        var typeParamTypes: [TypeID] = []

        // 戻り値型パラメータ R (out変位)
        let returnParamName = interner.intern("R")
        let returnParamFQName = interfaceFQName + [returnParamName]
        let returnParamSymbol = symbols.define(
            kind: .typeParameter,
            name: returnParamName,
            fqName: returnParamFQName,
            declSite: nil,
            visibility: .private,
            flags: []
        )
        typeParamSymbols.append(returnParamSymbol)
        typeParamTypes.append(types.make(.typeParam(TypeParamType(
            symbol: returnParamSymbol,
            nullability: .nonNull
        ))))

        // パラメータ型 P1-P22 (in変位)
        if arity > 0 {
            for i in 1...arity {
                let paramName = interner.intern("P\(i)")
                let paramFQName = interfaceFQName + [paramName]
                let paramSymbol = symbols.define(
                    kind: .typeParameter,
                    name: paramName,
                    fqName: paramFQName,
                    declSite: nil,
                    visibility: .private,
                    flags: []
                )
                typeParamSymbols.append(paramSymbol)
                typeParamTypes.append(types.make(.typeParam(TypeParamType(
                    symbol: paramSymbol,
                    nullability: .nonNull
                ))))
            }
        }

        // 型パラメータの変位指定を設定
        var variances: [TypeVariance] = [.out] // 戻り値はout
        if arity > 0 {
            for _ in 1...arity {
                variances.append(.in) // パラメータはin
            }
        }
        types.setNominalTypeParameterSymbols(typeParamSymbols, for: interfaceSymbol)
        types.setNominalTypeParameterVariances(variances, for: interfaceSymbol)

        // invokeメソッドの登録
        registerSyntheticFunctionInvokeMethod(
            ownerSymbol: interfaceSymbol,
            arity: arity,
            typeParamSymbols: typeParamSymbols,
            interfaceFQName: interfaceFQName,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    func registerSyntheticFunctionInvokeMethod(
        ownerSymbol: SymbolID,
        arity: Int,
        typeParamSymbols: [SymbolID],
        interfaceFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let invokeName = interner.intern("invoke")
        let invokeFQName = interfaceFQName + [invokeName]

        let invokeSymbol = symbols.define(
            kind: .function,
            name: invokeName,
            fqName: invokeFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .operatorFunction]
        )
        symbols.setParentSymbol(ownerSymbol, for: invokeSymbol)
        symbols.setExternalLinkName("kk_function_invoke", for: invokeSymbol)

        // パラメータ型の構築
        var parameterTypes: [TypeID] = []
        var parameterSymbols: [SymbolID] = []

        if arity > 0 {
            for i in 1...arity {
                let paramType = types.make(.typeParam(TypeParamType(
                    symbol: typeParamSymbols[i],
                    nullability: .nonNull
                )))
                parameterTypes.append(paramType)

                let paramName = interner.intern("p\(i)")
                let paramSymbol = symbols.define(
                    kind: .valueParameter,
                    name: paramName,
                    fqName: invokeFQName + [paramName],
                    declSite: nil,
                    visibility: .private,
                    flags: [.synthetic]
                )
                symbols.setParentSymbol(invokeSymbol, for: paramSymbol)
                parameterSymbols.append(paramSymbol)
            }
        }

        let returnType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbols[0], // R
            nullability: .nonNull
        )))

        // レシーバ型の構築
        let receiverType = types.make(.classType(ClassType(
            classSymbol: ownerSymbol,
            args: typeParamSymbols.enumerated().map { index, symbol in
                let variance: TypeVariance = index == 0 ? .out : .in
                let paramType = types.make(.typeParam(TypeParamType(
                    symbol: symbol,
                    nullability: .nonNull
                )))
                switch variance {
                case .out: return .out(paramType)
                case .in: return .in(paramType)
                case .invariant: return .invariant(paramType)
                }
            },
            nullability: .nonNull
        )))

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: parameterTypes,
                returnType: returnType,
                valueParameterSymbols: parameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: arity),
                valueParameterIsVararg: Array(repeating: false, count: arity),
                typeParameterSymbols: typeParamSymbols,
                classTypeParameterCount: typeParamSymbols.count
            ),
            for: invokeSymbol
        )
    }

    func registerSyntheticFunctionCompositionExtensions(
        packageFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        // Function1.andThen 拡張関数
        registerSyntheticFunctionAndThenExtension(
            packageFQName: packageFQName,
            symbols: symbols,
            types: types,
            interner: interner
        )

        // Function1.compose 拡張関数
        registerSyntheticFunctionComposeExtension(
            packageFQName: packageFQName,
            symbols: symbols,
            types: types,
            interner: interner
        )

        // Function2.curried 拡張関数
        registerSyntheticFunctionCurriedExtension(
            packageFQName: packageFQName,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    func registerSyntheticFunctionAndThenExtension(
        packageFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let function1Name = interner.intern("Function1")
        let function1FQName = packageFQName + [function1Name]
        guard let function1Symbol = symbols.lookup(fqName: function1FQName) else { return }

        let andThenName = interner.intern("andThen")
        let andThenFQName = function1FQName + [andThenName]

        let andThenSymbol = symbols.define(
            kind: .function,
            name: andThenName,
            fqName: andThenFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(function1Symbol, for: andThenSymbol)
        symbols.setExternalLinkName("kk_function_andThen", for: andThenSymbol)

        // 型パラメータの定義
        let tParamName = interner.intern("T")
        let rParamName = interner.intern("R")
        let newRParamName = interner.intern("NewR")

        let tParamSymbol = symbols.define(
            kind: .typeParameter,
            name: tParamName,
            fqName: andThenFQName + [tParamName],
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let rParamSymbol = symbols.define(
            kind: .typeParameter,
            name: rParamName,
            fqName: andThenFQName + [rParamName],
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let newRParamSymbol = symbols.define(
            kind: .typeParameter,
            name: newRParamName,
            fqName: andThenFQName + [newRParamName],
            declSite: nil,
            visibility: .private,
            flags: []
        )

        // パラメータ: g: (R) -> NewR
        let gFunctionType = types.make(.functionType(FunctionType(
            params: [types.make(.typeParam(TypeParamType(symbol: rParamSymbol, nullability: .nonNull)))],
            returnType: types.make(.typeParam(TypeParamType(symbol: newRParamSymbol, nullability: .nonNull)))
        )))

        let gParamSymbol = symbols.define(
            kind: .valueParameter,
            name: interner.intern("g"),
            fqName: andThenFQName + [interner.intern("g")],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(andThenSymbol, for: gParamSymbol)

        // 戻り値型: (T) -> NewR
        let returnType = types.make(.functionType(FunctionType(
            params: [types.make(.typeParam(TypeParamType(symbol: tParamSymbol, nullability: .nonNull)))],
            returnType: types.make(.typeParam(TypeParamType(symbol: newRParamSymbol, nullability: .nonNull)))
        )))

        // レシーバ型: (T) -> R
        let receiverType = types.make(.functionType(FunctionType(
            params: [types.make(.typeParam(TypeParamType(symbol: tParamSymbol, nullability: .nonNull)))],
            returnType: types.make(.typeParam(TypeParamType(symbol: rParamSymbol, nullability: .nonNull)))
        )))

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [gFunctionType],
                returnType: returnType,
                valueParameterSymbols: [gParamSymbol],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [false],
                typeParameterSymbols: [tParamSymbol, rParamSymbol, newRParamSymbol]
            ),
            for: andThenSymbol
        )
    }

    func registerSyntheticFunctionComposeExtension(
        packageFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let function1Name = interner.intern("Function1")
        let function1FQName = packageFQName + [function1Name]
        guard let function1Symbol = symbols.lookup(fqName: function1FQName) else { return }

        let composeName = interner.intern("compose")
        let composeFQName = function1FQName + [composeName]

        let composeSymbol = symbols.define(
            kind: .function,
            name: composeName,
            fqName: composeFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(function1Symbol, for: composeSymbol)
        symbols.setExternalLinkName("kk_function_compose", for: composeSymbol)

        // 型パラメータの定義
        let newTParamName = interner.intern("NewT")
        let tParamName = interner.intern("T")
        let rParamName = interner.intern("R")

        let newTParamSymbol = symbols.define(
            kind: .typeParameter,
            name: newTParamName,
            fqName: composeFQName + [newTParamName],
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let tParamSymbol = symbols.define(
            kind: .typeParameter,
            name: tParamName,
            fqName: composeFQName + [tParamName],
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let rParamSymbol = symbols.define(
            kind: .typeParameter,
            name: rParamName,
            fqName: composeFQName + [rParamName],
            declSite: nil,
            visibility: .private,
            flags: []
        )

        // パラメータ: g: (NewT) -> T
        let gFunctionType = types.make(.functionType(FunctionType(
            params: [types.make(.typeParam(TypeParamType(symbol: newTParamSymbol, nullability: .nonNull)))],
            returnType: types.make(.typeParam(TypeParamType(symbol: tParamSymbol, nullability: .nonNull)))
        )))

        let gParamSymbol = symbols.define(
            kind: .valueParameter,
            name: interner.intern("g"),
            fqName: composeFQName + [interner.intern("g")],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(composeSymbol, for: gParamSymbol)

        // 戻り値型: (NewT) -> R
        let returnType = types.make(.functionType(FunctionType(
            params: [types.make(.typeParam(TypeParamType(symbol: newTParamSymbol, nullability: .nonNull)))],
            returnType: types.make(.typeParam(TypeParamType(symbol: rParamSymbol, nullability: .nonNull)))
        )))

        // レシーバ型: (T) -> R
        let receiverType = types.make(.functionType(FunctionType(
            params: [types.make(.typeParam(TypeParamType(symbol: tParamSymbol, nullability: .nonNull)))],
            returnType: types.make(.typeParam(TypeParamType(symbol: rParamSymbol, nullability: .nonNull)))
        )))

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [gFunctionType],
                returnType: returnType,
                valueParameterSymbols: [gParamSymbol],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [false],
                typeParameterSymbols: [newTParamSymbol, tParamSymbol, rParamSymbol]
            ),
            for: composeSymbol
        )
    }

    func registerSyntheticFunctionCurriedExtension(
        packageFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let function2Name = interner.intern("Function2")
        let function2FQName = packageFQName + [function2Name]
        guard let function2Symbol = symbols.lookup(fqName: function2FQName) else { return }

        let curriedName = interner.intern("curried")
        let curriedFQName = function2FQName + [curriedName]

        let curriedSymbol = symbols.define(
            kind: .function,
            name: curriedName,
            fqName: curriedFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(function2Symbol, for: curriedSymbol)
        symbols.setExternalLinkName("kk_function_curried", for: curriedSymbol)

        // 型パラメータの定義
        let p1ParamName = interner.intern("P1")
        let p2ParamName = interner.intern("P2")
        let rParamName = interner.intern("R")

        let p1ParamSymbol = symbols.define(
            kind: .typeParameter,
            name: p1ParamName,
            fqName: curriedFQName + [p1ParamName],
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let p2ParamSymbol = symbols.define(
            kind: .typeParameter,
            name: p2ParamName,
            fqName: curriedFQName + [p2ParamName],
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let rParamSymbol = symbols.define(
            kind: .typeParameter,
            name: rParamName,
            fqName: curriedFQName + [rParamName],
            declSite: nil,
            visibility: .private,
            flags: []
        )

        // 戻り値型: (P1) -> (P2) -> R
        let innerFunctionType = types.make(.functionType(FunctionType(
            params: [types.make(.typeParam(TypeParamType(symbol: p2ParamSymbol, nullability: .nonNull)))],
            returnType: types.make(.typeParam(TypeParamType(symbol: rParamSymbol, nullability: .nonNull)))
        )))
        let returnType = types.make(.functionType(FunctionType(
            params: [types.make(.typeParam(TypeParamType(symbol: p1ParamSymbol, nullability: .nonNull)))],
            returnType: innerFunctionType
        )))

        // レシーバ型: (P1, P2) -> R
        let receiverType = types.make(.functionType(FunctionType(
            params: [
                types.make(.typeParam(TypeParamType(symbol: p1ParamSymbol, nullability: .nonNull))),
                types.make(.typeParam(TypeParamType(symbol: p2ParamSymbol, nullability: .nonNull)))
            ],
            returnType: types.make(.typeParam(TypeParamType(symbol: rParamSymbol, nullability: .nonNull)))
        )))

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [],
                returnType: returnType,
                valueParameterSymbols: [],
                valueParameterHasDefaultValues: [],
                valueParameterIsVararg: [],
                typeParameterSymbols: [p1ParamSymbol, p2ParamSymbol, rParamSymbol]
            ),
            for: curriedSymbol
        )
    }

    private func ensureSyntheticPackageHierarchy(
        fqName path: [InternedString],
        symbols: SymbolTable
    ) -> [InternedString] {
        var fqName: [InternedString] = []
        for part in path {
            fqName.append(part)
            if symbols.lookup(fqName: fqName) == nil {
                _ = symbols.define(
                    kind: .package,
                    name: part,
                    fqName: fqName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
            }
        }
        return fqName
    }
}
