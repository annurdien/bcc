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
        case .addl(let src, let dest):
            return "  addl \(emit(operand: src, size: .l)), \(emit(operand: dest, size: .l))\n"
        case .subl(let src, let dest):
            return "  subl \(emit(operand: src, size: .l)), \(emit(operand: dest, size: .l))\n"
        case .imull(let src, let dest):
            return "  imull \(emit(operand: src, size: .l)), \(emit(operand: dest, size: .l))\n"
        case .idivl(let op):
            return "  idivl \(emit(operand: op, size: .l))\n"
        case .cdq:
            return "  cdq\n"
        case .cmpl(let src, let dest):
            return "  cmpl \(emit(operand: src, size: .l)), \(emit(operand: dest, size: .l))\n"
        case .negl(let op):
            return "  negl \(emit(operand: op, size: .l))\n"
        case .notl(let op):
            return "  notl \(emit(operand: op, size: .l))\n"
        case .setz(let op):
            return "  setz \(emit(operand: op, size: .b))\n"
        case .setnz(let op):
            return "  setnz \(emit(operand: op, size: .b))\n"
        case .setl(let op):
            return "  setl \(emit(operand: op, size: .b))\n"
        case .setle(let op):
            return "  setle \(emit(operand: op, size: .b))\n"
        case .setg(let op):
            return "  setg \(emit(operand: op, size: .b))\n"
        case .setge(let op):
            return "  setge \(emit(operand: op, size: .b))\n"
        case .jmp(let target):
            return "  jmp \(target)\n"
        case .je(let target):
            return "  je \(target)\n"
        case .jne(let target):
            return "  jne \(target)\n"
        case .label(let name):
            return "\(name):\n"
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
            case .rax:
                switch size {
                case .q: return "%rax"
                case .l: return "%eax"
                case .b: return "%al"
                }
            case .eax:
                // Assuming eax maps to rax logic, but strictly speaking it's the same register
                switch size {
                case .q: return "%rax"
                case .l: return "%eax"
                case .b: return "%al"
                }
            case .rbp: return size == .q ? "%rbp" : "%ebp"
            case .rsp: return size == .q ? "%rsp" : "%esp"
            case .r10:
                switch size {
                case .q: return "%r10"
                case .l: return "%r10d"
                case .b: return "%r10b"
                }
            case .r10d:
                 switch size {
                case .q: return "%r10"
                case .l: return "%r10d"
                case .b: return "%r10b"
                }
            }
            
        case .stackOffset(let offset):
            return "\(offset)(%rbp)"
            
        case .pseudoregister(let name):
            // This should not happen by the time we emit
            return "%\(name)_ERROR"
        }
    }
}