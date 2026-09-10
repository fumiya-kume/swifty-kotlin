@testable import CompilerCore
import Testing

/// KSP-654: `Throwable` members are declared in bundled Kotlin source
/// (`Stdlib/kotlin/Throwable.kt`) instead of synthetic stubs, so they carry no
/// `kk_*` external link name of their own.
@Suite(.serialized)
struct ThrowableMemberSourceTests {
    private static let sharedSource = """
    fun sampleSuppressed(e: Throwable) {
        val suppressed: List<Throwable> = e.suppressedExceptions
    }

    fun sampleSubclass(e: IllegalStateException): Int {
        val text: String? = e.message
        val root: Throwable? = e.cause
        e.addSuppressed(IllegalArgumentException("x"))
        e.initCause(root)
        return e.getSuppressed().size + e.suppressedExceptions.size + (if (text == null) 0 else 1)
    }
    """

    private static nonisolated(unsafe) var _sharedSema: (SemaModule, StringInterner)?

    private func sharedSema() throws -> (SemaModule, StringInterner) {
        if let cached = Self._sharedSema { return cached }
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: Self.sharedSource) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
            #expect(!(ctx.diagnostics.hasError), "Expected Throwable surface to resolve cleanly, got: \(diagnostics)")
            result = try (#require(ctx.sema), ctx.interner)
        }
        let pair = try #require(result)
        Self._sharedSema = pair
        return pair
    }

    @Test
    func testMessageAndCauseAreSourceDeclaredMembers() throws {
        let (sema, interner) = try sharedSema()
        let throwableFQName = ["kotlin", "Throwable"].map { interner.intern($0) }
        let throwableSymbol = try #require(sema.symbols.lookup(fqName: throwableFQName))
        let nullableThrowableType = sema.types.make(.classType(ClassType(
            classSymbol: throwableSymbol,
            args: [],
            nullability: .nullable
        )))

        let message = try #require(sema.symbols.lookupAll(
            fqName: throwableFQName + [interner.intern("message")]
        ).first { sema.symbols.symbol($0)?.kind == .property })
        #expect(sema.symbols.propertyType(for: message) == sema.types.makeNullable(sema.types.stringType))
        #expect(sema.symbols.externalLinkName(for: message) == nil)

        let cause = try #require(sema.symbols.lookupAll(
            fqName: throwableFQName + [interner.intern("cause")]
        ).first { sema.symbols.symbol($0)?.kind == .property })
        #expect(sema.symbols.propertyType(for: cause) == nullableThrowableType)
        #expect(sema.symbols.externalLinkName(for: cause) == nil)
    }

    @Test
    func testSuppressedExceptionsRootExtensionPropertyIsRegistered() throws {
        let (sema, interner) = try sharedSema()
        let kotlinPackage = ["kotlin"].map { interner.intern($0) }
        let collectionsPackage = ["kotlin", "collections"].map { interner.intern($0) }

        let throwableSymbol = try #require(sema.symbols.lookup(
            fqName: kotlinPackage + [interner.intern("Throwable")]
        ))
        let listSymbol = try #require(sema.symbols.lookup(
            fqName: collectionsPackage + [interner.intern("List")]
        ))
        let throwableType = sema.types.make(.classType(ClassType(
            classSymbol: throwableSymbol,
            args: [],
            nullability: .nonNull
        )))
        let propertySymbol = try #require(
            sema.symbols.lookupAll(
                fqName: kotlinPackage + [interner.intern("suppressedExceptions")]
            ).first { symbolID in
                sema.symbols.symbol(symbolID)?.kind == .property
                    && sema.symbols.extensionPropertyReceiverType(for: symbolID) == throwableType
            },
            "Expected kotlin.Throwable.suppressedExceptions root extension property"
        )

        let propertyType = try #require(sema.symbols.propertyType(for: propertySymbol))
        guard case let .classType(listType) = sema.types.kind(of: propertyType) else {
            Issue.record("Expected suppressedExceptions to be List<Throwable>")
            return
        }
        #expect(listType.classSymbol == listSymbol)
        switch listType.args.first {
        case let .invariant(element), let .out(element), let .in(element):
            #expect(element == throwableType)
        default:
            Issue.record("Expected suppressedExceptions element type argument")
        }
        #expect(sema.symbols.externalLinkName(for: propertySymbol) == nil)
    }

    @Test
    func testSuppressedExceptionsCanBeAssignedToListOfThrowable() throws {
        let (sema, interner) = try sharedSema()
        let sampleSymbol = try #require(sema.symbols.lookup(
            fqName: [interner.intern("sampleSuppressed")]
        ))

        #expect(sema.symbols.functionSignature(for: sampleSymbol) != nil)
    }

    @Test
    func testMemberSurfaceTypeChecksOnSubclassReceivers() throws {
        let (sema, interner) = try sharedSema()
        let sampleSymbol = try #require(sema.symbols.lookup(
            fqName: [interner.intern("sampleSubclass")]
        ))

        #expect(sema.symbols.functionSignature(for: sampleSymbol)?.returnType == sema.types.intType)
    }
}
