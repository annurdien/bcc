import Foundation

struct AssemblyGenerator {
    // Function definition
    func emit(program: AsmProgram) -> String {
        var output = emit(function: program.function)
        
        #if os(Linux)
        output += "\n.section .note.GNU-stack,\"\",@progbits\n"
        #endif
        
        return output
    }

    private func emit(function: AsmFunction) -> String {
        #if os(macOS)
        let functionName = "_\(function.name)"
        #else
        let functionName = function.name
        #endif

        let instruction = function.instructions.map {
            " " + emit(instruction : $0)
        }.joined(separator: "\n")

        return """
        .globl \(functionName)
        \(functionName):
         \(instruction)
        """
    }

    private func emit(instruction: AsmInstruction) -> String {
        switch instruction {
            case .mov(let src, let dst):
            return "movl \(emit(operand: src)), \(emit(operand: dst))"
            case .ret:
            return "ret"
        }
    }

    private func emit(operand: AsmOperand) -> String {
        switch operand {
            case .immediate(let value):
            return "$\(value)"
            case .register:
            return "%eax" // Now we only have one register
        }
    }
}