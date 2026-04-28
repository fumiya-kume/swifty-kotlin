import Foundation

/// Synthetic stdlib stubs for kotlinx.serialization / kotlinx.serialization.json.
extension DataFlowSemaPhase {
    func registerSyntheticSerializationStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let serializationPkg = ensurePackage(
            path: ["kotlinx", "serialization"],
            symbols: symbols,
            interner: interner
        )
        let jsonPkg = ensurePackage(
            path: ["kotlinx", "serialization", "json"],
            symbols: symbols,
            interner: interner
        )
        let kotlinReflectPkg = ensurePackage(
            path: ["kotlin", "reflect"],
            symbols: symbols,
            interner: interner
        )

        let stringType = types.stringType
        let anyType = types.anyType
        let unitType = types.unitType
        let intType = types.intType
        let boolType = types.booleanType
        let doubleType = types.doubleType

        let jsonClassSymbol = ensureClassSymbol(
            named: "Json",
            in: jsonPkg,
            symbols: symbols,
            interner: interner
        )
        let jsonType = types.make(.classType(ClassType(
            classSymbol: jsonClassSymbol,
            args: [],
            nullability: .nonNull
        )))

        let encoderSymbol = ensureInterfaceSymbol(
            named: "Encoder",
            in: serializationPkg,
            symbols: symbols,
            interner: interner
        )
        let decoderSymbol = ensureInterfaceSymbol(
            named: "Decoder",
            in: serializationPkg,
            symbols: symbols,
            interner: interner
        )
        let serializerSymbol = ensureInterfaceSymbol(
            named: "KSerializer",
            in: serializationPkg,
            symbols: symbols,
            interner: interner
        )
        let kClassSymbol = ensureInterfaceSymbol(
            named: "KClass",
            in: kotlinReflectPkg,
            symbols: symbols,
            interner: interner
        )

        let encoderType = types.make(.classType(ClassType(
            classSymbol: encoderSymbol,
            args: [],
            nullability: .nonNull
        )))
        let decoderType = types.make(.classType(ClassType(
            classSymbol: decoderSymbol,
            args: [],
            nullability: .nonNull
        )))
        let serializerType = types.make(.classType(ClassType(
            classSymbol: serializerSymbol,
            args: [],
            nullability: .nonNull
        )))
        let nullableSerializerType = types.makeNullable(serializerType)
        let kClassType = types.make(.classType(ClassType(
            classSymbol: kClassSymbol,
            args: [],
            nullability: .nonNull
        )))
        registerKClassCastStub(
            kClassSymbol: kClassSymbol,
            anyType: anyType,
            nullableAnyType: types.nullableAnyType,
            symbols: symbols,
            types: types,
            interner: interner
        )

        registerSyntheticEncoderStubs(
            encoderSymbol: encoderSymbol,
            encoderType: encoderType,
            jsonType: jsonType,
            stringType: stringType,
            anyType: anyType,
            intType: intType,
            boolType: boolType,
            doubleType: doubleType,
            unitType: unitType,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticDecoderStubs(
            decoderSymbol: decoderSymbol,
            decoderType: decoderType,
            jsonType: jsonType,
            stringType: stringType,
            anyType: anyType,
            intType: intType,
            boolType: boolType,
            doubleType: doubleType,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticSerializerStubs(
            serializerSymbol: serializerSymbol,
            serializerType: serializerType,
            encoderType: encoderType,
            decoderType: decoderType,
            anyType: anyType,
            unitType: unitType,
            symbols: symbols,
            interner: interner
        )

        let companionFQName = ensureJsonDefaultCompanion(
            ownerSymbol: jsonClassSymbol,
            jsonType: jsonType,
            symbols: symbols,
            interner: interner
        )

        registerJsonCompanionMethod(
            named: "encodeToString",
            externalLinkName: "kk_json_encodeToString",
            returnType: stringType,
            parameters: [(name: "value", type: anyType)],
            receiverType: jsonType,
            companionFQName: companionFQName,
            symbols: symbols,
            interner: interner
        )
        registerJsonCompanionMethod(
            named: "encodeToString",
            externalLinkName: "kk_json_encodeWithSerializer",
            returnType: stringType,
            parameters: [
                (name: "serializer", type: serializerType),
                (name: "value", type: anyType),
            ],
            receiverType: jsonType,
            companionFQName: companionFQName,
            symbols: symbols,
            interner: interner
        )
        registerJsonCompanionMethod(
            named: "decodeFromString",
            externalLinkName: "kk_json_decodeFromString",
            returnType: anyType,
            parameters: [(name: "string", type: stringType)],
            receiverType: jsonType,
            companionFQName: companionFQName,
            symbols: symbols,
            interner: interner
        )
        registerJsonCompanionMethod(
            named: "decodeFromString",
            externalLinkName: "kk_json_decodeWithSerializer",
            returnType: anyType,
            parameters: [
                (name: "serializer", type: serializerType),
                (name: "string", type: stringType),
            ],
            receiverType: jsonType,
            companionFQName: companionFQName,
            symbols: symbols,
            interner: interner
        )

        registerJsonInstanceMethod(
            named: "encodeToString",
            externalLinkName: "kk_json_encodeMapToString",
            returnType: stringType,
            parameters: [(name: "value", type: anyType)],
            ownerSymbol: jsonClassSymbol,
            ownerType: jsonType,
            symbols: symbols,
            interner: interner
        )
        registerJsonInstanceMethod(
            named: "encodeToString",
            externalLinkName: "kk_json_encodeWithSerializer",
            returnType: stringType,
            parameters: [
                (name: "serializer", type: serializerType),
                (name: "value", type: anyType),
            ],
            ownerSymbol: jsonClassSymbol,
            ownerType: jsonType,
            symbols: symbols,
            interner: interner
        )
        registerJsonInstanceMethod(
            named: "decodeFromString",
            externalLinkName: "kk_json_decodeFromString",
            returnType: anyType,
            parameters: [(name: "string", type: stringType)],
            ownerSymbol: jsonClassSymbol,
            ownerType: jsonType,
            symbols: symbols,
            interner: interner
        )
        registerJsonInstanceMethod(
            named: "decodeFromString",
            externalLinkName: "kk_json_decodeWithSerializer",
            returnType: anyType,
            parameters: [
                (name: "serializer", type: serializerType),
                (name: "string", type: stringType),
            ],
            ownerSymbol: jsonClassSymbol,
            ownerType: jsonType,
            symbols: symbols,
            interner: interner
        )
        registerJsonInstanceMethod(
            named: "registerSerializer",
            externalLinkName: "kk_json_registerSerializer",
            returnType: jsonType,
            parameters: [
                (name: "type", type: kClassType),
                (name: "serializer", type: serializerType),
            ],
            ownerSymbol: jsonClassSymbol,
            ownerType: jsonType,
            symbols: symbols,
            interner: interner
        )
        registerJsonInstanceMethod(
            named: "serializerFor",
            externalLinkName: "kk_json_getRegisteredSerializer",
            returnType: nullableSerializerType,
            parameters: [(name: "type", type: kClassType)],
            ownerSymbol: jsonClassSymbol,
            ownerType: jsonType,
            symbols: symbols,
            interner: interner
        )
    }

    private func registerSyntheticEncoderStubs(
        encoderSymbol: SymbolID,
        encoderType: TypeID,
        jsonType: TypeID,
        stringType: TypeID,
        anyType: TypeID,
        intType: TypeID,
        boolType: TypeID,
        doubleType: TypeID,
        unitType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        registerInterfaceProperty(
            ownerSymbol: encoderSymbol,
            named: "context",
            propertyType: jsonType,
            externalLinkName: "kk_json_encoder_context",
            symbols: symbols,
            interner: interner
        )
        registerInterfaceMethod(
            ownerSymbol: encoderSymbol,
            ownerType: encoderType,
            named: "encodeString",
            returnType: unitType,
            parameters: [(name: "value", type: stringType)],
            externalLinkName: "kk_json_encoder_encodeString",
            symbols: symbols,
            interner: interner
        )
        registerInterfaceMethod(
            ownerSymbol: encoderSymbol,
            ownerType: encoderType,
            named: "encodeInt",
            returnType: unitType,
            parameters: [(name: "value", type: intType)],
            externalLinkName: "kk_json_encoder_encodeInt",
            symbols: symbols,
            interner: interner
        )
        registerInterfaceMethod(
            ownerSymbol: encoderSymbol,
            ownerType: encoderType,
            named: "encodeBoolean",
            returnType: unitType,
            parameters: [(name: "value", type: boolType)],
            externalLinkName: "kk_json_encoder_encodeBoolean",
            symbols: symbols,
            interner: interner
        )
        registerInterfaceMethod(
            ownerSymbol: encoderSymbol,
            ownerType: encoderType,
            named: "encodeDouble",
            returnType: unitType,
            parameters: [(name: "value", type: doubleType)],
            externalLinkName: "kk_json_encoder_encodeDouble",
            symbols: symbols,
            interner: interner
        )
        registerInterfaceMethod(
            ownerSymbol: encoderSymbol,
            ownerType: encoderType,
            named: "encodeNull",
            returnType: unitType,
            parameters: [],
            externalLinkName: "kk_json_encoder_encodeNull",
            symbols: symbols,
            interner: interner
        )
        registerInterfaceMethod(
            ownerSymbol: encoderSymbol,
            ownerType: encoderType,
            named: "encodeValue",
            returnType: unitType,
            parameters: [(name: "value", type: anyType)],
            externalLinkName: "kk_json_encoder_encodeValue",
            symbols: symbols,
            interner: interner
        )
    }

    private func registerSyntheticDecoderStubs(
        decoderSymbol: SymbolID,
        decoderType: TypeID,
        jsonType: TypeID,
        stringType: TypeID,
        anyType: TypeID,
        intType: TypeID,
        boolType: TypeID,
        doubleType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        registerInterfaceProperty(
            ownerSymbol: decoderSymbol,
            named: "context",
            propertyType: jsonType,
            externalLinkName: "kk_json_decoder_context",
            symbols: symbols,
            interner: interner
        )
        registerInterfaceMethod(
            ownerSymbol: decoderSymbol,
            ownerType: decoderType,
            named: "decodeString",
            returnType: stringType,
            parameters: [],
            externalLinkName: "kk_json_decoder_decodeString",
            symbols: symbols,
            interner: interner
        )
        registerInterfaceMethod(
            ownerSymbol: decoderSymbol,
            ownerType: decoderType,
            named: "decodeInt",
            returnType: intType,
            parameters: [],
            externalLinkName: "kk_json_decoder_decodeInt",
            symbols: symbols,
            interner: interner
        )
        registerInterfaceMethod(
            ownerSymbol: decoderSymbol,
            ownerType: decoderType,
            named: "decodeBoolean",
            returnType: boolType,
            parameters: [],
            externalLinkName: "kk_json_decoder_decodeBoolean",
            symbols: symbols,
            interner: interner
        )
        registerInterfaceMethod(
            ownerSymbol: decoderSymbol,
            ownerType: decoderType,
            named: "decodeDouble",
            returnType: doubleType,
            parameters: [],
            externalLinkName: "kk_json_decoder_decodeDouble",
            symbols: symbols,
            interner: interner
        )
        registerInterfaceMethod(
            ownerSymbol: decoderSymbol,
            ownerType: decoderType,
            named: "decodeValue",
            returnType: anyType,
            parameters: [],
            externalLinkName: "kk_json_decoder_decodeValue",
            symbols: symbols,
            interner: interner
        )
    }

    private func registerSyntheticSerializerStubs(
        serializerSymbol: SymbolID,
        serializerType: TypeID,
        encoderType: TypeID,
        decoderType: TypeID,
        anyType: TypeID,
        unitType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        registerInterfaceMethod(
            ownerSymbol: serializerSymbol,
            ownerType: serializerType,
            named: "serialize",
            returnType: unitType,
            parameters: [
                (name: "encoder", type: encoderType),
                (name: "value", type: anyType),
            ],
            externalLinkName: nil,
            symbols: symbols,
            interner: interner
        )
        registerInterfaceMethod(
            ownerSymbol: serializerSymbol,
            ownerType: serializerType,
            named: "deserialize",
            returnType: anyType,
            parameters: [(name: "decoder", type: decoderType)],
            externalLinkName: nil,
            symbols: symbols,
            interner: interner
        )
    }

    private func registerInterfaceProperty(
        ownerSymbol: SymbolID,
        named name: String,
        propertyType: TypeID,
        externalLinkName: String?,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let propertyName = interner.intern(name)
        let propertyFQName = ownerInfo.fqName + [propertyName]
        guard symbols.lookup(fqName: propertyFQName) == nil else {
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
        if let externalLinkName, !externalLinkName.isEmpty {
            symbols.setExternalLinkName(externalLinkName, for: propertySymbol)
        }
    }

    private func registerInterfaceMethod(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        named name: String,
        returnType: TypeID,
        parameters: [(name: String, type: TypeID)],
        externalLinkName: String?,
        canThrow: Bool = false,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let memberName = interner.intern(name)
        let memberFQName = ownerInfo.fqName + [memberName]
        guard symbols.lookupAll(fqName: memberFQName).first(where: { symbolID in
            guard let existingSignature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return existingSignature.receiverType == ownerType
                && existingSignature.parameterTypes == parameters.map(\.type)
                && existingSignature.returnType == returnType
        }) == nil else {
            return
        }

        var flags: SymbolFlags = [.synthetic]
        if canThrow {
            flags.insert(.throwingFunction)
        }
        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: flags
        )
        symbols.setParentSymbol(ownerSymbol, for: memberSymbol)
        if let externalLinkName, !externalLinkName.isEmpty {
            symbols.setExternalLinkName(externalLinkName, for: memberSymbol)
        }

        var valueParameterSymbols: [SymbolID] = []
        for parameter in parameters {
            let parameterName = interner.intern(parameter.name)
            let parameterSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: memberFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(memberSymbol, for: parameterSymbol)
            valueParameterSymbols.append(parameterSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: ownerType,
                parameterTypes: parameters.map(\.type),
                returnType: returnType,
                canThrow: canThrow,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
            ),
            for: memberSymbol
        )
    }

    private func registerKClassCastStub(
        kClassSymbol: SymbolID,
        anyType: TypeID,
        nullableAnyType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(kClassSymbol) else {
            return
        }
        let memberName = interner.intern("cast")
        let memberFQName = ownerInfo.fqName + [memberName]
        guard symbols.lookupAll(fqName: memberFQName).first(where: { symbolID in
            symbols.externalLinkName(for: symbolID) == "kk_kclass_cast"
        }) == nil else {
            return
        }

        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .throwingFunction]
        )
        symbols.setParentSymbol(kClassSymbol, for: memberSymbol)
        symbols.setExternalLinkName("kk_kclass_cast", for: memberSymbol)

        let tName = interner.intern("T")
        let tParamSymbol = symbols.define(
            kind: .typeParameter,
            name: tName,
            fqName: memberFQName + [tName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(memberSymbol, for: tParamSymbol)
        symbols.setTypeParameterUpperBounds([anyType], for: tParamSymbol)

        let valueName = interner.intern("value")
        let valueParamSymbol = symbols.define(
            kind: .valueParameter,
            name: valueName,
            fqName: memberFQName + [valueName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(memberSymbol, for: valueParamSymbol)

        let tType = types.make(.typeParam(TypeParamType(symbol: tParamSymbol, nullability: .nonNull)))
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: types.make(.classType(ClassType(
                    classSymbol: kClassSymbol,
                    args: [.out(tType)],
                    nullability: .nonNull
                ))),
                parameterTypes: [nullableAnyType],
                returnType: tType,
                canThrow: true,
                valueParameterSymbols: [valueParamSymbol],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [false],
                typeParameterSymbols: [tParamSymbol],
                typeParameterUpperBoundsList: [[anyType]],
                classTypeParameterCount: 1
            ),
            for: memberSymbol
        )
    }

    // MARK: - Json Helpers

    private func ensureJsonDefaultCompanion(
        ownerSymbol: SymbolID,
        jsonType: TypeID,
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

        let companionName = interner.intern("Default")
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

        let defaultName = interner.intern("Default")
        let defaultFQName = companionFQName + [defaultName]
        if symbols.lookup(fqName: defaultFQName) == nil {
            let defaultSymbol = symbols.define(
                kind: .property,
                name: defaultName,
                fqName: defaultFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .static]
            )
            symbols.setParentSymbol(companionSymbol, for: defaultSymbol)
            symbols.setPropertyType(jsonType, for: defaultSymbol)
            symbols.setExternalLinkName("kk_json_default", for: defaultSymbol)
        }

        return companionFQName
    }

    private func registerJsonCompanionMethod(
        named name: String,
        externalLinkName: String,
        returnType: TypeID,
        parameters: [(name: String, type: TypeID)],
        receiverType: TypeID,
        companionFQName: [InternedString],
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let memberName = interner.intern(name)
        let memberFQName = companionFQName + [memberName]
        guard symbols.lookupAll(fqName: memberFQName).first(where: { symbolID in
            guard let existingSignature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return existingSignature.parameterTypes == parameters.map(\.type)
                && existingSignature.returnType == returnType
                && existingSignature.receiverType == receiverType
        }) == nil else {
            return
        }

        guard let companionSymbol = symbols.lookup(fqName: companionFQName) else {
            return
        }

        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(companionSymbol, for: memberSymbol)
        symbols.setExternalLinkName(externalLinkName, for: memberSymbol)

        var valueParameterSymbols: [SymbolID] = []
        for parameter in parameters {
            let parameterName = interner.intern(parameter.name)
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: memberFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(memberSymbol, for: paramSymbol)
            valueParameterSymbols.append(paramSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: parameters.map(\.type),
                returnType: returnType,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
            ),
            for: memberSymbol
        )
    }

    private func registerJsonInstanceMethod(
        named name: String,
        externalLinkName: String,
        returnType: TypeID,
        parameters: [(name: String, type: TypeID)],
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let memberName = interner.intern(name)
        let memberFQName = ownerInfo.fqName + [memberName]
        guard symbols.lookupAll(fqName: memberFQName).first(where: { symbolID in
            guard let existingSignature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return existingSignature.parameterTypes == parameters.map(\.type)
                && existingSignature.returnType == returnType
                && existingSignature.receiverType == ownerType
        }) == nil else {
            return
        }
        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: memberSymbol)
        symbols.setExternalLinkName(externalLinkName, for: memberSymbol)

        var valueParameterSymbols: [SymbolID] = []
        for parameter in parameters {
            let parameterName = interner.intern(parameter.name)
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: memberFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(memberSymbol, for: paramSymbol)
            valueParameterSymbols.append(paramSymbol)
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
            for: memberSymbol
        )
    }
}
