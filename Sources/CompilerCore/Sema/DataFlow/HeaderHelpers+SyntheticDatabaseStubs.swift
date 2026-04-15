extension DataFlowSemaPhase {
    func registerSyntheticDatabaseStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let javaSQLPkg = ensurePackage(path: ["java", "sql"], symbols: symbols, interner: interner)
        let javaSQLPkgSymbol = symbols.lookup(fqName: javaSQLPkg)
        let javaIOCloseable = symbols.lookup(fqName: ensurePackage(path: ["java", "io"], symbols: symbols, interner: interner) + [interner.intern("Closeable")])

        let driverManagerSymbol = ensureDatabaseObjectSymbol(named: "DriverManager", in: javaSQLPkg, symbols: symbols, interner: interner)
        if let javaSQLPkgSymbol {
            symbols.setParentSymbol(javaSQLPkgSymbol, for: driverManagerSymbol)
        }
        let driverManagerType = types.make(.classType(ClassType(classSymbol: driverManagerSymbol, args: [], nullability: .nonNull)))
        symbols.setPropertyType(driverManagerType, for: driverManagerSymbol)

        let connectionSymbol = ensureClassSymbol(named: "Connection", in: javaSQLPkg, symbols: symbols, interner: interner)
        let statementSymbol = ensureClassSymbol(named: "Statement", in: javaSQLPkg, symbols: symbols, interner: interner)
        let preparedStatementSymbol = ensureClassSymbol(named: "PreparedStatement", in: javaSQLPkg, symbols: symbols, interner: interner)
        let resultSetSymbol = ensureClassSymbol(named: "ResultSet", in: javaSQLPkg, symbols: symbols, interner: interner)
        let savepointSymbol = ensureClassSymbol(named: "Savepoint", in: javaSQLPkg, symbols: symbols, interner: interner)

        for symbol in [connectionSymbol, statementSymbol, preparedStatementSymbol, resultSetSymbol, savepointSymbol] {
            if let javaSQLPkgSymbol {
                symbols.setParentSymbol(javaSQLPkgSymbol, for: symbol)
            }
        }

        let connectionType = types.make(.classType(ClassType(classSymbol: connectionSymbol, args: [], nullability: .nonNull)))
        let statementType = types.make(.classType(ClassType(classSymbol: statementSymbol, args: [], nullability: .nonNull)))
        let preparedStatementType = types.make(.classType(ClassType(classSymbol: preparedStatementSymbol, args: [], nullability: .nonNull)))
        let resultSetType = types.make(.classType(ClassType(classSymbol: resultSetSymbol, args: [], nullability: .nonNull)))
        let savepointType = types.make(.classType(ClassType(classSymbol: savepointSymbol, args: [], nullability: .nonNull)))

        if let closeableSymbol = javaIOCloseable {
            symbols.setDirectSupertypes([closeableSymbol], for: connectionSymbol)
            types.setNominalDirectSupertypes([closeableSymbol], for: connectionSymbol)
            symbols.setDirectSupertypes([closeableSymbol], for: statementSymbol)
            types.setNominalDirectSupertypes([closeableSymbol], for: statementSymbol)
            symbols.setDirectSupertypes([statementSymbol, closeableSymbol], for: preparedStatementSymbol)
            types.setNominalDirectSupertypes([statementSymbol, closeableSymbol], for: preparedStatementSymbol)
            symbols.setDirectSupertypes([closeableSymbol], for: resultSetSymbol)
            types.setNominalDirectSupertypes([closeableSymbol], for: resultSetSymbol)
        } else {
            symbols.setDirectSupertypes([statementSymbol], for: preparedStatementSymbol)
            types.setNominalDirectSupertypes([statementSymbol], for: preparedStatementSymbol)
        }

        registerInstanceFunction(
            ownerSymbol: driverManagerSymbol,
            ownerType: driverManagerType,
            parameters: [("url", types.stringType)],
            returnType: connectionType,
            externalLinkName: "kk_jdbc_driver_manager_getConnection",
            named: "getConnection",
            symbols: symbols,
            interner: interner
        )

        registerInstanceFunction(
            ownerSymbol: connectionSymbol,
            ownerType: connectionType,
            parameters: [],
            returnType: statementType,
            externalLinkName: "kk_jdbc_connection_createStatement",
            named: "createStatement",
            symbols: symbols,
            interner: interner
        )
        registerInstanceFunction(
            ownerSymbol: connectionSymbol,
            ownerType: connectionType,
            parameters: [("sql", types.stringType)],
            returnType: preparedStatementType,
            externalLinkName: "kk_jdbc_connection_prepareStatement",
            named: "prepareStatement",
            symbols: symbols,
            interner: interner
        )
        registerInstanceFunction(
            ownerSymbol: connectionSymbol,
            ownerType: connectionType,
            parameters: [],
            returnType: types.unitType,
            externalLinkName: "kk_jdbc_connection_close",
            named: "close",
            symbols: symbols,
            interner: interner
        )
        registerInstanceFunction(
            ownerSymbol: connectionSymbol,
            ownerType: connectionType,
            parameters: [],
            returnType: types.booleanType,
            externalLinkName: "kk_jdbc_connection_isClosed",
            named: "isClosed",
            symbols: symbols,
            interner: interner
        )
        registerInstanceFunction(
            ownerSymbol: connectionSymbol,
            ownerType: connectionType,
            parameters: [],
            returnType: types.booleanType,
            externalLinkName: "kk_jdbc_connection_getAutoCommit",
            named: "getAutoCommit",
            symbols: symbols,
            interner: interner
        )
        registerInstanceFunction(
            ownerSymbol: connectionSymbol,
            ownerType: connectionType,
            parameters: [("autoCommit", types.booleanType)],
            returnType: types.unitType,
            externalLinkName: "kk_jdbc_connection_setAutoCommit",
            named: "setAutoCommit",
            symbols: symbols,
            interner: interner
        )
        registerInstanceFunction(
            ownerSymbol: connectionSymbol,
            ownerType: connectionType,
            parameters: [],
            returnType: types.intType,
            externalLinkName: "kk_jdbc_connection_getTransactionIsolation",
            named: "getTransactionIsolation",
            symbols: symbols,
            interner: interner
        )
        registerInstanceFunction(
            ownerSymbol: connectionSymbol,
            ownerType: connectionType,
            parameters: [("level", types.intType)],
            returnType: types.unitType,
            externalLinkName: "kk_jdbc_connection_setTransactionIsolation",
            named: "setTransactionIsolation",
            symbols: symbols,
            interner: interner
        )
        registerInstanceFunction(
            ownerSymbol: connectionSymbol,
            ownerType: connectionType,
            parameters: [],
            returnType: types.unitType,
            externalLinkName: "kk_jdbc_connection_commit",
            named: "commit",
            symbols: symbols,
            interner: interner
        )
        registerInstanceFunction(
            ownerSymbol: connectionSymbol,
            ownerType: connectionType,
            parameters: [],
            returnType: types.unitType,
            externalLinkName: "kk_jdbc_connection_rollback",
            named: "rollback",
            symbols: symbols,
            interner: interner
        )
        registerInstanceFunction(
            ownerSymbol: connectionSymbol,
            ownerType: connectionType,
            parameters: [("savepoint", savepointType)],
            returnType: types.unitType,
            externalLinkName: "kk_jdbc_connection_rollback_savepoint",
            named: "rollback",
            symbols: symbols,
            interner: interner
        )
        registerInstanceFunction(
            ownerSymbol: connectionSymbol,
            ownerType: connectionType,
            parameters: [],
            returnType: savepointType,
            externalLinkName: "kk_jdbc_connection_setSavepoint",
            named: "setSavepoint",
            symbols: symbols,
            interner: interner
        )
        registerInstanceFunction(
            ownerSymbol: connectionSymbol,
            ownerType: connectionType,
            parameters: [("name", types.stringType)],
            returnType: savepointType,
            externalLinkName: "kk_jdbc_connection_setSavepointNamed",
            named: "setSavepoint",
            symbols: symbols,
            interner: interner
        )
        registerInstanceFunction(
            ownerSymbol: connectionSymbol,
            ownerType: connectionType,
            parameters: [("savepoint", savepointType)],
            returnType: types.unitType,
            externalLinkName: "kk_jdbc_connection_releaseSavepoint",
            named: "releaseSavepoint",
            symbols: symbols,
            interner: interner
        )
        registerInstanceFunction(
            ownerSymbol: savepointSymbol,
            ownerType: savepointType,
            parameters: [],
            returnType: types.intType,
            externalLinkName: "kk_jdbc_savepoint_getSavepointId",
            named: "getSavepointId",
            symbols: symbols,
            interner: interner
        )
        registerInstanceFunction(
            ownerSymbol: savepointSymbol,
            ownerType: savepointType,
            parameters: [],
            returnType: types.stringType,
            externalLinkName: "kk_jdbc_savepoint_getSavepointName",
            named: "getSavepointName",
            symbols: symbols,
            interner: interner
        )

        registerInstanceFunction(
            ownerSymbol: statementSymbol,
            ownerType: statementType,
            parameters: [("sql", types.stringType)],
            returnType: resultSetType,
            externalLinkName: "kk_jdbc_statement_executeQuery",
            named: "executeQuery",
            symbols: symbols,
            interner: interner
        )
        registerInstanceFunction(
            ownerSymbol: statementSymbol,
            ownerType: statementType,
            parameters: [("sql", types.stringType)],
            returnType: types.intType,
            externalLinkName: "kk_jdbc_statement_executeUpdate",
            named: "executeUpdate",
            symbols: symbols,
            interner: interner
        )
        registerInstanceFunction(
            ownerSymbol: statementSymbol,
            ownerType: statementType,
            parameters: [],
            returnType: types.unitType,
            externalLinkName: "kk_jdbc_statement_close",
            named: "close",
            symbols: symbols,
            interner: interner
        )

        registerInstanceFunction(
            ownerSymbol: preparedStatementSymbol,
            ownerType: preparedStatementType,
            parameters: [("parameterIndex", types.intType), ("value", types.intType)],
            returnType: types.unitType,
            externalLinkName: "kk_jdbc_prepared_statement_setInt",
            named: "setInt",
            symbols: symbols,
            interner: interner
        )
        registerInstanceFunction(
            ownerSymbol: preparedStatementSymbol,
            ownerType: preparedStatementType,
            parameters: [("parameterIndex", types.intType), ("value", types.stringType)],
            returnType: types.unitType,
            externalLinkName: "kk_jdbc_prepared_statement_setString",
            named: "setString",
            symbols: symbols,
            interner: interner
        )
        registerInstanceFunction(
            ownerSymbol: preparedStatementSymbol,
            ownerType: preparedStatementType,
            parameters: [],
            returnType: resultSetType,
            externalLinkName: "kk_jdbc_prepared_statement_executeQuery",
            named: "executeQuery",
            symbols: symbols,
            interner: interner
        )
        registerInstanceFunction(
            ownerSymbol: preparedStatementSymbol,
            ownerType: preparedStatementType,
            parameters: [],
            returnType: types.intType,
            externalLinkName: "kk_jdbc_prepared_statement_executeUpdate",
            named: "executeUpdate",
            symbols: symbols,
            interner: interner
        )
        registerInstanceFunction(
            ownerSymbol: preparedStatementSymbol,
            ownerType: preparedStatementType,
            parameters: [],
            returnType: types.unitType,
            externalLinkName: "kk_jdbc_prepared_statement_close",
            named: "close",
            symbols: symbols,
            interner: interner
        )

        registerInstanceFunction(
            ownerSymbol: resultSetSymbol,
            ownerType: resultSetType,
            parameters: [],
            returnType: types.booleanType,
            externalLinkName: "kk_jdbc_result_set_next",
            named: "next",
            symbols: symbols,
            interner: interner
        )
        registerInstanceFunction(
            ownerSymbol: resultSetSymbol,
            ownerType: resultSetType,
            parameters: [("columnIndex", types.intType)],
            returnType: types.intType,
            externalLinkName: "kk_jdbc_result_set_getInt",
            named: "getInt",
            symbols: symbols,
            interner: interner
        )
        registerInstanceFunction(
            ownerSymbol: resultSetSymbol,
            ownerType: resultSetType,
            parameters: [("columnLabel", types.stringType)],
            returnType: types.intType,
            externalLinkName: "kk_jdbc_result_set_getIntByLabel",
            named: "getInt",
            symbols: symbols,
            interner: interner
        )
        registerInstanceFunction(
            ownerSymbol: resultSetSymbol,
            ownerType: resultSetType,
            parameters: [("columnIndex", types.intType)],
            returnType: types.stringType,
            externalLinkName: "kk_jdbc_result_set_getString",
            named: "getString",
            symbols: symbols,
            interner: interner
        )
        registerInstanceFunction(
            ownerSymbol: resultSetSymbol,
            ownerType: resultSetType,
            parameters: [("columnLabel", types.stringType)],
            returnType: types.stringType,
            externalLinkName: "kk_jdbc_result_set_getStringByLabel",
            named: "getString",
            symbols: symbols,
            interner: interner
        )
        registerInstanceFunction(
            ownerSymbol: resultSetSymbol,
            ownerType: resultSetType,
            parameters: [],
            returnType: types.unitType,
            externalLinkName: "kk_jdbc_result_set_close",
            named: "close",
            symbols: symbols,
            interner: interner
        )
    }

    private func ensureDatabaseObjectSymbol(
        named name: String,
        in pkg: [InternedString],
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID {
        let internedName = interner.intern(name)
        let fqName = pkg + [internedName]
        if let existing = symbols.lookup(fqName: fqName) {
            return existing
        }
        return symbols.define(
            kind: .object,
            name: internedName,
            fqName: fqName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .static]
        )
    }

    private func registerInstanceFunction(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        parameters: [(String, TypeID)],
        returnType: TypeID,
        externalLinkName: String,
        named name: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else { return }
        let memberName = interner.intern(name)
        let fqName = ownerInfo.fqName + [memberName]
        guard symbols.lookupAll(fqName: fqName).first(where: { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == ownerType && signature.parameterTypes == parameters.map(\.1)
        }) == nil else {
            return
        }

        let fn = symbols.define(
            kind: .function,
            name: memberName,
            fqName: fqName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: fn)
        symbols.setExternalLinkName(externalLinkName, for: fn)

        var valueSymbols: [SymbolID] = []
        for parameter in parameters {
            let paramName = interner.intern(parameter.0)
            let param = symbols.define(
                kind: .valueParameter,
                name: paramName,
                fqName: fqName + [paramName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(fn, for: param)
            valueSymbols.append(param)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: ownerType,
                parameterTypes: parameters.map(\.1),
                returnType: returnType,
                valueParameterSymbols: valueSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueSymbols.count)
            ),
            for: fn
        )
    }
}
