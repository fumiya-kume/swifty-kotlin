#if canImport(Testing)
@testable import CompilerCore
import Testing

/// KSP-1264: The GCInfo nominal declaration and constructor are backed by
/// bundled Kotlin source. Its property surface remains synthetic for KSP-1265.
@Suite
struct GCInfoSourceMigrationTests {
    private func mapValueClassName(
        for type: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) throws -> String {
        let typeKind = sema.types.kind(of: type)
        let mapType = try requireTestValue(
            { () -> ClassType? in
                guard case let .classType(mapType) = typeKind else { return nil }
                return mapType
            }(),
            "Expected Map class type, got \(typeKind)"
        )
        let mapSymbol = try #require(sema.symbols.symbol(mapType.classSymbol))
        #expect(interner.resolve(mapSymbol.name) == "Map")
        let valueType = try requireTestValue(
            { () -> TypeID? in
                guard mapType.args.count >= 2,
                      let valueType = typeArgument(mapType.args[1])
                else {
                    return nil
                }
                return valueType
            }(),
            "Expected Map<String, V> value projection"
        )
        let valueKind = sema.types.kind(of: valueType)
        let valueClassType = try requireTestValue(
            { () -> ClassType? in
                guard case let .classType(valueClassType) = valueKind else { return nil }
                return valueClassType
            }(),
            "Expected Map value class type, got \(valueKind)"
        )
        let valueSymbol = try #require(sema.symbols.symbol(valueClassType.classSymbol))
        return interner.resolve(valueSymbol.name)
    }

    private func typeArgument(_ argument: TypeArg) -> TypeID? {
        switch argument {
        case let .invariant(type), let .out(type), let .in(type):
            return type
        case .star:
            return nil
        }
    }

    @Test
    func gcInfoConstructorIsBundledSourceBacked() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(
                errors.isEmpty,
                "Expected bundled GCInfo source to type-check, got: \(errors.map { $0.code + ": " + $0.message })"
            )

            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            let gcInfoFQName = ["kotlin", "native", "runtime", "GCInfo"].map(interner.intern)
            let classSymbol = try #require(sema.symbols.lookup(fqName: gcInfoFQName))
            let classInfo = try #require(sema.symbols.symbol(classSymbol))
            #expect(classInfo.kind == .class)
            #expect(!classInfo.flags.contains(.synthetic))
            #expect(sema.symbols.isSourceBackedSymbol(classSymbol))
            let classFileID = try #require(sema.symbols.sourceFileID(for: classSymbol))
            #expect(
                ctx.sourceManager.path(of: classFileID)
                    == "__bundled_kotlin/native/runtime/GCInfo/Stdlib.kt"
            )

            let constructors = sema.symbols.lookupAll(
                fqName: gcInfoFQName + [interner.intern("<init>")]
            ).filter { sema.symbols.symbol($0)?.kind == .constructor }
            #expect(constructors.count == 1, "Expected one source-backed GCInfo constructor")
            let constructor = try #require(constructors.first)
            let constructorInfo = try #require(sema.symbols.symbol(constructor))
            let signature = try #require(sema.symbols.functionSignature(for: constructor))
            #expect(!constructorInfo.flags.contains(.synthetic))
            #expect(sema.symbols.isSourceBackedSymbol(constructor))
            #expect(sema.symbols.externalLinkName(for: constructor) == nil)
            #expect(signature.parameterTypes.count == 15)
            #expect(
                Array(signature.parameterTypes.prefix(6))
                    == Array(repeating: sema.types.longType, count: 6)
            )

            for index in 6..<10 {
                let parameterType = signature.parameterTypes[index]
                #expect(sema.types.nullability(of: parameterType) == .nullable)
                #expect(sema.types.makeNonNullable(parameterType) == sema.types.longType)
            }

            let rootSetFQName = ["kotlin", "native", "runtime", "RootSetStatistics"].map(interner.intern)
            let rootSetSymbol = try #require(sema.symbols.lookup(fqName: rootSetFQName))
            let rootSetType = sema.types.make(.classType(ClassType(classSymbol: rootSetSymbol)))
            #expect(signature.parameterTypes[10] == rootSetType)
            #expect(signature.parameterTypes[11] == sema.types.longType)
            #expect(
                try mapValueClassName(
                    for: signature.parameterTypes[12],
                    sema: sema,
                    interner: interner
                ) == "SweepStatistics"
            )
            #expect(
                try mapValueClassName(
                    for: signature.parameterTypes[13],
                    sema: sema,
                    interner: interner
                ) == "MemoryUsage"
            )
            #expect(
                try mapValueClassName(
                    for: signature.parameterTypes[14],
                    sema: sema,
                    interner: interner
                ) == "MemoryUsage"
            )

            let expectedReturnType = sema.types.make(.classType(ClassType(classSymbol: classSymbol)))
            #expect(signature.returnType == expectedReturnType)

            let epochSymbol = try #require(
                sema.symbols.lookup(fqName: gcInfoFQName + [interner.intern("epoch")])
            )
            let epochInfo = try #require(sema.symbols.symbol(epochSymbol))
            #expect(epochInfo.flags.contains(.synthetic))
            #expect(!sema.symbols.isSourceBackedSymbol(epochSymbol))
            #expect(sema.symbols.propertyType(for: epochSymbol) == sema.types.longType)
        }
    }
}
#endif
