import Foundation

private func indent(_ s: String) -> String {
    return s.split(separator: "\n").map { "  " + $0 }.joined(separator: "\n")
}

struct AsmProgram: Equatable, CustomStringConvertible {
    let globals: [AsmGlobal]
    let functions: [AsmFunction]

    var description: String {
        let globalsDesc = globals.map { $0.description }.joined(separator: "\n")
        let funcsDesc = functions.map { $0.description }.joined(separator: "\n\n")
        return "AsmProgram(\nGlobals:\n\(indent(globalsDesc))\n\nFunctions:\n\(indent(funcsDesc))\n)"
    }
}

struct AsmGlobal: Equatable, CustomStringConvertible {
    let name: String
    let initialValue: Int? 
    let isStatic: Bool
    let size: Int
    let alignment: Int

    init(name: String, initialValue: Int?, isStatic: Bool, size: Int = 4, alignment: Int = 4) {
        self.name = name
        self.initialValue = initialValue
        self.isStatic = isStatic
        self.size = size
        self.alignment = alignment
    }

    var description: String {
        let visibility = isStatic ? "Static" : "Global"
        if let val = initialValue {
            return "\(visibility)(name: \(name), init: \(val), size: \(size))"
        } else {
            return "\(visibility)(name: \(name), uninit, size: \(size))"
        }
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
    case rax, eax
    case rbp, rsp
    case rdi, edi
    case rsi, esi
    case rdx, edx
    case rcx, ecx
    case r8, r8d
    case r9, r9d
    case r10, r10d
    case r11, r11d

    var description: String {
        "%" + self.rawValue
    }
}

enum AsmOperand: Equatable, CustomStringConvertible {
    case immediate(Int)
    case register(AsmRegister)
    case pseudoregister(String)
    case stackOffset(Int)
    case dataLabel(String)
    case indirect(AsmRegister)

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
        case .dataLabel(let name):
             return "\(name)(%rip)"
        case .indirect(let reg):
             return "(\(reg.description))"
        }
    }
}

enum AsmInstruction: Equatable, CustomStringConvertible {
    // Prologue / Epilogue
    case pushq(AsmOperand)
    case popq(AsmOperand)
    case movq(AsmOperand, AsmOperand) // 64-bit move
    case leaq(AsmOperand, AsmOperand) // Load effective address
    case addq(AsmOperand, AsmOperand) // 64-bit add
    case subq(AsmOperand, AsmOperand) // 64-bit subtract
    case imulq(AsmOperand, AsmOperand)
    case idivq(AsmOperand)
    case divq(AsmOperand)
    case negq(AsmOperand)
    case notq(AsmOperand)
    case cmpq(AsmOperand, AsmOperand)
    case andq(AsmOperand, AsmOperand)
    case orq(AsmOperand, AsmOperand)
    case xorq(AsmOperand, AsmOperand)
    case salq(AsmOperand, AsmOperand)
    case sarq(AsmOperand, AsmOperand)
    case shrq(AsmOperand, AsmOperand)
    case cqo // Sign extend RAX to RDX:RAX

    // Operations (32-bit)
    case movl(AsmOperand, AsmOperand)
    case addl(AsmOperand, AsmOperand)
    case subl(AsmOperand, AsmOperand)
    case imull(AsmOperand, AsmOperand)
    case idivl(AsmOperand)
    case divl(AsmOperand)
    case cdq // Sign extend EAX to EDX:EAX for division
    case cmpl(AsmOperand, AsmOperand)
    case negl(AsmOperand)
    case notl(AsmOperand)
    case andl(AsmOperand, AsmOperand)
    case orl(AsmOperand, AsmOperand)
    case xorl(AsmOperand, AsmOperand)
    case sall(AsmOperand, AsmOperand)
    case sarl(AsmOperand, AsmOperand)
    case shrl(AsmOperand, AsmOperand)
    case setz(AsmOperand)
    case setnz(AsmOperand)
    case setl(AsmOperand)
    case setle(AsmOperand)
    case setg(AsmOperand)
    case setge(AsmOperand)
    case setb(AsmOperand)
    case setbe(AsmOperand)
    case seta(AsmOperand)
    case setae(AsmOperand)
    case jmp(String)
    case je(String)
    case jne(String)
    case call(String)
    case label(String)
    case ret

    var description: String {
        switch self {
        case .pushq(let op):
            return "pushq \(op.description)"
        case .popq(let op):
            return "popq \(op.description)"
        case .movq(let src, let dest):
            return "movq \(src.description), \(dest.description)"
        case .leaq(let src, let dest):
            return "leaq \(src.description), \(dest.description)"
        case .addq(let src, let dest):
            return "addq \(src.description), \(dest.description)"
        case .subq(let src, let dest):
            return "subq \(src.description), \(dest.description)"
        case .imulq(let src, let dest):
            return "imulq \(src.description), \(dest.description)"
        case .idivq(let op):
            return "idivq \(op.description)"
        case .divq(let op):
            return "divq \(op.description)"
        case .negq(let op):
            return "negq \(op.description)"
        case .notq(let op):
            return "notq \(op.description)"
        case .cmpq(let src, let dest):
            return "cmpq \(src.description), \(dest.description)"
        case .cqo:
            return "cqo"
        case .andq(let src, let dest): return "andq \(src.description), \(dest.description)"
        case .orq(let src, let dest): return "orq \(src.description), \(dest.description)"
        case .xorq(let src, let dest): return "xorq \(src.description), \(dest.description)"
        case .salq(let src, let dest): return "salq \(src.description), \(dest.description)"
        case .sarq(let src, let dest): return "sarq \(src.description), \(dest.description)"
        case .shrq(let src, let dest): return "shrq \(src.description), \(dest.description)"
        case .movl(let src, let dest):
            return "movl \(src.description), \(dest.description)"
        case .addl(let src, let dest):
            return "addl \(src.description), \(dest.description)"
        case .subl(let src, let dest):
            return "subl \(src.description), \(dest.description)"
        case .imull(let src, let dest):
            return "imull \(src.description), \(dest.description)"
        case .idivl(let op):
            return "idivl \(op.description)"
        case .divl(let op):
            return "divl \(op.description)"
        case .cdq:
            return "cdq"
        case .negl(let op):
            return "negl \(op.description)"
        case .notl(let op):
            return "notl \(op.description)"
        case .andl(let src, let dest): return "andl \(src.description), \(dest.description)"
        case .orl(let src, let dest): return "orl \(src.description), \(dest.description)"
        case .xorl(let src, let dest): return "xorl \(src.description), \(dest.description)"
        case .sall(let src, let dest): return "sall \(src.description), \(dest.description)"
        case .sarl(let src, let dest): return "sarl \(src.description), \(dest.description)"
        case .shrl(let src, let dest): return "shrl \(src.description), \(dest.description)"
        case .cmpl(let src, let dest):
            return "cmpl \(src.description), \(dest.description)"
        case .setz(let op):
            return "setz \(op.description)"
        case .setnz(let op):
            return "setnz \(op.description)"
        case .setl(let op):
            return "setl \(op.description)"
        case .setle(let op):
            return "setle \(op.description)"
        case .setg(let op):
            return "setg \(op.description)"
        case .setge(let op):
            return "setge \(op.description)"
        case .setb(let op):
            return "setb \(op.description)"
        case .setbe(let op):
            return "setbe \(op.description)"
        case .seta(let op):
            return "seta \(op.description)"
        case .setae(let op):
            return "setae \(op.description)"
        case .jmp(let target):
            return "jmp \(target)"
        case .je(let target):
            return "je \(target)"
        case .jne(let target):
            return "jne \(target)"
        case .call(let funcName):
            return "call _\(funcName)"
        case .label(let name):
            return "_\(name):"
        case .ret:
            return "ret"
        }
    }
}