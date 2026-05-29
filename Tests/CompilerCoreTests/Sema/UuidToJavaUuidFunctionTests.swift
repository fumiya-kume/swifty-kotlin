@testable import CompilerCore
import XCTest

/// STDLIB-UUID-FN-003: Validates `Uuid.toJavaUuid()` as a kotlin.uuid
/// package-level extension function.
final class UuidToJavaUuidFunctionTests: XCTestCase {
    func testUuidToJavaUuidSyntheticFunctionIsRegistered() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner
        let kotlinUuidPkg = ["kotlin", "uuid"].map { interner.intern($0) }

        let functionSymbol = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: kotlinUuidPkg + [interner.intern("toJavaUuid")]).first {
                sema.symbols.externalLinkName(for: $0) == "kk_uuid_to_java_uuid"
            },
            "Uuid.toJavaUuid must link to kk_uuid_to_java_uuid"
        )
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: functionSymbol))
        let uuidSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: kotlinUuidPkg + [interner.intern("Uuid")]))
        let javaUuidSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
            interner.intern("java"),
            interner.intern("util"),
            interner.intern("UUID"),
        ]))

        guard case .classType(let receiverType) = sema.types.kind(of: signature.receiverType) else {
            XCTFail("toJavaUuid receiver must be kotlin.uuid.Uuid")
            return
        }
        XCTAssertEqual(receiverType.classSymbol, uuidSymbol)

        guard case .classType(let returnType) = sema.types.kind(of: signature.returnType) else {
            XCTFail("toJavaUuid return type must be java.util.UUID")
            return
        }
        XCTAssertEqual(returnType.classSymbol, javaUuidSymbol)
        XCTAssertTrue(sema.symbols.symbol(functionSymbol)?.flags.contains(.inlineFunction) == true)
        XCTAssertTrue(sema.symbols.annotations(for: functionSymbol).contains {
            $0.annotationFQName == "kotlin.uuid.ExperimentalUuidApi"
        })
    }

    func testUuidToJavaUuidResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import java.util.UUID
        import kotlin.OptIn
        import kotlin.uuid.ExperimentalUuidApi
        import kotlin.uuid.Uuid
        import kotlin.uuid.toJavaUuid

        @OptIn(ExperimentalUuidApi::class)
        fun convert(uuid: Uuid): UUID {
            return uuid.toJavaUuid()
        }
        """)
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected Uuid.toJavaUuid() to type-check, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
