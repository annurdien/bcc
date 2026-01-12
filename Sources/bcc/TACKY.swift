import Foundation

private func indent(_ s: String) -> String {
    return s.split(separator: "\n").map { "  " + $0 }.joined(separator: "\n")
}

struct TackyProgram: Equatable, CustomStringConvertible {
    let functions: [TackyFunction]
    
    var description: String {
        let funcsDesc = functions.map { $0.description }.joined(separator: "\n\n")
        return "TackyProgram(\n\(indent(funcsDesc))\n)"
    }
}

struct TackyFunction: Equatable, CustomStringConvertible {
    let name: String
    let parameters: [String]
    let body: [TackyInstruction]

    var description: String {
        let bodyDesc = body.map { $0.description }.joined(separator: "\n")
        return "TackyFunction(name: \(name), params: \(parameters)) {\n\(indent(bodyDesc))\n}"
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

enum TackyBinaryOperator: Equatable, CustomStringConvertible {
    case add
    case subtract
    case multiply
    case divide
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
        case .equal: return "Equal"
        case .notEqual: return "NotEqual"
        case .lessThan: return "LessThan"
        case .lessThanOrEqual: return "LessThanOrEqual"
        case .greaterThan: return "GreaterThan"
        case .greaterThanOrEqual: return "GreaterThanOrEqual"
        }
    }
}

enum TackyInstruction: Equatable, CustomStringConvertible {
    case `return`(TackyValue)
    case unary(op: TackyUnaryOperator, src: TackyValue, dest: TackyValue)
    case binary(op: TackyBinaryOperator, lhs: TackyValue, rhs: TackyValue, dest: TackyValue)
    case copy(src: TackyValue, dest: TackyValue)
    case jump(target: String)
    case jumpIfZero(condition: TackyValue, target: String)
    case jumpIfNotZero(condition: TackyValue, target: String)
    case label(String)
    case call(name: String, args: [TackyValue], dest: TackyValue)

    var description: String {
        switch self {
        case .return(let val):
            return "Return(\(val.description))"
        case .unary(let op, let src, let dest):
            return "\(dest.description) = \(op.description) \(src.description)"
        case .binary(let op, let lhs, let rhs, let dest):
            return "\(dest.description) = \(op.description) \(lhs.description), \(rhs.description)"
        case .copy(let src, let dest):
            return "\(dest.description) = Copy \(src.description)"
        case .jump(let target):
            return "Jump(\(target))"
        case .jumpIfZero(let cond, let target):
            return "JumpIfZero(\(cond.description), \(target))"
        case .jumpIfNotZero(let cond, let target):
            return "JumpIfNotZero(\(cond.description), \(target))"
        case .label(let name):
            return "Label(\(name))"
        case .call(let name, let args, let dest):
            let argsDesc = args.map { $0.description }.joined(separator: ", ")
            return "\(dest.description) = Call \(name)(\(argsDesc))"
        }
    }
}

