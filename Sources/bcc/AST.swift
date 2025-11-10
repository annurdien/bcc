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

// unary_operator = Complement | Negate
enum UnaryOperator: Equatable, CustomStringConvertible {
    case negate
    case complement

    var description: String {
        switch self {
            case .negate: return "Negate"
            case .complement: return "Complement"
        }
    }
}

// exp = Constant(int) | Unary(unary_operator, exp)
indirect enum Expression: Equatable, CustomStringConvertible {
    case constant(Int)
    case unary(UnaryOperator, Expression)

    var description: String {
        switch self {
        case .constant(let value):
            return "Constant(\(value))"
        case .unary(let op, let exp):
            let opLine = "op: \(op.description),"
            let expLine = "exp:\n\(indent(exp.description))"
            return "Unary(\n\(indent(opLine))\n\(indent(expLine))\n)"
        }
    }
}
