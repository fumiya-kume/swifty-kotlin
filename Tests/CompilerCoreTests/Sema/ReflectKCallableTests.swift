#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ReflectKCallableTests {
    @Test func testKCallableContractIsSourceBacked() throws {
        let source = """
        import kotlin.reflect.KCallable
        import kotlin.reflect.KType

        fun read(callable: KCallable<*>): KType = callable.returnType
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let callableSymbol = try #require(sema.symbols.lookup(
            fqName: ["kotlin", "reflect", "KCallable"].map { interner.intern($0) }
        ))
        let callableInfo = try #require(sema.symbols.symbol(callableSymbol))
        #expect(callableInfo.kind == .interface)
        #expect(!callableInfo.flags.contains(.synthetic))
        let callableSourceFile = try #require(sema.symbols.sourceFileID(for: callableSymbol))
        #expect(ctx.sourceManager.origin(of: callableSourceFile)?.isBundledStdlib == true)
        #expect(sema.types.nominalTypeParameterVariances(for: callableSymbol) == [.out])

        let typeParameters = sema.types.nominalTypeParameterSymbols(for: callableSymbol)
        #expect(typeParameters.count == 1)

        let kTypeSymbol = try #require(sema.symbols.lookup(
            fqName: ["kotlin", "reflect", "KType"].map { interner.intern($0) }
        ))
        let kType = sema.types.make(.classType(ClassType(
            classSymbol: kTypeSymbol,
            args: [],
            nullability: .nonNull
        )))
        let readSymbol = try #require(sema.symbols.lookup(
            fqName: [interner.intern("read")]
        ))
        let readSignature = try #require(sema.symbols.functionSignature(for: readSymbol))
        #expect(readSignature.parameterTypes.count == 1)
        #expect(readSignature.returnType == kType)

        let nameSymbol = try #require(sema.symbols.lookup(
            fqName: ["kotlin", "reflect", "KCallable", "name"].map { interner.intern($0) }
        ))
        let nameInfo = try #require(sema.symbols.symbol(nameSymbol))
        #expect(!nameInfo.flags.contains(.synthetic))
        #expect(ctx.sourceManager.origin(of: try #require(sema.symbols.sourceFileID(for: nameSymbol)))?.isBundledStdlib == true)
        #expect(sema.symbols.propertyType(for: nameSymbol) == sema.types.stringType)
        let returnTypeSymbol = try #require(sema.symbols.lookup(
            fqName: ["kotlin", "reflect", "KCallable", "returnType"].map { interner.intern($0) }
        ))
        let returnTypeInfo = try #require(sema.symbols.symbol(returnTypeSymbol))
        #expect(!returnTypeInfo.flags.contains(.synthetic))
        #expect(ctx.sourceManager.origin(of: try #require(sema.symbols.sourceFileID(for: returnTypeSymbol)))?.isBundledStdlib == true)
        #expect(sema.symbols.propertyType(for: returnTypeSymbol) == kType)
    }

    @Test func testKCallableMembersResolveThroughFunctionAndPropertyReferences() throws {
        let source = """
        import kotlin.reflect.KCallable
        import kotlin.reflect.KFunction
        import kotlin.reflect.KProperty

        class Sample(val value: Int)
        fun answer(): String = "answer"

        fun readName(callable: KCallable<*>): String = callable.name
        fun readType(callable: KCallable<*>): kotlin.reflect.KType = callable.returnType
        fun readNullableType(callable: KCallable<*>?): kotlin.reflect.KType? = callable?.returnType
        fun readFunctionType(function: KFunction<*>): kotlin.reflect.KType = function.returnType
        fun readPropertyType(property: KProperty<*>): kotlin.reflect.KType = property.returnType
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
