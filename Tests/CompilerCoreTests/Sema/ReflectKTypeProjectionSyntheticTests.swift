#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ReflectKTypeProjectionSyntheticTests {
    private static nonisolated(unsafe) var _sharedSema: (SemaModule, StringInterner)?

    private func sharedSema() throws -> (SemaModule, StringInterner) {
        if let cached = Self._sharedSema { return cached }
        let pair = try makeSema()
        Self._sharedSema = pair
        return pair
    }

    private func makeSema(
        source: String = "fun noop() {}"
    ) throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
            #expect(!(ctx.diagnostics.hasError), Comment(rawValue: "Expected KTypeProjection surface to resolve cleanly, got: \(diagnostics)"))
            result = (try #require(ctx.sema), ctx.interner)
        }
        return try #require(result)
    }

    @Test func testKTypeProjectionPropertiesAreSourceBacked() throws {
        let (sema, interner) = try sharedSema()
        let reflectPackage = ["kotlin", "reflect"].map { interner.intern($0) }
        let collectionsPackage = ["kotlin", "collections"].map { interner.intern($0) }

        let kTypeSymbol = try #require(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KType")]
        ))
        let kTypeProjectionSymbol = try #require(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KTypeProjection")]
        ))
        let kVarianceSymbol = try #require(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KVariance")]
        ))
        let listSymbol = try #require(sema.symbols.lookup(
            fqName: collectionsPackage + [interner.intern("List")]
        ))

        #expect(sema.symbols.symbol(kTypeProjectionSymbol)?.kind == .class)
        #expect(sema.symbols.symbol(kTypeProjectionSymbol)?.flags.contains(.synthetic) == false)

        let nullableKVariance = sema.types.makeNullable(sema.types.make(.classType(ClassType(
            classSymbol: kVarianceSymbol,
            args: [],
            nullability: .nonNull
        ))))
        let nullableKType = sema.types.makeNullable(sema.types.make(.classType(ClassType(
            classSymbol: kTypeSymbol,
            args: [],
            nullability: .nonNull
        ))))

        let varianceSymbol = try #require(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KTypeProjection"), interner.intern("variance")]
        ))
        let typeSymbol = try #require(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KTypeProjection"), interner.intern("type")]
        ))
        for symbol in [varianceSymbol, typeSymbol] {
            #expect(sema.symbols.symbol(symbol)?.declSite != nil)
            #expect(sema.symbols.symbol(symbol)?.flags.contains(.synthetic) == false)
            #expect(sema.symbols.isSourceBackedSymbol(symbol))
        }
        #expect(sema.symbols.propertyType(for: varianceSymbol) == nullableKVariance)
        #expect(sema.symbols.propertyType(for: typeSymbol) == nullableKType)

        let projectionType = sema.types.make(.classType(ClassType(
            classSymbol: kTypeProjectionSymbol,
            args: [],
            nullability: .nonNull
        )))
        let listOfProjection = sema.types.make(.classType(ClassType(
            classSymbol: listSymbol,
            args: [.out(projectionType)],
            nullability: .nonNull
        )))
        let argumentsSymbol = try #require(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KType"), interner.intern("arguments")]
        ))
        #expect(sema.symbols.propertyType(for: argumentsSymbol) == listOfProjection)
    }

    @Test func testKTypeProjectionConstructorAndCompanionAreSourceBacked() throws {
        let (sema, interner) = try sharedSema()
        let reflectPackage = [interner.intern("kotlin"), interner.intern("reflect")]
        let projectionName = interner.intern("KTypeProjection")
        let constructor = try #require(sema.symbols.lookup(
            fqName: reflectPackage + [projectionName, interner.intern("<init>")]
        ))
        let constructorSignature = try #require(sema.symbols.functionSignature(for: constructor))
        let kTypeSymbol = try #require(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KType")]
        ))
        let kVarianceSymbol = try #require(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KVariance")]
        ))
        let nullableKType = sema.types.makeNullable(sema.types.make(.classType(ClassType(
            classSymbol: kTypeSymbol, args: [], nullability: .nonNull
        ))))
        let nullableKVariance = sema.types.makeNullable(sema.types.make(.classType(ClassType(
            classSymbol: kVarianceSymbol, args: [], nullability: .nonNull
        ))))
        #expect(sema.symbols.symbol(constructor)?.kind == .constructor)
        #expect(constructorSignature.parameterTypes == [nullableKVariance, nullableKType])
        #expect(sema.symbols.externalLinkName(for: constructor) == "__kk_ktypeprojection_create_checked")

        let companion = try #require(sema.symbols.lookup(
            fqName: reflectPackage + [projectionName, interner.intern("Companion")]
        ))
        #expect(sema.symbols.symbol(companion)?.kind == .object)
        #expect(sema.symbols.symbol(companion)?.flags.contains(.synthetic) == false)
        #expect(sema.symbols.parentSymbol(for: companion) == sema.symbols.lookup(
            fqName: reflectPackage + [projectionName]
        ))
    }

    @Test func testKTypeProjectionDataClassMembersAreSourceBacked() throws {
        let (sema, interner) = try sharedSema()
        let reflectPackage = [interner.intern("kotlin"), interner.intern("reflect")]
        let projectionName = interner.intern("KTypeProjection")
        let projectionFQName = reflectPackage + [projectionName]
        let kTypeProjectionSymbol = try #require(sema.symbols.lookup(fqName: projectionFQName))
        let projectionType = sema.types.make(.classType(ClassType(
            classSymbol: kTypeProjectionSymbol, args: [], nullability: .nonNull
        )))
        let kTypeSymbol = try #require(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KType")]
        ))
        let kVarianceSymbol = try #require(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KVariance")]
        ))
        let nullableKType = sema.types.makeNullable(sema.types.make(.classType(ClassType(
            classSymbol: kTypeSymbol, args: [], nullability: .nonNull
        ))))
        let nullableKVariance = sema.types.makeNullable(sema.types.make(.classType(ClassType(
            classSymbol: kVarianceSymbol, args: [], nullability: .nonNull
        ))))
        let anyType = sema.types.anyType
        let nullableAny = sema.types.makeNullable(anyType)
        let booleanType = sema.types.booleanType
        let intType = sema.types.intType
        let stringType = sema.types.stringType

        let expected: [(name: String, parameters: [TypeID], returnType: TypeID, defaults: [Bool])] = [
            ("component1", [], nullableKVariance, []),
            ("component2", [], nullableKType, []),
            ("copy", [nullableKVariance, nullableKType], projectionType, [true, true]),
            ("equals", [nullableAny], booleanType, [false]),
            ("hashCode", [], intType, []),
            ("toString", [], stringType, []),
        ]

        for member in expected {
            let symbol = try #require(sema.symbols.lookup(
                fqName: projectionFQName + [interner.intern(member.name)]
            ))
            let info = try #require(sema.symbols.symbol(symbol))
            let signature = try #require(sema.symbols.functionSignature(for: symbol))
            #expect(info.declSite != nil)
            #expect(!info.flags.contains(.synthetic))
            #expect(sema.symbols.isSourceBackedSymbol(symbol))
            #expect(signature.receiverType == projectionType)
            #expect(signature.parameterTypes == member.parameters)
            #expect(signature.returnType == member.returnType)
            #expect(signature.valueParameterHasDefaultValues == member.defaults)
        }

        let varianceComponent = try #require(sema.symbols.lookup(
            fqName: projectionFQName + [interner.intern("varianceComponent")]
        ))
        let typeComponent = try #require(sema.symbols.lookup(
            fqName: projectionFQName + [interner.intern("typeComponent")]
        ))
        #expect(sema.symbols.externalLinkName(for: varianceComponent) == "__kk_ktypeprojection_get_variance")
        #expect(sema.symbols.externalLinkName(for: typeComponent) == "__kk_ktypeprojection_get_type")
    }

    @Test func testKTypeProjectionPropertiesResolveInSource() throws {
        let source = """
        import kotlin.reflect.KType
        import kotlin.reflect.KTypeProjection
        import kotlin.reflect.KVariance

        fun projectionVariance(projection: KTypeProjection): KVariance? = projection.variance
        fun projectionType(projection: KTypeProjection): KType? = projection.type
        fun projectionComponent1(projection: KTypeProjection): KVariance? = projection.component1()
        fun projectionComponent2(projection: KTypeProjection): KType? = projection.component2()
        fun projectionCopy(projection: KTypeProjection): KTypeProjection = projection.copy()
        fun projectionEquals(projection: KTypeProjection): Boolean = projection.equals(null)
        fun projectionHashCode(projection: KTypeProjection): Int = projection.hashCode()
        fun projectionToString(projection: KTypeProjection): String = projection.toString()
        fun typeArguments(type: KType): List<KTypeProjection> = type.arguments
        """

        _ = try makeSema(source: source)
    }
}
#endif
