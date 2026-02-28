public enum TypeArgRef: Equatable {
    case invariant(TypeRefID)
    case out(TypeRefID)
    case `in`(TypeRefID)
    case star
}

public enum TypeRef: Equatable {
    case named(path: [InternedString], args: [TypeArgRef], nullable: Bool)
    case functionType(params: [TypeRefID], returnType: TypeRefID, isSuspend: Bool, nullable: Bool)
    case intersection(parts: [TypeRefID])
}

public enum BinaryOp: Equatable {
    case add
    case subtract
    case multiply
    case divide
    case modulo
    case equal
    case notEqual
    case lessThan
    case lessOrEqual
    case greaterThan
    case greaterOrEqual
    case logicalAnd
    case logicalOr
    case elvis
    case rangeTo
    case rangeUntil
    case downTo
    case step
    case bitwiseAnd
    case bitwiseOr
    case bitwiseXor
    case shl
    case shr
    case ushr

    /// The Kotlin operator function name for this binary operator (e.g. "plus", "compareTo").
    public var kotlinFunctionName: String {
        switch self {
        case .add:          return "plus"
        case .subtract:     return "minus"
        case .multiply:     return "times"
        case .divide:       return "div"
        case .modulo:       return "rem"
        case .equal:        return "equals"
        case .notEqual:     return "equals"
        case .lessThan, .lessOrEqual, .greaterThan, .greaterOrEqual: return "compareTo"
        case .logicalAnd:   return "and"
        case .logicalOr:    return "or"
        case .elvis:        return "elvis"
        case .rangeTo:      return "rangeTo"
        case .rangeUntil:   return "rangeUntil"
        case .downTo:       return "downTo"
        case .step:         return "step"
        case .bitwiseAnd:   return "and"
        case .bitwiseOr:    return "or"
        case .bitwiseXor:   return "xor"
        case .shl:          return "shl"
        case .shr:          return "shr"
        case .ushr:         return "ushr"
        }
    }
}

public enum UnaryOp: Equatable {
    case not
    case unaryPlus
    case unaryMinus
}

public enum CompoundAssignOp: Equatable {
    case plusAssign
    case minusAssign
    case timesAssign
    case divAssign
    case modAssign
}

public struct WhenBranch: Equatable {
    public let conditions: [ExprID]
    public let body: ExprID
    public let range: SourceRange

    public init(conditions: [ExprID], body: ExprID, range: SourceRange) {
        self.conditions = conditions
        self.body = body
        self.range = range
    }

    /// Convenience: single-condition branch (backward compat helper).
    public init(condition: ExprID?, body: ExprID, range: SourceRange) {
        self.conditions = condition.map { [$0] } ?? []
        self.body = body
        self.range = range
    }

    /// Backward-compat accessor: returns the first condition, or nil for else branches.
    public var condition: ExprID? {
        conditions.first
    }
}

public struct CallArgument: Equatable {
    public let label: InternedString?
    public let isSpread: Bool
    public let expr: ExprID

    public init(label: InternedString? = nil, isSpread: Bool = false, expr: ExprID) {
        self.label = label
        self.isSpread = isSpread
        self.expr = expr
    }
}

public struct CatchClause: Equatable {
    public let paramName: InternedString?
    public let paramTypeName: InternedString?
    public let body: ExprID
    public let range: SourceRange

    public init(paramName: InternedString? = nil, paramTypeName: InternedString? = nil, body: ExprID, range: SourceRange) {
        self.paramName = paramName
        self.paramTypeName = paramTypeName
        self.body = body
        self.range = range
    }
}

public enum StringTemplatePart: Equatable {
    case literal(InternedString)
    case expression(ExprID)
}

public enum Expr: Equatable {
    case intLiteral(Int64, SourceRange)
    case longLiteral(Int64, SourceRange)
    case floatLiteral(Double, SourceRange)
    case doubleLiteral(Double, SourceRange)
    case charLiteral(UInt32, SourceRange)
    case boolLiteral(Bool, SourceRange)
    case stringLiteral(InternedString, SourceRange)
    case stringTemplate(parts: [StringTemplatePart], range: SourceRange)
    case nameRef(InternedString, SourceRange)
    case forExpr(loopVariable: InternedString?, iterable: ExprID, body: ExprID, label: InternedString? = nil, range: SourceRange)
    case whileExpr(condition: ExprID, body: ExprID, label: InternedString? = nil, range: SourceRange)
    case doWhileExpr(body: ExprID, condition: ExprID, label: InternedString? = nil, range: SourceRange)
    case breakExpr(label: InternedString? = nil, range: SourceRange)
    case continueExpr(label: InternedString? = nil, range: SourceRange)
    case localDecl(name: InternedString, isMutable: Bool, typeAnnotation: TypeRefID?, initializer: ExprID?, range: SourceRange)
    case localAssign(name: InternedString, value: ExprID, range: SourceRange)
    case memberAssign(receiver: ExprID, callee: InternedString, value: ExprID, range: SourceRange)
    case indexedAssign(receiver: ExprID, indices: [ExprID], value: ExprID, range: SourceRange)
    case call(callee: ExprID, typeArgs: [TypeRefID], args: [CallArgument], range: SourceRange)
    case memberCall(receiver: ExprID, callee: InternedString, typeArgs: [TypeRefID], args: [CallArgument], range: SourceRange)
    case indexedAccess(receiver: ExprID, indices: [ExprID], range: SourceRange)
    case binary(op: BinaryOp, lhs: ExprID, rhs: ExprID, range: SourceRange)
    case whenExpr(subject: ExprID?, branches: [WhenBranch], elseExpr: ExprID?, range: SourceRange)
    case returnExpr(value: ExprID?, label: InternedString? = nil, range: SourceRange)
    case ifExpr(condition: ExprID, thenExpr: ExprID, elseExpr: ExprID?, range: SourceRange)
    case tryExpr(body: ExprID, catchClauses: [CatchClause], finallyExpr: ExprID?, range: SourceRange)
    case unaryExpr(op: UnaryOp, operand: ExprID, range: SourceRange)
    case isCheck(expr: ExprID, type: TypeRefID, negated: Bool, range: SourceRange)
    case asCast(expr: ExprID, type: TypeRefID, isSafe: Bool, range: SourceRange)
    case nullAssert(expr: ExprID, range: SourceRange)
    case safeMemberCall(receiver: ExprID, callee: InternedString, typeArgs: [TypeRefID], args: [CallArgument], range: SourceRange)
    case compoundAssign(op: CompoundAssignOp, name: InternedString, value: ExprID, range: SourceRange)
    case indexedCompoundAssign(op: CompoundAssignOp, receiver: ExprID, indices: [ExprID], value: ExprID, range: SourceRange)
    case throwExpr(value: ExprID, range: SourceRange)
    case lambdaLiteral(params: [InternedString], body: ExprID, label: InternedString? = nil, range: SourceRange)
    case objectLiteral(superTypes: [TypeRefID], range: SourceRange)
    case callableRef(receiver: ExprID?, member: InternedString, range: SourceRange)
    case localFunDecl(name: InternedString, valueParams: [ValueParamDecl], returnType: TypeRefID?, body: FunctionBody, range: SourceRange)
    case blockExpr(statements: [ExprID], trailingExpr: ExprID?, range: SourceRange)
    case superRef(SourceRange)
    case thisRef(label: InternedString?, SourceRange)
    case inExpr(lhs: ExprID, rhs: ExprID, range: SourceRange)
    case notInExpr(lhs: ExprID, rhs: ExprID, range: SourceRange)
    case destructuringDecl(names: [InternedString?], isMutable: Bool, initializer: ExprID, range: SourceRange)
    case forDestructuringExpr(names: [InternedString?], iterable: ExprID, body: ExprID, range: SourceRange)
}
