@testable import CompilerCore
import XCTest

final class JsCollectionsViewInteropTests: XCTestCase {
    private func makeSema(
        source: String = "fun noop() {}"
    ) throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected JS collections view surface to resolve cleanly, got: \(diagnostics)"
            )
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testArrayViewFunctionsAreRegistered() throws {
        let (sema, interner) = try makeSema()

        try assertViewFunction(
            "asJsReadonlyArrayView",
            externalLinkName: "kk_list_asJsReadonlyArrayView",
            typeParameterCount: 1,
            receiverFQName: ["kotlin", "collections", "List"],
            returnFQName: ["kotlin", "js", "collections", "JsReadonlyArray"],
            sema: sema,
            interner: interner
        )
        try assertViewFunction(
            "asJsArrayView",
            externalLinkName: "kk_mutable_list_asJsArrayView",
            typeParameterCount: 1,
            receiverFQName: ["kotlin", "collections", "MutableList"],
            returnFQName: ["kotlin", "js", "collections", "JsArray"],
            sema: sema,
            interner: interner
        )
    }

    func testMapAndSetViewFunctionsAreRegistered() throws {
        let (sema, interner) = try makeSema()

        try assertViewFunction(
            "asJsReadonlyMapView",
            externalLinkName: "kk_map_asJsReadonlyMapView",
            typeParameterCount: 2,
            receiverFQName: ["kotlin", "collections", "Map"],
            returnFQName: ["kotlin", "js", "collections", "JsReadonlyMap"],
            sema: sema,
            interner: interner
        )
        try assertViewFunction(
            "asJsMapView",
            externalLinkName: "kk_mutable_map_asJsMapView",
            typeParameterCount: 2,
            receiverFQName: ["kotlin", "collections", "MutableMap"],
            returnFQName: ["kotlin", "js", "collections", "JsMap"],
            sema: sema,
            interner: interner
        )
        try assertViewFunction(
            "asJsReadonlySetView",
            externalLinkName: "kk_set_asJsReadonlySetView",
            typeParameterCount: 1,
            receiverFQName: ["kotlin", "collections", "Set"],
            returnFQName: ["kotlin", "js", "collections", "JsReadonlySet"],
            sema: sema,
            interner: interner
        )
        try assertViewFunction(
            "asJsSetView",
            externalLinkName: "kk_mutable_set_asJsSetView",
            typeParameterCount: 1,
            receiverFQName: ["kotlin", "collections", "MutableSet"],
            returnFQName: ["kotlin", "js", "collections", "JsSet"],
            sema: sema,
            interner: interner
        )
    }

    func testViewFunctionsResolveFromImportedSource() throws {
        let source = """
        @file:OptIn(kotlin.js.collections.ExperimentalJsCollectionsApi::class)

        import kotlin.js.collections.JsMap
        import kotlin.js.collections.JsReadonlyArray
        import kotlin.js.collections.JsSet
        import kotlin.js.collections.asJsMapView
        import kotlin.js.collections.asJsReadonlyArrayView
        import kotlin.js.collections.asJsSetView

        fun jsMapView(values: MutableMap<String, Int>): JsMap<String, Int> = values.asJsMapView()
        fun jsSetView(values: MutableSet<String>): JsSet<String> = values.asJsSetView()
        fun jsArrayView(values: List<Int>): JsReadonlyArray<Int> = values.asJsReadonlyArrayView()
        """

        let (sema, interner) = try makeSema(source: source)
        try assertFunctionReturnClass(
            "jsMapView",
            expectedFQName: ["kotlin", "js", "collections", "JsMap"],
            sema: sema,
            interner: interner
        )
        try assertFunctionReturnClass(
            "jsSetView",
            expectedFQName: ["kotlin", "js", "collections", "JsSet"],
            sema: sema,
            interner: interner
        )
        try assertFunctionReturnClass(
            "jsArrayView",
            expectedFQName: ["kotlin", "js", "collections", "JsReadonlyArray"],
            sema: sema,
            interner: interner
        )
    }

    private func assertViewFunction(
        _ name: String,
        externalLinkName: String,
        typeParameterCount: Int,
        receiverFQName: [String],
        returnFQName: [String],
        sema: SemaModule,
        interner: StringInterner,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let jsCollectionsPkg = ["kotlin", "js", "collections"].map { interner.intern($0) }
        let receiverSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: receiverFQName.map { interner.intern($0) }),
            file: file,
            line: line
        )
        let returnSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: returnFQName.map { interner.intern($0) }),
            file: file,
            line: line
        )
        let function = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: jsCollectionsPkg + [interner.intern(name)]).first {
                sema.symbols.externalLinkName(for: $0) == externalLinkName
            },
            "\(name) must be registered",
            file: file,
            line: line
        )
        let info = try XCTUnwrap(sema.symbols.symbol(function), file: file, line: line)
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: function), file: file, line: line)

        XCTAssertEqual(info.visibility, .public, file: file, line: line)
        XCTAssertTrue(info.flags.contains(.synthetic), file: file, line: line)
        XCTAssertEqual(signature.parameterTypes, [], file: file, line: line)
        XCTAssertEqual(signature.typeParameterSymbols.count, typeParameterCount, file: file, line: line)
        XCTAssertTrue(sema.symbols.annotations(for: function).contains {
            $0.annotationFQName == "kotlin.js.collections.ExperimentalJsCollectionsApi"
        }, file: file, line: line)

        guard let receiverType = signature.receiverType,
              case let .classType(receiverClassType) = sema.types.kind(of: receiverType) else {
            return XCTFail("Expected \(name) to have a class receiver", file: file, line: line)
        }
        XCTAssertEqual(receiverClassType.classSymbol, receiverSymbol, file: file, line: line)

        guard case let .classType(returnClassType) = sema.types.kind(of: signature.returnType) else {
            return XCTFail("Expected \(name) to return a JS collection class", file: file, line: line)
        }
        XCTAssertEqual(returnClassType.classSymbol, returnSymbol, file: file, line: line)
    }

    private func assertFunctionReturnClass(
        _ name: String,
        expectedFQName: [String],
        sema: SemaModule,
        interner: StringInterner,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let functionSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: [interner.intern(name)]),
            file: file,
            line: line
        )
        let expectedSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: expectedFQName.map { interner.intern($0) }),
            file: file,
            line: line
        )
        let signature = try XCTUnwrap(
            sema.symbols.functionSignature(for: functionSymbol),
            file: file,
            line: line
        )
        guard case let .classType(returnClassType) = sema.types.kind(of: signature.returnType) else {
            return XCTFail("\(name) must return a JS collection class", file: file, line: line)
        }
        XCTAssertEqual(returnClassType.classSymbol, expectedSymbol, file: file, line: line)
    }
}
