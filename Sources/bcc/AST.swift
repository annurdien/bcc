import Foundation

private func indent(_ s: String) -> String {
    return s.split(separator: "\n").map { "  " + $0 }.joined(separator: "\n")
}

// Program(function_definition)
struct Program: Equatable, CustomStringConvertible {
    let function: FunctionDeclaration

    var description: String {
        "Program(\n\(indent(function.description))\n)"
    }
}

// function_definition = Function(identifier name, block_item* body)
struct FunctionDeclaration: Equatable, CustomStringConvertible {
    let name: String
    let body: [BlockItem]

    var description: String {
        let nameLine = "name=\"\(name)\","
        let bodyDesc = body.map { $0.description }.joined(separator: "\n")
        let bodyLine = "body=[\n\(indent(bodyDesc))\n]"
        
        return "Function(\n\(indent(nameLine))\n\(indent(bodyLine))\n)"
    }
}

// block_item = Statement | Declaration
enum BlockItem: Equatable, CustomStringConvertible {
    case statement(Statement)
    case declaration(Declaration)

    var description: String {
        switch self {
        case .statement(let s): return s.description
        case .declaration(let d): return d.description
        }
    }
}

// declaration = Declare(identifier name, exp? initializer)
struct Declaration: Equatable, CustomStringConvertible {
    let name: String
    let initializer: Expression?

    var description: String {
        if let initExp = initializer {
            return "Declare(\(name), init: \(initExp.description))"
        }
        return "Declare(\(name))"
    }
}

// statement = Return(exp) | Expression(exp) | If(cond, then, else?) | Compound(block_item*) | While(cond, body) | DoWhile(body, cond) | For(init, cond, post, body) | Break | Continue
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
        case .return(let exp):
            return "Return(\n\(indent(exp.description))\n)"
        case .expression(let exp):
            return "ExprStmt(\n\(indent(exp.description))\n)"
        case .if(let cond, let thenStmt, let elseStmt):
            var desc = "If(\n\(indent("cond: " + cond.description))\n\(indent("then: " + thenStmt.description))\n"
            if let elseStmt = elseStmt {
                desc += indent("else: " + elseStmt.description) + "\n"
            }
            desc += ")"
            return desc
        case .compound(let items):
            let desc = items.map { $0.description }.joined(separator: "\n")
            return "Block {\n\(indent(desc))\n}"
        case .while(let cond, let body):
             return "While(\n\(indent("cond: " + cond.description))\n\(indent("body: " + body.description))\n)"
        case .doWhile(let body, let cond):
             return "DoWhile(\n\(indent("body: " + body.description))\n\(indent("cond: " + cond.description))\n)"
        case .for(let initClause, let cond, let post, let body):
            var parts = ["init: \(initClause.description)"]
            if let c = cond { parts.append("cond: \(c.description)") }
            if let p = post { parts.append("post: \(p.description)") }
            parts.append("body: \(body.description)")
            return "For(\n\(indent(parts.joined(separator: "\n")))\n)"
        case .break:
            return "Break"
        case .continue:
            return "Continue"
        }
    }
}

// For loop initialization can be a declaration or an expression or empty
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

// unary_operator = Complement | Negate | Not
enum UnaryOperator: Equatable, CustomStringConvertible {
    case negate
    case complement
    case logicalNot

    var description: String {
        switch self {
            case .negate: return "Negate"
            case .complement: return "Complement"
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

// exp = Constant(int) | Unary(unary_operator, exp) | Binary(binary_operator, exp, exp) | Var(identifier) | Assignment(identifier, exp)
indirect enum Expression: Equatable, CustomStringConvertible {
    case constant(Int)
    case unary(UnaryOperator, Expression)
    case binary(BinaryOperator, Expression, Expression)
    case variable(String)
    case assignment(name: String, expression: Expression)
    case conditional(condition: Expression, thenExpr: Expression, elseExpr: Expression)

    var description: String {
        switch self {
        case .constant(let value):
            return "Constant(\(value))"
        case .conditional(let cond, let thenExpr, let elseExpr):
            return "Conditional(\n\(indent(cond.description)) ?\n\(indent(thenExpr.description)) :\n\(indent(elseExpr.description))\n)"
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
        }
    }
}
