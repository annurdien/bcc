import Foundation

struct CodeEmitter {
    
    func emit(program: AsmProgram) -> String {
        return emit(function: program.function)
    }
    
    private func emit(function: AsmFunction) -> String {
        var output = ""
        
        #if os(macOS)
        output.append(".globl _\(function.name)\n")
        output.append("_\(function.name):\n")
        #elseif os(Linux)
        output.append(".globl \(function.name)\n")
        output.append("\(function.name):\n")
        #else
        output.append(".globl \(function.name)  // Warning: Unknown OS\n")
        output.append("\(function.name): // Warning: Unknown OS\n")
        #endif
        
        for instruction in function.instructions {
            output.append(emit(instruction: instruction))
        }
        
        #if os(Linux)
        output.append(".section .note.GNU-stack,\"\",@progbits\n")
        #endif
        
        return output
    }
    
    private func emit(instruction: AsmInstruction) -> String {
        switch instruction {
        case .pushq(let op):
            return "  pushq \(emit(operand: op, size: .q))\n"
        case .popq(let op):
            return "  popq \(emit(operand: op, size: .q))\n"
        case .movq(let src, let dest):
            return "  movq \(emit(operand: src, size: .q)), \(emit(operand: dest, size: .q))\n"
        case .subq(let src, let dest):
            return "  subq \(emit(operand: src, size: .q)), \(emit(operand: dest, size: .q))\n"
        case .movl(let src, let dest):
            return "  movl \(emit(operand: src, size: .l)), \(emit(operand: dest, size: .l))\n"
        case .negl(let op):
            return "  negl \(emit(operand: op, size: .l))\n"
        case .notl(let op):
            return "  notl \(emit(operand: op, size: .l))\n"
        case .ret:
            return "  ret\n"
        }
    }
    
    private enum AsmSize { case b, l, q }
    
    private func emit(operand: AsmOperand, size: AsmSize) -> String {
        switch operand {
        case .immediate(let value):
            return "$\(value)"
            
        case .register(let reg):
            // Select the correct register name based on size
            switch reg {
            case .rax: return size == .q ? "%rax" : "%eax"
            case .eax: return size == .l ? "%eax" : "%rax"
            case .rbp: return size == .q ? "%rbp" : "%ebp"
            case .rsp: return size == .q ? "%rsp" : "%esp"
            case .r10: return size == .q ? "%r10" : "%r10d"
            case .r10d: return size == .l ? "%r10d" : "%r10"
            }
            
        case .stackOffset(let offset):
            return "\(offset)(%rbp)"
            
        case .pseudoregister(let name):
            // This should not happen by the time we emit
            return "%\(name)_ERROR"
        }
    }
}