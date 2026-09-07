#if canImport(Testing)
import Foundation
import RuntimeABI
import Testing

// MARK: - Runtime Export / RuntimeABISpec Reconciliation

@Suite
struct ABIMismatchRuntimeExportParityTests {
    /// The String/Regex/Locale ABI surface is governed by the branch's flat-only
    /// contract, so it is reconciled by the dedicated flat-string tests rather than
    /// the cross-section export/spec parity checks here.
    private func isFlatOnlyExcludedABIName(_ name: String) -> Bool {
        name.hasPrefix("kk_string_")
            || name.hasPrefix("__kk_string_")
            || name.hasPrefix("kk_regex_")
            || name.hasPrefix("kk_locale_")
    }

    @Test
    func testRuntimeExportsHaveMatchingRuntimeABISpecEntries() throws {
        let exported = try runtimeExportedABIs()
        let specNames = Set(RuntimeABISpec.allFunctions.map { $0.name })
        let missing = exported.map { $0.name }
            .filter {
                !isFlatOnlyExcludedABIName($0)
                    && !specNames.contains($0)
                    && !allowedRuntimeExportOnlyABINames.contains($0)
            }
            .sorted()

        #expect(
            missing.isEmpty,
            "Runtime exported ABI names missing from RuntimeABISpec: \(missing.joined(separator: ", "))"
        )
    }

    @Test
    func testRuntimeExportSignaturesMatchRuntimeABISpec() throws {
        let specsByName = Dictionary(uniqueKeysWithValues: RuntimeABISpec.allFunctions.map { ($0.name, $0) })
        for exported in try runtimeExportedABIs() {
            guard !isFlatOnlyExcludedABIName(exported.name) else { continue }
            guard !allowedRuntimeExportOnlyABINames.contains(exported.name) else { continue }
            // Generic functions cannot have their parameter types validated against C ABI types
            guard exported.returnType != "generic" else { continue }
            let spec = try #require(
                specsByName[exported.name],
                "Runtime export '\(exported.name)' from \(exported.source) has no RuntimeABISpec entry"
            )
            #expect(
                spec.returnTypeString == exported.returnType,
                "Return type mismatch for runtime export '\(exported.name)' from \(exported.source)"
            )
            #expect(
                spec.parameterTypeStrings == exported.parameterTypes,
                "Parameter type mismatch for runtime export '\(exported.name)' from \(exported.source)"
            )
        }
    }

    @Test
    func testSpecOnlyRuntimeABINamesAreExplicitlyAllowed() throws {
        let exportedNames = Set(try runtimeExportedABIs().map { $0.name })
        let specNames = Set(RuntimeABISpec.allFunctions.map { $0.name })
        let unexpected = Set(specNames.filter { !isFlatOnlyExcludedABIName($0) })
            .subtracting(exportedNames)
            .subtracting(allowedSpecOnlyRuntimeABINames)
            .sorted()

        #expect(
            unexpected.isEmpty,
            "RuntimeABISpec entries without Runtime exports must be allowlisted: \(unexpected.joined(separator: ", "))"
        )
    }

    private var allowedRuntimeExportOnlyABINames: Set<String> {
        [
            "kk_regex_create_with_option",
            "kk_regex_create_with_options",
            "kk_string_toByte",
            "kk_string_toByte_radix",
            "kk_string_toRegex_with_option",
            "kk_string_toRegex_with_options",
            "kk_string_toShort",
        ]
    }

    private var allowedSpecOnlyRuntimeABINames: Set<String> {
        [
            "kk_annotation_class_name",
            "kk_annotation_get_arguments",
            "kk_annotation_simple_class_name",
            "kk_callable_ref_call_0",
            "kk_callable_ref_call_1",
            "kk_callable_ref_call_2",
            "kk_callable_ref_call_3",
            "kk_channel_send_suspending",
            "kk_flow_catch",
            "kk_flow_on_completion",
            "kk_flow_on_error_resume",
            "kk_flow_on_error_return",
            "kk_flow_retry",
            "kk_flow_retry_when",
            "kk_math_e",
            "kk_math_pi",
            "kk_mem_scope_alloc",
            "kk_mem_scope_enter",
            "kk_mem_scope_exit",
            "kk_native_alloc_bytes",
            "kk_char_sequence_length",
            "kk_dynamic_iterator",
            "kk_future_getState",
            "kk_int_to_int",
            "kk_kclass_has_annotation",
            "kk_kclass_js",
            "kk_kclass_register_annotation",
            // Kept in RuntimeABISpec for source-migration compatibility; the
            // runtime exports only the __kk_ bridge.
            "kk_list_fold",
            "kk_list_foldIndexed",
            "kk_list_foldRight",
            "kk_list_foldRightIndexed",
            "kk_list_reduceIndexedOrNull",
            "kk_list_reduceOrNull",
            "kk_list_runningFold",
            "kk_list_runningFoldIndexed",
            "kk_list_runningReduce",
            "kk_list_runningReduceIndexed",
            "kk_list_scan",
            "kk_list_scanIndexed",
            "kk_list_scanReduce",
            // KSP-426: source-backed in ListSortingHOF.kt / ListExtremaHOF.kt;
            // retained only in RuntimeABISpec and test-only compatibility shims.
            "kk_list_max",
            "kk_list_maxBy",
            "kk_list_maxByOrNull",
            "kk_list_maxOf",
            "kk_list_maxOfOrNull",
            "kk_list_maxOfWith",
            "kk_list_maxOfWithOrNull",
            "kk_list_maxOrNull",
            "kk_list_maxWith",
            "kk_list_maxWithOrNull",
            "kk_list_min",
            "kk_list_minBy",
            "kk_list_minByOrNull",
            "kk_list_minOf",
            "kk_list_minOfOrNull",
            "kk_list_minOfWith",
            "kk_list_minOfWithOrNull",
            "kk_list_minOrNull",
            "kk_list_minWith",
            "kk_list_minWithOrNull",
            "kk_list_sorted",
            "kk_list_sortedBy",
            "kk_list_sortedByDescending",
            "kk_list_sortedByDescending_primitive",
            "kk_list_sortedBy_primitive",
            "kk_list_sortedDescending",
            "kk_list_sortedDescending_primitive",
            "kk_list_sortedWith",
            "kk_list_sorted_primitive",
            "__kk_mutable_list_sort",
            "__kk_mutable_list_sortBy",
            "__kk_mutable_list_sortByDescending",
            "__kk_mutable_list_sortByDescending_primitive",
            "__kk_mutable_list_sortBy_primitive",
            "__kk_mutable_list_sortDescending",
            "__kk_mutable_list_sortDescending_primitive",
            "__kk_mutable_list_sortWith",
            "__kk_mutable_list_sort_primitive",
            "kk_mutable_list_sort",
            "kk_mutable_list_sortBy",
            "kk_mutable_list_sortByDescending",
            "kk_mutable_list_sortByDescending_primitive",
            "kk_mutable_list_sortBy_primitive",
            "kk_mutable_list_sortDescending",
            "kk_mutable_list_sortDescending_primitive",
            "kk_mutable_list_sortWith",
            "kk_mutable_list_sort_primitive",
            "kk_list_zip_transform",
            // KSP-688: List slice/take/drop HOFs are source-backed in
            // kotlin.collections.ListSliceTakeDrop.kt; their compatibility
            // ABI specs remain but no runtime exports are emitted.
            "kk_list_takeWhile",
            "kk_list_takeLastWhile",
            "kk_list_dropWhile",
            "kk_list_dropLastWhile",
            // KSP-445: Sequence fold/scan HOFs are source-backed in bundled
            // kotlin.collections/sequences; runtime bridge is no longer exported.
            "kk_sequence_foldIndexed",
            "kk_sequence_reduceIndexed",
            "kk_sequence_reduceIndexedOrNull",
            "kk_sequence_runningFold",
            "kk_sequence_runningFoldIndexed",
            "kk_sequence_runningReduce",
            "kk_sequence_runningReduceIndexed",
            "kk_sequence_scan",
            "kk_sequence_scanIndexed",
            // KSP-430: Map higher-order functions are now source-backed in
            // bundled MapHOF.kt; these ABI entries remain for compatibility
            // with the synthetic stub externalLinkName literals.
            "kk_map_all",
            "kk_map_any",
            "kk_map_count",
            "kk_map_filter",
            "kk_map_filterKeys",
            "kk_map_filterNot",
            "kk_map_filterValues",
            "kk_map_flatMap",
            "kk_map_forEach",
            "kk_map_map",
            "kk_map_mapKeys",
            "kk_map_mapKeysTo",
            "kk_map_mapNotNull",
            "kk_map_mapValues",
            "kk_map_mapValuesTo",
            "kk_map_maxByOrNull",
            "kk_map_minByOrNull",
            "kk_map_minus",
            "kk_map_none",
            "kk_map_plus",
            "kk_long_range_firstOrNull",
            "kk_long_range_lastOrNull",
            "kk_native_atomic_ref_compareAndSet",
            "kk_native_atomic_ref_compareAndSwap",
            "kk_native_atomic_ref_create",
            "kk_native_atomic_ref_load",
            "kk_path_createLinkPointingTo",
            "kk_path_deleteExisting",
            "kk_path_deleteRecursively",
            "kk_path_div_path",
            "kk_path_div_string",
            "kk_path_fileAttributesView",
            "kk_path_fileAttributesViewOrNull",
            "kk_path_fileSize",
            "kk_path_fileStore",
            "kk_path_fileAttributesView",

            "kk_path_getAttribute",
            "kk_path_getPosixFilePermissions",
            "kk_path_get_base_subpaths",
            "kk_path_isExecutable",
            "kk_path_isHidden",
            "kk_path_isReadable",
            "kk_path_isSameFileAs",
            "kk_path_isSymbolicLink",
            "kk_path_isWritable",
            "kk_path_moveTo_options",
            "kk_path_moveTo_overwrite",
            "kk_path_outputStream",
            "kk_path_inputStream",
            "kk_path_readAttributes",
            "kk_path_readBytes",
            "kk_path_readLines_charset",
            "kk_path_readSymbolicLink",
            "kk_path_readText_charset",
            "kk_path_relativeTo",
            "kk_path_relativeToOrNull",
            "kk_path_relativeToOrSelf",
            "kk_path_setAttribute",
            "kk_path_setOwner",
            "kk_path_setPosixFilePermissions",
            "kk_path_writeBytes",
            "kk_path_writeLines_iterable",
            "kk_path_writeLines_sequence",
            "kk_path_reader",
            "kk_path_reader_default",
            "kk_path_readAttributes_string",
            "kk_path_writeText_options",
        ]
    }

    private struct RuntimeExportedABI {
        let name: String
        let returnType: String
        let parameterTypes: [String]
        let source: String
    }

    private enum RuntimeExportParseError: Error, CustomStringConvertible {
        case missingParameterType(String, source: String)
        case unknownSwiftType(String, source: String)

        var description: String {
            switch self {
            case let .missingParameterType(parameter, source):
                "Runtime export parameter is missing a type in \(source): \(parameter)"
            case let .unknownSwiftType(type, source):
                "Runtime export uses an unmapped Swift ABI type in \(source): \(type)"
            }
        }
    }

    private func runtimeExportedABIs() throws -> [RuntimeExportedABI] {
        let root = packageRootForRuntimeTests().appendingPathComponent("Sources/Runtime")
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var exports: [RuntimeExportedABI] = []
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
            let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard resourceValues.isRegularFile == true else { continue }
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            let relativePath = fileURL.path.replacingOccurrences(
                of: packageRootForRuntimeTests().path + "/",
                with: ""
            )
            exports.append(contentsOf: try runtimeExportedABIs(in: source, sourcePath: relativePath))
        }
        return exports.sorted { $0.name < $1.name }
    }

    private func runtimeExportedABIs(in source: String, sourcePath: String) throws -> [RuntimeExportedABI] {
        let concretePatterns = [
            #"@_cdecl\("([^"]+)"\)\s*(?:public\s+)?func\s+[A-Za-z0-9_]+\s*\((.*?)\)\s*(?:->\s*([^{\n]+))?"#,
            #"@_silgen_name\("([^"]+)"\)\s*public\s+func\s+[A-Za-z0-9_]+\s*\((.*?)\)\s*(?:->\s*([^{\n]+))?"#,
        ]
        let genericPattern = #"@_silgen_name\("([^"]+)"\)\s*public\s+func\s+[A-Za-z0-9_]+<[^>]+>"#

        var exports: [RuntimeExportedABI] = []

        // Collect generic-function names first (name-only; signature cannot be mapped to C types)
        let genericRegex = try NSRegularExpression(pattern: genericPattern, options: [])
        let fullRange = NSRange(source.startIndex..<source.endIndex, in: source)
        var genericNames: Set<String> = []
        for match in genericRegex.matches(in: source, range: fullRange) {
            guard let nameRange = Range(match.range(at: 1), in: source) else { continue }
            genericNames.insert(String(source[nameRange]))
        }
        for name in genericNames {
            exports.append(RuntimeExportedABI(name: name, returnType: "generic", parameterTypes: [], source: sourcePath))
        }

        for pattern in concretePatterns {
            let regex = try NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
            let range = NSRange(source.startIndex..<source.endIndex, in: source)
            for match in regex.matches(in: source, range: range) {
                guard
                    let nameRange = Range(match.range(at: 1), in: source),
                    let paramsRange = Range(match.range(at: 2), in: source)
                else {
                    continue
                }
                let name = String(source[nameRange])
                guard !genericNames.contains(name) else { continue }
                let params = String(source[paramsRange])
                let returnType: String
                if match.range(at: 3).location == NSNotFound {
                    returnType = RuntimeABICType.void.rawValue
                } else if let returnRange = Range(match.range(at: 3), in: source) {
                    returnType = try cTypeString(
                        forSwiftType: normalizedSwiftType(String(source[returnRange])),
                        source: sourcePath
                    )
                } else {
                    returnType = RuntimeABICType.void.rawValue
                }

                exports.append(RuntimeExportedABI(
                    name: name,
                    returnType: returnType,
                    parameterTypes: try parameterCTypeStrings(params, exportName: name, source: sourcePath),
                    source: sourcePath
                ))
            }
        }
        return exports
    }

    private func parameterCTypeStrings(
        _ parameters: String,
        exportName: String,
        source: String
    ) throws -> [String] {
        let trimmed = parameters.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return []
        }

        return try trimmed.split(separator: ",").enumerated().map { index, rawParameter in
            let parameter = String(rawParameter).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let colonIndex = parameter.firstIndex(of: ":") else {
                throw RuntimeExportParseError.missingParameterType(parameter, source: source)
            }
            let typeStart = parameter.index(after: colonIndex)
            let swiftType = normalizedSwiftType(String(parameter[typeStart...]))
            if exportName == "kk_alloc", index == 1, swiftType == "UnsafeRawPointer" {
                return RuntimeABICType.constTypeInfoPointer.rawValue
            }
            return try cTypeString(forSwiftType: swiftType, source: source)
        }
    }

    private func normalizedSwiftType(_ type: String) -> String {
        let withoutDefault = type.split(separator: "=", maxSplits: 1).first.map(String.init) ?? type
        return withoutDefault
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func cTypeString(forSwiftType swiftType: String, source: String) throws -> String {
        switch swiftType {
        case "Void":
            RuntimeABICType.void.rawValue
        case "Never":
            RuntimeABICType.noreturn.rawValue
        case "Int":
            RuntimeABICType.intptr.rawValue
        case "Int32":
            RuntimeABICType.int32.rawValue
        case "UInt32":
            RuntimeABICType.uint32.rawValue
        case "UInt64":
            RuntimeABICType.uint64.rawValue
        case "Int64":
            RuntimeABICType.int64.rawValue
        case "Float":
            RuntimeABICType.float.rawValue
        case "Double":
            RuntimeABICType.double.rawValue
        case "UnsafeMutableRawPointer":
            RuntimeABICType.opaquePointer.rawValue
        case "UnsafeMutableRawPointer?":
            RuntimeABICType.nullableOpaquePointer.rawValue
        case "UnsafeRawPointer":
            RuntimeABICType.constRawPointer.rawValue
        case "UnsafeRawPointer?":
            RuntimeABICType.nullableConstRawPointer.rawValue
        case "UnsafePointer<KTypeInfo>":
            RuntimeABICType.constTypeInfoPointer.rawValue
        case "UnsafePointer<UInt8>":
            RuntimeABICType.constUInt8Pointer.rawValue
        case "UnsafePointer<UInt8>?":
            RuntimeABICType.nullableConstUInt8Pointer.rawValue
        case "UnsafeMutablePointer<UInt8>?":
            RuntimeABICType.nullableUInt8Pointer.rawValue
        case "UnsafeMutablePointer<Int>?":
            RuntimeABICType.nullableIntptrPointer.rawValue
        case "UnsafeMutablePointer<UnsafeMutableRawPointer?>?":
            RuntimeABICType.nullableRawPointerPointer.rawValue
        default:
            throw RuntimeExportParseError.unknownSwiftType(swiftType, source: source)
        }
    }

    private func packageRootForRuntimeTests(file: StaticString = #filePath) -> URL {
        URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
#endif
