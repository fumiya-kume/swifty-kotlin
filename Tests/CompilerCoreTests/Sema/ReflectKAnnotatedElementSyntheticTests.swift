@testable import CompilerCore
import XCTest

final class ReflectKAnnotatedElementSyntheticTests: XCTestCase {
    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    private func runSemaCollectingDiagnostics(_ source: String) -> CompilationContext {
        var context: CompilationContext?
        do {
            try withTemporaryFile(contents: source) { path in
                let ctx = makeCompilationContext(inputs: [path])
                try? runSema(ctx)
                context = ctx
            }
        } catch {
            XCTFail("Failed to run sema: \(error)")
        }
        return context!
    }

    func testKAnnotatedElementAnnotationsSurfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let reflectFQ = ["kotlin", "reflect"].map { interner.intern($0) }
        let annotatedElementFQ = reflectFQ + [interner.intern("KAnnotatedElement")]
        let annotatedElementSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: annotatedElementFQ),
            "Expected kotlin.reflect.KAnnotatedElement to be registered"
        )
        XCTAssertEqual(sema.symbols.symbol(annotatedElementSymbol)?.kind, .interface)
        XCTAssertTrue(sema.symbols.symbol(annotatedElementSymbol)?.flags.contains(.synthetic) == true)

        let annotationsSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: annotatedElementFQ + [interner.intern("annotations")]),
            "Expected KAnnotatedElement.annotations to be registered"
        )
        XCTAssertEqual(sema.symbols.symbol(annotationsSymbol)?.kind, .property)

        let listSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: ["kotlin", "collections", "List"].map { interner.intern($0) })
        )
        let annotationSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: ["kotlin", "Annotation"].map { interner.intern($0) })
        )
        let annotationType = sema.types.make(.classType(ClassType(
            classSymbol: annotationSymbol,
            args: [],
            nullability: .nonNull
        )))
        let expectedAnnotationsType = sema.types.make(.classType(ClassType(
            classSymbol: listSymbol,
            args: [.out(annotationType)],
            nullability: .nonNull
        )))
        XCTAssertEqual(sema.symbols.propertyType(for: annotationsSymbol), expectedAnnotationsType)
    }

    func testReflectionInterfacesExposeKAnnotatedElementSupertypes() throws {
        let (sema, interner) = try makeSema()

        let reflectFQ = ["kotlin", "reflect"].map { interner.intern($0) }
        let annotatedElementSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: reflectFQ + [interner.intern("KAnnotatedElement")])
        )
        let kCallableSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: reflectFQ + [interner.intern("KCallable")])
        )
        let kTypeSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: reflectFQ + [interner.intern("KType")])
        )
        let kClassSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: reflectFQ + [interner.intern("KClass")])
        )
        let kClassifierSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: reflectFQ + [interner.intern("KClassifier")])
        )

        XCTAssertTrue(sema.symbols.directSupertypes(for: kCallableSymbol).contains(annotatedElementSymbol))
        XCTAssertTrue(sema.symbols.directSupertypes(for: kTypeSymbol).contains(annotatedElementSymbol))
        XCTAssertTrue(sema.symbols.directSupertypes(for: kClassSymbol).contains(annotatedElementSymbol))
        XCTAssertTrue(sema.symbols.directSupertypes(for: kClassSymbol).contains(kClassifierSymbol))
        XCTAssertTrue(sema.types.isNominalSubtypeSymbol(kClassSymbol, of: annotatedElementSymbol))
        XCTAssertTrue(sema.types.isNominalSubtypeSymbol(kCallableSymbol, of: annotatedElementSymbol))
    }

    func testKDeclarationContainerMembersSurfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let reflectFQ = ["kotlin", "reflect"].map { interner.intern($0) }
        let declarationContainerFQ = reflectFQ + [interner.intern("KDeclarationContainer")]
        let declarationContainerSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: declarationContainerFQ),
            "Expected kotlin.reflect.KDeclarationContainer to be registered"
        )
        XCTAssertEqual(sema.symbols.symbol(declarationContainerSymbol)?.kind, .interface)
        XCTAssertTrue(sema.symbols.symbol(declarationContainerSymbol)?.flags.contains(.synthetic) == true)

        let membersSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: declarationContainerFQ + [interner.intern("members")]),
            "Expected KDeclarationContainer.members to be registered"
        )
        XCTAssertEqual(sema.symbols.symbol(membersSymbol)?.kind, .property)

        let collectionSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: ["kotlin", "collections", "Collection"].map { interner.intern($0) })
        )
        let kCallableSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: reflectFQ + [interner.intern("KCallable")])
        )
        let kCallableStarType = sema.types.make(.classType(ClassType(
            classSymbol: kCallableSymbol,
            args: [.star],
            nullability: .nonNull
        )))
        let expectedMembersType = sema.types.make(.classType(ClassType(
            classSymbol: collectionSymbol,
            args: [.out(kCallableStarType)],
            nullability: .nonNull
        )))
        XCTAssertEqual(sema.symbols.propertyType(for: membersSymbol), expectedMembersType)

        let kClassSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: reflectFQ + [interner.intern("KClass")])
        )
        XCTAssertTrue(sema.symbols.directSupertypes(for: kClassSymbol).contains(declarationContainerSymbol))
        XCTAssertTrue(sema.types.isNominalSubtypeSymbol(kClassSymbol, of: declarationContainerSymbol))
    }

    func testKAnnotatedElementAnnotationsResolveInSource() throws {
        let source = """
        import kotlin.reflect.KAnnotatedElement
        import kotlin.reflect.KDeclarationContainer
        import kotlin.reflect.KClass

        annotation class Marker
        class Box

        fun annotationsOf(element: KAnnotatedElement): Int = element.annotations.size

        fun membersOf(container: KDeclarationContainer): Int = container.members.size

        fun kclassAnnotations(k: KClass<*>): Int = k.annotations.size

        fun classReferenceAsAnnotatedElement(): KAnnotatedElement = Box::class

        fun classReferenceAsDeclarationContainer(): KDeclarationContainer = Box::class
        """

        let ctx = runSemaCollectingDiagnostics(source)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected KAnnotatedElement.annotations to type-check, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
