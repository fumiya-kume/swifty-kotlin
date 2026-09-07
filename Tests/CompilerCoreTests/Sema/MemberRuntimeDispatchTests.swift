#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct MemberRuntimeDispatchTests {
    @Test func testRangeRuntimeDispatchUsesTypedReceiverKind() {
        let cases: [(MemberDispatchReceiverKind, String, Int, String?)] = [
            (.intRange, "random", 0, nil),
            (.intRange, "random", 1, nil),
            (.longRange, "random", 0, nil),
            (.longRange, "random", 1, nil),
            (.charRange, "random", 0, nil),
            (.charRange, "random", 1, nil),
            (.uintRange, "randomOrNull", 0, nil),
            (.ulongRange, "randomOrNull", 1, nil),
            (.charRange, "randomOrNull", 0, nil),
            (.longRange, "firstOrNull", 0, "kk_long_range_firstOrNull"),
            (.longRange, "firstOrNull", 2, "kk_range_firstOrNull_predicate"),
            (.longRange, "lastOrNull", 0, "kk_long_range_lastOrNull"),
            (.longRange, "lastOrNull", 2, "kk_range_lastOrNull_predicate"),
            (.charProgression, "toList", 0, "kk_char_range_toList"),
            (.charProgression, "step", 1, "__kk_char_range_step"),
            (.longProgression, "step", 0, "kk_long_range_step"),
            (.uintProgression, "step", 2, nil),
            (.ulongProgression, "contains", 1, "kk_ulong_range_contains"),
            // step(n) as a dot call (arity 1) must resolve to the progression-
            // constructing runtime function, not the step-property getter
            // (KSWIFTK-RUNTIME-0001: (1L..10L).step(2L) used to alias the getter
            // and hand back a raw step value instead of a new range handle).
            (.intRange, "step", 1, "__kk_op_step"),
            (.longRange, "step", 1, "__kk_op_step"),
            (.longProgression, "step", 1, "__kk_op_step"),
            (.uintRange, "step", 1, nil),
            (.ulongRange, "step", 1, "__kk_ulong_step"),
        ]

        for (receiverKind, memberName, arity, expectedLinkName) in cases {
            let key = MemberDispatchKey(receiverKind: receiverKind, memberName: memberName, arity: arity)
            #expect(
                MemberRuntimeDispatch.rangeRuntimeLinkName(for: key) == expectedLinkName,
                "\(receiverKind.rawValue).\(memberName)/\(arity)"
            )
        }
    }

    @Test func testUIntRangeHOFDispatchDefersToBundledSource() {
        let sourceBackedMembers: [(String, Int)] = [
            ("iterator", 0), ("step", 1),
            ("forEach", 1),
            ("reduce", 1), ("reduceIndexed", 1), ("fold", 2), ("foldIndexed", 2),
            ("find", 1), ("findLast", 1),
            ("first", 1), ("firstOrNull", 1), ("last", 1), ("lastOrNull", 1),
            ("any", 1), ("all", 1), ("none", 1),
            ("take", 1), ("drop", 1), ("chunked", 1), ("windowed", 1),
        ]
        for member in sourceBackedMembers {
            let key = MemberDispatchKey(receiverKind: .uintRange, memberName: member.0, arity: member.1)
            #expect(
                MemberRuntimeDispatch.rangeRuntimeLinkName(for: key) == nil,
                "UIntRange.\(member.0) should be source-backed after KSP-1529"
            )
        }

        let progressionMembers: [(String, Int)] = [
            ("iterator", 0), ("step", 1),
            ("take", 1), ("drop", 1), ("chunked", 1), ("windowed", 1),
        ]
        for member in progressionMembers {
            let key = MemberDispatchKey(receiverKind: .uintProgression, memberName: member.0, arity: member.1)
            #expect(
                MemberRuntimeDispatch.rangeRuntimeLinkName(for: key) == nil,
                "UIntProgression.\(member.0) should be source-backed after KSP-1529"
            )
        }

        let uintProgressionKey = MemberDispatchKey(receiverKind: .uintProgression, memberName: "reduce", arity: 1)
        #expect(MemberRuntimeDispatch.rangeRuntimeLinkName(for: uintProgressionKey) == "kk_uint_range_reduce")

        // KSP-1523 retains the constant-time step property bridge (arity 0).
        let uintStepPropertyKey = MemberDispatchKey(receiverKind: .uintProgression, memberName: "step", arity: 0)
        #expect(MemberRuntimeDispatch.rangeRuntimeLinkName(for: uintStepPropertyKey) == "kk_uint_range_step")
    }

    @Test func testCollectionRuntimeDispatchUsesStdlibSurfaceSpec() {
        let cases: [(MemberDispatchReceiverKind, String, Int, String)] = [
            (.iterable, "firstNotNullOf", 1, "__kk_iterable_firstNotNullOf"),
            (.list, "forEach", 1, "kk_list_forEach"),
            (.sequence, "firstNotNullOf", 1, "kk_sequence_firstNotNullOf"),
        ]

        for (receiverKind, memberName, arity, expectedLinkName) in cases {
            let key = MemberDispatchKey(receiverKind: receiverKind, memberName: memberName, arity: arity)
            #expect(
                MemberRuntimeDispatch.collectionRuntimeLinkName(for: key) == expectedLinkName,
                "\(receiverKind.rawValue).\(memberName)/\(arity)"
            )
        }
    }

    @Test func testCollectionRuntimeDispatchIgnoresNonSurfaceMembers() {
        let cases: [(MemberDispatchReceiverKind, String, Int)] = [
            (.list, "size", 0),
            (.map, "getValue", 1),
            (.sequence, "toList", 0),
            (.intRange, "map", 1),
        ]

        for (receiverKind, memberName, arity) in cases {
            let key = MemberDispatchKey(receiverKind: receiverKind, memberName: memberName, arity: arity)
            #expect(
                MemberRuntimeDispatch.collectionRuntimeLinkName(for: key) == nil,
                "\(receiverKind.rawValue).\(memberName)/\(arity)"
            )
        }
    }

    @Test func testCollectionRuntimeDispatchDoesNotOverrideSourceBackedListTransformHOFMembers() {
        // KSP-421: List transform higher-order functions are now bundled Kotlin source.
        for (memberName, arity) in [
            ("map", 1),
            ("mapNotNull", 1),
            ("mapIndexed", 1),
            ("mapIndexedNotNull", 1),
            ("flatMap", 1),
            ("flatMapIndexed", 1),
            ("flatten", 0),
            ("mapTo", 2),
            ("mapNotNullTo", 2),
            ("mapIndexedTo", 2),
            ("mapIndexedNotNullTo", 2),
            ("flatMapTo", 2),
            ("flatMapIndexedTo", 2),
        ] {
            let key = MemberDispatchKey(receiverKind: .list, memberName: memberName, arity: arity)
            #expect(
                MemberRuntimeDispatch.collectionRuntimeLinkName(for: key) == nil,
                "List.\(memberName)/\(arity) should be source-backed after KSP-421"
            )
        }
    }

    @Test func testCollectionRuntimeDispatchDoesNotOverrideSourceBackedMapHOFMembers() {
        // KSP-430: Map higher-order functions are now bundled Kotlin source.
        for (memberName, arity) in [
            ("forEach", 1),
            ("map", 1),
            ("mapNotNull", 1),
            ("flatMap", 1),
            ("filter", 1),
            ("filterNot", 1),
            ("filterKeys", 1),
            ("filterValues", 1),
            ("mapValues", 1),
            ("mapKeys", 1),
            ("mapTo", 2),
            ("mapNotNullTo", 2),
            ("mapValuesTo", 2),
            ("mapKeysTo", 2),
            ("any", 1),
            ("all", 1),
            ("none", 1),
            ("count", 1),
            ("maxByOrNull", 1),
            ("minByOrNull", 1),
            ("plus", 1),
            ("minus", 1),
        ] {
            let key = MemberDispatchKey(receiverKind: .map, memberName: memberName, arity: arity)
            #expect(
                MemberRuntimeDispatch.collectionRuntimeLinkName(for: key) == nil,
                "Map.\(memberName)/\(arity) should be source-backed after KSP-430"
            )
        }
    }

    @Test func testStringRuntimeDispatchUsesFlatStringTable() {
        let cases: [(String, Int, String, Bool, MemberRuntimeArgumentMode, MemberRuntimeThrownResultMode)] = [
            ("lowercase", 0, "kk_string_lowercase_flat", false, .lowered, .none),
        ]

        for (memberName, arity, expectedLinkName, canThrow, argumentMode, thrownResultMode) in cases {
            let key = MemberDispatchKey(receiverKind: .string, memberName: memberName, arity: arity)
            let spec = MemberRuntimeDispatch.stringRuntimeCall(for: key)
            #expect(spec?.runtimeLinkName == expectedLinkName, "String.\(memberName)/\(arity)")
            #expect(spec?.canThrow == canThrow, "String.\(memberName)/\(arity) canThrow")
            #expect(spec?.argumentMode == argumentMode, "String.\(memberName)/\(arity) argument mode")
            #expect(spec?.thrownResultMode == thrownResultMode, "String.\(memberName)/\(arity) thrown result")
        }
    }

    @Test func testStringRuntimeDispatchDoesNotOverrideSourceBackedMembers() {
        for memberName in ["ifBlank", "ifEmpty"] {
            let key = MemberDispatchKey(receiverKind: .string, memberName: memberName, arity: 1)
            #expect(MemberRuntimeDispatch.stringRuntimeCall(for: key) == nil)
        }
        // KSP-404: prefix/suffix members are bundled Kotlin source.
        let ksp404Cases: [(String, Int)] = [
            ("startsWith", 1),
            ("endsWith", 1),
            ("removePrefix", 1),
            ("removeSuffix", 1),
            ("removeSurrounding", 1),
            ("removeSurrounding", 2),
        ]
        for (memberName, arity) in ksp404Cases {
            let key = MemberDispatchKey(receiverKind: .string, memberName: memberName, arity: arity)
            #expect(
                MemberRuntimeDispatch.stringRuntimeCall(for: key) == nil,
                "String.\(memberName)/\(arity) should be source-backed after KSP-404"
            )
        }
        // KSP-405: take/drop members are bundled Kotlin source.
        let ksp405Cases: [(String, Int)] = [
            ("take", 1),
            ("takeLast", 1),
            ("drop", 1),
            ("dropLast", 1),
            ("takeWhile", 1),
            ("takeLastWhile", 1),
            ("dropWhile", 1),
        ]
        for (memberName, arity) in ksp405Cases {
            let key = MemberDispatchKey(receiverKind: .string, memberName: memberName, arity: arity)
            #expect(
                MemberRuntimeDispatch.stringRuntimeCall(for: key) == nil,
                "String.\(memberName)/\(arity) should be source-backed after KSP-405"
            )
        }
        // KSP-410: filter/count/any/all/none/filterNot/find/findLast/onEach/
        // partition/sumBy/sumByDouble/filterIndexed/onEachIndexed/reduce
        // family/fold family are bundled Kotlin source. map/mapIndexed are
        // excluded (BUG-176 keeps them Swift-backed).
        let ksp410Cases: [(String, Int)] = [
            ("filter", 1),
            ("filterNot", 1),
            ("any", 1),
            ("all", 1),
            ("none", 1),
            ("count", 1),
            ("find", 1),
            ("findLast", 1),
            ("onEach", 1),
            ("partition", 1),
            ("sumBy", 1),
            ("sumByDouble", 1),
            ("filterIndexed", 1),
            ("onEachIndexed", 1),
            ("reduce", 1),
            ("reduceOrNull", 1),
            ("reduceIndexed", 1),
            ("reduceIndexedOrNull", 1),
            ("reduceRight", 1),
            ("reduceRightOrNull", 1),
            ("reduceRightIndexed", 1),
            ("reduceRightIndexedOrNull", 1),
            ("fold", 2),
            ("foldIndexed", 2),
            ("foldRight", 2),
            ("foldRightIndexed", 2),
        ]
        for (memberName, arity) in ksp410Cases {
            let key = MemberDispatchKey(receiverKind: .string, memberName: memberName, arity: arity)
            #expect(
                MemberRuntimeDispatch.stringRuntimeCall(for: key) == nil,
                "String.\(memberName)/\(arity) should be source-backed after KSP-410"
            )
        }
        // KSP-414: integer and boolean string parsing members are bundled Kotlin source.
        let ksp414Cases: [(String, Int)] = [
            ("toInt", 0), ("toInt", 1),
            ("toLong", 0),
            ("toShort", 0),
            ("toByte", 0), ("toByte", 1),
            ("toIntOrNull", 0), ("toIntOrNull", 1),
            ("toLongOrNull", 0),
            ("toShortOrNull", 0),
            ("toByteOrNull", 0),
            ("toUByteOrNull", 0), ("toUByteOrNull", 1),
            ("toUShortOrNull", 0), ("toUShortOrNull", 1),
            ("toUIntOrNull", 0), ("toUIntOrNull", 1),
            ("toULongOrNull", 0), ("toULongOrNull", 1),
            ("toBoolean", 0), ("toBooleanStrict", 0), ("toBooleanStrictOrNull", 0),
        ]
        for (memberName, arity) in ksp414Cases {
            let key = MemberDispatchKey(receiverKind: .string, memberName: memberName, arity: arity)
            #expect(
                MemberRuntimeDispatch.stringRuntimeCall(for: key) == nil,
                "String.\(memberName)/\(arity) should be source-backed after KSP-414"
            )
        }
    }
}
#endif
