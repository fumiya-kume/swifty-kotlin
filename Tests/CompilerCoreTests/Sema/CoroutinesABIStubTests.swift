@testable import CompilerCore
import Foundation
import XCTest

// STDLIB-CORO-ABI-001: Tests verifying that AbstractCoroutineContextElement,
// AbstractCoroutineContextKey, and the CoroutineContext.plus operator are
// registered as synthetic sema symbols and that user-defined context elements
// subclassing the abstract base resolve without diagnostics.

final class CoroutinesABIStubTests: XCTestCase {
    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    // ── Registration tests ────────────────────────────────────────────────

    func testAbstractCoroutineContextElementIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "coroutines", "AbstractCoroutineContextElement"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: fqName),
            "Expected kotlin.coroutines.AbstractCoroutineContextElement to be registered"
        )
        let info = try XCTUnwrap(sema.symbols.symbol(symbol))
        XCTAssertEqual(info.kind, .class)
        XCTAssertTrue(info.flags.contains(.synthetic))
        XCTAssertTrue(info.flags.contains(.abstractType))
    }

    func testAbstractCoroutineContextElementSupertype() throws {
        let (sema, interner) = try makeSema()
        let aceFQName = ["kotlin", "coroutines", "AbstractCoroutineContextElement"].map { interner.intern($0) }
        let aceSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: aceFQName))
        let elementFQName = ["kotlin", "coroutines", "CoroutineContext", "Element"].map { interner.intern($0) }
        let elementSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: elementFQName))
        XCTAssertTrue(
            sema.symbols.directSupertypes(for: aceSymbol).contains(elementSymbol),
            "AbstractCoroutineContextElement must extend CoroutineContext.Element"
        )
    }

    func testAbstractCoroutineContextElementPrimaryConstructor() throws {
        let (sema, interner) = try makeSema()
        let aceFQName = ["kotlin", "coroutines", "AbstractCoroutineContextElement"].map { interner.intern($0) }
        let aceSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: aceFQName))
        let ctorFQName = aceFQName + [interner.intern("<init>")]
        let ctorSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: ctorFQName),
            "Expected primary constructor for AbstractCoroutineContextElement"
        )
        let sig = try XCTUnwrap(sema.symbols.functionSignature(for: ctorSymbol))
        XCTAssertEqual(sig.parameterTypes.count, 1)
        // Receiver type must be ACE itself
        XCTAssertEqual(sig.receiverType, sema.symbols.propertyType(for: aceSymbol))
        // Single parameter must be Key<*>
        let keyFQName = ["kotlin", "coroutines", "CoroutineContext", "Key"].map { interner.intern($0) }
        let keySymbol = try XCTUnwrap(sema.symbols.lookup(fqName: keyFQName))
        guard case let .classType(paramKind) = sema.types.kind(of: sig.parameterTypes[0]) else {
            return XCTFail("Expected ACE ctor parameter to be a class type (Key<*>)")
        }
        XCTAssertEqual(paramKind.classSymbol, keySymbol)
        XCTAssertEqual(paramKind.args, [.star])
    }

    func testAbstractCoroutineContextKeyIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "coroutines", "AbstractCoroutineContextKey"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: fqName),
            "Expected kotlin.coroutines.AbstractCoroutineContextKey to be registered"
        )
        let info = try XCTUnwrap(sema.symbols.symbol(symbol))
        XCTAssertEqual(info.kind, .class)
        XCTAssertTrue(info.flags.contains(.synthetic))
        XCTAssertTrue(info.flags.contains(.abstractType))
    }

    func testAbstractCoroutineContextKeyHasTwoTypeParameters() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "coroutines", "AbstractCoroutineContextKey"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: fqName))
        let typeParams = sema.types.nominalTypeParameterSymbols(for: symbol)
        XCTAssertEqual(typeParams.count, 2, "AbstractCoroutineContextKey must have two type parameters B and E")
    }

    func testAbstractCoroutineContextKeyExtendsKey() throws {
        let (sema, interner) = try makeSema()
        let ackFQName = ["kotlin", "coroutines", "AbstractCoroutineContextKey"].map { interner.intern($0) }
        let ackSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: ackFQName))
        let keyFQName = ["kotlin", "coroutines", "CoroutineContext", "Key"].map { interner.intern($0) }
        let keySymbol = try XCTUnwrap(sema.symbols.lookup(fqName: keyFQName))
        XCTAssertTrue(
            sema.symbols.directSupertypes(for: ackSymbol).contains(keySymbol),
            "AbstractCoroutineContextKey must implement CoroutineContext.Key"
        )
    }

    func testCoroutineContextPlusOperatorIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "coroutines", "CoroutineContext", "plus"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: fqName),
            "Expected CoroutineContext.plus operator to be registered"
        )
        let info = try XCTUnwrap(sema.symbols.symbol(symbol))
        XCTAssertEqual(info.kind, .function)
        XCTAssertTrue(info.flags.contains(.operatorFunction))
        XCTAssertTrue(info.flags.contains(.synthetic))
        let sig = try XCTUnwrap(sema.symbols.functionSignature(for: symbol))
        XCTAssertEqual(sig.parameterTypes.count, 1)
        let contextFQName = ["kotlin", "coroutines", "CoroutineContext"].map { interner.intern($0) }
        let contextSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: contextFQName))
        let contextType = sema.types.make(.classType(ClassType(
            classSymbol: contextSymbol,
            args: [],
            nullability: .nonNull
        )))
        XCTAssertEqual(sig.parameterTypes[0], contextType)
        XCTAssertEqual(sig.returnType, contextType)
    }

    func testCoroutineContextKeyNestedInterfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "coroutines", "CoroutineContext", "Key"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: fqName),
            "Expected CoroutineContext.Key to be registered"
        )
        XCTAssertEqual(sema.symbols.symbol(symbol)?.kind, .interface)
    }

    func testCoroutineContextElementNestedInterfaceExtendsCoroutineContext() throws {
        let (sema, interner) = try makeSema()
        let elementFQName = ["kotlin", "coroutines", "CoroutineContext", "Element"].map { interner.intern($0) }
        let elementSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: elementFQName))
        let contextFQName = ["kotlin", "coroutines", "CoroutineContext"].map { interner.intern($0) }
        let contextSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: contextFQName))
        XCTAssertTrue(
            sema.symbols.directSupertypes(for: elementSymbol).contains(contextSymbol),
            "CoroutineContext.Element must extend CoroutineContext"
        )
    }

    func testCoroutineContextGetPolymorphicElementIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "coroutines", "getPolymorphicElement"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: fqName),
            "Expected kotlin.coroutines.getPolymorphicElement to be registered"
        )
        let info = try XCTUnwrap(sema.symbols.symbol(symbol))
        XCTAssertEqual(info.kind, .function)
        XCTAssertTrue(info.flags.contains(.synthetic))
        XCTAssertEqual(sema.symbols.externalLinkName(for: symbol), "kk_context_get")

        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbol))
        let elementSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: ["kotlin", "coroutines", "CoroutineContext", "Element"].map { interner.intern($0) })
        )
        let keySymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: ["kotlin", "coroutines", "CoroutineContext", "Key"].map { interner.intern($0) })
        )
        let elementType = sema.types.make(.classType(ClassType(
            classSymbol: elementSymbol,
            args: [],
            nullability: .nonNull
        )))
        let typeParam = try XCTUnwrap(signature.typeParameterSymbols.first)
        let typeParamType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParam,
            nullability: .nonNull
        )))
        let keyType = sema.types.make(.classType(ClassType(
            classSymbol: keySymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))
        XCTAssertEqual(signature.receiverType, elementType)
        XCTAssertEqual(signature.parameterTypes, [keyType])
        XCTAssertEqual(signature.returnType, sema.types.makeNullable(typeParamType))
        XCTAssertEqual(signature.typeParameterUpperBoundsList, [[elementType]])
        XCTAssertTrue(
            sema.symbols.annotations(for: symbol).contains {
                $0.annotationFQName == KnownCompilerAnnotation.experimentalStdlibApi.qualifiedName
            },
            "getPolymorphicElement should carry ExperimentalStdlibApi"
        )
    }

    // ── Integration / subclassing pattern tests ──────────────────────────────

    func testUserDefinedContextElementSubclassResolvesWithoutDiagnostics() throws {
        let source = """
        import kotlin.coroutines.AbstractCoroutineContextElement
        import kotlin.coroutines.CoroutineContext

        class MyElement(
            val value: String
        ) : AbstractCoroutineContextElement(MyElement) {
            companion object Key : CoroutineContext.Key<MyElement>
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected no errors for user-defined CoroutineContext.Element: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
        }
    }

    func testCoroutinePlusOperatorResolvesInSource() throws {
        let source = """
        import kotlin.coroutines.EmptyCoroutineContext
        import kotlinx.coroutines.CoroutineName

        fun probe(): kotlin.coroutines.CoroutineContext {
            return EmptyCoroutineContext + CoroutineName("test")
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected CoroutineContext.plus to resolve: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
        }
    }

    func testGetPolymorphicElementResolvesInSourceWithOptIn() throws {
        let source = """
        import kotlin.ExperimentalStdlibApi
        import kotlin.OptIn
        import kotlin.coroutines.AbstractCoroutineContextElement
        import kotlin.coroutines.CoroutineContext
        import kotlin.coroutines.CoroutineContext.Key
        import kotlin.coroutines.getPolymorphicElement

        class MyElement : AbstractCoroutineContextElement(MyElement) {
            companion object Key : CoroutineContext.Key<MyElement>
        }

        @OptIn(ExperimentalStdlibApi::class)
        fun probe(element: MyElement, key: Key<MyElement>): MyElement? {
            return element.getPolymorphicElement(key)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected getPolymorphicElement to resolve: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
        }
    }
}
