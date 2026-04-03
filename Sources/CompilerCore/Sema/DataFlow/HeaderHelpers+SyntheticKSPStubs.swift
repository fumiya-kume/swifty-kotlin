extension DataFlowSemaPhase {
    func registerSyntheticKSPStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let processingPkg = ensurePackage(
            path: ["com", "google", "devtools", "ksp", "processing"],
            symbols: symbols,
            interner: interner
        )
        let packageSymbol = symbols.lookup(fqName: processingPkg)

        let symbolProcessorSymbol = ensureInterfaceSymbol(
            named: "SymbolProcessor",
            in: processingPkg,
            symbols: symbols,
            interner: interner
        )
        let loggerSymbol = ensureClassSymbol(
            named: "KSPLogger",
            in: processingPkg,
            symbols: symbols,
            interner: interner
        )
        let resolverSymbol = ensureClassSymbol(
            named: "Resolver",
            in: processingPkg,
            symbols: symbols,
            interner: interner
        )
        let codeGeneratorSymbol = ensureClassSymbol(
            named: "CodeGenerator",
            in: processingPkg,
            symbols: symbols,
            interner: interner
        )

        if let packageSymbol {
            for symbol in [symbolProcessorSymbol, loggerSymbol, resolverSymbol, codeGeneratorSymbol] {
                symbols.setParentSymbol(packageSymbol, for: symbol)
            }
        }

        let symbolProcessorType = types.make(.classType(ClassType(
            classSymbol: symbolProcessorSymbol,
            args: [],
            nullability: .nonNull
        )))
        let loggerType = types.make(.classType(ClassType(
            classSymbol: loggerSymbol,
            args: [],
            nullability: .nonNull
        )))
        let resolverType = types.make(.classType(ClassType(
            classSymbol: resolverSymbol,
            args: [],
            nullability: .nonNull
        )))
        let codeGeneratorType = types.make(.classType(ClassType(
            classSymbol: codeGeneratorSymbol,
            args: [],
            nullability: .nonNull
        )))
        let listOfStringType = makeKSPListType(
            symbols: symbols,
            types: types,
            interner: interner,
            elementType: types.stringType
        )

        for (symbol, type) in [
            (symbolProcessorSymbol, symbolProcessorType),
            (loggerSymbol, loggerType),
            (resolverSymbol, resolverType),
            (codeGeneratorSymbol, codeGeneratorType),
        ] {
            symbols.setPropertyType(type, for: symbol)
        }

        registerKSPMember(
            ownerSymbol: symbolProcessorSymbol,
            ownerType: symbolProcessorType,
            name: "process",
            parameters: [(name: "resolver", type: resolverType)],
            returnType: listOfStringType,
            externalLinkName: nil,
            symbols: symbols,
            interner: interner
        )

        registerKSPConstructor(
            ownerSymbol: loggerSymbol,
            ownerType: loggerType,
            parameters: [],
            externalLinkName: "kk_ksp_logger_new",
            symbols: symbols,
            interner: interner
        )
        registerKSPMember(
            ownerSymbol: loggerSymbol,
            ownerType: loggerType,
            name: "info",
            parameters: [(name: "message", type: types.stringType)],
            returnType: types.unitType,
            externalLinkName: "kk_ksp_logger_info",
            symbols: symbols,
            interner: interner
        )
        registerKSPMember(
            ownerSymbol: loggerSymbol,
            ownerType: loggerType,
            name: "warn",
            parameters: [(name: "message", type: types.stringType)],
            returnType: types.unitType,
            externalLinkName: "kk_ksp_logger_warn",
            symbols: symbols,
            interner: interner
        )
        registerKSPMember(
            ownerSymbol: loggerSymbol,
            ownerType: loggerType,
            name: "error",
            parameters: [(name: "message", type: types.stringType)],
            returnType: types.unitType,
            externalLinkName: "kk_ksp_logger_error",
            symbols: symbols,
            interner: interner
        )
        registerKSPMember(
            ownerSymbol: loggerSymbol,
            ownerType: loggerType,
            name: "messages",
            parameters: [],
            returnType: listOfStringType,
            externalLinkName: "kk_ksp_logger_messages",
            symbols: symbols,
            interner: interner
        )

        registerKSPConstructor(
            ownerSymbol: resolverSymbol,
            ownerType: resolverType,
            parameters: [],
            externalLinkName: "kk_ksp_resolver_new",
            symbols: symbols,
            interner: interner
        )
        registerKSPMember(
            ownerSymbol: resolverSymbol,
            ownerType: resolverType,
            name: "addFile",
            parameters: [(name: "fileName", type: types.stringType)],
            returnType: types.unitType,
            externalLinkName: "kk_ksp_resolver_add_file",
            symbols: symbols,
            interner: interner
        )
        registerKSPMember(
            ownerSymbol: resolverSymbol,
            ownerType: resolverType,
            name: "addSymbol",
            parameters: [(name: "symbolName", type: types.stringType)],
            returnType: types.unitType,
            externalLinkName: "kk_ksp_resolver_add_symbol",
            symbols: symbols,
            interner: interner
        )
        registerKSPMember(
            ownerSymbol: resolverSymbol,
            ownerType: resolverType,
            name: "addAnnotatedSymbol",
            parameters: [
                (name: "annotationName", type: types.stringType),
                (name: "symbolName", type: types.stringType),
            ],
            returnType: types.unitType,
            externalLinkName: "kk_ksp_resolver_add_annotated_symbol",
            symbols: symbols,
            interner: interner
        )
        registerKSPMember(
            ownerSymbol: resolverSymbol,
            ownerType: resolverType,
            name: "getAllFiles",
            parameters: [],
            returnType: listOfStringType,
            externalLinkName: "kk_ksp_resolver_get_all_files",
            symbols: symbols,
            interner: interner
        )
        registerKSPMember(
            ownerSymbol: resolverSymbol,
            ownerType: resolverType,
            name: "getAllSymbols",
            parameters: [],
            returnType: listOfStringType,
            externalLinkName: "kk_ksp_resolver_get_all_symbols",
            symbols: symbols,
            interner: interner
        )
        registerKSPMember(
            ownerSymbol: resolverSymbol,
            ownerType: resolverType,
            name: "getSymbolsWithAnnotation",
            parameters: [(name: "annotationName", type: types.stringType)],
            returnType: listOfStringType,
            externalLinkName: "kk_ksp_resolver_get_symbols_with_annotation",
            symbols: symbols,
            interner: interner
        )

        registerKSPConstructor(
            ownerSymbol: codeGeneratorSymbol,
            ownerType: codeGeneratorType,
            parameters: [],
            externalLinkName: "kk_ksp_codegen_new",
            symbols: symbols,
            interner: interner
        )
        registerKSPMember(
            ownerSymbol: codeGeneratorSymbol,
            ownerType: codeGeneratorType,
            name: "createFile",
            parameters: [
                (name: "packageName", type: types.stringType),
                (name: "fileName", type: types.stringType),
                (name: "contents", type: types.stringType),
            ],
            returnType: types.unitType,
            externalLinkName: "kk_ksp_codegen_create_file",
            symbols: symbols,
            interner: interner
        )
        registerKSPMember(
            ownerSymbol: codeGeneratorSymbol,
            ownerType: codeGeneratorType,
            name: "generatedFiles",
            parameters: [],
            returnType: listOfStringType,
            externalLinkName: "kk_ksp_codegen_generated_files",
            symbols: symbols,
            interner: interner
        )

        registerKSPTopLevelFunction(
            named: "registerProcessor",
            packageFQName: processingPkg,
            parameters: [(name: "name", type: types.stringType)],
            returnType: types.unitType,
            externalLinkName: "kk_ksp_register_processor",
            symbols: symbols,
            interner: interner
        )
        registerKSPTopLevelFunction(
            named: "registeredProcessors",
            packageFQName: processingPkg,
            parameters: [],
            returnType: listOfStringType,
            externalLinkName: "kk_ksp_registered_processors",
            symbols: symbols,
            interner: interner
        )
        registerKSPTopLevelFunction(
            named: "runProcessors",
            packageFQName: processingPkg,
            parameters: [
                (name: "logger", type: loggerType),
                (name: "resolver", type: resolverType),
                (name: "codeGenerator", type: codeGeneratorType),
            ],
            returnType: listOfStringType,
            externalLinkName: "kk_ksp_run_processors",
            symbols: symbols,
            interner: interner
        )
    }

    private func registerKSPTopLevelFunction(
        named name: String,
        packageFQName: [InternedString],
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        externalLinkName: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let functionName = interner.intern(name)
        let functionFQName = packageFQName + [functionName]
        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.parameterTypes == parameters.map(\.type)
                && signature.returnType == returnType
        }) {
            symbols.setExternalLinkName(externalLinkName, for: existing)
            return
        }

        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }
        symbols.setExternalLinkName(externalLinkName, for: functionSymbol)
        let valueParameterSymbols = defineKSPValueParameters(
            ownerFQName: functionFQName,
            ownerSymbol: functionSymbol,
            parameters: parameters,
            symbols: symbols,
            interner: interner
        )
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: parameters.map(\.type),
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
            ),
            for: functionSymbol
        )
    }

    private func registerKSPConstructor(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        parameters: [(name: String, type: TypeID)],
        externalLinkName: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else { return }
        let initName = interner.intern("<init>")
        let constructorFQName = ownerInfo.fqName + [initName]
        if let existing = symbols.lookupAll(fqName: constructorFQName).first(where: { symbolID in
            symbols.functionSignature(for: symbolID)?.parameterTypes == parameters.map(\.type)
        }) {
            symbols.setExternalLinkName(externalLinkName, for: existing)
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
        symbols.setExternalLinkName(externalLinkName, for: constructorSymbol)
        let valueParameterSymbols = defineKSPValueParameters(
            ownerFQName: constructorFQName,
            ownerSymbol: constructorSymbol,
            parameters: parameters,
            symbols: symbols,
            interner: interner
        )
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: parameters.map(\.type),
                returnType: ownerType,
                isSuspend: false,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
            ),
            for: constructorSymbol
        )
    }

    private func registerKSPMember(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        name: String,
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        externalLinkName: String?,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else { return }
        let functionName = interner.intern(name)
        let functionFQName = ownerInfo.fqName + [functionName]
        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == ownerType
                && signature.parameterTypes == parameters.map(\.type)
                && signature.returnType == returnType
        }) {
            if let externalLinkName {
                symbols.setExternalLinkName(externalLinkName, for: existing)
            }
            return
        }

        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: functionSymbol)
        if let externalLinkName {
            symbols.setExternalLinkName(externalLinkName, for: functionSymbol)
        }
        let valueParameterSymbols = defineKSPValueParameters(
            ownerFQName: functionFQName,
            ownerSymbol: functionSymbol,
            parameters: parameters,
            symbols: symbols,
            interner: interner
        )
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: ownerType,
                parameterTypes: parameters.map(\.type),
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
            ),
            for: functionSymbol
        )
    }

    private func defineKSPValueParameters(
        ownerFQName: [InternedString],
        ownerSymbol: SymbolID,
        parameters: [(name: String, type: TypeID)],
        symbols: SymbolTable,
        interner: StringInterner
    ) -> [SymbolID] {
        var valueParameterSymbols: [SymbolID] = []
        for parameter in parameters {
            let parameterName = interner.intern(parameter.name)
            let parameterSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: ownerFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(ownerSymbol, for: parameterSymbol)
            valueParameterSymbols.append(parameterSymbol)
        }
        return valueParameterSymbols
    }

    private func makeKSPListType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        elementType: TypeID
    ) -> TypeID {
        let listFQName = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("List"),
        ]
        guard let listSymbol = symbols.lookup(fqName: listFQName) else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: listSymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))
    }
}
