#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct VolatileAnnotationSourceTests {

    // MARK: - Shared Sema context

    private static let sharedSources: [String] = [
        """
        package sample0
        import kotlin.concurrent.Volatile

        class Holder {
            @Volatile
            var value: Int = 0
        }
        """
    ]

    private static nonisolated(unsafe) var _sharedCtx: CompilationContext?

    private func sharedCtx() throws -> CompilationContext {
        if let cached = Self._sharedCtx { return cached }
        var result: CompilationContext?
        try withTemporaryFiles(contents: Self.sharedSources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            result = ctx
        }
        let ctx = try #require(result)
        Self._sharedCtx = ctx
        return ctx
    }
    private func sharedSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = (try #require(ctx.sema), ctx.interner)
        }
        return try #require(result)
    }

    @Test
    func testVolatileAnnotationIsSourceBackedWithOfficialMetadata() throws {
        let (sema, interner) = try sharedSema()

        let volatileFQName = ["kotlin", "concurrent", "Volatile"].map { interner.intern($0) }
        let volatileSymbol = try #require(
            sema.symbols.lookup(fqName: volatileFQName),
            "Expected source-backed kotlin.concurrent.Volatile to be registered"
        )
        let symbol = try #require(sema.symbols.symbol(volatileSymbol))

        #expect(symbol.kind == .annotationClass)
        #expect(!symbol.flags.contains(.synthetic))
        #expect(symbol.declSite != nil)
        #expect(sema.symbols.isSourceBackedSymbol(volatileSymbol))
        let annotations = sema.symbols.annotations(for: volatileSymbol)
        #expect(
            annotations.contains {
                ($0.annotationFQName == "Target" || $0.annotationFQName == "kotlin.annotation.Target")
                    && $0.arguments == ["AnnotationTarget.FIELD"]
            },
            "Expected Volatile to carry @Target(AnnotationTarget.FIELD), got: \(annotations)"
        )
        #expect(
            annotations.contains {
                ($0.annotationFQName == "Retention" || $0.annotationFQName == "kotlin.annotation.Retention")
                    && $0.arguments == ["AnnotationRetention.SOURCE"]
            },
            "Expected Volatile to carry @Retention(AnnotationRetention.SOURCE), got: \(annotations)"
        )
        #expect(
            annotations.contains {
                ($0.annotationFQName == "MustBeDocumented" || $0.annotationFQName == "kotlin.annotation.MustBeDocumented")
                    && $0.arguments.isEmpty
            },
            "Expected Volatile to carry @MustBeDocumented, got: \(annotations)"
        )

        let constructorFQName = volatileFQName + [interner.intern("<init>")]
        let constructorSymbol = try #require(
            sema.symbols.lookupAll(fqName: constructorFQName).first(where: { id in
                guard let constructor = sema.symbols.symbol(id),
                      constructor.kind == .constructor,
                      let signature = sema.symbols.functionSignature(for: id)
                else { return false }
                return signature.parameterTypes.isEmpty
                    && signature.returnType == sema.types.make(.classType(ClassType(
                        classSymbol: volatileSymbol,
                        args: [],
                        nullability: .nonNull
                    )))
            }),
            "Expected Volatile to expose a source-backed no-argument constructor"
        )
        let constructor = try #require(sema.symbols.symbol(constructorSymbol))
        #expect(!constructor.flags.contains(.synthetic))
        #expect(constructor.declSite != nil)
        #expect(sema.symbols.isSourceBackedSymbol(constructorSymbol))
    }

    @Test func testVolatileAnnotationResolvesInSource() throws {

        let ctx = try sharedCtx()
            #expect(!(ctx.diagnostics.hasError), "Expected Volatile annotation to resolve: \(ctx.diagnostics.diagnostics.map(\.message))")

    }
}
#endif
