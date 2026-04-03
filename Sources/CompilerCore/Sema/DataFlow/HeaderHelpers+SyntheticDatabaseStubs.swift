extension DataFlowSemaPhase {
    func registerSyntheticDatabaseStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let sqlPkg = ensurePackage(path: ["java", "sql"], symbols: symbols, interner: interner)
        let sqlPkgSymbol = symbols.lookup(fqName: sqlPkg)

        let stringType = types.stringType
        let intType = types.intType
        let boolType = types.booleanType
        let unitType = types.unitType

        let connectionSymbol = ensureClassSymbol(
            named: "Connection",
            in: sqlPkg,
            symbols: symbols,
            interner: interner
        )
        if let sqlPkgSymbol {
            symbols.setParentSymbol(sqlPkgSymbol, for: connectionSymbol)
        }
        let connectionType = types.make(.classType(ClassType(
            classSymbol: connectionSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(connectionType, for: connectionSymbol)

        let savepointSymbol = ensureClassSymbol(
            named: "Savepoint",
            in: sqlPkg,
            symbols: symbols,
            interner: interner
        )
        if let sqlPkgSymbol {
            symbols.setParentSymbol(sqlPkgSymbol, for: savepointSymbol)
        }
        let savepointType = types.make(.classType(ClassType(
            classSymbol: savepointSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(savepointType, for: savepointSymbol)

        let driverManagerSymbol = ensureClassSymbol(
            named: "DriverManager",
            in: sqlPkg,
            symbols: symbols,
            interner: interner
        )
        if let sqlPkgSymbol {
            symbols.setParentSymbol(sqlPkgSymbol, for: driverManagerSymbol)
        }
        let driverManagerType = types.make(.classType(ClassType(
            classSymbol: driverManagerSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(driverManagerType, for: driverManagerSymbol)

        let connectionCompanionFQName = ensureDatabaseCompanionSymbol(
            ownerSymbol: connectionSymbol,
            symbols: symbols,
            interner: interner
        )
        registerDatabaseConstant(
            name: "TRANSACTION_READ_UNCOMMITTED",
            value: 1,
            ownerFQName: connectionCompanionFQName,
            ownerSymbol: connectionSymbol,
            intType: intType,
            symbols: symbols,
            interner: interner
        )
        registerDatabaseConstant(
            name: "TRANSACTION_READ_COMMITTED",
            value: 2,
            ownerFQName: connectionCompanionFQName,
            ownerSymbol: connectionSymbol,
            intType: intType,
            symbols: symbols,
            interner: interner
        )
        registerDatabaseConstant(
            name: "TRANSACTION_REPEATABLE_READ",
            value: 4,
            ownerFQName: connectionCompanionFQName,
            ownerSymbol: connectionSymbol,
            intType: intType,
            symbols: symbols,
            interner: interner
        )
        registerDatabaseConstant(
            name: "TRANSACTION_SERIALIZABLE",
            value: 8,
            ownerFQName: connectionCompanionFQName,
            ownerSymbol: connectionSymbol,
            intType: intType,
            symbols: symbols,
            interner: interner
        )

        let driverManagerCompanionFQName = ensureDatabaseCompanionSymbol(
            ownerSymbol: driverManagerSymbol,
            symbols: symbols,
            interner: interner
        )
        registerDatabaseCompanionMethod(
            name: "getConnection",
            externalLinkName: "kk_driver_manager_getConnection",
            companionFQName: driverManagerCompanionFQName,
            parameters: [("url", stringType)],
            returnType: connectionType,
            symbols: symbols,
            interner: interner
        )
        registerDatabaseStaticMethod(
            name: "getConnection",
            externalLinkName: "kk_driver_manager_getConnection",
            ownerSymbol: driverManagerSymbol,
            parameters: [("url", stringType)],
            returnType: connectionType,
            symbols: symbols,
            interner: interner
        )

        registerDatabaseMemberMethod(
            ownerSymbol: connectionSymbol,
            ownerType: connectionType,
            name: "getAutoCommit",
            externalLinkName: "kk_connection_getAutoCommit",
            parameters: [],
            returnType: boolType,
            symbols: symbols,
            interner: interner
        )
        registerDatabaseMemberMethod(
            ownerSymbol: connectionSymbol,
            ownerType: connectionType,
            name: "setAutoCommit",
            externalLinkName: "kk_connection_setAutoCommit",
            parameters: [("autoCommit", boolType)],
            returnType: unitType,
            symbols: symbols,
            interner: interner
        )
        registerDatabaseMemberMethod(
            ownerSymbol: connectionSymbol,
            ownerType: connectionType,
            name: "commit",
            externalLinkName: "kk_connection_commit",
            parameters: [],
            returnType: unitType,
            symbols: symbols,
            interner: interner
        )
        registerDatabaseMemberMethod(
            ownerSymbol: connectionSymbol,
            ownerType: connectionType,
            name: "rollback",
            externalLinkName: "kk_connection_rollback",
            parameters: [],
            returnType: unitType,
            symbols: symbols,
            interner: interner
        )
        registerDatabaseMemberMethod(
            ownerSymbol: connectionSymbol,
            ownerType: connectionType,
            name: "rollback",
            externalLinkName: "kk_connection_rollback_to_savepoint",
            parameters: [("savepoint", savepointType)],
            returnType: unitType,
            symbols: symbols,
            interner: interner
        )
        registerDatabaseMemberMethod(
            ownerSymbol: connectionSymbol,
            ownerType: connectionType,
            name: "setSavepoint",
            externalLinkName: "kk_connection_setSavepoint",
            parameters: [],
            returnType: savepointType,
            symbols: symbols,
            interner: interner
        )
        registerDatabaseMemberMethod(
            ownerSymbol: connectionSymbol,
            ownerType: connectionType,
            name: "setSavepoint",
            externalLinkName: "kk_connection_setSavepoint_named",
            parameters: [("name", stringType)],
            returnType: savepointType,
            symbols: symbols,
            interner: interner
        )
        registerDatabaseMemberMethod(
            ownerSymbol: connectionSymbol,
            ownerType: connectionType,
            name: "releaseSavepoint",
            externalLinkName: "kk_connection_releaseSavepoint",
            parameters: [("savepoint", savepointType)],
            returnType: unitType,
            symbols: symbols,
            interner: interner
        )
        registerDatabaseMemberMethod(
            ownerSymbol: connectionSymbol,
            ownerType: connectionType,
            name: "getTransactionIsolation",
            externalLinkName: "kk_connection_getTransactionIsolation",
            parameters: [],
            returnType: intType,
            symbols: symbols,
            interner: interner
        )
        registerDatabaseMemberMethod(
            ownerSymbol: connectionSymbol,
            ownerType: connectionType,
            name: "setTransactionIsolation",
            externalLinkName: "kk_connection_setTransactionIsolation",
            parameters: [("level", intType)],
            returnType: unitType,
            symbols: symbols,
            interner: interner
        )
        registerDatabaseMemberMethod(
            ownerSymbol: connectionSymbol,
            ownerType: connectionType,
            name: "close",
            externalLinkName: "kk_connection_close",
            parameters: [],
            returnType: unitType,
            symbols: symbols,
            interner: interner
        )
        registerDatabaseMemberMethod(
            ownerSymbol: connectionSymbol,
            ownerType: connectionType,
            name: "isClosed",
            externalLinkName: "kk_connection_isClosed",
            parameters: [],
            returnType: boolType,
            symbols: symbols,
            interner: interner
        )

        registerDatabaseMemberMethod(
            ownerSymbol: savepointSymbol,
            ownerType: savepointType,
            name: "getSavepointId",
            externalLinkName: "kk_savepoint_getSavepointId",
            parameters: [],
            returnType: intType,
            symbols: symbols,
            interner: interner
        )
        registerDatabaseMemberMethod(
            ownerSymbol: savepointSymbol,
            ownerType: savepointType,
            name: "getSavepointName",
            externalLinkName: "kk_savepoint_getSavepointName",
            parameters: [],
            returnType: stringType,
            symbols: symbols,
            interner: interner
        )
    }

    private func ensureDatabaseCompanionSymbol(
        ownerSymbol: SymbolID,
        symbols: SymbolTable,
        interner: StringInterner
    ) -> [InternedString] {
        if let existingCompanion = symbols.companionObjectSymbol(for: ownerSymbol),
           let companionInfo = symbols.symbol(existingCompanion)
        {
            return companionInfo.fqName
        }
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return []
        }
        let companionName = interner.intern("Companion")
        let companionFQName = ownerInfo.fqName + [companionName]
        let companionSymbol = symbols.define(
            kind: .object,
            name: companionName,
            fqName: companionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .static]
        )
        symbols.setParentSymbol(ownerSymbol, for: companionSymbol)
        symbols.setCompanionObjectSymbol(companionSymbol, for: ownerSymbol)
        return companionFQName
    }

    private func registerDatabaseConstant(
        name: String,
        value: Int,
        ownerFQName: [InternedString],
        ownerSymbol: SymbolID,
        intType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let constName = interner.intern(name)
        let constFQName = ownerFQName + [constName]
        guard symbols.lookupAll(fqName: constFQName).first(where: { symbols.symbol($0)?.kind == .property }) == nil else {
            return
        }
        let symbol = symbols.define(
            kind: .property,
            name: constName,
            fqName: constFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .constValue]
        )
        let parentSymbol = symbols.lookup(fqName: ownerFQName) ?? ownerSymbol
        symbols.setParentSymbol(parentSymbol, for: symbol)
        symbols.setPropertyType(intType, for: symbol)
        symbols.setConstValueExprKind(.intLiteral(Int64(value)), for: symbol)
    }

    private func registerDatabaseCompanionMethod(
        name: String,
        externalLinkName: String,
        companionFQName: [InternedString],
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let companionSymbol = symbols.lookup(fqName: companionFQName) else {
            return
        }
        registerDatabaseFunction(
            ownerSymbol: companionSymbol,
            ownerType: nil,
            flags: [.synthetic, .static],
            name: name,
            externalLinkName: externalLinkName,
            parameters: parameters,
            returnType: returnType,
            symbols: symbols,
            interner: interner
        )
    }

    private func registerDatabaseStaticMethod(
        name: String,
        externalLinkName: String,
        ownerSymbol: SymbolID,
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        registerDatabaseFunction(
            ownerSymbol: ownerSymbol,
            ownerType: nil,
            flags: [.synthetic, .static],
            name: name,
            externalLinkName: externalLinkName,
            parameters: parameters,
            returnType: returnType,
            symbols: symbols,
            interner: interner
        )
    }

    private func registerDatabaseMemberMethod(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        name: String,
        externalLinkName: String,
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        registerDatabaseFunction(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            flags: [.synthetic],
            name: name,
            externalLinkName: externalLinkName,
            parameters: parameters,
            returnType: returnType,
            symbols: symbols,
            interner: interner
        )
    }

    private func registerDatabaseFunction(
        ownerSymbol: SymbolID,
        ownerType: TypeID?,
        flags: SymbolFlags,
        name: String,
        externalLinkName: String,
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let functionName = interner.intern(name)
        let functionFQName = ownerInfo.fqName + [functionName]
        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let existingSignature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return existingSignature.receiverType == ownerType &&
                existingSignature.parameterTypes == parameters.map(\.type)
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
            flags: flags
        )
        symbols.setParentSymbol(ownerSymbol, for: functionSymbol)
        symbols.setExternalLinkName(externalLinkName, for: functionSymbol)

        var valueParameterSymbols: [SymbolID] = []
        for parameter in parameters {
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
            valueParameterSymbols.append(parameterSymbol)
        }

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
}
