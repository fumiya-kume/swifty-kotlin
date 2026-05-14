@testable import CompilerCore
import XCTest

final class MemberRuntimeDispatchTests: XCTestCase {
    func testRangeRuntimeDispatchUsesTypedReceiverKind() {
        let cases: [(MemberDispatchReceiverKind, String, Int, String)] = [
            (.intRange, "random", 0, "kk_range_random"),
            (.intRange, "random", 1, "kk_range_random_random"),
            (.longRange, "random", 0, "kk_long_range_random"),
            (.longRange, "random", 1, "kk_long_range_random_random"),
            (.charRange, "random", 0, "kk_range_random"),
            (.charRange, "random", 1, "kk_char_range_random_random"),
            (.uintRange, "randomOrNull", 0, "kk_uint_range_randomOrNull"),
            (.ulongRange, "randomOrNull", 1, "kk_ulong_range_randomOrNull_random"),
            (.charRange, "randomOrNull", 0, "kk_char_range_randomOrNull"),
            (.longRange, "firstOrNull", 0, "kk_long_range_firstOrNull"),
            (.longRange, "firstOrNull", 2, "kk_range_firstOrNull_predicate"),
            (.longRange, "lastOrNull", 0, "kk_long_range_lastOrNull"),
            (.longRange, "lastOrNull", 2, "kk_range_lastOrNull_predicate"),
            (.charProgression, "toList", 0, "kk_char_range_toList"),
            (.charProgression, "step", 1, "kk_char_range_step"),
            (.longProgression, "step", 0, "kk_long_range_step"),
            (.uintProgression, "step", 2, "kk_uint_step"),
            (.ulongProgression, "contains", 1, "kk_ulong_range_contains"),
        ]

        for (receiverKind, memberName, arity, expectedLinkName) in cases {
            let key = MemberDispatchKey(receiverKind: receiverKind, memberName: memberName, arity: arity)
            XCTAssertEqual(
                MemberRuntimeDispatch.rangeRuntimeLinkName(for: key),
                expectedLinkName,
                "\(receiverKind.rawValue).\(memberName)/\(arity)"
            )
        }
    }

    func testCollectionRuntimeDispatchUsesStdlibSurfaceSpec() {
        let cases: [(MemberDispatchReceiverKind, String, Int, String)] = [
            (.iterable, "firstNotNullOf", 1, "kk_iterable_firstNotNullOf"),
            (.list, "filterIndexedTo", 2, "kk_list_filterIndexedTo"),
            (.set, "map", 1, "kk_list_map"),
            (.map, "filterKeys", 1, "kk_map_filterKeys"),
            (.map, "mapValuesTo", 2, "kk_map_mapValuesTo"),
            (.sequence, "firstNotNullOf", 1, "kk_sequence_firstNotNullOf"),
        ]

        for (receiverKind, memberName, arity, expectedLinkName) in cases {
            let key = MemberDispatchKey(receiverKind: receiverKind, memberName: memberName, arity: arity)
            XCTAssertEqual(
                MemberRuntimeDispatch.collectionRuntimeLinkName(for: key),
                expectedLinkName,
                "\(receiverKind.rawValue).\(memberName)/\(arity)"
            )
        }
    }

    func testCollectionRuntimeDispatchIgnoresNonSurfaceMembers() {
        let cases: [(MemberDispatchReceiverKind, String, Int)] = [
            (.list, "size", 0),
            (.map, "getValue", 1),
            (.sequence, "toList", 0),
            (.intRange, "map", 1),
        ]

        for (receiverKind, memberName, arity) in cases {
            let key = MemberDispatchKey(receiverKind: receiverKind, memberName: memberName, arity: arity)
            XCTAssertNil(
                MemberRuntimeDispatch.collectionRuntimeLinkName(for: key),
                "\(receiverKind.rawValue).\(memberName)/\(arity)"
            )
        }
    }
}
