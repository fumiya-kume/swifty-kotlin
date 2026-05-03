@testable import CompilerCore
import Foundation
import XCTest

final class ReflectKPropertyIsInitializedSyntheticTests: XCTestCase {
    func testKProperty0IsInitializedRootExtensionPropertyIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let propertyName = interner.intern("isInitialized")
        let propertySymbol = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: [interner.intern("kotlin"), propertyName]).first { symbolID in
                sema.symbols.symbol(symbolID)?.kind == .property
            }
        )

        XCTAssertEqual(sema.symbols.propertyType(for: propertySymbol), sema.types.booleanType)
        let receiverType = try XCTUnwrap(sema.symbols.extensionPropertyReceiverType(for: propertySymbol))
        guard case let .classType(classType) = sema.types.kind(of: receiverType) else {
            XCTFail("Expected KProperty0 receiver type, got \(sema.types.kind(of: receiverType))")
            return
        }
        let receiverSymbol = try XCTUnwrap(sema.symbols.symbol(classType.classSymbol))
        XCTAssertEqual(receiverSymbol.fqName.map { interner.resolve($0) }, ["kotlin", "reflect", "KProperty0"])
    }

    func testLateinitPropertyReferenceStillUsesSpecialRestriction() {
        let source = """
        class Box {
            var name: String = "value"
            fun ready(): Boolean = ::name.isInitialized
        }
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-LATEINIT" }

        XCTAssertEqual(diagnostics.count, 1, "Expected non-lateinit property reference to be rejected, got: \(ctx.diagnostics.diagnostics)")
    }

    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            result = (sema, ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    private func runSemaCollectingDiagnostics(_ source: String) -> CompilationContext {
        let fakePath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(inputs: [fakePath])
        _ = ctx.sourceManager.addFile(path: fakePath, contents: Data(source.utf8))
        do {
            try runSema(ctx)
        } catch {
            // Error diagnostics are asserted by each test.
        }
        return ctx
    }
}
