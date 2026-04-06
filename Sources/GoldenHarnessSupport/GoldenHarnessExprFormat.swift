@testable import CompilerCore
import Foundation

enum GoldenHarnessExprFormat {
    static func renderExpr(_ expr: Expr, interner: StringInterner) -> String {
        switch expr {
        // Literals
        case let .intLiteral(value, _):
            return renderLiteral("int", value)
        case let .longLiteral(value, _):
            return renderLiteral("long", value)
        case let .uintLiteral(value, _):
            return renderLiteral("uint", value)
        case let .ulongLiteral(value, _):
            return renderLiteral("ulong", value)
        case let .floatLiteral(value, _):
            return renderLiteral("float", value)
        case let .doubleLiteral(value, _):
            return renderLiteral("double", value)
        case let .charLiteral(value, _):
            return renderLiteral("char", value)
        case let .boolLiteral(value, _):
            return "bool(\(value ? "true" : "false"))"
        case let .stringLiteral(text, _):
            return "string(\(interner.resolve(text)))"
        case let .nameRef(name, _):
            return "name(\(interner.resolve(name)))"
            
        // Control flow
        case let .forExpr(loopVariable, iterable, body, label, _):
            return renderLoopExpr("for", loopVariable, iterable, body, label, interner, 
                variableKey: "var", iterableKey: "iterable", bodyKey: "body")
        case let .whileExpr(condition, body, label, _):
            return renderWhileLoop(condition, body, label, interner)
        case let .doWhileExpr(body, condition, label, _):
            return renderDoWhileLoop(body, condition, label, interner)
        case let .breakExpr(label, _):
            return renderJumpExpr("break", label, interner)
        case let .continueExpr(label, _):
            return renderJumpExpr("continue", label, interner)
            
        // Declarations and assignments
        case let .localDecl(name, isMutable, typeAnnotation, initializer, isDelegated, _):
            return renderLocalDecl(name, isMutable, typeAnnotation.map { TypeID(rawValue: $0.rawValue) }, initializer, isDelegated, interner)
        case let .localAssign(name, value, _):
            return "localAssign \(interner.resolve(name)) value=e\(value.rawValue)"
        case let .indexedAssign(receiver, indices, value, _):
            let idxStr = indices.map { "e\($0.rawValue)" }.joined(separator: ",")
            return "indexedAssign receiver=e\(receiver.rawValue) indices=[\(idxStr)] value=e\(value.rawValue)"
            
        // Calls and member access
        case let .call(callee, _, args, _):
            return renderCall("call", callee: callee, args: args, interner: interner)
        case let .memberCall(receiver, callee, _, args, _):
            return renderMemberCall("memberCall", receiver: receiver, callee: callee, args: args, interner: interner)
        case let .safeMemberCall(receiver, callee, _, args, _):
            return renderMemberCall("safeMemberCall", receiver: receiver, callee: callee, args: args, interner: interner)
        case let .indexedAccess(receiver, indices, _):
            let idxStr = indices.map { "e\($0.rawValue)" }.joined(separator: ",")
            return "indexedAccess receiver=e\(receiver.rawValue) indices=[\(idxStr)]"
            
        // Binary and unary operations
        case let .binary(oper, lhs, rhs, _):
            return "binary(\(oper)) lhs=e\(lhs.rawValue) rhs=e\(rhs.rawValue)"
        case let .unaryExpr(oper, operand, _):
            return "unary(\(oper)) operand=e\(operand.rawValue)"
            
        // Type operations
        case let .isCheck(expr, type, negated, _):
            return "isCheck\(negated ? "!" : "") expr=e\(expr.rawValue) type=t\(type.rawValue)"
        case let .asCast(expr, type, isSafe, _):
            return "asCast\(isSafe ? "?" : "") expr=e\(expr.rawValue) type=t\(type.rawValue)"
        case let .nullAssert(expr, _):
            return "nullAssert expr=e\(expr.rawValue)"
            
        // Control expressions
        case let .whenExpr(subject, branches, elseExpr, _):
            return renderWhenExpr(subject: subject, branches: branches, elseExpr: elseExpr, interner: interner)
        case let .returnExpr(value, label, _):
            let renderedValue = value.map { "e\($0.rawValue)" } ?? "_"
            let labelStr = label.map { "@\(interner.resolve($0))" } ?? ""
            return "return\(labelStr) value=\(renderedValue)"
        case let .ifExpr(condition, thenExpr, elseExpr, _):
            let renderedElse = elseExpr.map { "e\($0.rawValue)" } ?? "_"
            return "if cond=e\(condition.rawValue) then=e\(thenExpr.rawValue) else=\(renderedElse)"
        case let .tryExpr(body, catchClauses, finallyExpr, _):
            let catches = catchClauses.map { "e\($0.body.rawValue)" }.joined(separator: ",")
            let renderedFinally = finallyExpr.map { "e\($0.rawValue)" } ?? "_"
            return "try body=e\(body.rawValue) catches=[\(catches)] finally=\(renderedFinally)"
        case let .compoundAssign(oper, name, value, _):
            return "compoundAssign(\(oper)) name=\(interner.resolve(name)) value=e\(value.rawValue)"
        case let .indexedCompoundAssign(oper, receiver, indices, value, _):
            let idxStr = indices.map { "e\($0.rawValue)" }.joined(separator: ",")
            let recv = "receiver=e\(receiver.rawValue)"
            return "indexedCompoundAssign(\(oper)) \(recv) indices=[\(idxStr)] value=e\(value.rawValue)"
        case let .stringTemplate(parts, _):
            let rendered = parts.map { part -> String in
                switch part {
                case let .literal(text):
                    return "lit(\(interner.resolve(text)))"
                case let .expression(exprID):
                    return "expr(e\(exprID.rawValue))"
                }
            }.joined(separator: ",")
            return "stringTemplate[\(rendered)]"
        case let .throwExpr(value, _):
            return "throw value=e\(value.rawValue)"
        case let .lambdaLiteral(params, body, label, _):
            let renderedParams = params.map { interner.resolve($0) }.joined(separator: ",")
            let labelStr = label.map { " label=\(interner.resolve($0))" } ?? ""
            return "lambda params=[\(renderedParams)] body=e\(body.rawValue)\(labelStr)"
        case let .objectLiteral(superTypes, _, _):
            let renderedSuperTypes = superTypes.map { "t\($0.rawValue)" }.joined(separator: ",")
            return "objectLiteral supers=[\(renderedSuperTypes)]"
        case let .callableRef(receiver, member, _):
            let renderedReceiver = receiver.map { "e\($0.rawValue)" } ?? "_"
            return "callableRef recv=\(renderedReceiver) member=\(interner.resolve(member))"
        case let .localFunDecl(name, valueParams, returnType, body, isSuspend, _):
            let params = valueParams.map { interner.resolve($0.name) }.joined(separator: ",")
            let bodyStr = switch body {
            case let .block(exprs, _):
                "block[\(exprs.map { "e\($0.rawValue)" }.joined(separator: ","))]"
            case let .expr(exprID, _):
                "e\(exprID.rawValue)"
            case .unit:
                "unit"
            }
            let retStr = returnType.map { "t\($0.rawValue)" } ?? "nil"
            return "localFunDecl \(interner.resolve(name)) suspend=\(isSuspend ? 1 : 0) params=[\(params)] returnType=\(retStr) body=\(bodyStr)"
        case let .blockExpr(statements, trailingExpr, _):
            let stmts = statements.map { "e\($0.rawValue)" }.joined(separator: ",")
            let trailing = trailingExpr.map { "e\($0.rawValue)" } ?? "_"
            return "blockExpr stmts=[\(stmts)] trailing=\(trailing)"
        case let .superRef(qualifier, _):
            if let qualifier {
                return "super<\(interner.resolve(qualifier))>"
            }
            return "super"
        case let .thisRef(label, _):
            if let label {
                return "this@\(interner.resolve(label))"
            }
            return "this"
        case let .inExpr(lhs, rhs, _):
            return "inExpr lhs=e\(lhs.rawValue) rhs=e\(rhs.rawValue)"
        case let .notInExpr(lhs, rhs, _):
            return "notInExpr lhs=e\(lhs.rawValue) rhs=e\(rhs.rawValue)"
        case let .destructuringDecl(names, isMutable, initializer, _):
            let renderedNames = names.map { $0.map { interner.resolve($0) } ?? "_" }
                .joined(separator: ",")
            let mutStr = "mutable=\(isMutable ? 1 : 0)"
            return "destructuringDecl names=[\(renderedNames)] \(mutStr) init=e\(initializer.rawValue)"
        case let .forDestructuringExpr(names, iterable, body, _):
            let renderedNames = names.map { $0.map { interner.resolve($0) } ?? "_" }
                .joined(separator: ",")
            return "forDestructuring names=[\(renderedNames)] iterable=e\(iterable.rawValue) body=e\(body.rawValue)"
        case let .memberAssign(receiver, callee, value, _):
            return "memberAssign recv=e\(receiver.rawValue) callee=\(interner.resolve(callee)) value=e\(value.rawValue)"
        }
    }
    
    // MARK: - Helper methods
    
    private static func renderLiteral<T>(_ type: String, _ value: T) -> String {
        return "\(type)(\(value))"
    }
    
    private static func renderLoopExpr(
        _ loopType: String,
        _ loopVariable: InternedString?,
        _ iterable: ExprID,
        _ body: ExprID,
        _ label: InternedString?,
        _ interner: StringInterner,
        variableKey: String,
        iterableKey: String,
        bodyKey: String
    ) -> String {
        let variable = loopVariable.map { interner.resolve($0) } ?? "_"
        let labelStr = label.map { " label=\(interner.resolve($0))" } ?? ""
        return "\(loopType) \(variableKey)=\(variable) \(iterableKey)=e\(iterable.rawValue) \(bodyKey)=e\(body.rawValue)\(labelStr)"
    }
    
    private static func renderWhileLoop(_ condition: ExprID, _ body: ExprID, _ label: InternedString?, _ interner: StringInterner) -> String {
        let labelStr = label.map { " label=\(interner.resolve($0))" } ?? ""
        return "while cond=e\(condition.rawValue) body=e\(body.rawValue)\(labelStr)"
    }
    
    private static func renderDoWhileLoop(_ body: ExprID, _ condition: ExprID, _ label: InternedString?, _ interner: StringInterner) -> String {
        let labelStr = label.map { " label=\(interner.resolve($0))" } ?? ""
        return "doWhile body=e\(body.rawValue) cond=e\(condition.rawValue)\(labelStr)"
    }
    
    private static func renderJumpExpr(_ jumpType: String, _ label: InternedString?, _ interner: StringInterner) -> String {
        let labelStr = label.map { "@\(interner.resolve($0))" } ?? ""
        return "\(jumpType)\(labelStr)"
    }
    
    private static func renderLocalDecl(
        _ name: InternedString,
        _ isMutable: Bool,
        _ typeAnnotation: TypeID?,
        _ initializer: ExprID?,
        _ isDelegated: Bool,
        _ interner: StringInterner
    ) -> String {
        let typeStr = typeAnnotation.map { "t\($0.rawValue)" } ?? "_"
        let initStr = initializer.map { "e\($0.rawValue)" } ?? "_"
        let delegatedStr = isDelegated ? " delegated=1" : ""
        return "localDecl \(interner.resolve(name)) mutable=\(isMutable ? 1 : 0) type=\(typeStr) init=\(initStr)\(delegatedStr)"
    }
    
    private static func renderCall(_ callType: String, callee: ExprID, args: [CallArgument], interner: StringInterner) -> String {
        let renderedArgs = args.map { arg in
            let label = arg.label.map { interner.resolve($0) } ?? "_"
            return "\(label):e\(arg.expr.rawValue)"
        }.joined(separator: ",")
        return "\(callType) callee=e\(callee.rawValue) args=[\(renderedArgs)]"
    }
    
    private static func renderMemberCall(
        _ callType: String,
        receiver: ExprID,
        callee: InternedString,
        args: [CallArgument],
        interner: StringInterner
    ) -> String {
        let renderedArgs = args.map { arg in
            let label = arg.label.map { interner.resolve($0) } ?? "_"
            return "\(label):e\(arg.expr.rawValue)"
        }.joined(separator: ",")
        return "\(callType) recv=e\(receiver.rawValue) callee=\(interner.resolve(callee)) args=[\(renderedArgs)]"
    }

    private static func renderWhenExpr(
        subject: ExprID?,
        branches: [WhenBranch],
        elseExpr: ExprID?,
        interner _: StringInterner
    ) -> String {
        let renderedBranches = branches.map { branch in
            let conditions: String = if branch.conditions.isEmpty {
                "else"
            } else {
                branch.conditions.map { "e\($0.rawValue)" }.joined(separator: ",")
            }
            let guardPart = branch.guard_.map { " if e\($0.rawValue)" } ?? ""
            return "\(conditions)\(guardPart)->e\(branch.body.rawValue)"
        }.joined(separator: ",")
        let renderedElse = elseExpr.map { "e\($0.rawValue)" } ?? "_"
        let renderedSubject = subject.map { "e\($0.rawValue)" } ?? "_"
        return "when subject=\(renderedSubject) branches=[\(renderedBranches)] else=\(renderedElse)"
    }
}
