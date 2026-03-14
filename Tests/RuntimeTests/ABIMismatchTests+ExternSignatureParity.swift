import CompilerCore
@testable import Runtime
import XCTest

// MARK: - Cross-Module ABI Reconciliation (Runtime <-> CompilerCore)

extension ABIMismatchTests {
    func testExternCountMatchesSpec() {
        let specNames = RuntimeABISpec.allFunctions.map(\.name)
        let externNames = RuntimeABIExterns.allExterns.map(\.name)
        XCTAssertEqual(
            specNames.count,
            externNames.count,
            "RuntimeABISpec has \(specNames.count) functions but RuntimeABIExterns has \(externNames.count)"
        )
    }

    func testEverySpecFunctionHasMatchingExtern() {
        for spec in RuntimeABISpec.allFunctions {
            let externDecl = RuntimeABIExterns.externDecl(named: spec.name)
            XCTAssertNotNil(
                externDecl,
                "RuntimeABISpec function '\(spec.name)' has no matching entry in RuntimeABIExterns"
            )
        }
    }

    func testEveryExternHasMatchingSpecFunction() {
        for externDecl in RuntimeABIExterns.allExterns {
            let spec = RuntimeABISpec.allFunctions.first { $0.name == externDecl.name }
            XCTAssertNotNil(
                spec,
                "RuntimeABIExterns entry '\(externDecl.name)' has no matching entry in RuntimeABISpec"
            )
        }
    }

    func testFunctionOrderMatches() {
        let specNames = RuntimeABISpec.allFunctions.map(\.name)
        let externNames = RuntimeABIExterns.allExterns.map(\.name)
        XCTAssertEqual(
            specNames,
            externNames,
            "Function order in RuntimeABISpec and RuntimeABIExterns must match"
        )
    }

    func testReturnTypesMatch() {
        for spec in RuntimeABISpec.allFunctions {
            guard let externDecl = RuntimeABIExterns.externDecl(named: spec.name) else {
                continue
            }
            XCTAssertEqual(
                spec.returnTypeString,
                externDecl.returnType,
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
                spec.parameterTypeStrings,
                externDecl.parameterTypes,
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

    // MARK: - HOF function fnPtr parameter consistency

    func testCollectionHOFLambdaFunctionsHaveFnPtrParameter() {
        // Builder thunk functions (kk_build_*) correctly use fnPtr without closureRaw
        let builderThunks: Set<String> = [
            "kk_build_string", "kk_build_list", "kk_build_list_with_capacity",
            "kk_build_set", "kk_build_map", "kk_sequence_builder_build",
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
