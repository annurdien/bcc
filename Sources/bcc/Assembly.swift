import Foundation
struct AsmProgram {
    let function: AsmFunction
}
struct AsmFunction {
    let name: String
    var instructions: [AsmInstruction]
    var stackSize: Int
}

enum AsmRegister: String {
    case rax, eax, rbp, rsp, r10, r10d
}

enum AsmOperand: Equatable {
    case immediate(Int)
    case register(AsmRegister)
    case pseudoregister(String)
    case stackOffset(Int)
}

enum AsmInstruction: Equatable {
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
}