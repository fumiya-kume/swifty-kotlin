// swiftlint:disable file_length

/// KClass / KFunction reflection-aware member-call lowerings.
///
/// Covers `lowerClassRefPropertyAccess`, `lowerKClassReifiedTypeNameHint`,
/// `lowerKClassReflectMemberCall`, and `lowerKClassVarReflectMemberCall`.
///
/// Split out from `CallLowerer+MemberCalls.swift`.
extension CallLowerer {
    func lowerClassRefPropertyAccess(
        _: ExprID,
        classRefExprID _: ExprID,
        classRefReceiver _: ExprID?,
        classRefTargetType: TypeID,
        propertyName: String,
        ast _: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let intType = sema.types.make(.primitive(.int, .nonNull))
        let stringType = sema.types.make(.primitive(.string, .nonNull))
        let nullableStringType = sema.types.makeNullable(stringType)

        // 1. Emit the type token.
        let tokenExpr: KIRExprID
        if case let .typeParam(typeParam) = sema.types.kind(of: classRefTargetType) {
            // Reified type parameter — look up the synthetic token symbol.
            let tokenSymbol = SyntheticSymbolScheme.reifiedTypeTokenSymbol(for: typeParam.symbol)
            tokenExpr = arena.appendExpr(.symbolRef(tokenSymbol), type: intType)
            instructions.append(.constValue(result: tokenExpr, value: .symbolRef(tokenSymbol)))
        } else {
            // Concrete type — encode the type token at compile time.
            let encoded = RuntimeTypeCheckToken.encode(type: classRefTargetType, sema: sema, interner: interner)
            tokenExpr = arena.appendExpr(.intLiteral(encoded), type: intType)
            instructions.append(.constValue(result: tokenExpr, value: .intLiteral(encoded)))
        }

        // 2. Emit the name-hint string.
        let nameHintExpr: KIRExprID
        if let name = RuntimeTypeCheckToken.simpleName(of: classRefTargetType, sema: sema, interner: interner) {
            let internedName = interner.intern(name)
            nameHintExpr = arena.appendExpr(.stringLiteral(internedName), type: stringType)
            instructions.append(.constValue(result: nameHintExpr, value: .stringLiteral(internedName)))
        } else {
            // No name available — pass 0 (null sentinel) so the runtime falls
            // back to token-based decoding.
            nameHintExpr = arena.appendExpr(.intLiteral(0), type: intType)
            instructions.append(.constValue(result: nameHintExpr, value: .intLiteral(0)))
        }

        // 3. Emit the runtime call.
        let runtimeFuncName = propertyName == "qualifiedName"
            ? "kk_type_token_qualified_name"
            : "kk_type_token_simple_name"
        let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: nullableStringType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern(runtimeFuncName),
            arguments: [tokenExpr, nameHintExpr],
            result: result,
            canThrow: false,
            thrownResult: nil
        ))
        return result
    }

    // MARK: - REFL-005: KClass.isInstance / members / constructors Lowering

    func lowerKClassReifiedTypeNameHint(
        exprID: ExprID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let typeArg = sema.bindings.callBindings[exprID]?.substitutedTypeArguments.first
        let name = typeArg.flatMap { RuntimeTypeCheckToken.qualifiedName(of: $0, sema: sema, interner: interner) }
            ?? typeArg.flatMap { RuntimeTypeCheckToken.simpleName(of: $0, sema: sema, interner: interner) }
            ?? typeArg.map { sema.types.renderType($0) }
            ?? ""
        let internedName = interner.intern(name)
        let result = arena.appendExpr(.stringLiteral(internedName), type: sema.types.stringType)
        instructions.append(.constValue(result: result, value: .stringLiteral(internedName)))
        return result
    }

    /// Lowers `T::class.isInstance(value)`, `T::class.members`, `T::class.constructors`
    /// to runtime calls `kk_kclass_isInstance`, `kk_kclass_members`, `kk_kclass_constructors`.
    ///
    /// These functions operate on the KClass box, so we first create the KClass
    /// via `kk_kclass_create` and then call the appropriate runtime function.
    func lowerKClassReflectMemberCall(
        _ exprID: ExprID,
        classRefTargetType: TypeID,
        memberName: String,
        args: [CallArgument],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let intType = sema.types.make(.primitive(.int, .nonNull))
        let stringType = sema.types.stringType

        // 1. Create the KClass box via kk_kclass_create.
        let tokenExpr: KIRExprID
        if case let .typeParam(typeParam) = sema.types.kind(of: classRefTargetType) {
            let tokenSymbol = SyntheticSymbolScheme.reifiedTypeTokenSymbol(for: typeParam.symbol)
            tokenExpr = arena.appendExpr(.symbolRef(tokenSymbol), type: intType)
            instructions.append(.constValue(result: tokenExpr, value: .symbolRef(tokenSymbol)))
        } else {
            let encoded = RuntimeTypeCheckToken.encode(type: classRefTargetType, sema: sema, interner: interner)
            tokenExpr = arena.appendExpr(.intLiteral(encoded), type: intType)
            instructions.append(.constValue(result: tokenExpr, value: .intLiteral(encoded)))
        }

        let nameHintExpr: KIRExprID
        if let name = RuntimeTypeCheckToken.simpleName(of: classRefTargetType, sema: sema, interner: interner) {
            let internedName = interner.intern(name)
            nameHintExpr = arena.appendExpr(.stringLiteral(internedName), type: stringType)
            instructions.append(.constValue(result: nameHintExpr, value: .stringLiteral(internedName)))
        } else {
            nameHintExpr = arena.appendExpr(.intLiteral(0), type: intType)
            instructions.append(.constValue(result: nameHintExpr, value: .intLiteral(0)))
        }

        let kClassFallback = sema.types.makeKClassType(argument: classRefTargetType)
        let kclassExpr = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: kClassFallback)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_kclass_create"),
            arguments: [tokenExpr, nameHintExpr],
            result: kclassExpr,
            canThrow: false,
            thrownResult: nil
        ))

        // STDLIB-REFLECT-065: For annotation-related calls, ensure metadata and
        // annotations are registered even if the class was never instantiated.
        if memberName == "annotations" || memberName == "findAnnotation" || memberName == "findAssociatedObject" {
            if case let .classType(classType) = sema.types.kind(of: classRefTargetType) {
                let classSymbol = classType.classSymbol
                if let symbol = sema.symbols.symbol(classSymbol) {
                    // Emit metadata registration.
                    let fqName = symbol.fqName.map { interner.resolve($0) }.joined(separator: ".")
                    let fqNameInterned = interner.intern(fqName)
                    let fqNameExpr = arena.appendExpr(.stringLiteral(fqNameInterned), type: intType)
                    instructions.append(.constValue(result: fqNameExpr, value: .stringLiteral(fqNameInterned)))

                    let simpleNameStr = interner.resolve(symbol.name)
                    let simpleInterned = interner.intern(simpleNameStr)
                    let simpleNameExpr = arena.appendExpr(.stringLiteral(simpleInterned), type: intType)
                    instructions.append(.constValue(result: simpleNameExpr, value: .stringLiteral(simpleInterned)))

                    let supertypes = sema.symbols.directSupertypes(for: classSymbol)
                    let superClassSymbol = supertypes.first(where: { sema.symbols.symbol($0)?.kind == .class })
                    let supertypeNameExpr: KIRExprID
                    if let superClassSymbol, let superSym = sema.symbols.symbol(superClassSymbol) {
                        let superFq = superSym.fqName.map { interner.resolve($0) }.joined(separator: ".")
                        let superIn = interner.intern(superFq)
                        supertypeNameExpr = arena.appendExpr(.stringLiteral(superIn), type: intType)
                        instructions.append(.constValue(result: supertypeNameExpr, value: .stringLiteral(superIn)))
                    } else {
                        supertypeNameExpr = arena.appendExpr(.intLiteral(0), type: intType)
                        instructions.append(.constValue(result: supertypeNameExpr, value: .intLiteral(0)))
                    }

                    var flags: Int64 = 0
                    if symbol.flags.contains(.dataType) { flags |= 1 << 0 }
                    if symbol.flags.contains(.sealedType) { flags |= 1 << 1 }
                    if symbol.flags.contains(.valueType) { flags |= 1 << 2 }
                    if symbol.kind == .interface { flags |= 1 << 3 }
                    if symbol.kind == .object { flags |= 1 << 4 }
                    if symbol.kind == .enumClass { flags |= 1 << 5 }
                    if symbol.kind == .annotationClass { flags |= 1 << 6 }
                    if symbol.flags.contains(.abstractType) { flags |= 1 << 7 }
                    let flagsExpr = arena.appendExpr(.intLiteral(flags), type: intType)
                    instructions.append(.constValue(result: flagsExpr, value: .intLiteral(flags)))

                    let fieldCount: Int64 = sema.symbols.nominalLayout(for: classSymbol).map { Int64($0.instanceFieldCount) } ?? -1
                    let fieldCountExpr = arena.appendExpr(.intLiteral(fieldCount), type: intType)
                    instructions.append(.constValue(result: fieldCountExpr, value: .intLiteral(fieldCount)))

                    let memberCount: Int64 = sema.symbols.nominalLayout(for: classSymbol).map { Int64($0.instanceFieldCount + $0.vtableSize) } ?? -1
                    let memberCountExpr = arena.appendExpr(.intLiteral(memberCount), type: intType)
                    instructions.append(.constValue(result: memberCountExpr, value: .intLiteral(memberCount)))

                    let constructorCount = Int64(sema.symbols.children(ofFQName: symbol.fqName).filter { sema.symbols.symbol($0)?.kind == .constructor }.count)
                    let constructorCountExpr = arena.appendExpr(.intLiteral(constructorCount), type: intType)
                    instructions.append(.constValue(result: constructorCountExpr, value: .intLiteral(constructorCount)))

                    let registerResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: intType)
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_kclass_register_metadata"),
                        arguments: [tokenExpr, fqNameExpr, simpleNameExpr, supertypeNameExpr, flagsExpr, fieldCountExpr, memberCountExpr, constructorCountExpr],
                        result: registerResult,
                        canThrow: false,
                        thrownResult: nil
                    ))

                    let classID = RuntimeTypeCheckToken.stableNominalTypeID(
                        symbol: classSymbol,
                        sema: sema,
                        interner: interner
                    )
                    emitDataClassFieldRegistration(
                        objectSymbol: classSymbol,
                        classID: classID,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        instructions: &instructions
                    )

                    // Emit annotation registration.
                    let annotations = sema.symbols.annotations(for: classSymbol)
                    for annotation in annotations {
                        let annNameInterned = interner.intern(annotation.annotationFQName)
                        let annNameExpr = arena.appendExpr(.stringLiteral(annNameInterned), type: stringType)
                        instructions.append(.constValue(result: annNameExpr, value: .stringLiteral(annNameInterned)))

                        let argsEncoded = annotation.arguments.joined(separator: "|")
                        let argsInterned = interner.intern(argsEncoded)
                        let argsExpr = arena.appendExpr(.stringLiteral(argsInterned), type: stringType)
                        instructions.append(.constValue(result: argsExpr, value: .stringLiteral(argsInterned)))

                        let argCount = Int64(annotation.arguments.count)
                        let argCountExpr = arena.appendExpr(.intLiteral(argCount), type: intType)
                        instructions.append(.constValue(result: argCountExpr, value: .intLiteral(argCount)))

                        let annRegResult = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: intType)
                        instructions.append(.call(
                            symbol: nil,
                            callee: interner.intern("kk_kclass_register_single_annotation"),
                            arguments: [tokenExpr, annNameExpr, argsExpr, argCountExpr],
                            result: annRegResult,
                            canThrow: false,
                            thrownResult: nil
                        ))
                    }
                }
            }
        }

        return lowerKClassRuntimeMemberCall(
            exprID,
            kclassExpr: kclassExpr,
            memberName: memberName,
            args: args,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            castFallbackType: classRefTargetType,
            visibilityFallbackType: stringType,
            instructions: &instructions
        )
    }

    private func lowerKClassRuntimeMemberCall(
        _ exprID: ExprID,
        kclassExpr: KIRExprID,
        memberName: String,
        args: [CallArgument],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        castFallbackType: TypeID,
        visibilityFallbackType: TypeID,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let intType = sema.types.make(.primitive(.int, .nonNull))
        let boolType = sema.types.make(.primitive(.boolean, .nonNull))
        let stringType = sema.types.stringType

        func lowerFirstArgumentOrNull() -> KIRExprID {
            guard let firstArg = args.first else {
                let valueExpr = arena.appendExpr(.intLiteral(0), type: intType)
                instructions.append(.constValue(result: valueExpr, value: .intLiteral(0)))
                return valueExpr
            }
            return driver.lowerExpr(
                firstArg.expr,
                ast: ast, sema: sema, arena: arena, interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
        }

        func emitRuntimeCall(
            callee: String,
            arguments: [KIRExprID],
            fallbackType: TypeID,
            canThrow: Bool = false
        ) -> KIRExprID {
            let resultType = sema.bindings.exprTypes[exprID] ?? fallbackType
            let result = arena.appendExpr(.temporary(Int32(arena.expressions.count)), type: resultType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern(callee),
                arguments: arguments,
                result: result,
                canThrow: canThrow,
                thrownResult: nil
            ))
            return result
        }

        switch memberName {
        case "isInstance":
            return emitRuntimeCall(
                callee: "kk_kclass_isInstance",
                arguments: [kclassExpr, lowerFirstArgumentOrNull()],
                fallbackType: boolType
            )

        case "cast", "safeCast":
            let canThrow = memberName == "cast"
            return emitRuntimeCall(
                callee: canThrow ? "kk_kclass_cast" : "kk_kclass_safeCast",
                arguments: [kclassExpr, lowerFirstArgumentOrNull()],
                fallbackType: castFallbackType,
                canThrow: canThrow
            )

        case "members":
            return emitRuntimeCall(
                callee: "kk_kclass_members",
                arguments: [kclassExpr],
                fallbackType: sema.types.anyType
            )

        case "constructors":
            return emitRuntimeCall(
                callee: "kk_kclass_constructors",
                arguments: [kclassExpr],
                fallbackType: sema.types.anyType
            )

        case "primaryConstructor":
            return emitRuntimeCall(
                callee: "kk_kclass_primary_constructor",
                arguments: [kclassExpr],
                fallbackType: sema.types.anyType
            )

        case "properties":
            return emitRuntimeCall(
                callee: "kk_kclass_properties",
                arguments: [kclassExpr],
                fallbackType: sema.types.anyType
            )

        case "memberProperties":
            return emitRuntimeCall(
                callee: "kk_kclass_member_properties",
                arguments: [kclassExpr],
                fallbackType: sema.types.anyType
            )

        case "declaredMemberProperties":
            return emitRuntimeCall(
                callee: "kk_kclass_declared_member_properties",
                arguments: [kclassExpr],
                fallbackType: sema.types.anyType
            )

        case "functions":
            return emitRuntimeCall(
                callee: "kk_kclass_functions",
                arguments: [kclassExpr],
                fallbackType: sema.types.anyType
            )

        case "memberFunctions":
            return emitRuntimeCall(
                callee: "kk_kclass_member_functions",
                arguments: [kclassExpr],
                fallbackType: sema.types.anyType
            )

        case "declaredMemberFunctions":
            return emitRuntimeCall(
                callee: "kk_kclass_declared_member_functions",
                arguments: [kclassExpr],
                fallbackType: sema.types.anyType
            )

        case "isFinal":
            return emitRuntimeCall(
                callee: "kk_kclass_is_final",
                arguments: [kclassExpr],
                fallbackType: boolType
            )

        case "isOpen":
            return emitRuntimeCall(
                callee: "kk_kclass_is_open",
                arguments: [kclassExpr],
                fallbackType: boolType
            )

        case "isAbstract":
            return emitRuntimeCall(
                callee: "kk_kclass_is_abstract",
                arguments: [kclassExpr],
                fallbackType: boolType
            )

        case "visibility":
            return emitRuntimeCall(
                callee: "kk_kclass_visibility",
                arguments: [kclassExpr],
                fallbackType: visibilityFallbackType
            )

        case "typeParameters":
            return emitRuntimeCall(
                callee: "kk_kclass_type_parameters",
                arguments: [kclassExpr],
                fallbackType: sema.types.anyType
            )

        case "supertypes":
            return emitRuntimeCall(
                callee: "kk_kclass_supertypes",
                arguments: [kclassExpr],
                fallbackType: sema.types.anyType
            )

        case "annotations":
            return emitRuntimeCall(
                callee: "kk_kclass_get_annotations",
                arguments: [kclassExpr],
                fallbackType: sema.types.anyType
            )

        case "findAnnotation":
            let searchNameExpr: KIRExprID
            if let firstArg = args.first {
                searchNameExpr = driver.lowerExpr(
                    firstArg.expr,
                    ast: ast, sema: sema, arena: arena, interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
            } else {
                let emptyStr = interner.intern("")
                searchNameExpr = arena.appendExpr(.stringLiteral(emptyStr), type: stringType)
                instructions.append(.constValue(result: searchNameExpr, value: .stringLiteral(emptyStr)))
            }
            return emitRuntimeCall(
                callee: "kk_kclass_find_annotation",
                arguments: [kclassExpr, searchNameExpr],
                fallbackType: sema.types.anyType
            )

        case "findAssociatedObject":
            let keyNameExpr = lowerKClassReifiedTypeNameHint(
                exprID: exprID,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
            return emitRuntimeCall(
                callee: "kk_kclass_find_associated_object",
                arguments: [kclassExpr, keyNameExpr],
                fallbackType: sema.types.makeNullable(sema.types.anyType)
            )

        default:
            let result = arena.appendExpr(.intLiteral(0), type: intType)
            instructions.append(.constValue(result: result, value: .intLiteral(0)))
            return result
        }
    }

    // MARK: - REFL-005: KClass variable receiver member calls

    /// Lowers `kclassVar.isInstance(value)`, `kclassVar.members`, `kclassVar.constructors`
    /// where the receiver is a local variable of type KClass<T>, not a direct `T::class` expression.
    /// The receiver variable already holds a KClass box, so we use it directly.
    func lowerKClassVarReflectMemberCall(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        memberName: String,
        args: [CallArgument],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        // Lower the receiver expression to get the KClass box.
        let kclassExpr = driver.lowerExpr(
            receiverExpr,
            ast: ast, sema: sema, arena: arena, interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )

        return lowerKClassRuntimeMemberCall(
            exprID,
            kclassExpr: kclassExpr,
            memberName: memberName,
            args: args,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            castFallbackType: sema.types.anyType,
            visibilityFallbackType: sema.types.anyType,
            instructions: &instructions
        )
    }
}
