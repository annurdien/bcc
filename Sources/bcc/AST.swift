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

// exp = Constant(int)
enum Expression: Equatable, CustomStringConvertible {
    case constant(Int)

    var description: String {
        switch self {
        case .constant(let value):
            return "Constant(\(value))"
        }
    }
}
