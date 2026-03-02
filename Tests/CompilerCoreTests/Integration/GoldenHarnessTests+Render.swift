@testable import CompilerCore
import Foundation

// MARK: - Render helpers extracted from GoldenHarnessTests to reduce type/file body length.

extension GoldenHarnessTests {
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func renderExpr(_ expr: Expr, interner: StringInterner) -> String {
        switch expr {
        case let .intLiteral(value, _):
            return "int(\(value))"
        case let .longLiteral(value, _):
            return "long(\(value))"
        case let .floatLiteral(value, _):
            return "float(\(value))"
        case let .doubleLiteral(value, _):
            return "double(\(value))"
        case let .charLiteral(value, _):
            return "char(\(value))"
        case let .boolLiteral(value, _):
            return "bool(\(value ? "true" : "false"))"
        case let .stringLiteral(text, _):
            return "string(\(interner.resolve(text)))"
        case let .nameRef(name, _):
            return "name(\(interner.resolve(name)))"
        case let .forExpr(loopVariable, iterable, body, label, _):
            let variable = loopVariable.map { interner.resolve($0) } ?? "_"
            let labelStr = label.map { " label=\(interner.resolve($0))" } ?? ""
            return "for var=\(variable) iterable=e\(iterable.rawValue) body=e\(body.rawValue)\(labelStr)"
        case let .whileExpr(condition, body, label, _):
            let labelStr = label.map { " label=\(interner.resolve($0))" } ?? ""
            return "while cond=e\(condition.rawValue) body=e\(body.rawValue)\(labelStr)"
        case let .doWhileExpr(body, condition, label, _):
            let labelStr = label.map { " label=\(interner.resolve($0))" } ?? ""
            return "doWhile body=e\(body.rawValue) cond=e\(condition.rawValue)\(labelStr)"
        case let .breakExpr(label, _):
            let labelStr = label.map { "@\(interner.resolve($0))" } ?? ""
            return "break\(labelStr)"
        case let .continueExpr(label, _):
            let labelStr = label.map { "@\(interner.resolve($0))" } ?? ""
            return "continue\(labelStr)"
        case let .localDecl(name, isMutable, typeAnnotation, initializer, _):
            let typeStr = typeAnnotation.map { "t\($0.rawValue)" } ?? "_"
            let initStr = initializer.map { "e\($0.rawValue)" } ?? "_"
            return "localDecl \(interner.resolve(name)) mutable=\(isMutable ? 1 : 0) type=\(typeStr) init=\(initStr)"
        case let .localAssign(name, value, _):
            return "localAssign \(interner.resolve(name)) value=e\(value.rawValue)"
        case let .indexedAssign(receiver, indices, value, _):
            let idxStr = indices.map { "e\($0.rawValue)" }.joined(separator: ",")
            return "indexedAssign receiver=e\(receiver.rawValue) indices=[\(idxStr)] value=e\(value.rawValue)"
        case let .call(callee, _, args, _):
            let renderedArgs = args.map { arg in
                let label = arg.label.map { interner.resolve($0) } ?? "_"
                return "\(label):e\(arg.expr.rawValue)"
            }.joined(separator: ",")
            return "call callee=e\(callee.rawValue) args=[\(renderedArgs)]"
        case let .memberCall(receiver, callee, _, args, _):
            let renderedArgs = args.map { arg in
                let label = arg.label.map { interner.resolve($0) } ?? "_"
                return "\(label):e\(arg.expr.rawValue)"
            }.joined(separator: ",")
            return "memberCall recv=e\(receiver.rawValue) callee=\(interner.resolve(callee)) args=[\(renderedArgs)]"
        case let .indexedAccess(receiver, indices, _):
            let idxStr = indices.map { "e\($0.rawValue)" }.joined(separator: ",")
            return "indexedAccess receiver=e\(receiver.rawValue) indices=[\(idxStr)]"
        case let .binary(oper, lhs, rhs, _):
            return "binary(\(oper)) lhs=e\(lhs.rawValue) rhs=e\(rhs.rawValue)"
        case let .whenExpr(subject, branches, elseExpr, _):
            return renderWhenExpr(
                subject: subject, branches: branches,
                elseExpr: elseExpr, interner: interner
            )
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
        case let .unaryExpr(oper, operand, _):
            return "unary(\(oper)) operand=e\(operand.rawValue)"
        case let .isCheck(expr, type, negated, _):
            return "isCheck\(negated ? "!" : "") expr=e\(expr.rawValue) type=t\(type.rawValue)"
        case let .asCast(expr, type, isSafe, _):
            return "asCast\(isSafe ? "?" : "") expr=e\(expr.rawValue) type=t\(type.rawValue)"
        case let .nullAssert(expr, _):
            return "nullAssert expr=e\(expr.rawValue)"
        case let .safeMemberCall(receiver, callee, _, args, _):
            let renderedArgs = args.map { arg in
                let label = arg.label.map { interner.resolve($0) } ?? "_"
                return "\(label):e\(arg.expr.rawValue)"
            }.joined(separator: ",")
            return "safeMemberCall recv=e\(receiver.rawValue) callee=\(interner.resolve(callee)) args=[\(renderedArgs)]"
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
        case let .objectLiteral(superTypes, _):
            let renderedSuperTypes = superTypes.map { "t\($0.rawValue)" }.joined(separator: ",")
            return "objectLiteral supers=[\(renderedSuperTypes)]"
        case let .callableRef(receiver, member, _):
            let renderedReceiver = receiver.map { "e\($0.rawValue)" } ?? "_"
            return "callableRef recv=\(renderedReceiver) member=\(interner.resolve(member))"
        case let .localFunDecl(name, valueParams, returnType, body, _):
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
            return "localFunDecl \(interner.resolve(name)) params=[\(params)] returnType=\(retStr) body=\(bodyStr)"
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

    private func renderWhenExpr(
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
            return "\(conditions)->e\(branch.body.rawValue)"
        }.joined(separator: ",")
        let renderedElse = elseExpr.map { "e\($0.rawValue)" } ?? "_"
        let renderedSubject = subject.map { "e\($0.rawValue)" } ?? "_"
        return "when subject=\(renderedSubject) branches=[\(renderedBranches)] else=\(renderedElse)"
    }

    func renderFunctionSignature(
        _ signature: FunctionSignature,
        types: TypeSystem
    ) -> String {
        let receiver = signature.receiverType.map { types.renderType($0) } ?? "_"
        let parameters = signature.parameterTypes.map { types.renderType($0) }.joined(separator: ",")
        let returnType = types.renderType(signature.returnType)
        let defaults = signature.valueParameterHasDefaultValues.map { $0 ? "1" : "0" }.joined(separator: ",")
        let vararg = signature.valueParameterIsVararg.map { $0 ? "1" : "0" }.joined(separator: ",")
        var result = "recv=\(receiver) params=[\(parameters)] ret=\(returnType)"
        result += " suspend=\(signature.isSuspend ? 1 : 0) defaults=[\(defaults)] vararg=[\(vararg)]"
        let hasBounds = !signature.typeParameterUpperBounds.isEmpty
            && signature.typeParameterUpperBounds.contains(where: { $0 != nil })
        if hasBounds {
            let bounds = signature.typeParameterUpperBounds.map { bound in
                bound.map { types.renderType($0) } ?? "_"
            }.joined(separator: ",")
            result += " bounds=[\(bounds)]"
        }
        return result
    }

    // swiftlint:disable:next cyclomatic_complexity
    func renderSymbolFlags(_ flags: SymbolFlags) -> String {
        if flags.isEmpty {
            return "_"
        }
        var names: [String] = []
        if flags.contains(.suspendFunction) { names.append("suspendFunction") }
        if flags.contains(.inlineFunction) { names.append("inlineFunction") }
        if flags.contains(.mutable) { names.append("mutable") }
        if flags.contains(.synthetic) { names.append("synthetic") }
        if flags.contains(.static) { names.append("static") }
        if flags.contains(.sealedType) { names.append("sealedType") }
        if flags.contains(.dataType) { names.append("dataType") }
        if flags.contains(.innerClass) { names.append("innerClass") }
        if flags.contains(.valueType) { names.append("valueType") }
        if flags.contains(.operatorFunction) { names.append("operatorFunction") }
        if flags.contains(.constValue) { names.append("constValue") }
        if flags.contains(.abstractType) { names.append("abstractType") }
        if flags.contains(.openType) { names.append("openType") }
        if flags.contains(.overrideMember) { names.append("overrideMember") }
        if flags.contains(.finalMember) { names.append("finalMember") }
        return names.joined(separator: "|")
    }

    func renderFQName(
        _ fqName: [InternedString],
        interner: StringInterner
    ) -> String {
        if fqName.isEmpty {
            return "_"
        }
        return fqName.map { interner.resolve($0) }.joined(separator: ".")
    }
}
