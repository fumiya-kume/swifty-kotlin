import RuntimeABI
import Testing

@Suite
struct ABIMismatchTests {
    // MARK: - Helpers

    private struct MissingSpecError: Error, CustomStringConvertible {
        let name: String

        var description: String {
            "'\(name)' not found in RuntimeABISpec.allFunctions"
        }
    }

    private func requireSpec(_ name: String) throws -> RuntimeABIFunctionSpec {
        guard let spec = RuntimeABISpec.allFunctions.first(where: { $0.name == name }) else {
            throw MissingSpecError(name: name)
        }
        return spec
    }

    // MARK: - Spec Integrity

    @Test
    func allParameterNamesAreNonEmpty() {
        for spec in RuntimeABISpec.allFunctions {
            for param in spec.parameters {
                #expect(
                    !(param.name.isEmpty),
                    "Parameter in '\(spec.name)' has an empty name"
                )
            }
        }
    }

    @Test
    func parameterNamesUniquePerFunction() {
        for spec in RuntimeABISpec.allFunctions {
            let names = spec.parameters.map { $0.name }
            let uniqueNames = Set(names)
            #expect(
                names.count == uniqueNames.count,
                "Duplicate parameter names in '\(spec.name)'"
            )
        }
    }

    @Test
    func collectionMutationSignaturesIncludeThrowingChannel() throws {
        let expected: [(name: String, parameters: [String])] = [
            ("__kk_mutable_list_add", ["listRaw", "elem", "outThrown"]),
            ("__kk_mutable_set_add", ["setRaw", "elem", "outThrown"]),
            ("__kk_mutable_map_put", ["mapRaw", "key", "value", "outThrown"]),
        ]
        for item in expected {
            let spec = try requireSpec(item.name)
            #expect(spec.parameters.map(\.name) == item.parameters)
            #expect(spec.parameters.dropLast().allSatisfy { $0.type == .intptr })
            #expect(spec.parameters.last?.type == .nullableIntptrPointer)
            #expect(spec.isThrowing)
            #expect(!RuntimeABISpec.nonThrowingRuntimeCalleeNames.contains(item.name))

            let extern = try #require(RuntimeABIExterns.externDecl(named: item.name))
            #expect(extern.parameterTypes == spec.parameterTypeStrings)
            #expect(
                RuntimeABISpec.generateCHeader().contains(spec.cDeclaration),
                "Generated C header must expose the throwing collection mutation ABI for \(item.name)"
            )
        }
    }

    @Test
    func charNumericBridgeABIsRemoved() {
        for name in ["kk_char_to_int", "kk_char_to_long", "kk_char_to_uint", "kk_char_to_ulong"] {
            #expect(
                !RuntimeABISpec.allFunctions.contains { $0.name == name },
                "Char numeric conversion bridge \(name) should be removed after KSP-1539"
            )
        }
    }

    @Test
    func longToCharBridgeABIIsRemoved() {
        #expect(
            !RuntimeABISpec.allFunctions.contains { $0.name == "kk_long_to_char" },
            "Long.toChar should be provided by bundled Kotlin source, not RuntimeABI"
        )
    }

    @Test
    func floorDivABISignatures() throws {
        for name in ["kk_op_floor_div", "kk_op_lfloor_div"] {
            let spec = try requireSpec(name)
            #expect(spec.returnType == .intptr)
            #expect(spec.parameters.map(\.type) == [.intptr, .intptr])
            #expect(spec.parameters.map(\.name) == ["lhs", "rhs"])
        }
    }

    // MARK: - J16.1 Signature Verification (spec-fixed)

    @Test
    func kkAllocSignature() throws {
        let spec = try requireSpec("kk_alloc")
        #expect(spec.returnType == .opaquePointer)
        #expect(spec.parameters.count == 2)
        #expect(spec.parameters[0].name == "size")
        #expect(spec.parameters[0].type == .uint32)
        #expect(spec.parameters[1].name == "typeInfo")
        #expect(
            spec.parameters[1].type == .constTypeInfoPointer,
            "kk_alloc typeInfo must be const KTypeInfo * per J16.1"
        )
    }

    @Test
    func kkGcCollectSignature() throws {
        let spec = try requireSpec("kk_gc_collect")
        #expect(spec.returnType == .void)
        #expect(spec.parameters.count == 0)
    }

    @Test
    func kkThreadLocalNewSignature() throws {
        let spec = try requireSpec("kk_thread_local_new")
        #expect(spec.returnType == .intptr)
        #expect(spec.parameters.count == 0)
    }

    @Test
    func kkThreadLocalGetOrSetSignature() throws {
        let spec = try requireSpec("kk_thread_local_getOrSet")
        #expect(spec.returnType == .intptr)
        #expect(spec.parameters.count == 4)
        #expect(spec.parameters[0].name == "receiver")
        #expect(spec.parameters[0].type == .intptr)
        #expect(spec.parameters[1].name == "fnPtr")
        #expect(spec.parameters[1].type == .intptr)
        #expect(spec.parameters[2].name == "closureRaw")
        #expect(spec.parameters[2].type == .intptr)
        #expect(spec.parameters[3].name == "outThrown")
        #expect(spec.parameters[3].type == .nullableIntptrPointer)
    }

    @Test
    func kkThrowableNewSignature() throws {
        let spec = try requireSpec("__kk_throwable_new")
        #expect(spec.returnType == .opaquePointer)
        #expect(spec.parameters.count == 1)
        #expect(spec.parameters[0].type == .nullableOpaquePointer)
    }

    @Test
    func kkThrowableNewCauseSignature() throws {
        let spec = try requireSpec("__kk_throwable_new_cause")
        #expect(spec.returnType == .opaquePointer)
        #expect(spec.parameters.map(\.type) == [.intptr])
    }

    @Test
    func kkFloorModSignatures() throws {
        for name in ["kk_op_floor_mod", "kk_op_lfloor_mod"] {
            let spec = try requireSpec(name)
            #expect(spec.returnType == .intptr)
            #expect(spec.parameters.map(\.type) == [.intptr, .intptr])
        }
    }

    /// Both accessors back Kotlin-source members of `Throwable`, so their
    /// runtime exports carry the hidden `outThrown` channel that every
    /// source-backed callee ABI appends.
    @Test
    func throwableRawStackFramesSignature() throws {
        let spec = try requireSpec("__kk_throwable_rawStackFrames")
        #expect(spec.returnType == .intptr)
        #expect(spec.isThrowing)
        #expect(spec.parameters.map(\.type) == [.intptr, .nullableIntptrPointer])
    }

    @Test
    func throwableToStringSignature() throws {
        let spec = try requireSpec("__kk_throwable_toString")
        #expect(spec.returnType == .intptr)
        #expect(spec.isThrowing)
        #expect(spec.parameters.map(\.type) == [.intptr, .nullableIntptrPointer])
    }

    @Test
    func printStderrSignature() throws {
        let spec = try requireSpec("__kk_printStderr")
        #expect(spec.returnType == .intptr)
        #expect(spec.parameters.count == 1)
        #expect(spec.parameters[0].type == .intptr)
    }

    @Test
    func kkNoWhenBranchMatchedExceptionConstructorsSignature() throws {
        let noArg = try requireSpec("__kk_no_when_branch_matched_exception_new")
        #expect(noArg.returnType == .intptr)
        #expect(noArg.parameters.count == 0)

        let message = try requireSpec("__kk_no_when_branch_matched_exception_new_message")
        #expect(message.returnType == .intptr)
        #expect(message.parameters.map(\.type) == [.intptr])

        let messageCause = try requireSpec("__kk_no_when_branch_matched_exception_new_message_cause")
        #expect(messageCause.returnType == .intptr)
        #expect(messageCause.parameters.map(\.type) == [.intptr, .intptr])

        let cause = try requireSpec("__kk_no_when_branch_matched_exception_new_cause")
        #expect(cause.returnType == .intptr)
        #expect(cause.parameters.map(\.type) == [.intptr])
    }

    @Test
    func kkConcurrentModificationExceptionConstructorsSignature() throws {
        let noArg = try requireSpec("__kk_concurrent_modification_exception_new")
        #expect(noArg.returnType == .intptr)
        #expect(noArg.parameters.count == 0)

        let message = try requireSpec("__kk_concurrent_modification_exception_new_message")
        #expect(message.returnType == .intptr)
        #expect(message.parameters.map(\.type) == [.intptr])

        let messageCause = try requireSpec("__kk_concurrent_modification_exception_new_message_cause")
        #expect(messageCause.returnType == .intptr)
        #expect(messageCause.parameters.map(\.type) == [.intptr, .intptr])

        let cause = try requireSpec("__kk_concurrent_modification_exception_new_cause")
        #expect(cause.returnType == .intptr)
        #expect(cause.parameters.map(\.type) == [.intptr])
    }

    @Test
    func kkArrayIndexOutOfBoundsExceptionConstructorsSignature() throws {
        let noArg = try requireSpec("__kk_array_index_out_of_bounds_exception_new")
        #expect(noArg.returnType == .intptr)
        #expect(noArg.parameters.count == 0)

        let message = try requireSpec("__kk_array_index_out_of_bounds_exception_new_message")
        #expect(message.returnType == .intptr)
        #expect(message.parameters.map(\.type) == [.intptr])
    }

    @Test
    func genericListAndArrayJoinToStringABIsAreSourceBacked() throws {
        #expect(
            RuntimeABISpec.allFunctions.first(where: { $0.name == "kk_list_joinToString" }) == nil
        )
        #expect(
            RuntimeABISpec.allFunctions.first(where: { $0.name == "kk_array_joinToString" }) == nil
        )
        let privateBridge = try requireSpec("__kk_string_joinToString")
        #expect(privateBridge.parameters.map(\.type) == [.intptr, .intptr, .intptr, .intptr])
        #expect(privateBridge.returnType == .intptr)
    }

    // KSP-621: Iterable.joinTo/joinToString and Sequence.joinTo/joinToString share
    // one bundled Kotlin implementation (Iterables.kt's appendJoinToPlain/
    // appendJoinToTransform, called via iterator()), so the runtime bridges these
    // names used to route through when Sema left the callee unresolved are gone.
    @Test
    func iterableJoinToABIsAreSourceBacked() throws {
        #expect(
            RuntimeABISpec.allFunctions.first(where: { $0.name == "__kk_iterable_joinTo" }) == nil
        )
        #expect(
            RuntimeABISpec.allFunctions.first(where: { $0.name == "__kk_iterable_joinToString" }) == nil
        )
        #expect(
            RuntimeABISpec.allFunctions.first(where: { $0.name == "__kk_iterable_joinToString_transform" }) == nil
        )
    }

    @Test
    func kkThrowableIsCancellationSignature() throws {
        let spec = try requireSpec("kk_throwable_is_cancellation")
        #expect(spec.returnType == .intptr)
        #expect(spec.parameters.count == 1)
        #expect(spec.parameters[0].type == .intptr)
    }

    @Test
    func kkThrowableSuppressedRawSignature() throws {
        let spec = try requireSpec("__kk_throwable_suppressedRaw")
        #expect(spec.returnType == .intptr)
        #expect(spec.parameters.count == 1)
        #expect(spec.parameters[0].type == .intptr)
    }

    @Test
    func kkStringFromUTF8Signature() throws {
        let spec = try requireSpec("kk_string_from_utf8")
        #expect(spec.returnType == .opaquePointer)
        #expect(spec.parameters.count == 2)
        #expect(spec.parameters[0].type == .constUInt8Pointer)
        #expect(spec.parameters[1].type == .int32)
    }

    @Test
    func kkStringConcatPointerABIRemoved() {
        #expect(
            !(RuntimeABISpec.allFunctions.contains { $0.name == "kk_string_concat" }),
            "String concat should use kk_string_concat_flat instead of the legacy pointer ABI"
        )
    }

    @Test
    func kkStringRepeatPointerABIRemoved() {
        #expect(
            !(RuntimeABISpec.allFunctions.contains { $0.name == "kk_string_repeat" }),
            "String repeat should use kk_string_repeat_flat instead of the legacy pointer ABI"
        )
    }

    @Test
    func kkStringSubstringAndReplaceSegmentPointerABIRemoved() {
        let legacyNames = [
            "kk_string_substringBefore",
            "kk_string_substringBefore_char",
            "kk_string_substringBeforeLast",
            "kk_string_substringBeforeLast_char",
            "kk_string_substringAfter",
            "kk_string_substringAfter_char",
            "kk_string_substringAfterLast",
            "kk_string_substringAfterLast_char",
            "kk_string_replaceAfter",
            "kk_string_replaceAfter_char",
            "kk_string_replaceAfterLast",
            "kk_string_replaceAfterLast_char",
            "kk_string_replaceBefore",
            "kk_string_replaceBefore_char",
            "kk_string_replaceBeforeLast",
            "kk_string_replaceBeforeLast_char",
        ]
        for legacyName in legacyNames {
            #expect(
                !(RuntimeABISpec.allFunctions.contains { $0.name == legacyName }),
                "\(legacyName) should be removed in favor of bundled Kotlin source (StringSearchReplace.kt)"
            )
        }
    }

    // KSP-407: substringBefore/After/BeforeLast/AfterLast and
    // replaceBefore/After/BeforeLast/AfterLast are bundled Kotlin source
    // (StringSearchReplace.kt); neither the raw pointer nor the flattened
    // runtime ABI remains.
    @Test
    func kkStringSubstringAndReplaceSegmentFlatABIRemoved() {
        let removedNames = [
            "kk_string_substringBefore_flat",
            "kk_string_substringBefore_char_flat",
            "kk_string_substringBeforeLast_flat",
            "kk_string_substringBeforeLast_char_flat",
            "kk_string_substringAfter_flat",
            "kk_string_substringAfter_char_flat",
            "kk_string_substringAfterLast_flat",
            "kk_string_substringAfterLast_char_flat",
            "kk_string_replaceAfter_flat",
            "kk_string_replaceAfter_char_flat",
            "kk_string_replaceAfterLast_flat",
            "kk_string_replaceAfterLast_char_flat",
            "kk_string_replaceBefore_flat",
            "kk_string_replaceBefore_char_flat",
            "kk_string_replaceBeforeLast_flat",
            "kk_string_replaceBeforeLast_char_flat",
        ]
        for removedName in removedNames {
            #expect(
                !(RuntimeABISpec.allFunctions.contains { $0.name == removedName }),
                "\(removedName) should be removed in favor of bundled Kotlin source (StringSearchReplace.kt)"
            )
        }
    }

    @Test
    func kkStringConcatFlatSignature() throws {
        let spec = try requireSpec("kk_string_concat_flat")
        #expect(spec.returnType == .nullableUInt8Pointer)
        #expect(spec.parameters.count == 11)
        #expect(spec.parameters.map(\.type) == [
            .nullableConstUInt8Pointer,
            .intptr,
            .intptr,
            .intptr,
            .nullableConstUInt8Pointer,
            .intptr,
            .intptr,
            .intptr,
            .nullableIntptrPointer,
            .nullableIntptrPointer,
            .nullableIntptrPointer,
        ])
    }

    @Test
    func kkStringReplacePointerABIRemoved() {
        let legacyNames = [
            "kk_string_replace",
            "kk_string_replace_char",
            "kk_string_replace_ignoreCase",
            "kk_string_replace_char_ignoreCase",
        ]
        for legacyName in legacyNames {
            #expect(
                !(RuntimeABISpec.allFunctions.contains { $0.name == legacyName }),
                "\(legacyName) should use the flattened string ABI instead of the legacy pointer ABI"
            )
        }
    }

    // KSP-404: startsWith/endsWith/removePrefix/removeSuffix/removeSurrounding are
    // bundled Kotlin source (StringPrefixSuffix.kt); neither the raw pointer nor
    // the flattened runtime ABI remains.
    @Test
    func kkStringPrefixSuffixABIRemoved() {
        let removedNames = [
            "kk_string_startsWith",
            "kk_string_startsWith_flat",
            "kk_string_endsWith",
            "kk_string_endsWith_flat",
            "kk_string_removePrefix",
            "kk_string_removePrefix_flat",
            "kk_string_removeSuffix",
            "kk_string_removeSuffix_flat",
            "kk_string_removeSurrounding",
            "kk_string_removeSurrounding_flat",
            "kk_string_removeSurrounding_pair",
            "kk_string_removeSurrounding_pair_flat",
        ]
        for removedName in removedNames {
            #expect(
                !(RuntimeABISpec.allFunctions.contains { $0.name == removedName }),
                "\(removedName) should be removed in favor of bundled Kotlin source (StringPrefixSuffix.kt)"
            )
        }
    }

    @Test
    func kkStringReplaceFlatSignature() throws {
        let spec = try requireSpec("kk_string_replace_flat")
        #expect(spec.returnType == .nullableUInt8Pointer)
        #expect(spec.parameters.count == 15)
        #expect(spec.parameters.map(\.type) == [
            .nullableConstUInt8Pointer,
            .intptr,
            .intptr,
            .intptr,
            .nullableConstUInt8Pointer,
            .intptr,
            .intptr,
            .intptr,
            .nullableConstUInt8Pointer,
            .intptr,
            .intptr,
            .intptr,
            .nullableIntptrPointer,
            .nullableIntptrPointer,
            .nullableIntptrPointer,
        ])
    }

    @Test
    func kkStringReplaceCharFlatSignature() throws {
        let spec = try requireSpec("kk_string_replace_char_flat")
        #expect(spec.returnType == .nullableUInt8Pointer)
        #expect(spec.parameters.count == 9)
        #expect(spec.parameters.map(\.type) == [
            .nullableConstUInt8Pointer,
            .intptr,
            .intptr,
            .intptr,
            .intptr,
            .intptr,
            .nullableIntptrPointer,
            .nullableIntptrPointer,
            .nullableIntptrPointer,
        ])
    }

    @Test
    func kkStringReplaceIgnoreCaseFlatSignature() throws {
        let spec = try requireSpec("kk_string_replace_ignoreCase_flat")
        #expect(spec.returnType == .nullableUInt8Pointer)
        #expect(spec.parameters.count == 16)
        #expect(spec.parameters.map(\.type) == [
            .nullableConstUInt8Pointer,
            .intptr,
            .intptr,
            .intptr,
            .nullableConstUInt8Pointer,
            .intptr,
            .intptr,
            .intptr,
            .nullableConstUInt8Pointer,
            .intptr,
            .intptr,
            .intptr,
            .intptr,
            .nullableIntptrPointer,
            .nullableIntptrPointer,
            .nullableIntptrPointer,
        ])
    }

    @Test
    func kkStringReplaceCharIgnoreCaseFlatSignature() throws {
        let spec = try requireSpec("kk_string_replace_char_ignoreCase_flat")
        #expect(spec.returnType == .nullableUInt8Pointer)
        #expect(spec.parameters.count == 10)
        #expect(spec.parameters.map(\.type) == [
            .nullableConstUInt8Pointer,
            .intptr,
            .intptr,
            .intptr,
            .intptr,
            .intptr,
            .intptr,
            .nullableIntptrPointer,
            .nullableIntptrPointer,
            .nullableIntptrPointer,
        ])
    }

    @Test
    func kkStringReplaceFirstRangePointerABIRemoved() {
        let legacyNames = [
            "kk_string_replaceFirst",
            "kk_string_replaceFirst_ignoreCase",
            "kk_string_replaceRange",
            "kk_string_removeRange",
            "kk_string_removeRange_range",
        ]
        for legacyName in legacyNames {
            #expect(
                !(RuntimeABISpec.allFunctions.contains { $0.name == legacyName }),
                "\(legacyName) should use the flattened string ABI instead of the legacy pointer ABI"
            )
        }
    }

    @Test
    func kkStringReplaceFirstFlatSignature() throws {
        let spec = try requireSpec("kk_string_replaceFirst_flat")
        #expect(spec.returnType == .nullableUInt8Pointer)
        #expect(spec.parameters.count == 15)
        #expect(spec.parameters.map(\.type) == [
            .nullableConstUInt8Pointer,
            .intptr,
            .intptr,
            .intptr,
            .nullableConstUInt8Pointer,
            .intptr,
            .intptr,
            .intptr,
            .nullableConstUInt8Pointer,
            .intptr,
            .intptr,
            .intptr,
            .nullableIntptrPointer,
            .nullableIntptrPointer,
            .nullableIntptrPointer,
        ])
    }

    @Test
    func kkStringSubstringSliceRangeABIRemoved() {
        // KSP-406: substring / subSequence / slice / removeRange / replaceRange are
        // bundled Kotlin source with no String-specific runtime ABI (raw or flat).
        let removedNames = [
            "kk_string_substring",
            "kk_string_substring_flat",
            "kk_string_subSequence",
            "kk_string_subSequence_flat",
            "kk_string_slice_range",
            "kk_string_slice_iterable",
            "kk_string_removeRange",
            "kk_string_removeRange_flat",
            "kk_string_removeRange_range",
            "kk_string_removeRange_range_flat",
            "kk_string_replaceRange",
            "kk_string_replaceRange_flat",
            "kk_string_replaceRange_indices",
        ]
        for removedName in removedNames {
            #expect(
                !(RuntimeABISpec.allFunctions.contains { $0.name == removedName }),
                "\(removedName) should be removed: substring/slice/range edits are source-backed after KSP-406"
            )
        }
    }

    @Test
    func kkStringPadPointerABIRemoved() {
        let legacyNames = [
            "kk_string_padStart_default",
            "kk_string_padEnd_default",
            "kk_string_padStart",
            "kk_string_padEnd",
        ]
        for legacyName in legacyNames {
            #expect(
                !(RuntimeABISpec.allFunctions.contains { $0.name == legacyName }),
                "\(legacyName) should use the flattened string ABI instead of the legacy pointer ABI"
            )
        }
    }

    @Test
    func kkStringPadDefaultFlatSignatures() throws {
        for name in ["kk_string_padStart_default_flat", "kk_string_padEnd_default_flat"] {
            let spec = try requireSpec(name)
            #expect(spec.returnType == .nullableUInt8Pointer)
            #expect(spec.parameters.count == 8)
            #expect(spec.parameters.map(\.type) == [
                .nullableConstUInt8Pointer,
                .intptr,
                .intptr,
                .intptr,
                .intptr,
                .nullableIntptrPointer,
                .nullableIntptrPointer,
                .nullableIntptrPointer,
            ])
        }
    }

    @Test
    func kkStringPadExplicitFlatSignatures() throws {
        for name in ["kk_string_padStart_flat", "kk_string_padEnd_flat"] {
            let spec = try requireSpec(name)
            #expect(spec.returnType == .nullableUInt8Pointer)
            #expect(spec.parameters.count == 9)
            #expect(spec.parameters.map(\.type) == [
                .nullableConstUInt8Pointer,
                .intptr,
                .intptr,
                .intptr,
                .intptr,
                .intptr,
                .nullableIntptrPointer,
                .nullableIntptrPointer,
                .nullableIntptrPointer,
            ])
        }
    }

    @Test
    func kkStringTrimPointerABIRemoved() {
        let legacyNames = [
            "kk_string_trim",
            "kk_string_trim_predicate",
            "kk_string_trimStart",
            "kk_string_trimStart_predicate",
            "kk_string_trimEnd",
            "kk_string_trimEnd_predicate",
        ]
        for legacyName in legacyNames {
            #expect(
                !(RuntimeABISpec.allFunctions.contains { $0.name == legacyName }),
                "\(legacyName) should use the flattened string ABI instead of the legacy pointer ABI"
            )
        }
    }

    @Test
    func kkStringTrimPredicateFlatSignatures() throws {
        let names = [
            "kk_string_trim_predicate_flat",
            "kk_string_trimStart_predicate_flat",
            "kk_string_trimEnd_predicate_flat",
        ]
        for name in names {
            let spec = try requireSpec(name)
            #expect(spec.returnType == .nullableUInt8Pointer)
            #expect(spec.parameters.count == 10)
            #expect(spec.parameters.map(\.type) == [
                .nullableConstUInt8Pointer,
                .intptr,
                .intptr,
                .intptr,
                .intptr,
                .intptr,
                .nullableIntptrPointer,
                .nullableIntptrPointer,
                .nullableIntptrPointer,
                .nullableIntptrPointer,
            ])
        }
    }

    @Test
    func kkStringIfBlankEmptyFlatSignatures() throws {
        for name in ["kk_string_ifBlank_flat", "kk_string_ifEmpty_flat"] {
            let spec = try requireSpec(name)
            #expect(spec.returnType == .nullableUInt8Pointer)
            #expect(spec.parameters.count == 10)
            #expect(spec.parameters.map(\.type) == [
                .nullableConstUInt8Pointer,
                .intptr,
                .intptr,
                .intptr,
                .intptr,
                .intptr,
                .nullableIntptrPointer,
                .nullableIntptrPointer,
                .nullableIntptrPointer,
                .nullableIntptrPointer,
            ])
        }
    }

    @Test
    func kkStringReplaceFirstCharABIRemoved() {
        #expect(
            !(RuntimeABISpec.allFunctions.contains { $0.name == "kk_string_replaceFirstChar" }),
            "kk_string_replaceFirstChar should be removed now that replaceFirstChar is source-backed"
        )
        #expect(
            !(RuntimeABISpec.allFunctions.contains { $0.name == "kk_string_replaceFirstChar_flat" }),
            "kk_string_replaceFirstChar_flat should be removed now that replaceFirstChar is source-backed"
        )
    }

    @Test
    func kkStringCommonPrefixSuffixRuntimeABIRemoved() {
        let migratedNames = [
            "kk_string_commonPrefixWith",
            "kk_string_commonSuffixWith",
            "kk_string_commonPrefixWith_ignoreCase",
            "kk_string_commonSuffixWith_ignoreCase",
            "kk_string_commonPrefixWith_flat",
            "kk_string_commonSuffixWith_flat",
            "kk_string_commonPrefixWith_ignoreCase_flat",
            "kk_string_commonSuffixWith_ignoreCase_flat",
        ]
        for migratedName in migratedNames {
            #expect(
                !(RuntimeABISpec.allFunctions.contains { $0.name == migratedName }),
                "\(migratedName) should be provided by bundled Kotlin source, not runtime ABI"
            )
        }
    }

    @Test
    func kkStringFormatPointerABIRemoved() {
        for legacyName in ["kk_string_format", "kk_string_format_locale"] {
            #expect(
                !(RuntimeABISpec.allFunctions.contains { $0.name == legacyName }),
                "\(legacyName) should use the flattened string ABI instead of the legacy pointer ABI"
            )
        }
    }

    /// KSP-418: `String.format` is a private stdlib bridge, so only `__kk_`-prefixed
    /// entry points may exist.
    @Test
    func kkStringFormatPublicNamesDemoted() {
        for publicName in ["kk_string_format_flat", "kk_string_format_locale_flat"] {
            #expect(
                !(RuntimeABISpec.allFunctions.contains { $0.name == publicName }),
                "\(publicName) should be demoted to the __kk_ bridge namespace"
            )
        }
    }

    @Test
    func kkStringFormatFlatSignatures() throws {
        let formatSpec = try requireSpec("__kk_string_format_flat")
        #expect(formatSpec.returnType == .nullableUInt8Pointer)
        #expect(formatSpec.parameters.map(\.type) == [
            .nullableConstUInt8Pointer,
            .intptr,
            .intptr,
            .intptr,
            .intptr,
            .nullableIntptrPointer,
            .nullableIntptrPointer,
            .nullableIntptrPointer,
        ])

        let localeSpec = try requireSpec("__kk_string_format_locale_flat")
        #expect(localeSpec.returnType == .nullableUInt8Pointer)
        #expect(localeSpec.parameters.map(\.type) == [
            .intptr,
            .nullableConstUInt8Pointer,
            .intptr,
            .intptr,
            .intptr,
            .intptr,
            .nullableIntptrPointer,
            .nullableIntptrPointer,
            .nullableIntptrPointer,
        ])
    }

    @Test
    func kkStringIndentPointerABIRemoved() {
        let legacyNames = [
            "kk_string_trimIndent",
            "kk_string_trimMargin_default",
            "kk_string_trimMargin",
            "kk_string_prependIndent_default",
            "kk_string_prependIndent",
            "kk_string_replaceIndent_default",
            "kk_string_replaceIndent",
            "kk_string_replaceIndentByMargin",
        ]
        for legacyName in legacyNames {
            #expect(
                !(RuntimeABISpec.allFunctions.contains { $0.name == legacyName }),
                "\(legacyName) should use the flattened string ABI instead of the legacy pointer ABI"
            )
        }
    }

    @Test
    func kkStringIndentFlatABIRemoved() {
        let flatNames = [
            "kk_string_trimIndent_flat",
            "kk_string_trimMargin_default_flat",
            "kk_string_trimMargin_flat",
            "kk_string_prependIndent_default_flat",
            "kk_string_prependIndent_flat",
            "kk_string_replaceIndent_default_flat",
            "kk_string_replaceIndent_flat",
            "kk_string_replaceIndentByMargin_flat",
        ]
        for name in flatNames {
            #expect(
                !(RuntimeABISpec.allFunctions.contains { $0.name == name }),
                "\(name) should be provided by bundled Kotlin source, not the flattened runtime ABI"
            )
        }
    }

    @Test
    func printRawSignature() throws {
        let spec = try requireSpec("__kk_print_raw")
        #expect(spec.returnType == .void)
        #expect(spec.parameters.count == 1)
        #expect(spec.parameters[0].type == .intptr)
    }

    @Test
    func printlnRawSignature() throws {
        let spec = try requireSpec("__kk_println_raw")
        #expect(spec.returnType == .void)
        #expect(spec.parameters.count == 1)
        #expect(spec.parameters[0].type == .intptr)
    }

    @Test
    func stringLengthHasNoRuntimeABISignature() {
        #expect(
            RuntimeABISpec.allFunctions.first(where: { $0.name == "kk_string_struct_get_length" }) == nil,
            "String.length is lowered as an aggregate field extract and must not have a runtime ABI entry"
        )
    }

    @Test
    func kkOpIsSignature() throws {
        let spec = try requireSpec("kk_op_is")
        #expect(spec.returnType == .intptr)
        #expect(spec.parameters.count == 2)
        #expect(spec.parameters[0].type == .intptr)
        #expect(spec.parameters[1].type == .intptr)
    }

    @Test
    func kkCoroutineSuspendedSignature() throws {
        let spec = try requireSpec("kk_coroutine_suspended")
        #expect(spec.returnType == .opaquePointer)
        #expect(spec.parameters.count == 0)
    }

    @Test
    func kkCreateCoroutineUninterceptedSignature() throws {
        let spec = try requireSpec("kk_create_coroutine_unintercepted")
        #expect(spec.returnType == .intptr)
        #expect(spec.parameters.count == 2)
        #expect(spec.parameters[0].name == "entryPointRaw")
        #expect(spec.parameters[0].type == .intptr)
        #expect(spec.parameters[1].name == "completionContinuation")
        #expect(spec.parameters[1].type == .intptr)
    }

    @Test
    func kkStartCoroutineUninterceptedOrReturnSignature() throws {
        let spec = try requireSpec("kk_start_coroutine_unintercepted_or_return")
        #expect(spec.returnType == .intptr)
        #expect(spec.parameters.count == 3)
        #expect(spec.parameters[0].name == "entryPointRaw")
        #expect(spec.parameters[0].type == .intptr)
        #expect(spec.parameters[1].name == "continuation")
        #expect(spec.parameters[1].type == .intptr)
        #expect(spec.parameters[2].name == "outThrown")
        #expect(spec.parameters[2].type == .nullableIntptrPointer)
    }

    @Test
    func kkSuspendFunctionInvokeSignature() throws {
        let spec = try requireSpec("kk_suspend_function_invoke")
        #expect(spec.returnType == .intptr)
        #expect(spec.parameters.count == 3)
        #expect(spec.parameters[0].name == "functionRaw")
        #expect(spec.parameters[0].type == .intptr)
        #expect(spec.parameters[1].name == "arg")
        #expect(spec.parameters[1].type == .intptr)
        #expect(spec.parameters[2].name == "outThrown")
        #expect(spec.parameters[2].type == .nullableIntptrPointer)
    }

    @Test
    func kkSuspendFunctionInvokeZeroAritySignature() throws {
        let spec = try requireSpec("kk_suspend_function_invoke_0")
        #expect(spec.returnType == .intptr)
        #expect(spec.parameters.count == 2)
        #expect(spec.parameters[0].name == "functionRaw")
        #expect(spec.parameters[0].type == .intptr)
        #expect(spec.parameters[1].name == "outThrown")
        #expect(spec.parameters[1].type == .nullableIntptrPointer)
    }

    @Test
    func kkMutableListAddAtSignature() throws {
        let spec = try requireSpec("__kk_mutable_list_add_at")
        #expect(spec.returnType == .intptr)
        #expect(spec.parameters.count == 4)
        #expect(spec.parameters[0].name == "listRaw")
        #expect(spec.parameters[0].type == .intptr)
        #expect(spec.parameters[1].name == "index")
        #expect(spec.parameters[1].type == .intptr)
        #expect(spec.parameters[2].name == "element")
        #expect(spec.parameters[2].type == .intptr)
        #expect(spec.parameters[3].name == "outThrown")
        #expect(spec.parameters[3].type == .nullableIntptrPointer)
    }

    @Test
    func kkMutableListSetSignature() throws {
        let spec = try requireSpec("__kk_mutable_list_set")
        #expect(spec.returnType == .intptr)
        #expect(spec.parameters.count == 4)
        #expect(spec.parameters[0].name == "listRaw")
        #expect(spec.parameters[0].type == .intptr)
        #expect(spec.parameters[1].name == "index")
        #expect(spec.parameters[1].type == .intptr)
        #expect(spec.parameters[2].name == "element")
        #expect(spec.parameters[2].type == .intptr)
        #expect(spec.parameters[3].name == "outThrown")
        #expect(spec.parameters[3].type == .nullableIntptrPointer)
    }

    @Test
    func kkListSortedSignature() throws {
        let spec = try requireSpec("kk_list_sorted")
        #expect(spec.returnType == .intptr)
        #expect(spec.parameters.count == 1)
        #expect(spec.parameters[0].type == .intptr)
    }

    @Test
    func kkListSortedPrimitiveSignature() throws {
        let spec = try requireSpec("kk_list_sorted_primitive")
        #expect(spec.returnType == .intptr)
        #expect(spec.parameters.count == 2)
        #expect(spec.parameters[0].type == .intptr)
        #expect(spec.parameters[1].type == .int32)
    }

    @Test
    func kkListSortedDescendingSignature() throws {
        let spec = try requireSpec("kk_list_sortedDescending")
        #expect(spec.returnType == .intptr)
        #expect(spec.parameters.count == 1)
        #expect(spec.parameters[0].type == .intptr)
    }

    @Test
    func kkListSortedBySignature() throws {
        let spec = try requireSpec("kk_list_sortedBy")
        #expect(spec.returnType == .intptr)
        #expect(spec.parameters.count == 4)
        #expect(spec.parameters[0].type == .intptr)
        #expect(spec.parameters[1].type == .intptr)
        #expect(spec.parameters[2].type == .intptr)
        #expect(spec.parameters[3].type == .nullableIntptrPointer)
    }

    @Test
    func kkListSortedByPrimitiveSignature() throws {
        let spec = try requireSpec("kk_list_sortedBy_primitive")
        #expect(spec.returnType == .intptr)
        #expect(spec.parameters.count == 5)
        #expect(spec.parameters[0].type == .intptr)
        #expect(spec.parameters[1].type == .intptr)
        #expect(spec.parameters[2].type == .intptr)
        #expect(spec.parameters[3].type == .int32)
        #expect(spec.parameters[4].type == .nullableIntptrPointer)
    }

    @Test
    func kkListSortedByDescendingSignature() throws {
        let spec = try requireSpec("kk_list_sortedByDescending")
        #expect(spec.returnType == .intptr)
        #expect(spec.parameters.count == 4)
        #expect(spec.parameters[0].type == .intptr)
        #expect(spec.parameters[1].type == .intptr)
        #expect(spec.parameters[2].type == .intptr)
        #expect(spec.parameters[3].type == .nullableIntptrPointer)
    }

    @Test
    func kkListSortedByDescendingPrimitiveSignature() throws {
        let spec = try requireSpec("kk_list_sortedByDescending_primitive")
        #expect(spec.returnType == .intptr)
        #expect(spec.parameters.count == 5)
        #expect(spec.parameters[0].type == .intptr)
        #expect(spec.parameters[1].type == .intptr)
        #expect(spec.parameters[2].type == .intptr)
        #expect(spec.parameters[3].type == .int32)
        #expect(spec.parameters[4].type == .nullableIntptrPointer)
    }

    @Test
    func kkListSortedWithSignature() throws {
        let spec = try requireSpec("kk_list_sortedWith")
        #expect(spec.returnType == .intptr)
        #expect(spec.parameters.count == 4)
        #expect(spec.parameters[0].type == .intptr)
        #expect(spec.parameters[1].type == .intptr)
        #expect(spec.parameters[2].type == .intptr)
        #expect(spec.parameters[3].type == .nullableIntptrPointer)
    }

    @Test
    func kkMutableListSortSignature() throws {
        let spec = try requireSpec("__kk_mutable_list_sort")
        #expect(spec.returnType == .intptr)
        #expect(spec.parameters.count == 1)
        #expect(spec.parameters[0].type == .intptr)
    }

    @Test
    func kkMutableListSortPrimitiveSignature() throws {
        let spec = try requireSpec("__kk_mutable_list_sort_primitive")
        #expect(spec.returnType == .intptr)
        #expect(spec.parameters.count == 2)
        #expect(spec.parameters[0].type == .intptr)
        #expect(spec.parameters[1].type == .int32)
    }

    @Test
    func kkMutableListSortBySignature() throws {
        let spec = try requireSpec("__kk_mutable_list_sortBy")
        #expect(spec.returnType == .intptr)
        #expect(spec.parameters.count == 4)
        #expect(spec.parameters[0].type == .intptr)
        #expect(spec.parameters[1].type == .intptr)
        #expect(spec.parameters[2].type == .intptr)
        #expect(spec.parameters[3].type == .nullableIntptrPointer)
    }

    @Test
    func kkMutableListSortWithSignature() throws {
        let spec = try requireSpec("__kk_mutable_list_sortWith")
        #expect(spec.returnType == .intptr)
        #expect(spec.parameters.count == 4)
        #expect(spec.parameters[0].type == .intptr)
        #expect(spec.parameters[1].type == .intptr)
        #expect(spec.parameters[2].type == .intptr)
        #expect(spec.parameters[3].type == .nullableIntptrPointer)
    }

    @Test
    func kkMutableListSortByPrimitiveSignature() throws {
        let spec = try requireSpec("__kk_mutable_list_sortBy_primitive")
        #expect(spec.returnType == .intptr)
        #expect(spec.parameters.count == 5)
        #expect(spec.parameters[0].type == .intptr)
        #expect(spec.parameters[1].type == .intptr)
        #expect(spec.parameters[2].type == .intptr)
        #expect(spec.parameters[3].type == .int32)
        #expect(spec.parameters[4].type == .nullableIntptrPointer)
    }

    @Test
    func kkMutableListSortByDescendingSignature() throws {
        let spec = try requireSpec("__kk_mutable_list_sortByDescending")
        #expect(spec.returnType == .intptr)
        #expect(spec.parameters.count == 4)
        #expect(spec.parameters[0].type == .intptr)
        #expect(spec.parameters[1].type == .intptr)
        #expect(spec.parameters[2].type == .intptr)
        #expect(spec.parameters[3].type == .nullableIntptrPointer)
    }

    @Test
    func kkMutableListSortByDescendingPrimitiveSignature() throws {
        let spec = try requireSpec("__kk_mutable_list_sortByDescending_primitive")
        #expect(spec.returnType == .intptr)
        #expect(spec.parameters.count == 5)
        #expect(spec.parameters[0].type == .intptr)
        #expect(spec.parameters[1].type == .intptr)
        #expect(spec.parameters[2].type == .intptr)
        #expect(spec.parameters[3].type == .int32)
        #expect(spec.parameters[4].type == .nullableIntptrPointer)
    }

    @Test
    func kkLockWithLockSignature() throws {
        let spec = try requireSpec("__kk_lock_withLock")
        #expect(spec.returnType == .intptr)
        #expect(spec.parameters.count == 4)
        #expect(spec.parameters[0].name == "handle")
        #expect(spec.parameters[0].type == .intptr)
        #expect(spec.parameters[1].name == "actionFnPtr")
        #expect(spec.parameters[1].type == .intptr)
        #expect(spec.parameters[2].name == "closureRaw")
        #expect(spec.parameters[2].type == .intptr)
        #expect(spec.parameters[3].name == "outThrown")
        #expect(spec.parameters[3].type == .nullableIntptrPointer)
    }

    // KSP-618: kotlin.synchronized is Kotlin source over this demoted bridge.
    @Test
    func kkSynchronizedSignature() throws {
        let spec = try requireSpec("__kk_synchronized")
        #expect(spec.returnType == .intptr)
        #expect(spec.parameters.count == 4)
        #expect(spec.parameters[0].name == "lock")
        #expect(spec.parameters[0].type == .intptr)
        #expect(spec.parameters[1].name == "fnPtr")
        #expect(spec.parameters[1].type == .intptr)
        #expect(spec.parameters[2].name == "closureRaw")
        #expect(spec.parameters[2].type == .intptr)
        #expect(spec.parameters[3].name == "outThrown")
        #expect(spec.parameters[3].type == .nullableIntptrPointer)
    }

    @Test
    func kkMutexCreateSignature() throws {
        let spec = try requireSpec("__kk_mutex_create")
        #expect(spec.returnType == .intptr)
        #expect(spec.parameters.count == 0)
    }

    @Test
    func kkMutexLockSignature() throws {
        let spec = try requireSpec("kk_mutex_lock")
        #expect(spec.returnType == .intptr)
        #expect(spec.parameters.count == 2)
        #expect(spec.parameters[0].name == "handle")
        #expect(spec.parameters[0].type == .intptr)
        #expect(spec.parameters[1].name == "continuation")
        #expect(spec.parameters[1].type == .intptr)
    }

    @Test
    func kkMutexUnlockSignature() throws {
        let spec = try requireSpec("kk_mutex_unlock")
        #expect(spec.returnType == .intptr)
        #expect(spec.parameters.count == 1)
        #expect(spec.parameters[0].name == "handle")
        #expect(spec.parameters[0].type == .intptr)
    }

    @Test
    func kkMutexTryLockSignature() throws {
        let spec = try requireSpec("__kk_mutex_tryLock")
        #expect(spec.returnType == .intptr)
        #expect(spec.parameters.count == 1)
        #expect(spec.parameters[0].name == "handle")
        #expect(spec.parameters[0].type == .intptr)
    }

    @Test
    func kkMutexIsLockedSignature() throws {
        let spec = try requireSpec("__kk_mutex_isLocked")
        #expect(spec.returnType == .intptr)
        #expect(spec.parameters.count == 1)
        #expect(spec.parameters[0].name == "handle")
        #expect(spec.parameters[0].type == .intptr)
    }

    // KSP-677: kk_mutex_withLock removed — Mutex.withLock is Kotlin source.

    // MARK: - Header Generation

    @Test
    func generatedHeaderContainsGuard() {
        let header = RuntimeABISpec.generateCHeader()
        #expect(header.contains("#ifndef KK_RUNTIME_ABI_H"))
        #expect(header.contains("#define KK_RUNTIME_ABI_H"))
        #expect(header.contains("#endif"))
    }

    @Test
    func generatedHeaderContainsAllFunctions() {
        let header = RuntimeABISpec.generateCHeader()
        let headerLines = Set(
            header
                .split(separator: "\n")
                .map { String($0).trimmingCharacters(in: .whitespaces) }
        )
        for spec in RuntimeABISpec.allFunctions {
            #expect(
                headerLines.contains(spec.cDeclaration),
                "Generated header missing declaration for '\(spec.name)': expected line '\(spec.cDeclaration)'"
            )
        }
    }

    @Test
    func generatedHeaderContainsSpecVersion() {
        let header = RuntimeABISpec.generateCHeader()
        #expect(header.contains(RuntimeABISpec.specVersion))
    }

}
