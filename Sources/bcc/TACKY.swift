import Foundation

private func indent(_ s: String) -> String {
    return s.split(separator: "\n").map { "  " + $0 }.joined(separator: "\n")
}

enum TackyType: Equatable, CustomStringConvertible {
    case int
    case long
    case uint
    case ulong
    
    var size: Int {
        switch self {
        case .int, .uint: return 4
        case .long, .ulong: return 8
        }
    }
    
    var description: String {
        switch self {
        case .int: return "Int"
        case .long: return "Long"
        case .uint: return "UInt"
        case .ulong: return "ULong"
        }
    }
}

struct TackyProgram: Equatable, CustomStringConvertible {
    let globals: [TackyGlobal]
    let functions: [TackyFunction]
    
    // helper for old code
    var function: TackyFunction {
        return functions.last!
    }
    
    var description: String {
        let globalsDesc = globals.map { $0.description }.joined(separator: "\n")
        let funcsDesc = functions.map { $0.description }.joined(separator: "\n\n")
        return "TackyProgram(\nGlobals:\n\(indent(globalsDesc))\n\nFunctions:\n\(indent(funcsDesc))\n)"
    }
}

struct TackyGlobal: Equatable, CustomStringConvertible {
    let name: String
    let type: TackyType
    let initialValue: Int? // nil for uninitialized (BSS)
    let isStatic: Bool
    
    var description: String {
        let visibility = isStatic ? "Static" : "Global"
        if let val = initialValue {
            return "\(visibility)(\(type), name: \(name), init: \(val))"
        } else {
            return "\(visibility)(\(type), name: \(name), uninit)"
        }
    }
}

struct TackyFunction: Equatable, CustomStringConvertible {
    let name: String
    let parameters: [String]
    let variableTypes: [String: TackyType] // Map name -> type
    let body: [TackyInstruction]

    var description: String {
        let bodyDesc = body.map { $0.description }.joined(separator: "\n")
        // Just print body
        return "TackyFunction(name: \(name), params: \(parameters)) {\n\(indent(bodyDesc))\n}"
    }
}

enum TackyValue: Equatable, CustomStringConvertible {
    case constant(Int)
    case variable(String) // Local variable or Temporary
    case global(String)   // Global variable
    
    var description: String {
        switch self {
        case .constant(let val): return "Constant(\(val))"
        case .variable(let name): return "Var(\"\(name)\")"
        case .global(let name): return "Global(\"\(name)\")"
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
    case divideU
    case remainder
    case remainderU
    case equal
    case notEqual
    case lessThan
    case lessThanU
    case lessThanOrEqual
    case lessThanOrEqualU
    case greaterThan
    case greaterThanU
    case greaterThanOrEqual
    case greaterThanOrEqualU
    case bitwiseAnd
    case bitwiseOr
    case bitwiseXor
    case shiftLeft
    case shiftRight
    case shiftRightU
    
    var description: String {
        switch self {
        case .add: return "Add"
        case .subtract: return "Subtract"
        case .multiply: return "Multiply"
        case .divide: return "Divide"
        case .divideU: return "DivideU"
        case .remainder: return "Remainder"
        case .remainderU: return "RemainderU"
        case .equal: return "Equal"
        case .notEqual: return "NotEqual"
        case .lessThan: return "LessThan"
        case .lessThanU: return "LessThanU"
        case .lessThanOrEqual: return "LessThanOrEqual"
        case .lessThanOrEqualU: return "LessThanOrEqualU"
        case .greaterThan: return "GreaterThan"
        case .greaterThanU: return "GreaterThanU"
        case .greaterThanOrEqual: return "GreaterThanOrEqual"
        case .greaterThanOrEqualU: return "GreaterThanOrEqualU"
        case .bitwiseAnd: return "BitwiseAnd"
        case .bitwiseOr: return "BitwiseOr"
        case .bitwiseXor: return "BitwiseXor"
        case .shiftLeft: return "ShiftLeft"
        case .shiftRight: return "ShiftRight"
        case .shiftRightU: return "ShiftRightU"
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

