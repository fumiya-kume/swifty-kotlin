import XCTest
@testable import CompilerCore

final class ConstraintSolverTests: XCTestCase {
    private func makeDeps() -> (solver: ConstraintSolver, types: TypeSystem) {
        (ConstraintSolver(), TypeSystem())
    }

    func testSolveInitializesSubstitutionForAllVariables() {
        let (solver, types) = makeDeps()
        let vars = [TypeVarID(rawValue: 1), TypeVarID(rawValue: 2)]
        let constraints: [Constraint] = []

        let solution = solver.solve(vars: vars, constraints: constraints, typeSystem: types)

        XCTAssertTrue(solution.isSuccess)
        XCTAssertNil(solution.failure)
        XCTAssertEqual(solution.substitution[vars[0]], types.errorType)
        XCTAssertEqual(solution.substitution[vars[1]], types.errorType)
    }

    func testSolveSupportsSubtypeEqualAndSupertypeConstraints() {
        let (solver, types) = makeDeps()
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
        let (solver, types) = makeDeps()
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
        let (solver, types) = makeDeps()
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
        let (solver, types) = makeDeps()
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
        let (solver, types) = makeDeps()
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
        // With corrected intersection subtype rules (P5-97), the solver now detects
        // the conflict at the bound-checking phase rather than post-substitution.
        XCTAssertTrue(failure.message.contains("not satisfied") || failure.message.contains("not a subtype"))
    }

    func testSolveSupertypeConstraintKindSatisfaction() {
        let (solver, types) = makeDeps()
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
        let (solver, types) = makeDeps()
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
        let (solver, types) = makeDeps()
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
        let (solver, types) = makeDeps()
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
        let (solver, types) = makeDeps()
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
        let (solver, types) = makeDeps()
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
        let (solver, types) = makeDeps()
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
        let (solver, types) = makeDeps()
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
        let (solver, types) = makeDeps()
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
        let (solver, types) = makeDeps()
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
        let (solver, types) = makeDeps()
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
        let (solver, types) = makeDeps()
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
        let (solver, types) = makeDeps()
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
        let types = TypeSystem()
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
        let (solver, types) = makeDeps()
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
        let (solver, types) = makeDeps()
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
        let (solver, types) = makeDeps()
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
        let (solver, types) = makeDeps()
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
        let (solver, types) = makeDeps()
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
        let (solver, types) = makeDeps()
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
        let (solver, types) = makeDeps()
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
        let (solver, types) = makeDeps()
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

    // MARK: - Empty constraints with multiple variables

    func testSolveEmptyConstraintsWithManyVariablesAllGetErrorType() {
        let (solver, types) = makeDeps()
        let vars = (0..<5).map { TypeVarID(rawValue: Int32(200 + $0)) }

        let solution = solver.solve(
            vars: vars,
            constraints: [] as [VariableConstraint],
            typeSystem: types
        )

        XCTAssertTrue(solution.isSuccess)
        XCTAssertNil(solution.failure)
        for v in vars {
            XCTAssertEqual(solution.substitution[v], types.errorType)
        }
    }

    func testSolveEmptyConstraintsWithSingleVariableGetsErrorType() {
        let (solver, types) = makeDeps()
        let t0 = TypeVarID(rawValue: 210)

        let solution = solver.solve(
            vars: [t0],
            constraints: [] as [VariableConstraint],
            typeSystem: types
        )

        XCTAssertTrue(solution.isSuccess)
        XCTAssertEqual(solution.substitution[t0], types.errorType)
    }

    func testSolveEmptyConstraintsEmptyVarsSucceeds() {
        let (solver, types) = makeDeps()

        let solution = solver.solve(
            vars: [],
            constraints: [] as [VariableConstraint],
            typeSystem: types
        )

        XCTAssertTrue(solution.isSuccess)
        XCTAssertTrue(solution.substitution.isEmpty)
    }

    // MARK: - Circular variable constraints

    func testSolveCircularTwoVariablesWithSharedBound() {
        let (solver, types) = makeDeps()
        let intType = types.make(.primitive(.int, .nonNull))
        let t0 = TypeVarID(rawValue: 220)
        let t1 = TypeVarID(rawValue: 221)

        // t0 <: t1, t1 <: t0 forms a cycle; both get intType from lower bound
        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .subtype, left: .type(intType), right: .variable(t0)),
            VariableConstraint(kind: .subtype, left: .variable(t0), right: .variable(t1)),
            VariableConstraint(kind: .subtype, left: .variable(t1), right: .variable(t0))
        ]
        let solution = solver.solve(vars: [t0, t1], constraints: constraints, typeSystem: types)

        XCTAssertTrue(solution.isSuccess)
        XCTAssertEqual(solution.substitution[t0], intType)
        XCTAssertEqual(solution.substitution[t1], intType)
    }

    func testSolveCircularThreeVariablesWithSharedBound() {
        let (solver, types) = makeDeps()
        let intType = types.make(.primitive(.int, .nonNull))
        let anyType = types.anyType
        let t0 = TypeVarID(rawValue: 230)
        let t1 = TypeVarID(rawValue: 231)
        let t2 = TypeVarID(rawValue: 232)

        // circular: t0 <: t1 <: t2 <: t0, with intType lower on t0 and anyType upper on t2
        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .subtype, left: .type(intType), right: .variable(t0)),
            VariableConstraint(kind: .subtype, left: .variable(t0), right: .variable(t1)),
            VariableConstraint(kind: .subtype, left: .variable(t1), right: .variable(t2)),
            VariableConstraint(kind: .subtype, left: .variable(t2), right: .variable(t0)),
            VariableConstraint(kind: .subtype, left: .variable(t2), right: .type(anyType))
        ]
        let solution = solver.solve(vars: [t0, t1, t2], constraints: constraints, typeSystem: types)

        XCTAssertTrue(solution.isSuccess)
        XCTAssertEqual(solution.substitution[t0], intType)
        XCTAssertEqual(solution.substitution[t1], intType)
        XCTAssertEqual(solution.substitution[t2], intType)
    }

    func testSolveCircularVariablesNoBoundsAllGetErrorType() {
        let (solver, types) = makeDeps()
        let t0 = TypeVarID(rawValue: 240)
        let t1 = TypeVarID(rawValue: 241)

        // circular with no concrete bounds → both remain empty → errorType
        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .subtype, left: .variable(t0), right: .variable(t1)),
            VariableConstraint(kind: .subtype, left: .variable(t1), right: .variable(t0))
        ]
        let solution = solver.solve(vars: [t0, t1], constraints: constraints, typeSystem: types)

        XCTAssertTrue(solution.isSuccess)
        XCTAssertEqual(solution.substitution[t0], types.errorType)
        XCTAssertEqual(solution.substitution[t1], types.errorType)
    }

    // MARK: - Mixed constraint types (subtype, equal, supertype)

    func testSolveMixedConstraintKindsOnSingleVariable() {
        let (solver, types) = makeDeps()
        let intType = types.make(.primitive(.int, .nonNull))
        let anyType = types.anyType
        let t0 = TypeVarID(rawValue: 250)

        // equal binds both lower and upper to intType,
        // subtype adds upper bound anyType,
        // supertype adds lower bound intType
        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .equal, left: .variable(t0), right: .type(intType)),
            VariableConstraint(kind: .subtype, left: .variable(t0), right: .type(anyType)),
            VariableConstraint(kind: .supertype, left: .variable(t0), right: .type(intType))
        ]
        let solution = solver.solve(vars: [t0], constraints: constraints, typeSystem: types)

        XCTAssertTrue(solution.isSuccess)
        XCTAssertEqual(solution.substitution[t0], intType)
    }

    func testSolveMixedConstraintKindsAcrossMultipleVariables() {
        let (solver, types) = makeDeps()
        let intType = types.make(.primitive(.int, .nonNull))
        let stringType = types.make(.primitive(.string, .nonNull))
        let anyType = types.anyType
        let t0 = TypeVarID(rawValue: 260)
        let t1 = TypeVarID(rawValue: 261)
        let t2 = TypeVarID(rawValue: 262)

        let constraints: [VariableConstraint] = [
            // t0 == intType
            VariableConstraint(kind: .equal, left: .variable(t0), right: .type(intType)),
            // t1 :> stringType (lower bound = stringType)
            VariableConstraint(kind: .supertype, left: .variable(t1), right: .type(stringType)),
            // t1 <: anyType (upper bound = anyType)
            VariableConstraint(kind: .subtype, left: .variable(t1), right: .type(anyType)),
            // t2 <: t1 (variable-to-variable subtype)
            VariableConstraint(kind: .subtype, left: .variable(t2), right: .variable(t1)),
            // t2 :> stringType (lower bound on t2)
            VariableConstraint(kind: .supertype, left: .variable(t2), right: .type(stringType))
        ]
        let solution = solver.solve(vars: [t0, t1, t2], constraints: constraints, typeSystem: types)

        XCTAssertTrue(solution.isSuccess)
        XCTAssertEqual(solution.substitution[t0], intType)
        XCTAssertEqual(solution.substitution[t1], stringType)
        XCTAssertEqual(solution.substitution[t2], stringType)
    }

    func testSolveMixedConstraintKindsWithTypeTypeConflictFails() {
        let (solver, types) = makeDeps()
        let intType = types.make(.primitive(.int, .nonNull))
        let boolType = types.make(.primitive(.boolean, .nonNull))
        let t0 = TypeVarID(rawValue: 270)

        // type-type equal constraint fails: Int == Bool
        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .equal, left: .type(intType), right: .type(boolType)),
            VariableConstraint(kind: .supertype, left: .variable(t0), right: .type(intType))
        ]
        let solution = solver.solve(vars: [t0], constraints: constraints, typeSystem: types)

        XCTAssertFalse(solution.isSuccess)
        XCTAssertEqual(solution.substitution[t0], types.errorType)
    }

    func testSolveSupertypeTypeTypeConstraintSatisfied() {
        let (solver, types) = makeDeps()
        let intType = types.make(.primitive(.int, .nonNull))
        let anyType = types.anyType
        let t0 = TypeVarID(rawValue: 275)

        // supertype type-type: Any :> Int → normalized to Int <: Any (true)
        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .supertype, left: .type(anyType), right: .type(intType)),
            VariableConstraint(kind: .equal, left: .variable(t0), right: .type(intType))
        ]
        let solution = solver.solve(vars: [t0], constraints: constraints, typeSystem: types)

        XCTAssertTrue(solution.isSuccess)
        XCTAssertEqual(solution.substitution[t0], intType)
    }

    // MARK: - Multiple failure scenario combinations

    func testSolveMultipleConflictingBoundsReportsFirstFailure() throws {
        let (solver, types) = makeDeps()
        let intType = types.make(.primitive(.int, .nonNull))
        let boolType = types.make(.primitive(.boolean, .nonNull))
        let stringType = types.make(.primitive(.string, .nonNull))
        let t0 = TypeVarID(rawValue: 280)
        let t1 = TypeVarID(rawValue: 281)
        let blame0 = makeRange(start: 100, end: 105)
        let blame1 = makeRange(start: 110, end: 115)

        // t0 has conflicting bounds: lower=Int, upper=Bool
        // t1 has conflicting bounds: lower=String, upper=Int
        // Solver should fail on first variable it encounters
        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .supertype, left: .variable(t0), right: .type(intType), blameRange: blame0),
            VariableConstraint(kind: .subtype, left: .variable(t0), right: .type(boolType), blameRange: blame0),
            VariableConstraint(kind: .supertype, left: .variable(t1), right: .type(stringType), blameRange: blame1),
            VariableConstraint(kind: .subtype, left: .variable(t1), right: .type(intType), blameRange: blame1)
        ]
        let solution = solver.solve(vars: [t0, t1], constraints: constraints, typeSystem: types)

        XCTAssertFalse(solution.isSuccess)
        let failure = try XCTUnwrap(solution.failure)
        XCTAssertEqual(failure.code, "KSWIFTK-TYPE-0001")
        XCTAssertTrue(failure.message.contains("Conflicting bounds"))
        XCTAssertEqual(failure.primaryRange, blame0)
    }

    func testSolveTypeTypeFailurePlusVariableConflict(){
        let (solver, types) = makeDeps()
        let intType = types.make(.primitive(.int, .nonNull))
        let boolType = types.make(.primitive(.boolean, .nonNull))
        let t0 = TypeVarID(rawValue: 290)
        let blame = makeRange(start: 120, end: 125)

        // type-type constraint fails first: Bool <: Int (false)
        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .subtype, left: .type(boolType), right: .type(intType), blameRange: blame),
            VariableConstraint(kind: .equal, left: .variable(t0), right: .type(intType))
        ]
        let solution = solver.solve(vars: [t0], constraints: constraints, typeSystem: types)

        XCTAssertFalse(solution.isSuccess)
        XCTAssertEqual(solution.substitution[t0], types.errorType)
    }

    func testSolvePostSubstitutionSupertypeViolation() throws {
        let (solver, types) = makeDeps()
        let intType = types.make(.primitive(.int, .nonNull))
        let boolType = types.make(.primitive(.boolean, .nonNull))
        let t0 = TypeVarID(rawValue: 295)
        let blame = makeRange(start: 130, end: 135)

        // equal normalizes to: t0 <: intType (upper) + intType <: t0 (lower)
        // supertype normalizes to: boolType <: t0 (lower)
        // lowers=[intType, boolType], uppers=[intType]
        // lub([intType, boolType]) = anyType, not subtype of intType → conflicting bounds
        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .equal, left: .variable(t0), right: .type(intType)),
            VariableConstraint(kind: .supertype, left: .variable(t0), right: .type(boolType), blameRange: blame)
        ]
        let solution = solver.solve(vars: [t0], constraints: constraints, typeSystem: types)

        XCTAssertFalse(solution.isSuccess)
        let failure = try XCTUnwrap(solution.failure)
        XCTAssertTrue(failure.message.contains("Conflicting bounds"))
    }

    func testSolveAllVariablesGetErrorTypeOnEarlyFailure() {
        let (solver, types) = makeDeps()
        let intType = types.make(.primitive(.int, .nonNull))
        let boolType = types.make(.primitive(.boolean, .nonNull))
        let t0 = TypeVarID(rawValue: 300)
        let t1 = TypeVarID(rawValue: 301)
        let t2 = TypeVarID(rawValue: 302)

        // type-type constraint fails immediately; all vars should be errorType
        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .subtype, left: .type(boolType), right: .type(intType)),
            VariableConstraint(kind: .equal, left: .variable(t0), right: .type(intType)),
            VariableConstraint(kind: .equal, left: .variable(t1), right: .type(intType)),
            VariableConstraint(kind: .equal, left: .variable(t2), right: .type(intType))
        ]
        let solution = solver.solve(vars: [t0, t1, t2], constraints: constraints, typeSystem: types)

        XCTAssertFalse(solution.isSuccess)
        XCTAssertEqual(solution.substitution[t0], types.errorType)
        XCTAssertEqual(solution.substitution[t1], types.errorType)
        XCTAssertEqual(solution.substitution[t2], types.errorType)
    }

    // MARK: - Complex variable dependencies

    func testSolveDiamondDependencyPattern() {
        let (solver, types) = makeDeps()
        let intType = types.make(.primitive(.int, .nonNull))
        let anyType = types.anyType
        let t0 = TypeVarID(rawValue: 310)
        let t1 = TypeVarID(rawValue: 311)
        let t2 = TypeVarID(rawValue: 312)
        let t3 = TypeVarID(rawValue: 313)

        // Diamond: t0 → t1 → t3, t0 → t2 → t3
        // intType feeds in at t0, anyType caps at t3
        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .subtype, left: .type(intType), right: .variable(t0)),
            VariableConstraint(kind: .subtype, left: .variable(t0), right: .variable(t1)),
            VariableConstraint(kind: .subtype, left: .variable(t0), right: .variable(t2)),
            VariableConstraint(kind: .subtype, left: .variable(t1), right: .variable(t3)),
            VariableConstraint(kind: .subtype, left: .variable(t2), right: .variable(t3)),
            VariableConstraint(kind: .subtype, left: .variable(t3), right: .type(anyType))
        ]
        let solution = solver.solve(
            vars: [t0, t1, t2, t3],
            constraints: constraints,
            typeSystem: types
        )

        XCTAssertTrue(solution.isSuccess)
        XCTAssertEqual(solution.substitution[t0], intType)
        // t1, t2 propagated intType lower from t0
        XCTAssertEqual(solution.substitution[t1], intType)
        XCTAssertEqual(solution.substitution[t2], intType)
        XCTAssertEqual(solution.substitution[t3], intType)
    }

    func testSolveLongChainDependency() {
        let (solver, types) = makeDeps()
        let intType = types.make(.primitive(.int, .nonNull))
        let anyType = types.anyType
        let t0 = TypeVarID(rawValue: 320)
        let t1 = TypeVarID(rawValue: 321)
        let t2 = TypeVarID(rawValue: 322)
        let t3 = TypeVarID(rawValue: 323)
        let t4 = TypeVarID(rawValue: 324)

        // Chain: intType → t0 → t1 → t2 → t3 → t4 → anyType
        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .subtype, left: .type(intType), right: .variable(t0)),
            VariableConstraint(kind: .subtype, left: .variable(t0), right: .variable(t1)),
            VariableConstraint(kind: .subtype, left: .variable(t1), right: .variable(t2)),
            VariableConstraint(kind: .subtype, left: .variable(t2), right: .variable(t3)),
            VariableConstraint(kind: .subtype, left: .variable(t3), right: .variable(t4)),
            VariableConstraint(kind: .subtype, left: .variable(t4), right: .type(anyType))
        ]
        let solution = solver.solve(
            vars: [t0, t1, t2, t3, t4],
            constraints: constraints,
            typeSystem: types
        )

        XCTAssertTrue(solution.isSuccess)
        for v in [t0, t1, t2, t3, t4] {
            XCTAssertEqual(solution.substitution[v], intType)
        }
    }

    func testSolveMultipleIndependentVariableGroups() {
        let (solver, types) = makeDeps()
        let intType = types.make(.primitive(.int, .nonNull))
        let stringType = types.make(.primitive(.string, .nonNull))
        let t0 = TypeVarID(rawValue: 330)
        let t1 = TypeVarID(rawValue: 331)
        let t2 = TypeVarID(rawValue: 332)
        let t3 = TypeVarID(rawValue: 333)

        // Group 1: t0 → t1 with intType
        // Group 2: t2 → t3 with stringType
        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .subtype, left: .type(intType), right: .variable(t0)),
            VariableConstraint(kind: .subtype, left: .variable(t0), right: .variable(t1)),
            VariableConstraint(kind: .subtype, left: .type(stringType), right: .variable(t2)),
            VariableConstraint(kind: .subtype, left: .variable(t2), right: .variable(t3))
        ]
        let solution = solver.solve(
            vars: [t0, t1, t2, t3],
            constraints: constraints,
            typeSystem: types
        )

        XCTAssertTrue(solution.isSuccess)
        XCTAssertEqual(solution.substitution[t0], intType)
        XCTAssertEqual(solution.substitution[t1], intType)
        XCTAssertEqual(solution.substitution[t2], stringType)
        XCTAssertEqual(solution.substitution[t3], stringType)
    }

    func testSolveVariableDependencyWithEqualAndSubtype() {
        let (solver, types) = makeDeps()
        let intType = types.make(.primitive(.int, .nonNull))
        let anyType = types.anyType
        let t0 = TypeVarID(rawValue: 340)
        let t1 = TypeVarID(rawValue: 341)

        // t0 == intType, t0 <: t1, t1 <: anyType
        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .equal, left: .variable(t0), right: .type(intType)),
            VariableConstraint(kind: .subtype, left: .variable(t0), right: .variable(t1)),
            VariableConstraint(kind: .subtype, left: .variable(t1), right: .type(anyType))
        ]
        let solution = solver.solve(vars: [t0, t1], constraints: constraints, typeSystem: types)

        XCTAssertTrue(solution.isSuccess)
        XCTAssertEqual(solution.substitution[t0], intType)
        XCTAssertEqual(solution.substitution[t1], intType)
    }

    // MARK: - Coverage: relationOperator (private helper exposed as internal for testability)

    func testRelationOperatorReturnsCorrectSymbols() {
        let solver = ConstraintSolver()
        XCTAssertEqual(solver.relationOperator(for: .subtype), "<:")
        XCTAssertEqual(solver.relationOperator(for: .equal), "==")
        XCTAssertEqual(solver.relationOperator(for: .supertype), ":>")
    }

    // MARK: - Coverage: firstRelevantBlameRange returns nil

    func testSolveBlameRangeIsNilWhenVariableOnlyOnRightOfVarVarConstraint() throws {
        // When a variable only appears on the RIGHT side of a variable-to-variable
        // constraint, the firstRelevantBlameRange helper cannot find it because
        // the first switch case (.variable(let lhs), _) matches but lhs != target.
        // This exercises the `return nil` path in firstRelevantBlameRange.
        let (solver, types) = makeDeps()
        let t0 = TypeVarID(rawValue: 400)
        let t1 = TypeVarID(rawValue: 401)

        // errorType propagates from t0 → t1 through var-var relation.
        // t1 is processed first (listed first in vars), so firstRelevantBlameRange
        // searches for t1 but only finds t0 on the left of the var-var constraint.
        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .subtype, left: .type(types.errorType), right: .variable(t0)),
            VariableConstraint(kind: .subtype, left: .variable(t0), right: .variable(t1))
        ]
        let solution = solver.solve(vars: [t1, t0], constraints: constraints, typeSystem: types)

        XCTAssertFalse(solution.isSuccess)
        let failure = try XCTUnwrap(solution.failure)
        XCTAssertTrue(failure.message.contains("Failed to infer"))
        // blameRange should be nil since firstRelevantBlameRange couldn't find t1
        XCTAssertNil(failure.primaryRange)
    }

    func testSolveDiamondWithConflictingLeafBoundsFails() throws {
        let (solver, types) = makeDeps()
        let intType = types.make(.primitive(.int, .nonNull))
        let boolType = types.make(.primitive(.boolean, .nonNull))
        let t0 = TypeVarID(rawValue: 350)
        let t1 = TypeVarID(rawValue: 351)
        let t2 = TypeVarID(rawValue: 352)
        let blame = makeRange(start: 200, end: 205)

        // t0 → t1, t0 → t2; t1 upper-bounded by boolType, t2 lower-bounded by intType
        // t0 gets propagated lower intType from t2 and upper boolType from t1 → conflict
        let constraints: [VariableConstraint] = [
            VariableConstraint(kind: .subtype, left: .variable(t0), right: .variable(t1)),
            VariableConstraint(kind: .subtype, left: .variable(t2), right: .variable(t0)),
            VariableConstraint(kind: .subtype, left: .variable(t1), right: .type(boolType), blameRange: blame),
            VariableConstraint(kind: .subtype, left: .type(intType), right: .variable(t2))
        ]
        let solution = solver.solve(vars: [t0, t1, t2], constraints: constraints, typeSystem: types)

        XCTAssertFalse(solution.isSuccess)
        let failure = try XCTUnwrap(solution.failure)
        XCTAssertEqual(failure.code, "KSWIFTK-TYPE-0001")
    }
}
