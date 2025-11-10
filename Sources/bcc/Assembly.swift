// ASDL: operand = Imm(int) | Register
enum AsmOperand {
    case immediate(Int)
    case register
}

// ASDL: instruction = Mov(operand src, operand dst) | Ret
enum AsmInstruction {
    case mov(AsmOperand, AsmOperand)
    case ret
}

// ASDL: function_definition = Function(identifier name, instruction* instructions)
struct AsmFunction {
    let name: String
    let instructions: [AsmInstruction]
}

// ASDL: program = Program(function_definition)
struct AsmProgram {
    let function: AsmFunction
}