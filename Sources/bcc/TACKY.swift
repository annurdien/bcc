import Foundation

private func indent(_ s: String) -> String {
    return s.split(separator: "\n").map { "  " + $0 }.joined(separator: "\n")
}

struct TackyProgram: Equatable, CustomStringConvertible {
    let function: TackyFunction
    
    var description: String {
        "TackyProgram(\n\(indent(function.description))\n)"
    }
}

struct TackyFunction: Equatable, CustomStringConvertible {
    let name: String
    let body: [TackyInstruction]

    var description: String {
        let bodyDesc = body.map { $0.description }.joined(separator: "\n")
        return "TackyFunction(name: \(name)) {\n\(indent(bodyDesc))\n}"
    }
}

enum TackyValue: Equatable, CustomStringConvertible {
    case constant(Int)
    case variable(String) // "tmp.0", "tmp.1"
    
    var description: String {
        switch self {
        case .constant(let val): return "Constant(\(val))"
        case .variable(let name): return "Var(\"\(name)\")"
        }
    }
}

enum TackyUnaryOperator: Equatable, CustomStringConvertible {
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

enum TackyInstruction: Equatable, CustomStringConvertible {
    case `return`(TackyValue)
    case unary(op: TackyUnaryOperator, src: TackyValue, dest: TackyValue)

        var description: String {
        switch self {
        case .return(let val):
            return "Return(\(val.description))"
        case .unary(let op, let src, let dest):
            return "\(dest.description) = \(op.description) \(src.description)"
        }
    }
}

