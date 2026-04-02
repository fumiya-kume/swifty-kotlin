extension DataFlowSemaPhase {
    func registerSyntheticLoggingStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let loggingPkg = ensurePackage(path: ["java", "util", "logging"], symbols: symbols, interner: interner)
        let loggingPkgSymbol = symbols.lookup(fqName: loggingPkg)
        let loggerSymbol = ensureClassSymbol(named: "Logger", in: loggingPkg, symbols: symbols, interner: interner)
        let levelSymbol = ensureClassSymbol(named: "Level", in: loggingPkg, symbols: symbols, interner: interner)
        let consoleHandlerSymbol = ensureClassSymbol(named: "ConsoleHandler", in: loggingPkg, symbols: symbols, interner: interner)
        let fileHandlerSymbol = ensureClassSymbol(named: "FileHandler", in: loggingPkg, symbols: symbols, interner: interner)
        if let loggingPkgSymbol {
            for sym in [loggerSymbol, levelSymbol, consoleHandlerSymbol, fileHandlerSymbol] {
                symbols.setParentSymbol(loggingPkgSymbol, for: sym)
            }
        }
        let loggerType = types.make(.classType(ClassType(classSymbol: loggerSymbol, args: [], nullability: .nonNull)))
        let levelType = types.make(.classType(ClassType(classSymbol: levelSymbol, args: [], nullability: .nonNull)))
        let consoleHandlerType = types.make(.classType(ClassType(classSymbol: consoleHandlerSymbol, args: [], nullability: .nonNull)))
        let fileHandlerType = types.make(.classType(ClassType(classSymbol: fileHandlerSymbol, args: [], nullability: .nonNull)))
        let throwableFQName = [interner.intern("kotlin"), interner.intern("Throwable")]
        let throwableType = symbols.lookup(fqName: throwableFQName).map {
            types.make(.classType(ClassType(classSymbol: $0, args: [], nullability: .nonNull)))
        } ?? types.anyType
        for (sym, type) in [(loggerSymbol, loggerType), (levelSymbol, levelType), (consoleHandlerSymbol, consoleHandlerType), (fileHandlerSymbol, fileHandlerType)] {
            symbols.setPropertyType(type, for: sym)
        }

        registerLoggingTopLevel(packageFQName: loggingPkg, name: "getLogger", parameterTypes: [types.stringType], returnType: loggerType, externalLinkName: "kk_logger_getLogger", symbols: symbols, interner: interner)
        for (name, link) in [
            ("SEVERE", "kk_logging_level_severe"),
            ("WARNING", "kk_logging_level_warning"),
            ("INFO", "kk_logging_level_info"),
            ("CONFIG", "kk_logging_level_config"),
            ("FINE", "kk_logging_level_fine"),
            ("FINER", "kk_logging_level_finer"),
            ("FINEST", "kk_logging_level_finest"),
        ] {
            let fq = loggingPkg + [interner.intern(name)]
            guard symbols.lookup(fqName: fq) == nil else { continue }
            let prop = symbols.define(kind: .property, name: interner.intern(name), fqName: fq, declSite: nil, visibility: .public, flags: [.synthetic, .static])
            symbols.setParentSymbol(levelSymbol, for: prop)
            symbols.setExternalLinkName(link, for: prop)
            symbols.setPropertyType(levelType, for: prop)
        }
        registerLoggingCtor(ownerSymbol: consoleHandlerSymbol, ownerType: consoleHandlerType, parameterTypes: [], externalLinkName: "kk_console_handler_new", symbols: symbols, interner: interner)
        registerLoggingCtor(ownerSymbol: fileHandlerSymbol, ownerType: fileHandlerType, parameterTypes: [types.stringType], externalLinkName: "kk_file_handler_new", symbols: symbols, interner: interner)
        registerLoggingMember(ownerSymbol: loggerSymbol, ownerType: loggerType, name: "addHandler", parameterTypes: [consoleHandlerType], returnType: types.unitType, externalLinkName: "kk_logger_addHandler", symbols: symbols, interner: interner)
        registerLoggingMember(ownerSymbol: loggerSymbol, ownerType: loggerType, name: "addHandler", parameterTypes: [fileHandlerType], returnType: types.unitType, externalLinkName: "kk_logger_addHandler", symbols: symbols, interner: interner)
        registerLoggingMember(ownerSymbol: loggerSymbol, ownerType: loggerType, name: "log", parameterTypes: [levelType, types.stringType], returnType: types.unitType, externalLinkName: "kk_logger_log", symbols: symbols, interner: interner)
        registerLoggingMember(ownerSymbol: loggerSymbol, ownerType: loggerType, name: "log", parameterTypes: [levelType, types.stringType, throwableType], returnType: types.unitType, externalLinkName: "kk_logger_log_throwable", symbols: symbols, interner: interner)
        registerLoggingMember(ownerSymbol: loggerSymbol, ownerType: loggerType, name: "info", parameterTypes: [types.stringType], returnType: types.unitType, externalLinkName: "kk_logger_info", symbols: symbols, interner: interner)
        registerLoggingMember(ownerSymbol: loggerSymbol, ownerType: loggerType, name: "warning", parameterTypes: [types.stringType], returnType: types.unitType, externalLinkName: "kk_logger_warning", symbols: symbols, interner: interner)
        registerLoggingMember(ownerSymbol: loggerSymbol, ownerType: loggerType, name: "severe", parameterTypes: [types.stringType], returnType: types.unitType, externalLinkName: "kk_logger_severe", symbols: symbols, interner: interner)
    }

    private func registerLoggingTopLevel(packageFQName: [InternedString], name: String, parameterTypes: [TypeID], returnType: TypeID, externalLinkName: String, symbols: SymbolTable, interner: StringInterner) {
        let fn = interner.intern(name)
        let fq = packageFQName + [fn]
        guard symbols.lookupAll(fqName: fq).isEmpty else { return }
        let sym = symbols.define(kind: .function, name: fn, fqName: fq, declSite: nil, visibility: .public, flags: [.synthetic])
        if let pkg = symbols.lookup(fqName: packageFQName) { symbols.setParentSymbol(pkg, for: sym) }
        symbols.setExternalLinkName(externalLinkName, for: sym)
        symbols.setFunctionSignature(FunctionSignature(parameterTypes: parameterTypes, returnType: returnType, valueParameterSymbols: [], valueParameterHasDefaultValues: [], valueParameterIsVararg: []), for: sym)
    }

    private func registerLoggingCtor(ownerSymbol: SymbolID, ownerType: TypeID, parameterTypes: [TypeID], externalLinkName: String, symbols: SymbolTable, interner: StringInterner) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else { return }
        let initName = interner.intern("<init>")
        let fq = ownerInfo.fqName + [initName]
        let ctor = symbols.define(kind: .constructor, name: initName, fqName: fq, declSite: nil, visibility: .public, flags: [.synthetic])
        symbols.setParentSymbol(ownerSymbol, for: ctor)
        symbols.setExternalLinkName(externalLinkName, for: ctor)
        symbols.setFunctionSignature(FunctionSignature(parameterTypes: parameterTypes, returnType: ownerType, valueParameterSymbols: [], valueParameterHasDefaultValues: [], valueParameterIsVararg: []), for: ctor)
    }

    private func registerLoggingMember(ownerSymbol: SymbolID, ownerType: TypeID, name: String, parameterTypes: [TypeID], returnType: TypeID, externalLinkName: String, symbols: SymbolTable, interner: StringInterner) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else { return }
        let fn = interner.intern(name)
        let fq = ownerInfo.fqName + [fn]
        guard symbols.lookupAll(fqName: fq).first(where: { symbols.functionSignature(for: $0)?.parameterTypes == parameterTypes }) == nil else { return }
        let sym = symbols.define(kind: .function, name: fn, fqName: fq, declSite: nil, visibility: .public, flags: [.synthetic])
        symbols.setParentSymbol(ownerSymbol, for: sym)
        symbols.setExternalLinkName(externalLinkName, for: sym)
        symbols.setFunctionSignature(FunctionSignature(receiverType: ownerType, parameterTypes: parameterTypes, returnType: returnType, valueParameterSymbols: [], valueParameterHasDefaultValues: [], valueParameterIsVararg: []), for: sym)
    }
}
