import Foundation

struct CodeEmitter {
    
    func emit(program: AsmProgram) -> String {
        var output = ""
        
        // Data Section (Globals)
        if !program.globals.isEmpty {
            #if os(macOS)
            output.append(".section __DATA,__data\n")
            #else
            output.append(".section .data\n")
            #endif
            
            for global in program.globals {
                output.append(emit(global: global))
            }
            output.append("\n")
        }
        
        // Text Section (Code)
        #if os(macOS)
        output.append(".section __TEXT,__text\n")
        #else
        output.append(".section .text\n")
        #endif
        
        for function in program.functions {
            output.append(emit(function: function))
            output.append("\n")
        }
        
        #if os(Linux)
        output.append(".section .note.GNU-stack,\"\",@progbits\n")
        #endif
        
        return output
    }

    private func emit(global: AsmGlobal) -> String {
        var output = ""
        let name = global.name
        
        #if os(macOS)
        if !global.isStatic {
            output.append(".globl _\(name)\n")
        }
        let align = global.size == 8 ? 3 : 2
        output.append(".p2align \(align)\n") 
        output.append("_\(name):\n")
        #else
        if !global.isStatic {
            output.append(".globl \(name)\n")
        }
        let align = global.alignment
        output.append(".align \(align)\n")
        output.append("\(name):\n")
        #endif
        
        let value = global.initialValue ?? 0
        if global.size == 8 {
             output.append("  .quad \(value)\n")
        } else {
             output.append("  .long \(value)\n")
        }
        return output
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
        case .leaq(let src, let dest):
            return "  leaq \(emit(operand: src, size: .q)), \(emit(operand: dest, size: .q))\n"
        case .addq(let src, let dest):
            return "  addq \(emit(operand: src, size: .q)), \(emit(operand: dest, size: .q))\n"
        case .subq(let src, let dest):
            return "  subq \(emit(operand: src, size: .q)), \(emit(operand: dest, size: .q))\n"
        case .imulq(let src, let dest):
            return "  imulq \(emit(operand: src, size: .q)), \(emit(operand: dest, size: .q))\n"
        case .idivq(let src):
            return "  idivq \(emit(operand: src, size: .q))\n"
        case .divq(let src):
            return "  divq \(emit(operand: src, size: .q))\n"
        case .negq(let dest):
            return "  negq \(emit(operand: dest, size: .q))\n"
        case .notq(let dest):
            return "  notq \(emit(operand: dest, size: .q))\n"
        case .cmpq(let src, let dest):
            return "  cmpq \(emit(operand: src, size: .q)), \(emit(operand: dest, size: .q))\n"
        case .andq(let src, let dest):
            return "  andq \(emit(operand: src, size: .q)), \(emit(operand: dest, size: .q))\n"
        case .orq(let src, let dest):
            return "  orq \(emit(operand: src, size: .q)), \(emit(operand: dest, size: .q))\n"
        case .xorq(let src, let dest):
            return "  xorq \(emit(operand: src, size: .q)), \(emit(operand: dest, size: .q))\n"
        case .salq(let src, let dest):
            return "  salq \(emit(operand: src, size: .b)), \(emit(operand: dest, size: .q))\n"
        case .sarq(let src, let dest):
            return "  sarq \(emit(operand: src, size: .b)), \(emit(operand: dest, size: .q))\n"
        case .shrq(let src, let dest):
            return "  shrq \(emit(operand: src, size: .b)), \(emit(operand: dest, size: .q))\n"
        case .cqo:
            return "  cqo\n"
        case .movl(let src, let dest):
            return "  movl \(emit(operand: src, size: .l)), \(emit(operand: dest, size: .l))\n"
        case .addl(let src, let dest):
            return "  addl \(emit(operand: src, size: .l)), \(emit(operand: dest, size: .l))\n"
        case .subl(let src, let dest):
            return "  subl \(emit(operand: src, size: .l)), \(emit(operand: dest, size: .l))\n"
        case .imull(let src, let dest):
            return "  imull \(emit(operand: src, size: .l)), \(emit(operand: dest, size: .l))\n"
        case .idivl(let op):
            return "  idivl \(emit(operand: op, size: .l))\n"        case .divl(let src):
            return "  divl \(emit(operand: src, size: .l))\n"        case .cdq:
            return "  cdq\n"
        case .cmpl(let src, let dest):
            return "  cmpl \(emit(operand: src, size: .l)), \(emit(operand: dest, size: .l))\n"
        case .negl(let op):
            return "  negl \(emit(operand: op, size: .l))\n"
        case .notl(let op):
            return "  notl \(emit(operand: op, size: .l))\n"
        case .andl(let src, let dest):
            return "  andl \(emit(operand: src, size: .l)), \(emit(operand: dest, size: .l))\n"
        case .orl(let src, let dest):
            return "  orl \(emit(operand: src, size: .l)), \(emit(operand: dest, size: .l))\n"
        case .xorl(let src, let dest):
            return "  xorl \(emit(operand: src, size: .l)), \(emit(operand: dest, size: .l))\n"
        case .sall(let src, let dest):
            return "  sall \(emit(operand: src, size: .b)), \(emit(operand: dest, size: .l))\n"
        case .sarl(let src, let dest):
            return "  sarl \(emit(operand: src, size: .b)), \(emit(operand: dest, size: .l))\n"
        case .shrl(let src, let dest):
            return "  shrl \(emit(operand: src, size: .b)), \(emit(operand: dest, size: .l))\n"
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
        case .setb(let op):
            return "  setb \(emit(operand: op, size: .b))\n"
        case .setbe(let op):
            return "  setbe \(emit(operand: op, size: .b))\n"
        case .seta(let op):
            return "  seta \(emit(operand: op, size: .b))\n"
        case .setae(let op):
            return "  setae \(emit(operand: op, size: .b))\n"
        case .jmp(let target):
            return "  jmp \(target)\n"
        case .je(let target):
            return "  je \(target)\n"
        case .jne(let target):
            return "  jne \(target)\n"
        case .call(let funcName):
            #if os(macOS)
            return "  call _\(funcName)\n"
            #else
            return "  call \(funcName)\n"
            #endif
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
            case .r10, .r10d:
                switch size {
                case .q: return "%r10"
                case .l: return "%r10d"
                case .b: return "%r10b"
                }
            case .r11, .r11d:
                switch size {
                case .q: return "%r11"
                case .l: return "%r11d"
                case .b: return "%r11b"
                }
            case .rdi, .edi:
                switch size {
                case .q: return "%rdi"
                case .l: return "%edi"
                case .b: return "%dil"
                }
            case .rsi, .esi:
                switch size {
                case .q: return "%rsi"
                case .l: return "%esi"
                case .b: return "%sil"
                }
            case .rdx, .edx:
                switch size {
                case .q: return "%rdx"
                case .l: return "%edx"
                case .b: return "%dl"
                }
            case .rcx, .ecx:
                switch size {
                case .q: return "%rcx"
                case .l: return "%ecx"
                case .b: return "%cl"
                }
            case .r8, .r8d:
                switch size {
                case .q: return "%r8"
                case .l: return "%r8d"
                case .b: return "%r8b"
                }
            case .r9, .r9d:
                switch size {
                case .q: return "%r9"
                case .l: return "%r9d"
                case .b: return "%r9b"
                }
            }
            
        case .stackOffset(let offset):
            return "\(offset)(%rbp)"
            
        case .indirect(let reg):
             return "(\(emit(operand: .register(reg), size: .q)))"

        case .pseudoregister(let name):
            // This should not happen by the time we emit
            return "%\(name)_ERROR"
            
        case .dataLabel(let name):
            #if os(macOS)
            return "_\(name)(%rip)"
            #else
            return "\(name)(%rip)"
            #endif
        }
    }
}
