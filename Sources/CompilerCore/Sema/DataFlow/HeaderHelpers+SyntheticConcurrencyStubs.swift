import Foundation

/// Synthetic stdlib stubs for `java.lang.Thread` and `kotlin.concurrent`.
extension DataFlowSemaPhase {
    func registerSyntheticConcurrencyStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let javaLangPkg = ensurePackage(
            path: ["java", "lang"],
            symbols: symbols,
            interner: interner
        )
        let concurrentPkg = ensurePackage(
            path: ["kotlin", "concurrent"],
            symbols: symbols,
            interner: interner
        )
        let concurrentPkgSymbol = symbols.lookup(fqName: concurrentPkg)

        let classLoaderSymbol = symbols.lookup(fqName: javaLangPkg + [interner.intern("ClassLoader")])
        let classLoaderType: TypeID = if let classLoaderSymbol {
            types.make(.classType(ClassType(
                classSymbol: classLoaderSymbol,
                args: [],
                nullability: .nonNull
            )))
        } else {
            types.anyType
        }
        let nullableClassLoaderType = types.makeNullable(classLoaderType)
        let nullableStringType = types.makeNullable(types.stringType)

        let threadSymbol = ensureClassSymbol(
            named: "Thread",
            in: javaLangPkg,
            symbols: symbols,
            interner: interner
        )
        if let javaLangPkgSymbol = symbols.lookup(fqName: javaLangPkg) {
            symbols.setParentSymbol(javaLangPkgSymbol, for: threadSymbol)
        }
        let threadType = types.make(.classType(ClassType(
            classSymbol: threadSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(threadType, for: threadSymbol)

        registerSyntheticThreadTopLevelFunction(
            packageFQName: concurrentPkg,
            packageSymbol: concurrentPkgSymbol,
            threadType: threadType,
            classLoaderType: nullableClassLoaderType,
            nullableStringType: nullableStringType,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticVolatileAnnotation(
            packageFQName: concurrentPkg,
            packageSymbol: concurrentPkgSymbol,
            symbols: symbols,
            interner: interner
        )
    }

    private func registerSyntheticVolatileAnnotation(
        packageFQName: [InternedString],
        packageSymbol: SymbolID?,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let volatileSymbol = ensureAnnotationClassSymbol(
            named: "Volatile",
            in: packageFQName,
            symbols: symbols,
            interner: interner
        )
        if let packageSymbol {
            symbols.setParentSymbol(packageSymbol, for: volatileSymbol)
        }

        let targetRecord = MetadataAnnotationRecord(
            annotationFQName: "kotlin.annotation.Target",
            arguments: ["AnnotationTarget.FIELD"]
        )
        var annotations = symbols.annotations(for: volatileSymbol)
        if !annotations.contains(targetRecord) {
            annotations.append(targetRecord)
            symbols.setAnnotations(annotations, for: volatileSymbol)
        }
    }

    private func registerSyntheticThreadTopLevelFunction(
        packageFQName: [InternedString],
        packageSymbol: SymbolID?,
        threadType: TypeID,
        classLoaderType: TypeID,
        nullableStringType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let functionName = interner.intern("thread")
        let functionFQName = packageFQName + [functionName]

        let existingSymbol = symbols.lookupAll(fqName: functionFQName).first { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            let defaultFunctionType = types.make(.functionType(FunctionType(
                params: [],
                returnType: types.unitType
            )))
            return signature.receiverType == nil
                && signature.parameterTypes == [
                    types.booleanType,
                    types.booleanType,
                    classLoaderType,
                    nullableStringType,
                    types.intType,
                    defaultFunctionType,
                ]
                && signature.returnType == threadType
        }
        if let existingSymbol {
            symbols.setExternalLinkName("kk_thread_create", for: existingSymbol)
            return
        }

        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .inlineFunction]
        )
        if let packageSymbol {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }
        symbols.setExternalLinkName("kk_thread_create", for: functionSymbol)

        let parameterSpecs: [(name: String, type: TypeID, hasDefault: Bool)] = [
            ("start", types.booleanType, true),
            ("isDaemon", types.booleanType, true),
            ("contextClassLoader", classLoaderType, true),
            ("name", nullableStringType, true),
            ("priority", types.intType, true),
            ("block", types.make(.functionType(FunctionType(
                params: [],
                returnType: types.unitType
            ))), false),
        ]

        var valueParameterSymbols: [SymbolID] = []
        valueParameterSymbols.reserveCapacity(parameterSpecs.count)
        for spec in parameterSpecs {
            let parameterName = interner.intern(spec.name)
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
                parameterTypes: parameterSpecs.map { $0.type },
                returnType: threadType,
                isSuspend: false,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: parameterSpecs.map { $0.hasDefault },
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
            ),
            for: functionSymbol
        )
    }
}
