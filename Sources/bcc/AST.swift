private func indent(_ s: String) -> String {
    return s.split(separator: "\n").map { "  " + $0 }.joined(separator: "\n")
}

enum CType: Equatable, CustomStringConvertible {
    case int
    case long
    case unsignedInt
    case unsignedLong
    
    var description: String {
        switch self {
        case .int: return "int"
        case .long: return "long"
        case .unsignedInt: return "unsigned int"
        case .unsignedLong: return "unsigned long"
        }
    }
}

enum TopLevelItem: Equatable, CustomStringConvertible {
    case function(FunctionDeclaration)
    case variable(Declaration)
    
    var description: String {
        switch self {
        case .function(let f): return f.description
        case .variable(let d): return d.description
        }
    }
}

struct Program: Equatable, CustomStringConvertible {
    let items: [TopLevelItem]
    
    init(items: [TopLevelItem]) {
        self.items = items
    }

    // Computed property for backward compatibility
    var functions: [FunctionDeclaration] {
        return items.compactMap { 
            if case .function(let f) = $0 { return f }
            return nil
        }
    }
    
    var function: FunctionDeclaration {
        return functions.last!
    }

    var description: String {
        let itemsDesc = items.map { $0.description }.joined(separator: "\n")
        return "Program(\n\(indent(itemsDesc))\n)"
    }
}

struct FunctionDeclaration: Equatable, CustomStringConvertible {
    let name: String
    let returnType: CType 
    let parameters: [String] 
    let parameterTypes: [CType] // Added parallel array to minimize impact, though tuple suggests better design. 
    // Actually, keeping separate arrays runs risk of desync. 
    // Let's use parameters: [String] for names, and just add parameterTypes.
    // Or just change parameters to [(CType, String)]?
    // Let's go with just adding parameterTypes for now to be safe with existing code iterating parameters.
    // Wait, if I add `parameterTypes`, I must init it.
    let body: Statement

    var description: String {
        var paramsDesc = ""
        for i in 0..<parameters.count {
            if i > 0 { paramsDesc += ", " }
            let type = i < parameterTypes.count ? parameterTypes[i] : .int
            paramsDesc += "\(type) \(parameters[i])"
        }
        return "Function(name: \"\(name)\", return: \(returnType), params: [\(paramsDesc)], body:\n\(indent(body.description))\n)"
    }
}

struct Declaration: Equatable, CustomStringConvertible {
    let name: String
    let type: CType
    let initializer: Expression?
    let isStatic: Bool

    var description: String {
        let storage = isStatic ? "Static " : ""
        if let initExpr = initializer {
            return "\(storage)\(type) \(name) = \(initExpr);"
        } else {
            return "\(storage)\(type) \(name);"
        }
    }
}

indirect enum BlockItem: Equatable, CustomStringConvertible {
    case statement(Statement)
    case declaration(Declaration)
    
    var description: String {
        switch self {
        case .statement(let s): return "Stmt(\n\(indent(s.description)))"
        case .declaration(let d): return "Decl(\n\(indent(d.description)))"
        }
    }
}

indirect enum Statement: Equatable, CustomStringConvertible {
    case `return`(Expression)
    case expression(Expression)
    case `if`(condition: Expression, then: Statement, `else`: Statement?)
    case compound([BlockItem])
    case `while`(condition: Expression, body: Statement)
    case doWhile(body: Statement, condition: Expression)
    case `for`(initial: ForInit, condition: Expression?, post: Expression?, body: Statement)
    case `break`
    case `continue`

    var description: String {
        switch self {
        case .return(let expr):
            return "Return(\n\(indent(expr.description))\n)"
        case .expression(let expr):
            return "ExprStmt(\n\(indent(expr.description))\n)"
        case .if(let cond, let thenStmt, let elseStmt):
            var desc = "If(\n\(indent(cond.description)),\n\(indent(thenStmt.description))"
            if let e = elseStmt {
                desc += ",\n\(indent(e.description))"
            }
            desc += "\n)"
            return desc
        case .compound(let items):
            let itemDesc = items.map { $0.description }.joined(separator: "\n")
            return "Compound(\n\(indent(itemDesc))\n)"
        case .while(let cond, let body):
            return "While(\n\(indent(cond.description)),\n\(indent(body.description))\n)"
        case .doWhile(let body, let cond):
            return "DoWhile(\n\(indent(body.description)),\n\(indent(cond.description))\n)"
        case .for(let initClause, let cond, let post, let body):
            let cDesc = cond?.description ?? "Core.Empty"
            let pDesc = post?.description ?? "Core.Empty"
            return "For(\n\(indent(initClause.description)),\n\(indent(cDesc)),\n\(indent(pDesc)),\n\(indent(body.description))\n)"
        case .break: return "Break"
        case .continue: return "Continue"
        }
    }
}

enum ForInit: Equatable, CustomStringConvertible {
    case declaration(Declaration)
    case expression(Expression?)
    
    var description: String {
        switch self {
        case .declaration(let d): return d.description
        case .expression(let e): return e?.description ?? "Empty"
        }
    }
}

enum UnaryOperator: Equatable, CustomStringConvertible {
    case negate
    case complement
    case logicalNot

    var description: String {
        switch self {
        case .negate: return "Negate"
        case .complement: return "BitwiseNot"
        case .logicalNot: return "LogicalNot"
        }
    }
}

enum BinaryOperator: Equatable, CustomStringConvertible {
    case add
    case subtract
    case multiply
    case divide
    case logicalAnd
    case logicalOr
    case equal
    case notEqual
    case lessThan
    case lessThanOrEqual
    case greaterThan
    case greaterThanOrEqual

    var description: String {
        switch self {
        case .add: return "Add"
        case .subtract: return "Subtract"
        case .multiply: return "Multiply"
        case .divide: return "Divide"
        case .logicalAnd: return "And"
        case .logicalOr: return "Or"
        case .equal: return "Equal"
        case .notEqual: return "NotEqual"
        case .lessThan: return "LessThan"
        case .lessThanOrEqual: return "LessThanOrEqual"
        case .greaterThan: return "GreaterThan"
        case .greaterThanOrEqual: return "GreaterThanOrEqual"
        }
    }
}

indirect enum Expression: Equatable, CustomStringConvertible {
    case constant(Int)
    case unary(UnaryOperator, Expression)
    case binary(BinaryOperator, Expression, Expression)
    case variable(String)
    case assignment(name: String, expression: Expression)
    case conditional(condition: Expression, thenExpr: Expression, elseExpr: Expression)
    case functionCall(name: String, arguments: [Expression])

    var description: String {
        switch self {
        case .constant(let value):
            return "Constant(\(value))"
        case .unary(let op, let exp):
            let opLine = "op: \(op.description),"
            let expLine = "exp:\n\(indent(exp.description))"
            return "Unary(\n\(indent(opLine))\n\(indent(expLine))\n)"
        case .binary(let op, let lhs, let rhs):
            let opLine = "op: \(op.description),"
            let lhsLine = "lhs:\n\(indent(lhs.description))"
            let rhsLine = "rhs:\n\(indent(rhs.description))"
            return "Binary(\n\(indent(opLine))\n\(indent(lhsLine))\n\(indent(rhsLine))\n)"
        case .variable(let name):
            return "Var(\(name))"
        case .assignment(let name, let exp):
             return "Assign(name: \(name), val:\n\(indent(exp.description)))"
        case .conditional(let cond, let thenExpr, let elseExpr):
            return "Conditional(\n\(indent(cond.description)) ?\n\(indent(thenExpr.description)) :\n\(indent(elseExpr.description))\n)"
        case .functionCall(let name, let args):
            let argsDesc = args.map { $0.description }.joined(separator: ", ")
            return "Call(name: \(name), args: [\(argsDesc)])"
        }
    }
}
