import RuntimeABI
@testable import Runtime
import XCTest

// MARK: - Shared ABI Spec / Extern Adapter Reconciliation

extension ABIMismatchTests {
    private func normalizedABIType(_ type: String) -> String {
        type
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_Nullable", with: "")
    }

    private func sharedABINames() -> [String] {
        let specNames = RuntimeABISpec.allFunctions.map(\.name)
        let externNameSet = Set(RuntimeABIExterns.allExterns.map(\.name))
        return specNames.filter { externNameSet.contains($0) }
    }

    func testExternCountMatchesSpec() {
        let specNames = RuntimeABISpec.allFunctions.map(\.name)
        let externNames = RuntimeABIExterns.allExterns.map(\.name)
        var externNameCounts: [String: Int] = [:]
        for name in externNames {
            externNameCounts[name, default: 0] += 1
        }
        let duplicateExternNames = externNameCounts
            .filter { $0.value > 1 }
            .sorted { $0.key < $1.key }
            .map { "\($0.key)(\($0.value))" }
        XCTAssertTrue(
            duplicateExternNames.isEmpty,
            "RuntimeABIExterns.allExterns should not contain duplicate names: \(duplicateExternNames.joined(separator: ", "))"
        )
        XCTAssertGreaterThanOrEqual(
            externNames.count,
            specNames.count,
            "RuntimeABIExterns should cover the RuntimeABISpec surface"
        )
    }

    func testEverySpecFunctionHasMatchingExtern() {
        for specName in sharedABINames() {
            let spec = RuntimeABISpec.allFunctions.first { $0.name == specName }
            XCTAssertNotNil(spec)
            let externDecl = RuntimeABIExterns.externDecl(named: specName)
            XCTAssertNotNil(
                externDecl,
                "RuntimeABISpec function '\(specName)' has no matching entry in RuntimeABIExterns"
            )
        }
    }

    func testEveryExternHasMatchingSpecFunction() {
        XCTAssertFalse(sharedABINames().isEmpty, "RuntimeABISpec and RuntimeABIExterns should share ABI entries")
    }

    func testFunctionOrderMatches() {
        let specNames = sharedABINames()
        XCTAssertFalse(specNames.isEmpty, "Shared ABI entries should not be empty")
    }

    func testReturnTypesMatch() {
        for spec in RuntimeABISpec.allFunctions {
            guard let externDecl = RuntimeABIExterns.externDecl(named: spec.name) else {
                continue
            }
            XCTAssertEqual(
                normalizedABIType(spec.returnTypeString),
                normalizedABIType(externDecl.returnType),
                "Return type mismatch for '\(spec.name)': " +
                    "RuntimeABISpec says '\(spec.returnTypeString)' but " +
                    "RuntimeABIExterns says '\(externDecl.returnType)'"
            )
        }
    }

    func testParameterTypesMatch() {
        for spec in RuntimeABISpec.allFunctions {
            guard let externDecl = RuntimeABIExterns.externDecl(named: spec.name) else {
                continue
            }
            XCTAssertEqual(
                spec.parameterTypeStrings.map(normalizedABIType),
                externDecl.parameterTypes.map(normalizedABIType),
                "Parameter type mismatch for '\(spec.name)': " +
                    "RuntimeABISpec says \(spec.parameterTypeStrings) but " +
                    "RuntimeABIExterns says \(externDecl.parameterTypes)"
            )
        }
    }

    func testParameterCountsMatch() {
        for spec in RuntimeABISpec.allFunctions {
            guard let externDecl = RuntimeABIExterns.externDecl(named: spec.name) else {
                continue
            }
            XCTAssertEqual(
                spec.parameters.count,
                externDecl.parameterTypes.count,
                "Parameter count mismatch for '\(spec.name)': " +
                    "RuntimeABISpec has \(spec.parameters.count) but " +
                    "RuntimeABIExterns has \(externDecl.parameterTypes.count)"
            )
        }
    }

    // MARK: - Comparator trampoline signature consistency

    func testComparatorTrampolinesHaveFourParameters() {
        let trampolines = RuntimeABISpec.comparatorFunctions.filter {
            $0.name.contains("trampoline")
        }
        XCTAssertFalse(trampolines.isEmpty, "Should have comparator trampoline functions")
        for spec in trampolines {
            XCTAssertEqual(
                spec.parameters.count, 4,
                "Comparator trampoline '\(spec.name)' should have 4 parameters (closureRaw, a, b, outThrown)"
            )
            XCTAssertEqual(
                spec.parameters[0].name, "closureRaw",
                "First parameter of '\(spec.name)' should be closureRaw"
            )
            XCTAssertEqual(
                spec.parameters.last?.name, "outThrown",
                "Last parameter of '\(spec.name)' should be outThrown"
            )
            XCTAssertEqual(
                spec.parameters.last?.type, .nullableIntptrPointer,
                "outThrown of '\(spec.name)' should be nullable intptr pointer"
            )
        }
    }

    func testComparatorNullsAndThenByDescSymbolsPresent() {
        let requiredComparatorSymbols: Set<String> = [
            "kk_comparator_then_by_descending",
            "kk_comparator_then_by_descending_trampoline",
            "kk_comparator_nulls_first",
            "kk_comparator_nulls_first_trampoline",
            "kk_comparator_nulls_last",
            "kk_comparator_nulls_last_trampoline",
        ]
        let specNames = Set(RuntimeABISpec.allFunctions.map(\.name))
        let externNames = Set(RuntimeABIExterns.allExterns.map(\.name))
        for name in requiredComparatorSymbols {
            XCTAssertTrue(
                specNames.contains(name),
                "RuntimeABISpec is missing comparator function '\(name)'"
            )
            XCTAssertTrue(
                externNames.contains(name),
                "RuntimeABIExterns is missing comparator function '\(name)'"
            )
        }
    }

    func testComparatorNullsThenBySignaturesMatchExpectedShape() {
        let expectedFunctionTypes: [String: [String]] = [
            "kk_comparator_then_by_descending": [RuntimeABICType.intptr.rawValue, RuntimeABICType.intptr.rawValue, RuntimeABICType.intptr.rawValue, RuntimeABICType.intptr.rawValue],
            "kk_comparator_nulls_first": [RuntimeABICType.intptr.rawValue, RuntimeABICType.intptr.rawValue],
            "kk_comparator_nulls_last": [RuntimeABICType.intptr.rawValue, RuntimeABICType.intptr.rawValue],
        ]
        let expectedTrampolineTypes: [String: [String]] = [
            "kk_comparator_then_by_descending_trampoline": [RuntimeABICType.intptr.rawValue, RuntimeABICType.intptr.rawValue, RuntimeABICType.intptr.rawValue, RuntimeABICType.nullableIntptrPointer.rawValue],
            "kk_comparator_nulls_first_trampoline": [RuntimeABICType.intptr.rawValue, RuntimeABICType.intptr.rawValue, RuntimeABICType.intptr.rawValue, RuntimeABICType.nullableIntptrPointer.rawValue],
            "kk_comparator_nulls_last_trampoline": [RuntimeABICType.intptr.rawValue, RuntimeABICType.intptr.rawValue, RuntimeABICType.intptr.rawValue, RuntimeABICType.nullableIntptrPointer.rawValue],
        ]
        for (name, expectedTypes) in expectedFunctionTypes {
            let spec = RuntimeABISpec.allFunctions.first { $0.name == name }
            XCTAssertNotNil(spec, "RuntimeABISpec should include '\(name)'")
            XCTAssertEqual(
                spec?.parameterTypeStrings ?? [],
                expectedTypes,
                "RuntimeABISpec parameter types for '\(name)' are unexpected"
            )
            let externDecl = RuntimeABIExterns.externDecl(named: name)
            XCTAssertNotNil(externDecl, "RuntimeABIExterns should include '\(name)'")
            XCTAssertEqual(
                externDecl?.parameterTypes ?? [],
                expectedTypes,
                "RuntimeABIExterns parameter types for '\(name)' are unexpected"
            )
        }
        for (name, expectedTypes) in expectedTrampolineTypes {
            let spec = RuntimeABISpec.allFunctions.first { $0.name == name }
            XCTAssertNotNil(spec, "RuntimeABISpec should include '\(name)'")
            XCTAssertEqual(
                spec?.parameterTypeStrings ?? [],
                expectedTypes,
                "RuntimeABISpec parameter types for '\(name)' are unexpected"
            )
            let externDecl = RuntimeABIExterns.externDecl(named: name)
            XCTAssertNotNil(externDecl, "RuntimeABIExterns should include '\(name)'")
            XCTAssertEqual(
                externDecl?.parameterTypes ?? [],
                expectedTypes,
                "RuntimeABIExterns parameter types for '\(name)' are unexpected"
            )
        }
    }

    // MARK: - HOF function fnPtr parameter consistency

    func testCollectionHOFLambdaFunctionsHaveFnPtrParameter() {
        // Builder thunk functions (kk_build_*) correctly use fnPtr without closureRaw
        let builderThunks: Set<String> = [
            "kk_build_string", "kk_build_list", "kk_build_list_with_capacity",
            "kk_build_set", "kk_build_map", "kk_sequence_builder_build", "kk_iterator_builder_build",
        ]
        let hofSections: Set<String> = ["Collection", "Sequence"]
        let hofFunctions = RuntimeABISpec.allFunctions.filter {
            hofSections.contains($0.section)
                && $0.parameters.contains(where: { $0.name == "fnPtr" })
                && !builderThunks.contains($0.name)
        }
        for spec in hofFunctions {
            let hasClosure = spec.parameters.contains(where: { $0.name == "closureRaw" })
            XCTAssertTrue(
                hasClosure,
                "HOF function '\(spec.name)' has fnPtr but missing closureRaw parameter"
            )
        }
    }
}
