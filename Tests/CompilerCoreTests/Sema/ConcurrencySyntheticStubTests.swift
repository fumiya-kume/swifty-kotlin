@testable import CompilerCore
import Foundation
import XCTest

final class ConcurrencySyntheticStubTests: XCTestCase {
    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testThreadClassAndFunctionSignatures() throws {
        let (sema, interner) = try makeSema()

        let threadFQName = ["java", "lang", "Thread"].map { interner.intern($0) }
        let threadSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: threadFQName),
            "Expected java.lang.Thread to be registered"
        )
        XCTAssertEqual(sema.symbols.symbol(threadSymbol)?.kind, .class)

        let threadType = sema.types.make(.classType(ClassType(
            classSymbol: threadSymbol,
            args: [],
            nullability: .nonNull
        )))
        XCTAssertEqual(sema.symbols.propertyType(for: threadSymbol), threadType)

        let threadFunctionFQName = ["kotlin", "concurrent", "thread"].map { interner.intern($0) }
        let threadFunctionSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: threadFunctionFQName),
            "Expected kotlin.concurrent.thread to be registered"
        )
        let threadSignature = try XCTUnwrap(sema.symbols.functionSignature(for: threadFunctionSymbol))
        XCTAssertTrue(sema.symbols.symbol(threadFunctionSymbol)?.flags.contains(.synthetic) == true)
        XCTAssertTrue(sema.symbols.symbol(threadFunctionSymbol)?.flags.contains(.inlineFunction) == true)
        XCTAssertEqual(sema.symbols.externalLinkName(for: threadFunctionSymbol), "kk_thread_create")
        XCTAssertEqual(threadSignature.receiverType, nil)
        XCTAssertEqual(threadSignature.returnType, threadType)
        XCTAssertEqual(threadSignature.parameterTypes.count, 6)
        XCTAssertEqual(threadSignature.parameterTypes[0], sema.types.booleanType)
        XCTAssertEqual(threadSignature.parameterTypes[1], sema.types.booleanType)
        XCTAssertEqual(threadSignature.parameterTypes[3], sema.types.makeNullable(sema.types.stringType))
        XCTAssertEqual(threadSignature.parameterTypes[4], sema.types.intType)

        let classLoaderFQName = ["java", "lang", "ClassLoader"].map { interner.intern($0) }
        let classLoaderSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: classLoaderFQName),
            "Expected java.lang.ClassLoader to be registered"
        )
        let classLoaderType = sema.types.make(.classType(ClassType(
            classSymbol: classLoaderSymbol,
            args: [],
            nullability: .nonNull
        )))
        let nullableClassLoaderType = sema.types.makeNullable(classLoaderType)
        XCTAssertEqual(threadSignature.parameterTypes[2], nullableClassLoaderType)

        let blockType = sema.types.make(.functionType(FunctionType(
            params: [],
            returnType: sema.types.unitType
        )))
        XCTAssertEqual(threadSignature.parameterTypes[5], blockType)
        XCTAssertEqual(threadSignature.valueParameterHasDefaultValues, [true, true, true, true, true, false])
    }

    func testThreadResolvesInSource() throws {
        let source = """
        import kotlin.concurrent.thread

        fun probe(): Unit {
            thread(
                start = false,
                isDaemon = false,
                contextClassLoader = null,
                name = "worker",
                priority = 7,
                block = {}
            )
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected thread call to resolve: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
            XCTAssertTrue(
                ctx.diagnostics.diagnostics.isEmpty,
                "Unexpected diagnostics: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
        }
    }

}
