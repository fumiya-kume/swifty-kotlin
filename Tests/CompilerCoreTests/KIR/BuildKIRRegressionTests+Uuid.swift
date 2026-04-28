@testable import CompilerCore
import Foundation
import XCTest

extension BuildKIRRegressionTests {
    func testUuidCompanionAndInstanceCallsLowerToRuntimeCallees() throws {
        let source = """
        @file:OptIn(kotlin.uuid.ExperimentalUuidApi::class)

        import kotlin.uuid.Uuid

        fun main() {
            val nil = Uuid.NIL
            val uuid = Uuid.parse("550e8400-e29b-41d4-a716-446655440000")
            val hexUuid = Uuid.parseHex("550e8400e29b41d4a716446655440000")
            nil.toString()
            uuid.toString()
            hexUuid.toString()
            uuid.toHexString()
            uuid.toLongs()
            uuid.toByteArray()
            uuid.version()
            uuid.variant()
            val msb = uuid.mostSignificantBits
            val lsb = uuid.leastSignificantBits
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            XCTAssertTrue(callees.contains("kk_uuid_nil"), "Expected Uuid.NIL runtime call")
            XCTAssertTrue(callees.contains("kk_uuid_parse"), "Expected Uuid.parse runtime call")
            XCTAssertTrue(callees.contains("kk_uuid_parseHex"), "Expected Uuid.parseHex runtime call")
            XCTAssertTrue(callees.contains("kk_uuid_toString"), "Expected Uuid.toString runtime call")
            XCTAssertTrue(callees.contains("kk_uuid_toHexString"), "Expected Uuid.toHexString runtime call")
            XCTAssertTrue(callees.contains("kk_uuid_toLongs"), "Expected Uuid.toLongs runtime call")
            XCTAssertTrue(callees.contains("kk_uuid_toByteArray"), "Expected Uuid.toByteArray runtime call")
            XCTAssertTrue(callees.contains("kk_uuid_version"), "Expected Uuid.version runtime call")
            XCTAssertTrue(callees.contains("kk_uuid_variant"), "Expected Uuid.variant runtime call")
            XCTAssertTrue(callees.contains("kk_uuid_mostSignificantBits"), "Expected Uuid.mostSignificantBits runtime call")
            XCTAssertTrue(callees.contains("kk_uuid_leastSignificantBits"), "Expected Uuid.leastSignificantBits runtime call")
        }
    }

    func testUuidAdditionalFactoriesLowerToRuntimeCallees() throws {
        let source = """
        @file:OptIn(kotlin.uuid.ExperimentalUuidApi::class)

        import kotlin.uuid.Uuid

        fun main(bytes: ByteArray) {
            Uuid.random()
            Uuid.nameUUIDFromBytes(bytes)
            Uuid.fromLongs(0L, 1L)
            Uuid.fromByteArray(bytes)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            XCTAssertTrue(callees.contains("kk_uuid_random"), "Expected Uuid.random runtime call")
            XCTAssertTrue(callees.contains("kk_uuid_nameUUIDFromBytes"), "Expected Uuid.nameUUIDFromBytes runtime call")
            XCTAssertTrue(callees.contains("kk_uuid_fromLongs"), "Expected Uuid.fromLongs runtime call")
            XCTAssertTrue(callees.contains("kk_uuid_fromByteArray"), "Expected Uuid.fromByteArray runtime call")
        }
    }

    func testABILoweringMarksUuidPureRuntimeHelpersAsNonThrowing() {
        let pass = ABILoweringPass()
        let interner = StringInterner()
        let callees = pass.nonThrowingCallees(interner: interner)

        let nonThrowingUuidCallees = [
            "kk_uuid_random",
            "kk_uuid_nil",
            "kk_uuid_toString",
            "kk_uuid_toHexString",
            "kk_uuid_toLongs",
            "kk_uuid_toByteArray",
            "kk_uuid_version",
            "kk_uuid_variant",
            "kk_uuid_mostSignificantBits",
            "kk_uuid_leastSignificantBits",
            "kk_uuid_nameUUIDFromBytes",
            "kk_uuid_fromLongs",
        ]

        for callee in nonThrowingUuidCallees {
            XCTAssertTrue(
                callees.contains(interner.intern(callee)),
                "\(callee) should not receive an outThrown slot during ABI lowering"
            )
        }

        XCTAssertFalse(callees.contains(interner.intern("kk_uuid_parse")))
        XCTAssertFalse(callees.contains(interner.intern("kk_uuid_fromByteArray")))
    }
}
