import XCTest
@testable import CompilerCore

final class ConstraintSolverTests: XCTestCase {
    func testSolveInitializesSubstitutionForAllVariables() {
        let solver = ConstraintSolver()
        let types = TypeSystem()
        let vars = [TypeVarID(rawValue: 1), TypeVarID(rawValue: 2)]
        let constraints: [Constraint] = []

        let solution = solver.solve(vars: vars, constraints: constraints, typeSystem: types)

        XCTAssertTrue(solution.isSuccess)
        XCTAssertNil(solution.failure)
        XCTAssertEqual(solution.substitution[vars[0]], types.errorType)
        XCTAssertEqual(solution.substitution[vars[1]], types.errorType)
    }

    func testSolveSupportsSubtypeEqualAndSupertypeConstraints() {
        let solver = ConstraintSolver()
        let types = TypeSystem()
        let intType = types.make(.primitive(.int, .nonNull))
        let boolType = types.make(.primitive(.boolean, .nonNull))
        let nullableAny = types.nullableAnyType

        let constraints = [
            Constraint(kind: .subtype, left: intType, right: nullableAny),
            Constraint(kind: .equal, left: boolType, right: boolType),
            Constraint(kind: .supertype, left: nullableAny, right: intType)
        ]

        let solution = solver.solve(
            vars: [TypeVarID(rawValue: 3)],
            constraints: constraints,
            typeSystem: types
        )

        XCTAssertTrue(solution.isSuccess)
        XCTAssertNil(solution.failure)
    }

    func testSolveReturnsFailureDiagnosticForUnsatisfiedConstraint() {
        let solver = ConstraintSolver()
        let types = TypeSystem()
        let intType = types.make(.primitive(.int, .nonNull))
        let boolType = types.make(.primitive(.boolean, .nonNull))
        let variable = TypeVarID(rawValue: 4)
        let blameRange = makeRange(start: 2, end: 5)

        let solution = solver.solve(
            vars: [variable],
            constraints: [Constraint(kind: .subtype, left: boolType, right: intType, blameRange: blameRange)],
            typeSystem: types
        )

        XCTAssertFalse(solution.isSuccess)
        XCTAssertEqual(solution.substitution[variable], types.errorType)
        XCTAssertEqual(solution.failure?.severity, .error)
        XCTAssertEqual(solution.failure?.code, "KSWIFTK-TYPE-0001")
        XCTAssertEqual(solution.failure?.primaryRange, blameRange)
    }

    func testSolveVariableConstraintsBindsTypeVariablesFromEqualityAndBounds() {
        let solver = ConstraintSolver()
        let types = TypeSystem()
        let intType = types.make(.primitive(.int, .nonNull))
        let anyType = types.anyType
        let t0 = TypeVarID(rawValue: 10)
        let t1 = TypeVarID(rawValue: 11)

        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .equal, left: .variable(t0), right: .type(intType)),
            VariableConstraint(kind: .supertype, left: .variable(t1), right: .type(intType)),
            VariableConstraint(kind: .subtype, left: .variable(t1), right: .type(anyType))
        ]
        let solution = solver.solve(vars: [t0, t1], constraints: constraints, typeSystem: types)

        XCTAssertTrue(solution.isSuccess)
        XCTAssertNil(solution.failure)
        XCTAssertEqual(solution.substitution[t0], intType)
        XCTAssertEqual(solution.substitution[t1], intType)
    }

    func testSolveVariableConstraintsFailsOnConflictingBounds() {
        let solver = ConstraintSolver()
        let types = TypeSystem()
        let intType = types.make(.primitive(.int, .nonNull))
        let boolType = types.make(.primitive(.boolean, .nonNull))
        let t0 = TypeVarID(rawValue: 12)
        let blame = makeRange(start: 9, end: 12)

        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .supertype, left: .variable(t0), right: .type(intType), blameRange: blame),
            VariableConstraint(kind: .subtype, left: .variable(t0), right: .type(boolType), blameRange: blame)
        ]
        let solution = solver.solve(vars: [t0], constraints: constraints, typeSystem: types)

        XCTAssertFalse(solution.isSuccess)
        XCTAssertEqual(solution.failure?.code, "KSWIFTK-TYPE-0001")
        XCTAssertEqual(solution.failure?.primaryRange, blame)
        XCTAssertTrue(solution.failure?.message.contains("Conflicting bounds for type variable #12") ?? false)
        XCTAssertEqual(solution.substitution[t0], types.errorType)
    }

    // MARK: - Variable-to-variable propagation

    func testSolveVariableConstraintsPropagatesBoundsThroughVariableRelations() {
        let solver = ConstraintSolver()
        let types = TypeSystem()
        let intType = types.make(.primitive(.int, .nonNull))
        let anyType = types.anyType
        let t0 = TypeVarID(rawValue: 20)
        let t1 = TypeVarID(rawValue: 21)

        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .subtype, left: .variable(t0), right: .variable(t1)),
            VariableConstraint(kind: .subtype, left: .type(intType), right: .variable(t0)),
            VariableConstraint(kind: .subtype, left: .variable(t1), right: .type(anyType))
        ]
        let solution = solver.solve(vars: [t0, t1], constraints: constraints, typeSystem: types)

        XCTAssertTrue(solution.isSuccess)
        XCTAssertEqual(solution.substitution[t0], intType)
        XCTAssertEqual(solution.substitution[t1], intType)
    }

    // MARK: - Post-solve constraint verification failures

    func testSolveFailsWhenResolvedConstraintIsNotSatisfied() {
        let solver = ConstraintSolver()
        let types = TypeSystem()
        let intType = types.make(.primitive(.int, .nonNull))
        let boolType = types.make(.primitive(.boolean, .nonNull))
        let t0 = TypeVarID(rawValue: 30)
        let blame = makeRange(start: 20, end: 25)

        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .subtype, left: .type(intType), right: .variable(t0)),
            VariableConstraint(kind: .equal, left: .variable(t0), right: .type(boolType), blameRange: blame)
        ]
        let solution = solver.solve(vars: [t0], constraints: constraints, typeSystem: types)

        XCTAssertFalse(solution.isSuccess)
        XCTAssertNotNil(solution.failure)
        XCTAssertTrue(solution.failure?.message.contains("not satisfied") ?? false)
    }

    func testSolveFailsWithSupertypeConstraintNotSatisfied() {
        let solver = ConstraintSolver()
        let types = TypeSystem()
        let intType = types.make(.primitive(.int, .nonNull))
        let boolType = types.make(.primitive(.boolean, .nonNull))
        let t0 = TypeVarID(rawValue: 31)
        let blame = makeRange(start: 30, end: 35)

        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .subtype, left: .type(intType), right: .variable(t0)),
            VariableConstraint(kind: .supertype, left: .variable(t0), right: .type(boolType), blameRange: blame)
        ]
        let solution = solver.solve(vars: [t0], constraints: constraints, typeSystem: types)

        XCTAssertFalse(solution.isSuccess)
        XCTAssertNotNil(solution.failure)
    }

    // MARK: - Error type candidate

    func testSolveFailsWhenCandidateIsErrorType() {
        let solver = ConstraintSolver()
        let types = TypeSystem()
        let t0 = TypeVarID(rawValue: 40)
        let blame = makeRange(start: 40, end: 45)

        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .subtype, left: .type(types.errorType), right: .variable(t0), blameRange: blame)
        ]
        let solution = solver.solve(vars: [t0], constraints: constraints, typeSystem: types)

        XCTAssertFalse(solution.isSuccess)
        XCTAssertTrue(solution.failure?.message.contains("Failed to infer") ?? false)
    }

    // MARK: - Upper-bound only resolution

    func testSolveResolvesVariableWithOnlyUpperBound() {
        let solver = ConstraintSolver()
        let types = TypeSystem()
        let intType = types.make(.primitive(.int, .nonNull))
        let t0 = TypeVarID(rawValue: 50)

        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .subtype, left: .variable(t0), right: .type(intType))
        ]
        let solution = solver.solve(vars: [t0], constraints: constraints, typeSystem: types)

        XCTAssertTrue(solution.isSuccess)
        XCTAssertEqual(solution.substitution[t0], intType)
    }

    // MARK: - Both lower and upper bounds (compatible)

    func testSolveResolvesVariableWithCompatibleLowerAndUpperBounds() {
        let solver = ConstraintSolver()
        let types = TypeSystem()
        let intType = types.make(.primitive(.int, .nonNull))
        let anyType = types.anyType
        let t0 = TypeVarID(rawValue: 60)

        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .subtype, left: .type(intType), right: .variable(t0)),
            VariableConstraint(kind: .subtype, left: .variable(t0), right: .type(anyType))
        ]
        let solution = solver.solve(vars: [t0], constraints: constraints, typeSystem: types)

        XCTAssertTrue(solution.isSuccess)
        XCTAssertEqual(solution.substitution[t0], intType)
    }

    // MARK: - TypeVarID static invalid

    func testTypeVarIDInvalidHasNegativeRawValue() {
        XCTAssertEqual(TypeVarID.invalid.rawValue, -1)
    }

    func testTypeVarIDDefaultInit() {
        let id = TypeVarID()
        XCTAssertEqual(id.rawValue, -1)
    }

    // MARK: - ConstraintOperand Equatable

    func testConstraintOperandEquatable() {
        let a: ConstraintOperand = .type(TypeID(rawValue: 1))
        let b: ConstraintOperand = .type(TypeID(rawValue: 1))
        let c: ConstraintOperand = .variable(TypeVarID(rawValue: 2))
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    // MARK: - appendUnique duplicate

    func testSolveDuplicateBoundsAreDeduped() {
        let solver = ConstraintSolver()
        let types = TypeSystem()
        let intType = types.make(.primitive(.int, .nonNull))
        let t0 = TypeVarID(rawValue: 70)

        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .subtype, left: .type(intType), right: .variable(t0)),
            VariableConstraint(kind: .subtype, left: .type(intType), right: .variable(t0))
        ]
        let solution = solver.solve(vars: [t0], constraints: constraints, typeSystem: types)

        XCTAssertTrue(solution.isSuccess)
        XCTAssertEqual(solution.substitution[t0], intType)
    }

    // MARK: - firstRelevantBlameRange right-side variable

    func testSolveBlameRangeFromRightSideVariable() {
        let solver = ConstraintSolver()
        let types = TypeSystem()
        let intType = types.make(.primitive(.int, .nonNull))
        let boolType = types.make(.primitive(.boolean, .nonNull))
        let t0 = TypeVarID(rawValue: 80)
        let blame = makeRange(start: 50, end: 55)

        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .subtype, left: .type(intType), right: .type(boolType), blameRange: blame),
            VariableConstraint(kind: .subtype, left: .type(intType), right: .variable(t0), blameRange: blame)
        ]
        let solution = solver.solve(vars: [t0], constraints: constraints, typeSystem: types)

        XCTAssertFalse(solution.isSuccess)
        XCTAssertEqual(solution.failure?.primaryRange, blame)
    }

    // MARK: - Solution init

    func testSolutionInitStoresAllFields() {
        let sub: [TypeVarID: TypeID] = [TypeVarID(rawValue: 0): TypeID(rawValue: 5)]
        let diag = Diagnostic(
            severity: .error,
            code: "TEST",
            message: "test",
            primaryRange: nil,
            secondaryRanges: []
        )
        let solution = Solution(substitution: sub, isSuccess: false, failure: diag)
        XCTAssertEqual(solution.substitution[TypeVarID(rawValue: 0)], TypeID(rawValue: 5))
        XCTAssertFalse(solution.isSuccess)
        XCTAssertEqual(solution.failure?.code, "TEST")
    }

    // MARK: - Variable-to-variable convergence (no change early break)

    func testSolveVarToVarConvergesWithoutChange() {
        let solver = ConstraintSolver()
        let types = TypeSystem()
        let intType = types.make(.primitive(.int, .nonNull))
        let t0 = TypeVarID(rawValue: 90)
        let t1 = TypeVarID(rawValue: 91)

        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .subtype, left: .variable(t0), right: .variable(t1)),
            VariableConstraint(kind: .subtype, left: .type(intType), right: .variable(t0)),
            VariableConstraint(kind: .subtype, left: .type(intType), right: .variable(t1))
        ]
        let solution = solver.solve(vars: [t0, t1], constraints: constraints, typeSystem: types)

        XCTAssertTrue(solution.isSuccess)
        XCTAssertEqual(solution.substitution[t0], intType)
        XCTAssertEqual(solution.substitution[t1], intType)
    }

    // MARK: - Constraint init with blameRange

    func testConstraintInitWithBlameRange() {
        let blame = makeRange(start: 10, end: 20)
        let constraint = Constraint(
            kind: .equal,
            left: TypeID(rawValue: 1),
            right: TypeID(rawValue: 2),
            blameRange: blame
        )
        XCTAssertEqual(constraint.kind, .equal)
        XCTAssertEqual(constraint.blameRange, blame)
    }

    func testConstraintInitWithoutBlameRange() {
        let constraint = Constraint(
            kind: .subtype,
            left: TypeID(rawValue: 1),
            right: TypeID(rawValue: 2)
        )
        XCTAssertNil(constraint.blameRange)
    }

    // MARK: - VariableConstraint init

    func testVariableConstraintInitWithBlameRange() {
        let blame = makeRange(start: 0, end: 5)
        let vc = VariableConstraint(
            kind: .supertype,
            left: .variable(TypeVarID(rawValue: 1)),
            right: .type(TypeID(rawValue: 2)),
            blameRange: blame
        )
        XCTAssertEqual(vc.kind, .supertype)
        XCTAssertEqual(vc.blameRange, blame)
    }

    func testVariableConstraintInitWithoutBlameRange() {
        let vc = VariableConstraint(
            kind: .equal,
            left: .type(TypeID(rawValue: 1)),
            right: .variable(TypeVarID(rawValue: 2))
        )
        XCTAssertNil(vc.blameRange)
    }
}
