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
}
