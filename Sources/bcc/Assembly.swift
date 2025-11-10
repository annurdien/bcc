import Foundation

private func indent(_ s: String) -> String {
    return s.split(separator: "\n").map { "  " + $0 }.joined(separator: "\n")
}

struct AsmProgram: Equatable, CustomStringConvertible {
    let function: AsmFunction

    var description: String {
        "AsmProgram(\n\(indent(function.description))\n)"
    }
}
struct AsmFunction: Equatable, CustomStringConvertible {
    let name: String
    var instructions: [AsmInstruction]
    var stackSize: Int

    var description: String {
        let bodyDesc = instructions.map { $0.description }.joined(separator: "\n")
        return "AsmFunction(name: \(name), stackSize: \(stackSize)) {\n\(indent(bodyDesc))\n}"
    }
}

enum AsmRegister: String, Equatable, CustomStringConvertible {
    case rax, eax, rbp, rsp, r10, r10d

    var description: String {
        "%" + self.rawValue
    }
}

enum AsmOperand: Equatable, CustomStringConvertible {
    case immediate(Int)
    case register(AsmRegister)
    case pseudoregister(String)
    case stackOffset(Int)

    var description: String {
        switch self {
        case .immediate(let val):
            return "$\(val)"
        case .register(let reg):
            return reg.description
        case .pseudoregister(let name):
            return "%\(name)"
        case .stackOffset(let offset):
            return "\(offset)(%rbp)"
        }
    }
}

enum AsmInstruction: Equatable, CustomStringConvertible {
    // Prologue / Epilogue
    case pushq(AsmOperand)
    case popq(AsmOperand)
    case movq(AsmOperand, AsmOperand) // 64-bit move
    case subq(AsmOperand, AsmOperand) // 64-bit subtract

    // Operations (32-bit)
    case movl(AsmOperand, AsmOperand)
    case negl(AsmOperand)
    case notl(AsmOperand)
    case ret

    var description: String {
        switch self {
        case .pushq(let op):
            return "pushq \(op.description)"
        case .popq(let op):
            return "popq \(op.description)"
        case .movq(let src, let dest):
            return "movq \(src.description), \(dest.description)"
        case .subq(let src, let dest):
            return "subq \(src.description), \(dest.description)"
        case .movl(let src, let dest):
            return "movl \(src.description), \(dest.description)"
        case .negl(let op):
            return "negl \(op.description)"
        case .notl(let op):
            return "notl \(op.description)"
        case .ret:
            return "ret"
        }
    }
}