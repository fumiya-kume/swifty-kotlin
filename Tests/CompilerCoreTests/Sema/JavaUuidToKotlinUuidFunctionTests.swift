@testable import CompilerCore
import XCTest

/// STDLIB-UUID-FN-004: Validates `UUID.toKotlinUuid()` as a kotlin.uuid
/// package-level extension function.
final class JavaUuidToKotlinUuidFunctionTests: XCTestCase {
    func testJavaUuidToKotlinUuidSyntheticFunctionIsRegistered() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner
        let kotlinUuidPkg = ["kotlin", "uuid"].map { interner.intern($0) }

        let functionSymbol = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: kotlinUuidPkg + [interner.intern("toKotlinUuid")]).first {
                sema.symbols.externalLinkName(for: $0) == "kk_java_uuid_to_kotlin_uuid"
            },
            "UUID.toKotlinUuid must link to kk_java_uuid_to_kotlin_uuid"
        )
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: functionSymbol))
        let javaUuidSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
            interner.intern("java"),
            interner.intern("util"),
            interner.intern("UUID"),
        ]))
        let uuidSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: kotlinUuidPkg + [interner.intern("Uuid")]))

        guard case .classType(let receiverType) = sema.types.kind(of: signature.receiverType) else {
            XCTFail("toKotlinUuid receiver must be java.util.UUID")
            return
        }
        XCTAssertEqual(receiverType.classSymbol, javaUuidSymbol)

        guard case .classType(let returnType) = sema.types.kind(of: signature.returnType) else {
            XCTFail("toKotlinUuid return type must be kotlin.uuid.Uuid")
            return
        }
        XCTAssertEqual(returnType.classSymbol, uuidSymbol)
        XCTAssertTrue(sema.symbols.symbol(functionSymbol)?.flags.contains(.inlineFunction) == true)
        XCTAssertTrue(sema.symbols.annotations(for: functionSymbol).contains {
            $0.annotationFQName == "kotlin.uuid.ExperimentalUuidApi"
        })
    }

    func testJavaUuidToKotlinUuidResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import java.util.UUID
        import kotlin.OptIn
        import kotlin.uuid.ExperimentalUuidApi
        import kotlin.uuid.Uuid
        import kotlin.uuid.toKotlinUuid

        @OptIn(ExperimentalUuidApi::class)
        fun convert(uuid: UUID): Uuid {
            return uuid.toKotlinUuid()
        }
        """)
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected UUID.toKotlinUuid() to type-check, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
