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

// function_definition = Function(identifier name, statement body)
struct FunctionDeclaration: Equatable, CustomStringConvertible {
    let name: String
    let body: Statement

    var description: String {
        let nameLine = "name=\"\(name)\","
        let bodyLine = "body=\(body.description)"
        
        return "Function(\n\(indent(nameLine))\n\(indent(bodyLine))\n)"
    }
}

// statement = Return(exp)
enum Statement: Equatable, CustomStringConvertible {
    case `return`(Expression)

    var description: String {
        switch self {
        case .return(let exp):
            return "Return(\n\(indent(exp.description))\n)"
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

// exp = Constant(int) | Unary(unary_operator, exp) | Binary(binary_operator, exp, exp)
indirect enum Expression: Equatable, CustomStringConvertible {
    case constant(Int)
    case unary(UnaryOperator, Expression)
    case binary(BinaryOperator, Expression, Expression)

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
        }
    }
}
