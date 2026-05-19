/// Inference for KClass-receiver member-call expressions:
/// - `T::class.simpleName / .qualifiedName / .isInstance(...) / .cast(...) /
///   .safeCast(...) / .isFinal / .isOpen / .isAbstract / .visibility / ...`
/// - Runtime `kotlin.reflect.KClass<T>` receiver expressions.
///
/// Split out from `CallTypeChecker+MemberCallInference.swift`.
extension CallTypeChecker {
    /// Handles `T::class.simpleName / .qualifiedName / .isInstance(...) / .cast(...) /
    /// .safeCast(...) / .isFinal / .isOpen / .isAbstract / .visibility /
    /// .{members,constructors,properties,...} / .findAnnotation<T>() /
    /// .findAssociatedObject<T>()` when the receiver is a compile-time class
    /// reference (callableRef with member "class").
    /// Returns the inferred type, or `nil` when the receiver isn't a class-ref
    /// or the calleeName doesn't match any handled KClass member.
    func tryInferClassRefMemberCall(
        _ id: ExprID,
        receiverID: ExprID,
        calleeName: InternedString,
        args: [CallArgument],
        explicitTypeArgs: [TypeID],
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID? {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        let knownNames = KnownCompilerNames(interner: interner)

        guard case let .callableRef(_, refMember, _) = ast.arena.expr(receiverID),
              refMember == knownNames.className
        else {
            return nil
        }

        _ = driver.inferExpr(receiverID, ctx: ctx, locals: &locals)
        guard let classRefTargetType = sema.bindings.classRefTargetType(for: receiverID) else {
            return nil
        }

        if calleeName == interner.intern("java"), args.isEmpty {
            let javaTypeArgument = javaClassTypeArgument(
                from: classRefTargetType,
                sema: sema,
                interner: interner
            )
            return bindKClassJavaPropertyAccess(
                id,
                typeArgument: javaTypeArgument,
                sema: sema,
                interner: interner
            )
        }
        if calleeName == interner.intern("js"), args.isEmpty {
            let jsTypeArgument = javaClassTypeArgument(
                from: classRefTargetType,
                sema: sema,
                interner: interner
            )
            return bindKClassJsPropertyAccess(
                id,
                typeArgument: jsTypeArgument,
                sema: sema,
                interner: interner
            )
        }
        if calleeName == interner.intern("javaClass"), args.isEmpty {
            let javaTypeArgument = javaClassTypeArgument(
                from: classRefTargetType,
                sema: sema,
                interner: interner
            )
            return bindKClassJavaClassPropertyAccess(
                id,
                typeArgument: javaTypeArgument,
                sema: sema,
                interner: interner
            )
        }
        if calleeName == knownNames.simpleName || calleeName == knownNames.qualifiedName {
            _ = args.map { driver.inferExpr($0.expr, ctx: ctx, locals: &locals) }
            let nullableStringType = sema.types.makeNullable(
                sema.types.make(.primitive(.string, .nonNull))
            )
            sema.bindings.bindExprType(id, type: nullableStringType)
            return nullableStringType
        }
        if calleeName == knownNames.isInstanceName, args.count == 1 {
            _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
            let boolType = sema.types.booleanType
            sema.bindings.bindExprType(id, type: boolType)
            return boolType
        }
        if calleeName == knownNames.kClassCastName, args.count == 1 {
            _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
            let targetType = sema.bindings.classRefTargetType(for: receiverID) ?? sema.types.anyType
            let returnType = kClassCastReturnType(from: targetType, sema: sema, interner: interner)
            sema.bindings.bindExprType(id, type: returnType)
            return returnType
        }
        if calleeName == knownNames.kClassSafeCastName, args.count == 1 {
            _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
            let targetType = sema.bindings.classRefTargetType(for: receiverID) ?? sema.types.anyType
            let returnType = kClassSafeCastReturnType(from: targetType, sema: sema, interner: interner)
            sema.bindings.bindExprType(id, type: returnType)
            return returnType
        }
        // STDLIB-REFLECT-060: KClass boolean properties (isFinal, isOpen, isAbstract)
        let kclassBooleanCallees: Set<InternedString> = [
            knownNames.isFinalName, knownNames.isOpenName, knownNames.isAbstractName,
        ]
        if kclassBooleanCallees.contains(calleeName), args.isEmpty {
            let boolType = sema.types.booleanType
            sema.bindings.bindExprType(id, type: boolType)
            return boolType
        }
        // STDLIB-REFLECT-060: KClass.visibility -> String?
        if calleeName == knownNames.visibilityName, args.isEmpty {
            let nullableStringType = sema.types.makeNullable(
                sema.types.make(.primitive(.string, .nonNull))
            )
            sema.bindings.bindExprType(id, type: nullableStringType)
            return nullableStringType
        }
        // STDLIB-REFLECT-065 / 060: KClass collection-shaped properties.
        let kclassMemberCollectionCallees: Set<InternedString> = [
            knownNames.membersName, knownNames.constructorsName,
            knownNames.propertiesName, knownNames.memberPropertiesName,
            knownNames.declaredMemberPropertiesName,
            knownNames.functionsName, knownNames.memberFunctionsName,
            knownNames.declaredMemberFunctionsName,
            knownNames.typeParametersName, knownNames.supertypesName,
            knownNames.annotationsName,
        ]
        if kclassMemberCollectionCallees.contains(calleeName), args.isEmpty {
            let listType = makeSyntheticListType(
                symbols: sema.symbols,
                types: sema.types,
                interner: interner,
                elementType: sema.types.anyType
            )
            sema.bindings.markCollectionExpr(id)
            sema.bindings.bindExprType(id, type: listType)
            return listType
        }
        // STDLIB-REFLECT-065: findAnnotation<T>()
        if calleeName == knownNames.findAnnotationName {
            for arg in args {
                _ = driver.inferExpr(arg.expr, ctx: ctx, locals: &locals)
            }
            let nullableAnyType = sema.types.makeNullable(sema.types.anyType)
            sema.bindings.bindExprType(id, type: nullableAnyType)
            return nullableAnyType
        }
        // STDLIB-REFLECT-079: findAssociatedObject<T>()
        if calleeName == knownNames.findAssociatedObjectName {
            return bindKClassFindAssociatedObjectCall(
                id,
                args: args,
                explicitTypeArgs: explicitTypeArgs,
                range: range,
                ctx: ctx,
                locals: &locals
            )
        }
        return nil
    }

    /// Handles KClass member access when the receiver is a runtime KClass<T>
    /// expression (variable / property whose type is `kotlin.reflect.KClass<…>`).
    /// Returns the inferred type, or `nil` when the receiver isn't a runtime
    /// KClass or the calleeName doesn't match any handled KClass member.
    func tryInferKClassReceiverMemberCall(
        _ id: ExprID,
        receiverType: TypeID,
        calleeName: InternedString,
        args: [CallArgument],
        explicitTypeArgs: [TypeID],
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID? {
        let sema = ctx.sema
        let interner = ctx.interner
        let knownNames = KnownCompilerNames(interner: interner)

        guard let kClassArgumentType = kClassReceiverArgumentType(receiverType, sema: sema, interner: interner) else {
            return nil
        }

        if calleeName == interner.intern("java"), args.isEmpty {
            return bindKClassJavaPropertyAccess(
                id,
                typeArgument: kClassArgumentType,
                sema: sema,
                interner: interner
            )
        }
        if calleeName == interner.intern("js"), args.isEmpty {
            return bindKClassJsPropertyAccess(
                id,
                typeArgument: kClassArgumentType,
                sema: sema,
                interner: interner
            )
        }
        if calleeName == interner.intern("javaClass"), args.isEmpty {
            return bindKClassJavaClassPropertyAccess(
                id,
                typeArgument: kClassArgumentType,
                sema: sema,
                interner: interner
            )
        }
        if calleeName == knownNames.isInstanceName, args.count == 1 {
            _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
            let boolType = sema.types.booleanType
            sema.bindings.bindExprType(id, type: boolType)
            return boolType
        }
        if calleeName == knownNames.kClassCastName, args.count == 1 {
            _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
            let returnType = kClassCastReturnType(from: kClassArgumentType, sema: sema, interner: interner)
            sema.bindings.bindExprType(id, type: returnType)
            return returnType
        }
        if calleeName == knownNames.kClassSafeCastName, args.count == 1 {
            _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
            let returnType = kClassSafeCastReturnType(from: kClassArgumentType, sema: sema, interner: interner)
            sema.bindings.bindExprType(id, type: returnType)
            return returnType
        }
        // STDLIB-REFLECT-060: KClass boolean properties via variable receiver
        let kclassVarBooleanCallees: Set<InternedString> = [
            knownNames.isFinalName, knownNames.isOpenName, knownNames.isAbstractName,
        ]
        if kclassVarBooleanCallees.contains(calleeName), args.isEmpty {
            let boolType = sema.types.booleanType
            sema.bindings.bindExprType(id, type: boolType)
            return boolType
        }
        // STDLIB-REFLECT-060: KClass.visibility via variable receiver -> String?
        if calleeName == knownNames.visibilityName, args.isEmpty {
            let nullableStringType = sema.types.makeNullable(
                sema.types.make(.primitive(.string, .nonNull))
            )
            sema.bindings.bindExprType(id, type: nullableStringType)
            return nullableStringType
        }
        // STDLIB-REFLECT-065 / 060: KClass collection-shaped properties (via variable receiver).
        let kclassVarMemberCollectionCallees: Set<InternedString> = [
            knownNames.membersName, knownNames.constructorsName,
            knownNames.propertiesName, knownNames.memberPropertiesName,
            knownNames.declaredMemberPropertiesName,
            knownNames.functionsName, knownNames.memberFunctionsName,
            knownNames.declaredMemberFunctionsName,
            knownNames.typeParametersName, knownNames.supertypesName,
            knownNames.annotationsName,
        ]
        if kclassVarMemberCollectionCallees.contains(calleeName), args.isEmpty {
            let listType = makeSyntheticListType(
                symbols: sema.symbols,
                types: sema.types,
                interner: interner,
                elementType: sema.types.anyType
            )
            sema.bindings.markCollectionExpr(id)
            sema.bindings.bindExprType(id, type: listType)
            return listType
        }
        // STDLIB-REFLECT-065: findAnnotation<T>()
        if calleeName == knownNames.findAnnotationName {
            for arg in args {
                _ = driver.inferExpr(arg.expr, ctx: ctx, locals: &locals)
            }
            let nullableAnyType = sema.types.makeNullable(sema.types.anyType)
            sema.bindings.bindExprType(id, type: nullableAnyType)
            return nullableAnyType
        }
        // STDLIB-REFLECT-079: findAssociatedObject<T>()
        if calleeName == knownNames.findAssociatedObjectName {
            return bindKClassFindAssociatedObjectCall(
                id,
                args: args,
                explicitTypeArgs: explicitTypeArgs,
                range: range,
                ctx: ctx,
                locals: &locals
            )
        }
        return nil
    }

    private func javaClassTypeArgument(
        from classRefTargetType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID {
        guard case let .classType(classType) = sema.types.kind(of: classRefTargetType),
              let targetSymbol = sema.symbols.symbol(classType.classSymbol),
              targetSymbol.fqName.count == 2,
              targetSymbol.fqName.first == interner.intern("kotlin"),
              let builtin = driver.helpers.resolveBuiltinTypeName(
                  targetSymbol.name,
                  nullability: classType.nullability,
                  types: sema.types,
                  interner: interner
              )
        else {
            return classRefTargetType
        }
        return builtin
    }

    private func bindKClassJavaPropertyAccess(
        _ id: ExprID,
        typeArgument: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID? {
        let classFQName = [
            interner.intern("java"),
            interner.intern("lang"),
            interner.intern("Class"),
        ]
        guard let classSymbol = sema.symbols.lookup(fqName: classFQName) else {
            return nil
        }

        let returnType = sema.types.make(.classType(ClassType(
            classSymbol: classSymbol,
            args: [.invariant(typeArgument)],
            nullability: .nonNull
        )))
        let propertyFQName = [
            interner.intern("kotlin"),
            interner.intern("jvm"),
            interner.intern("java"),
        ]
        if let propertySymbol = sema.symbols.lookupAll(fqName: propertyFQName).first(where: { symbolID in
            sema.symbols.symbol(symbolID)?.kind == .property
                && sema.symbols.extensionPropertyReceiverType(for: symbolID) != nil
        }) {
            sema.bindings.bindIdentifier(id, symbol: propertySymbol)
            if let getterSymbol = sema.symbols.extensionPropertyGetterAccessor(for: propertySymbol) {
                sema.bindings.bindCall(
                    id,
                    binding: CallBinding(
                        chosenCallee: getterSymbol,
                        substitutedTypeArguments: [typeArgument],
                        parameterMapping: [:]
                    )
                )
                sema.bindings.bindCallableTarget(id, target: .symbol(getterSymbol))
            }
        }
        sema.bindings.bindExprType(id, type: returnType)
        return returnType
    }

    private func bindKClassJsPropertyAccess(
        _ id: ExprID,
        typeArgument: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID? {
        let jsClassFQName = [
            interner.intern("kotlin"),
            interner.intern("js"),
            interner.intern("JsClass"),
        ]
        guard let jsClassSymbol = sema.symbols.lookup(fqName: jsClassFQName) else {
            return nil
        }

        let returnType = sema.types.make(.classType(ClassType(
            classSymbol: jsClassSymbol,
            args: [.invariant(typeArgument)],
            nullability: .nonNull
        )))
        let propertyFQName = [
            interner.intern("kotlin"),
            interner.intern("js"),
            interner.intern("js"),
        ]
        if let propertySymbol = sema.symbols.lookupAll(fqName: propertyFQName).first(where: { symbolID in
            sema.symbols.symbol(symbolID)?.kind == .property
                && sema.symbols.extensionPropertyReceiverType(for: symbolID) != nil
        }) {
            sema.bindings.bindIdentifier(id, symbol: propertySymbol)
            if let getterSymbol = sema.symbols.extensionPropertyGetterAccessor(for: propertySymbol) {
                sema.bindings.bindCall(
                    id,
                    binding: CallBinding(
                        chosenCallee: getterSymbol,
                        substitutedTypeArguments: [typeArgument],
                        parameterMapping: [:]
                    )
                )
                sema.bindings.bindCallableTarget(id, target: .symbol(getterSymbol))
            }
        }
        sema.bindings.bindExprType(id, type: returnType)
        return returnType
    }

    private func bindKClassJavaClassPropertyAccess(
        _ id: ExprID,
        typeArgument: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID? {
        let classFQName = [
            interner.intern("java"),
            interner.intern("lang"),
            interner.intern("Class"),
        ]
        guard let classSymbol = sema.symbols.lookup(fqName: classFQName),
              let kClassSymbol = sema.types.kClassInterfaceSymbol
        else {
            return nil
        }

        let kClassType = sema.types.make(.classType(ClassType(
            classSymbol: kClassSymbol,
            args: [.invariant(typeArgument)],
            nullability: .nonNull
        )))
        let returnType = sema.types.make(.classType(ClassType(
            classSymbol: classSymbol,
            args: [.invariant(kClassType)],
            nullability: .nonNull
        )))
        let propertyFQName = [
            interner.intern("kotlin"),
            interner.intern("jvm"),
            interner.intern("javaClass"),
        ]
        if let propertySymbol = sema.symbols.lookupAll(fqName: propertyFQName).first(where: { symbolID in
            sema.symbols.symbol(symbolID)?.kind == .property
                && sema.symbols.extensionPropertyReceiverType(for: symbolID) != nil
        }) {
            sema.bindings.bindIdentifier(id, symbol: propertySymbol)
            if let getterSymbol = sema.symbols.extensionPropertyGetterAccessor(for: propertySymbol) {
                sema.bindings.bindCall(
                    id,
                    binding: CallBinding(
                        chosenCallee: getterSymbol,
                        substitutedTypeArguments: [typeArgument],
                        parameterMapping: [:]
                    )
                )
                sema.bindings.bindCallableTarget(id, target: .symbol(getterSymbol))
            }
        }
        sema.bindings.bindExprType(id, type: returnType)
        return returnType
    }
}
