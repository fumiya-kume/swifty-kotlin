#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ReflectKTypeSourceMigrationTests {
    private static nonisolated(unsafe) var _sharedSema: (SemaModule, StringInterner)?

    private func sharedSema() throws -> (SemaModule, StringInterner) {
        if let cached = Self._sharedSema { return cached }
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            #expect(!ctx.diagnostics.hasError, Comment(rawValue: "Expected KType source to resolve cleanly, got: \(diagnostics)"))
            result = (try #require(ctx.sema), ctx.interner)
        }
        let sema = try #require(result)
        Self._sharedSema = sema
        return sema
    }

    @Test
    func kTypePropertiesAreSourceBackedWithKotlinTypes() throws {
        let (sema, interner) = try sharedSema()
        let reflectPackage = [interner.intern("kotlin"), interner.intern("reflect")]
        let kTypeSymbol = try #require(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KType")]
        ))
        let kClassifierSymbol = try #require(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KClassifier")]
        ))
        let kTypeProjectionSymbol = try #require(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KTypeProjection")]
        ))
        let listSymbol = try #require(sema.symbols.lookup(fqName: [
            interner.intern("kotlin"), interner.intern("collections"), interner.intern("List"),
        ]))

        #expect(sema.symbols.symbol(kTypeSymbol)?.kind == .interface)
        #expect(sema.symbols.symbol(kTypeSymbol)?.flags.contains(.synthetic) == false)

        let classifierType = sema.types.make(.classType(ClassType(
            classSymbol: kClassifierSymbol,
            args: [],
            nullability: .nonNull
        )))
        let projectionType = sema.types.make(.classType(ClassType(
            classSymbol: kTypeProjectionSymbol,
            args: [],
            nullability: .nonNull
        )))
        let listOfProjectionType = sema.types.make(.classType(ClassType(
            classSymbol: listSymbol,
            args: [.out(projectionType)],
            nullability: .nonNull
        )))

        let expectedProperties: [(name: String, type: TypeID)] = [
            ("arguments", listOfProjectionType),
            ("classifier", sema.types.makeNullable(classifierType)),
            ("isMarkedNullable", sema.types.booleanType),
        ]
        for expected in expectedProperties {
            let property = try #require(sema.symbols.lookup(
                fqName: reflectPackage + [interner.intern("KType"), interner.intern(expected.name)]
            ))
            let propertyInfo = try #require(sema.symbols.symbol(property))
            #expect(propertyInfo.kind == .property)
            #expect(!propertyInfo.flags.contains(.synthetic), "KType.\(expected.name) must be source-backed")
            #expect(propertyInfo.declSite != nil, "KType.\(expected.name) must retain its source declaration")
            #expect(sema.symbols.isSourceBackedSymbol(property))
            #expect(sema.symbols.externalLinkName(for: property) == nil)
            #expect(sema.symbols.propertyType(for: property) == expected.type)
        }
    }

    @Test
    func kTypePropertiesResolveInSource() throws {
        let source = """
        import kotlin.reflect.KClassifier
        import kotlin.reflect.KType
        import kotlin.reflect.KTypeProjection

        fun classifierOf(type: KType): KClassifier? = type.classifier
        fun argumentsOf(type: KType): List<KTypeProjection> = type.arguments
        fun markedNullableOf(type: KType): Boolean = type.isMarkedNullable
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            #expect(!ctx.diagnostics.hasError, Comment(rawValue: "Expected KType property reads to resolve cleanly, got: \(diagnostics)"))
        }
    }
}
#endif
