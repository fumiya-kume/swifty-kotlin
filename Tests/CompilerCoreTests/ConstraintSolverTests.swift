import XCTest
@testable import CompilerCore

final class ConstraintSolverTests: XCTestCase {
    private var solver: ConstraintSolver!
    private var types: TypeSystem!

    override func setUp() {
        super.setUp()
        solver = ConstraintSolver()
        types = TypeSystem()
    }

    func testSolveInitializesSubstitutionForAllVariables() {
        let vars = [TypeVarID(rawValue: 1), TypeVarID(rawValue: 2)]
        let constraints: [Constraint] = []

        let solution = solver.solve(vars: vars, constraints: constraints, typeSystem: types)

        XCTAssertTrue(solution.isSuccess)
        XCTAssertNil(solution.failure)
        XCTAssertEqual(solution.substitution[vars[0]], types.errorType)
        XCTAssertEqual(solution.substitution[vars[1]], types.errorType)
    }

    func testSolveSupportsSubtypeEqualAndSupertypeConstraints() {
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

    func testSolveVariableToVariableRelationPropagatesBounds() {
        let intType = types.make(.primitive(.int, .nonNull))
        let anyType = types.anyType
        let t0 = TypeVarID(rawValue: 20)
        let t1 = TypeVarID(rawValue: 21)

        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .subtype, left: .type(intType), right: .variable(t0)),
            VariableConstraint(kind: .subtype, left: .variable(t0), right: .variable(t1)),
            VariableConstraint(kind: .subtype, left: .variable(t1), right: .type(anyType))
        ]
        let solution = solver.solve(vars: [t0, t1], constraints: constraints, typeSystem: types)

        XCTAssertTrue(solution.isSuccess)
        XCTAssertEqual(solution.substitution[t0], intType)
    }

    func testSolvePostSubstitutionConstraintVerificationFailure() throws {
        let intType = types.make(.primitive(.int, .nonNull))
        let boolType = types.make(.primitive(.boolean, .nonNull))
        let t0 = TypeVarID(rawValue: 30)
        let blame = makeRange(start: 0, end: 3)

        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .equal, left: .variable(t0), right: .type(intType)),
            VariableConstraint(kind: .subtype, left: .variable(t0), right: .type(boolType), blameRange: blame)
        ]
        let solution = solver.solve(vars: [t0], constraints: constraints, typeSystem: types)

        XCTAssertFalse(solution.isSuccess)
        let failure = try XCTUnwrap(solution.failure)
        XCTAssertEqual(failure.code, "KSWIFTK-TYPE-0001")
        XCTAssertTrue(failure.message.contains("not satisfied"))
    }

    func testSolveSupertypeConstraintKindSatisfaction() {
        let intType = types.make(.primitive(.int, .nonNull))
        let anyType = types.anyType
        let t0 = TypeVarID(rawValue: 40)

        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .supertype, left: .variable(t0), right: .type(intType)),
            VariableConstraint(kind: .supertype, left: .type(anyType), right: .variable(t0))
        ]
        let solution = solver.solve(vars: [t0], constraints: constraints, typeSystem: types)

        XCTAssertTrue(solution.isSuccess)
        XCTAssertEqual(solution.substitution[t0], intType)
    }

    func testSolveOnlyUpperBoundsUsesGLB() {
        let anyType = types.anyType
        let t0 = TypeVarID(rawValue: 50)

        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .subtype, left: .variable(t0), right: .type(anyType))
        ]
        let solution = solver.solve(vars: [t0], constraints: constraints, typeSystem: types)

        XCTAssertTrue(solution.isSuccess)
        XCTAssertNotNil(solution.substitution[t0])
    }

    func testSolveVariableConstraintsFailsOnConflictingBounds() throws {
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
        let failure = try XCTUnwrap(solution.failure)
        XCTAssertEqual(failure.code, "KSWIFTK-TYPE-0001")
        XCTAssertEqual(failure.primaryRange, blame)
        XCTAssertTrue(failure.message.contains("Conflicting bounds for type variable #12"))
        XCTAssertEqual(solution.substitution[t0], types.errorType)
    }

    func testSolveSupertypeConstraintAddsLowerBound() {
        let intType = types.make(.primitive(.int, .nonNull))
        let t0 = TypeVarID(rawValue: 31)

        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .supertype, left: .variable(t0), right: .type(intType))
        ]
        let solution = solver.solve(vars: [t0], constraints: constraints, typeSystem: types)

        XCTAssertTrue(solution.isSuccess)
        XCTAssertEqual(solution.substitution[t0], intType)
    }

    func testSolveFailsWhenCandidateIsErrorType() throws {
        let t0 = TypeVarID(rawValue: 41)
        let blame = makeRange(start: 40, end: 45)

        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .subtype, left: .type(types.errorType), right: .variable(t0), blameRange: blame)
        ]
        let solution = solver.solve(vars: [t0], constraints: constraints, typeSystem: types)

        XCTAssertFalse(solution.isSuccess)
        let failure = try XCTUnwrap(solution.failure)
        XCTAssertTrue(failure.message.contains("Failed to infer"))
    }

    func testSolveResolvesVariableWithOnlyUpperBound() {
        let intType = types.make(.primitive(.int, .nonNull))
        let t0 = TypeVarID(rawValue: 51)

        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .subtype, left: .variable(t0), right: .type(intType))
        ]
        let solution = solver.solve(vars: [t0], constraints: constraints, typeSystem: types)

        XCTAssertTrue(solution.isSuccess)
        XCTAssertEqual(solution.substitution[t0], intType)
    }

    func testSolveResolvesVariableWithCompatibleLowerAndUpperBounds() {
        let intType = types.make(.primitive(.int, .nonNull))
        let anyType = types.anyType
        let t0 = TypeVarID(rawValue: 61)

        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .subtype, left: .type(intType), right: .variable(t0)),
            VariableConstraint(kind: .subtype, left: .variable(t0), right: .type(anyType))
        ]
        let solution = solver.solve(vars: [t0], constraints: constraints, typeSystem: types)

        XCTAssertTrue(solution.isSuccess)
        XCTAssertEqual(solution.substitution[t0], intType)
    }

    func testConstraintOperandEquatable() {
        let a: ConstraintOperand = .type(TypeID(rawValue: 1))
        let b: ConstraintOperand = .type(TypeID(rawValue: 1))
        let c: ConstraintOperand = .variable(TypeVarID(rawValue: 2))
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testSolveDuplicateBoundsAreDeduped() {
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

    func testSolveBlameRangeFromRightSideVariable() {
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

    func testSolveVarToVarConvergesWithoutChange() {
        let intType = types.make(.primitive(.int, .nonNull))
        let t0 = TypeVarID(rawValue: 92)
        let t1 = TypeVarID(rawValue: 93)

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

    func testSolveBothBoundsUsesLowerCandidate(){
        let intType = types.make(.primitive(.int, .nonNull))
        let anyType = types.anyType
        let t0 = TypeVarID(rawValue: 60)

        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .supertype, left: .variable(t0), right: .type(intType)),
            VariableConstraint(kind: .subtype, left: .variable(t0), right: .type(anyType))
        ]
        let solution = solver.solve(vars: [t0], constraints: constraints, typeSystem: types)

        XCTAssertTrue(solution.isSuccess)
        XCTAssertEqual(solution.substitution[t0], intType)
    }

    func testSolveErrorCandidateReportsFailure() throws {
        let t0 = TypeVarID(rawValue: 70)
        let blame = makeRange(start: 5, end: 8)

        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .supertype, left: .variable(t0), right: .type(types.errorType), blameRange: blame)
        ]
        let solution = solver.solve(vars: [t0], constraints: constraints, typeSystem: types)

        XCTAssertFalse(solution.isSuccess)
        let failure = try XCTUnwrap(solution.failure)
        XCTAssertTrue(failure.message.contains("Failed to infer type variable"))
    }

    func testSolveMultipleVarRelationsConverge() {
        let intType = types.make(.primitive(.int, .nonNull))
        let anyType = types.anyType
        let t0 = TypeVarID(rawValue: 80)
        let t1 = TypeVarID(rawValue: 81)
        let t2 = TypeVarID(rawValue: 82)

        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .supertype, left: .variable(t0), right: .type(intType)),
            VariableConstraint(kind: .subtype, left: .variable(t0), right: .variable(t1)),
            VariableConstraint(kind: .subtype, left: .variable(t1), right: .variable(t2)),
            VariableConstraint(kind: .subtype, left: .variable(t2), right: .type(anyType))
        ]
        let solution = solver.solve(vars: [t0, t1, t2], constraints: constraints, typeSystem: types)

        XCTAssertTrue(solution.isSuccess)
    }

    func testTypeVarIDInvalidAndEquality() {
        XCTAssertEqual(TypeVarID.invalid.rawValue, -1)
        XCTAssertEqual(TypeVarID(), TypeVarID.invalid)
        XCTAssertNotEqual(TypeVarID(rawValue: 0), TypeVarID(rawValue: 1))
    }

    func testConstraintOperandEquality() {
        let intType = types.make(.primitive(.int, .nonNull))
        let op1 = ConstraintOperand.type(intType)
        let op2 = ConstraintOperand.type(intType)
        let op3 = ConstraintOperand.variable(TypeVarID(rawValue: 1))
        let op4 = ConstraintOperand.variable(TypeVarID(rawValue: 1))

        XCTAssertEqual(op1, op2)
        XCTAssertEqual(op3, op4)
        XCTAssertNotEqual(op1, op3)
    }

    func testSolveSupertypeConstraintViolationReportsFailure() {
        let intType = types.make(.primitive(.int, .nonNull))
        let boolType = types.make(.primitive(.boolean, .nonNull))
        let t0 = TypeVarID(rawValue: 90)

        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .supertype, left: .type(intType), right: .type(boolType))
        ]
        let solution = solver.solve(vars: [t0], constraints: constraints, typeSystem: types)

        XCTAssertFalse(solution.isSuccess)
    }

    func testFirstRelevantBlameRangeFindsRightSideVariable() {
        let intType = types.make(.primitive(.int, .nonNull))
        let boolType = types.make(.primitive(.boolean, .nonNull))
        let t0 = TypeVarID(rawValue: 100)
        let blame = makeRange(start: 20, end: 25)

        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .subtype, left: .type(intType), right: .variable(t0), blameRange: blame),
            VariableConstraint(kind: .subtype, left: .variable(t0), right: .type(boolType))
        ]
        let solution = solver.solve(vars: [t0], constraints: constraints, typeSystem: types)

        XCTAssertFalse(solution.isSuccess)
        XCTAssertEqual(solution.failure?.primaryRange, blame)
    }

    func testSolveUnresolvedVariableInConstraintProducesFailure() throws {
        let intType = types.make(.primitive(.int, .nonNull))
        let t0 = TypeVarID(rawValue: 60)
        let tUnknown = TypeVarID(rawValue: 99)
        let blame = makeRange(start: 1, end: 2)

        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .equal, left: .variable(t0), right: .type(intType)),
            VariableConstraint(kind: .subtype, left: .variable(tUnknown), right: .type(intType), blameRange: blame)
        ]
        let solution = solver.solve(vars: [t0], constraints: constraints, typeSystem: types)

        XCTAssertFalse(solution.isSuccess)
        let failure = try XCTUnwrap(solution.failure)
        XCTAssertTrue(failure.message.contains("unresolved variables"))
    }

    func testSolveConflictingBoundsWithMixedTypeTypeConstraints() {
        let intType = types.make(.primitive(.int, .nonNull))
        let boolType = types.make(.primitive(.boolean, .nonNull))
        let anyType = types.anyType
        let t0 = TypeVarID(rawValue: 95)
        let blame = makeRange(start: 5, end: 8)

        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .subtype, left: .type(intType), right: .type(anyType)),
            VariableConstraint(kind: .supertype, left: .variable(t0), right: .type(intType), blameRange: blame),
            VariableConstraint(kind: .subtype, left: .variable(t0), right: .type(boolType), blameRange: blame)
        ]
        let solution = solver.solve(vars: [t0], constraints: constraints, typeSystem: types)

        XCTAssertFalse(solution.isSuccess)
    }

    func testSolveCandidateErrorTypeFromUpperBoundsOnly() throws {
        let t0 = TypeVarID(rawValue: 101)
        let blame = makeRange(start: 0, end: 1)

        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .subtype, left: .variable(t0), right: .type(types.errorType), blameRange: blame)
        ]
        let solution = solver.solve(vars: [t0], constraints: constraints, typeSystem: types)

        XCTAssertFalse(solution.isSuccess)
        let failure = try XCTUnwrap(solution.failure)
        XCTAssertTrue(failure.message.contains("Failed to infer"))
    }

    func testTypeVarIDInvalidIsMinusOne() {
        XCTAssertEqual(TypeVarID.invalid.rawValue, -1)
        XCTAssertEqual(TypeVarID().rawValue, -1)
    }

    func testSolveRenderBoundsIncludesEmptyMarker() throws {
        let t0 = TypeVarID(rawValue: 110)
        let blame = makeRange(start: 60, end: 65)

        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .subtype, left: .variable(t0), right: .type(types.errorType), blameRange: blame)
        ]
        let solution = solver.solve(vars: [t0], constraints: constraints, typeSystem: types)
        XCTAssertFalse(solution.isSuccess)
        let failure = try XCTUnwrap(solution.failure)
        XCTAssertTrue(failure.message.contains("lower=[-]"))
    }

    func testSolveHandlesUnregisteredVariablesInConstraints() {
        let intType = types.make(.primitive(.int, .nonNull))
        let t0 = TypeVarID(rawValue: 0)
        let t1 = TypeVarID(rawValue: 1) // not in vars
        let t2 = TypeVarID(rawValue: 2) // not in vars
        let t3 = TypeVarID(rawValue: 3) // not in vars

        // Only t0 is in vars; t1, t2, t3 are unregistered.
        // This exercises dictionary default-value closures in the solver:
        //   - lowerBounds default for t1 (type-to-variable constraint)
        //   - upperBounds default for t1 (var-to-var propagation read)
        //   - upperBounds default for t1 (var-to-var propagation write from t2)
        //   - lowerBounds default for t2 (var-to-var propagation write from t1)
        //   - lowerBounds default for t3 (var-to-var propagation read)
        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .subtype, left: .type(intType), right: .variable(t1)),
            VariableConstraint(kind: .subtype, left: .variable(t0), right: .variable(t1)),
            VariableConstraint(kind: .subtype, left: .variable(t2), right: .type(intType)),
            VariableConstraint(kind: .subtype, left: .variable(t1), right: .variable(t2)),
            VariableConstraint(kind: .subtype, left: .variable(t3), right: .variable(t0)),
        ]
        let solution = solver.solve(vars: [t0], constraints: constraints, typeSystem: types)
        // t1 is not in vars so resolve returns nil → failure
        XCTAssertFalse(solution.isSuccess)
        XCTAssertNotNil(solution.failure)
    }

    func testSolvePostSubstitutionEqualConstraintViolationMessage() {
        let intType = types.make(.primitive(.int, .nonNull))
        let boolType = types.make(.primitive(.boolean, .nonNull))
        let t0 = TypeVarID(rawValue: 120)
        let blame = makeRange(start: 70, end: 75)

        // t0 gets bound to intType via lower bound, then equal constraint
        // forces post-substitution check: intType == boolType fails
        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .subtype, left: .type(intType), right: .variable(t0)),
            VariableConstraint(kind: .equal, left: .variable(t0), right: .type(boolType), blameRange: blame)
        ]
        let solution = solver.solve(vars: [t0], constraints: constraints, typeSystem: types)
        XCTAssertFalse(solution.isSuccess)
        XCTAssertNotNil(solution.failure)
    }
}
