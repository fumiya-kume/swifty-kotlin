import CompilerCore
@testable import Runtime
import XCTest

// MARK: - Cross-Module ABI Reconciliation (Runtime <-> CompilerCore)

extension ABIMismatchTests {
    /// Verify that RuntimeABISpec and RuntimeABIExterns have the same function count.
    func testExternCountMatchesSpec() {
        let specNames = RuntimeABISpec.allFunctions.map(\.name)
        let externNames = RuntimeABIExterns.allExterns.map(\.name)
        XCTAssertEqual(
            specNames.count,
            externNames.count,
            "RuntimeABISpec has \(specNames.count) functions but RuntimeABIExterns has \(externNames.count)"
        )
    }

    /// Verify that every RuntimeABISpec function has a matching RuntimeABIExterns entry.
    func testEverySpecFunctionHasMatchingExtern() {
        for spec in RuntimeABISpec.allFunctions {
            let externDecl = RuntimeABIExterns.externDecl(named: spec.name)
            XCTAssertNotNil(
                externDecl,
                "RuntimeABISpec function '\(spec.name)' has no matching entry in RuntimeABIExterns"
            )
        }
    }

    /// Verify that every RuntimeABIExterns entry has a matching RuntimeABISpec function.
    func testEveryExternHasMatchingSpecFunction() {
        for externDecl in RuntimeABIExterns.allExterns {
            let spec = RuntimeABISpec.allFunctions.first { $0.name == externDecl.name }
            XCTAssertNotNil(
                spec,
                "RuntimeABIExterns entry '\(externDecl.name)' has no matching entry in RuntimeABISpec"
            )
        }
    }

    /// Verify that function names appear in the same order in both lists.
    func testFunctionOrderMatches() {
        let specNames = RuntimeABISpec.allFunctions.map(\.name)
        let externNames = RuntimeABIExterns.allExterns.map(\.name)
        XCTAssertEqual(
            specNames,
            externNames,
            "Function order in RuntimeABISpec and RuntimeABIExterns must match"
        )
    }

    /// The core ABI mismatch detection: verify return types match.
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

    /// The core ABI mismatch detection: verify parameter types match.
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

    /// Verify parameter count match for each function.
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
}
