@testable import Runtime
import Testing

@Suite
struct RuntimeKTypeProjectionTests {
    private func projection(
        varianceOrdinal: Int,
        typeRaw: Int
    ) throws -> RuntimeKTypeProjectionBox {
        let boxedVariance = kk_enum_box_ordinal(varianceOrdinal, 0, 0)
        #expect(kk_unbox_int(boxedVariance) == varianceOrdinal)

        var thrown = 0
        let raw = __kk_ktypeprojection_create_checked(boxedVariance, typeRaw, &thrown)
        #expect(thrown == 0)
        let pointer = try #require(
            UnsafeMutableRawPointer(bitPattern: raw),
            "Expected a KTypeProjection handle"
        )
        return try #require(
            tryCast(pointer, to: RuntimeKTypeProjectionBox.self),
            "Expected a RuntimeKTypeProjectionBox"
        )
    }

    @Test func boxedKVarianceOrdinalsPreserveConstructorVariance() throws {
        let invariant = try projection(varianceOrdinal: 0, typeRaw: 1)
        let `in` = try projection(varianceOrdinal: 1, typeRaw: 1)
        let out = try projection(varianceOrdinal: 2, typeRaw: 1)

        #expect(invariant.variance == .invariant)
        #expect(`in`.variance == .in)
        #expect(out.variance == .out)
    }

    @Test func nullPairCreatesStarProjection() throws {
        var thrown = 0
        let raw = __kk_ktypeprojection_create_checked(
            runtimeNullSentinelInt,
            runtimeNullSentinelInt,
            &thrown
        )
        #expect(thrown == 0)
        let pointer = try #require(UnsafeMutableRawPointer(bitPattern: raw))
        let box = try #require(tryCast(pointer, to: RuntimeKTypeProjectionBox.self))
        #expect(box.variance == nil)
        #expect(box.typeRaw == 0)
    }

    @Test func sourceBackedAccessorsExposeKotlinProjectionSurface() throws {
        let typeRaw = 1
        for (varianceOrdinal, expectedVarianceOrdinal) in [(0, 0), (1, 1), (2, 2)] {
            let boxedVariance = kk_enum_box_ordinal(varianceOrdinal, 0, 0)
            var thrown = 0
            let raw = __kk_ktypeprojection_create_checked(boxedVariance, typeRaw, &thrown)
            #expect(thrown == 0)
            #expect(__kk_ktypeprojection_get_variance(raw) == expectedVarianceOrdinal)
            #expect(__kk_ktypeprojection_get_type(raw) == typeRaw)
        }

        var thrown = 0
        let starRaw = __kk_ktypeprojection_create_checked(
            runtimeNullSentinelInt,
            runtimeNullSentinelInt,
            &thrown
        )
        #expect(thrown == 0)
        #expect(__kk_ktypeprojection_get_variance(starRaw) == runtimeNullSentinelInt)
        #expect(__kk_ktypeprojection_get_type(starRaw) == runtimeNullSentinelInt)
    }

    @Test func mismatchedNullablePairReportsKotlinValidationErrors() throws {
        let boxedIn = kk_enum_box_ordinal(1, 0, 0)
        var varianceThrown = 0
        _ = __kk_ktypeprojection_create_checked(boxedIn, runtimeNullSentinelInt, &varianceThrown)
        let varianceErrorPointer = try #require(UnsafeMutableRawPointer(bitPattern: varianceThrown))
        let varianceError = try #require(tryCast(varianceErrorPointer, to: RuntimeThrowableBox.self))
        #expect(varianceError.message == "The projection variance IN requires type to be specified.")

        var typeThrown = 0
        _ = __kk_ktypeprojection_create_checked(runtimeNullSentinelInt, 1, &typeThrown)
        let typeErrorPointer = try #require(UnsafeMutableRawPointer(bitPattern: typeThrown))
        let typeError = try #require(tryCast(typeErrorPointer, to: RuntimeThrowableBox.self))
        #expect(typeError.message == "Star projection must have no type specified.")
    }
}
