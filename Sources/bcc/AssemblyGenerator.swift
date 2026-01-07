import Foundation

// --- Updated File: AssemblyGenerator.swift ---
// This class converts TACKY IR to Assembly AST

struct AssemblyGenerator {

    /// Main generation function
    func generate(program: TackyProgram) -> AsmProgram {
        var asmFunction = convertTackyToAsm(function: program.function)
        let (finalInstructions, stackSize) = replacePseudoregisters(in: asmFunction.instructions)
        asmFunction.instructions = finalInstructions
        asmFunction.stackSize = stackSize
        
        // Add prologue and epilogue
        addPrologueAndEpilogue(&asmFunction)
        
        // Fix-up pass
        asmFunction.instructions = fixUpInstructions(asmFunction.instructions)
        
        return AsmProgram(function: asmFunction)
    }
    
    // --- Pass 1: Convert TACKY to Assembly (using Pseudoregisters) ---
    // --- THIS FUNCTION IS NOW UPDATED TO MATCH TABLE 2-3 ---
    private func convertTackyToAsm(function: TackyFunction) -> AsmFunction {
        var instructions: [AsmInstruction] = []
        
        for tackyInst in function.body {
            switch tackyInst {
            case .return(let value):
                // Per Table 2-3:
                // 1. Mov(val, Reg(AX))
                instructions.append(.movl(convert(value), .register(.eax)))
                // 2. Ret
                instructions.append(.ret) // <-- ADDED
                
            case .unary(let op, let src, let dest):
                let destOperand = convert(dest)
                // Per Table 2-3:
                // 1. Mov(src, dst)
                instructions.append(.movl(convert(src), destOperand))
                
                // 2. Unary(unary_operator, dst)
                switch op {
                case .negate:
                    instructions.append(.negl(destOperand))
                case .complement:
                    instructions.append(.notl(destOperand))
                case .logicalNot:
                    // 1. Compare with 0
                    instructions.append(.cmpl(.immediate(0), destOperand))
                    // 2. Zero out the destination
                    instructions.append(.movl(.immediate(0), destOperand))
                    // 3. Set lower byte if equal (zero flag set)
                    instructions.append(.setz(destOperand))
                }

            case .binary(let op, let lhs, let rhs, let dest):
                let destOperand = convert(dest)
                let lhsOperand = convert(lhs)
                let rhsOperand = convert(rhs)
                
                // For Add/Sub/Mul:
                // 1. mov lhs -> dest  (dest = lhs)
                // 2. op rhs, dest     (dest = dest op rhs) -> (dest = lhs op rhs)

                // For Div:
                // Special handling because idivl uses EAX:EDX
                
                switch op {
                case .add:
                    instructions.append(.movl(lhsOperand, destOperand))
                    instructions.append(.addl(rhsOperand, destOperand))
                case .subtract:
                    instructions.append(.movl(lhsOperand, destOperand))
                    instructions.append(.subl(rhsOperand, destOperand))
                case .multiply:
                    instructions.append(.movl(lhsOperand, destOperand))
                    instructions.append(.imull(rhsOperand, destOperand))
                case .divide:
                    // idivl S
                    // 1. mov lhs -> EAX
                    // 2. cltd (sign extend EAX -> EDX:EAX) - we use cdq for 32-bit
                    // 3. idivl rhs
                    // 4. mov EAX -> dest
                    
                    instructions.append(.movl(lhsOperand, .register(.eax)))
                    instructions.append(.cdq)
                    instructions.append(.idivl(rhsOperand))
                    instructions.append(.movl(.register(.eax), destOperand))
                
                case .equal:
                    instructions.append(.cmpl(rhsOperand, lhsOperand))
                    instructions.append(.movl(.immediate(0), destOperand))
                    instructions.append(.setz(destOperand))

                case .notEqual:
                    instructions.append(.cmpl(rhsOperand, lhsOperand))
                    instructions.append(.movl(.immediate(0), destOperand))
                    instructions.append(.setnz(destOperand))

                case .lessThan:
                    instructions.append(.cmpl(rhsOperand, lhsOperand))
                    instructions.append(.movl(.immediate(0), destOperand))
                    instructions.append(.setl(destOperand))

                case .lessThanOrEqual:
                    instructions.append(.cmpl(rhsOperand, lhsOperand))
                    instructions.append(.movl(.immediate(0), destOperand))
                    instructions.append(.setle(destOperand))

                case .greaterThan:
                    instructions.append(.cmpl(rhsOperand, lhsOperand))
                    instructions.append(.movl(.immediate(0), destOperand))
                    instructions.append(.setg(destOperand))

                case .greaterThanOrEqual:
                    instructions.append(.cmpl(rhsOperand, lhsOperand))
                    instructions.append(.movl(.immediate(0), destOperand))
                    instructions.append(.setge(destOperand))
                }

            case .copy(let src, let dest):
                instructions.append(.movl(convert(src), convert(dest)))

            case .jump(let target):
                instructions.append(.jmp(target))

            case .jumpIfZero(let cond, let target):
                instructions.append(.cmpl(.immediate(0), convert(cond)))
                instructions.append(.je(target))

            case .jumpIfNotZero(let cond, let target):
                instructions.append(.cmpl(.immediate(0), convert(cond)))
                instructions.append(.jne(target))

            case .label(let name):
                instructions.append(.label(name))
            }
        }
        
        return AsmFunction(name: function.name, instructions: instructions, stackSize: 0)
    }
    // --- END UPDATED SECTION ---

    private func convert(_ value: TackyValue) -> AsmOperand {
        switch value {
        case .constant(let int):
            return .immediate(int)
        case .variable(let name):
            return .pseudoregister(name)
        }
    }

    // --- Pass 2: Replace Pseudoregisters with Stack Offsets ---
    private func replacePseudoregisters(in instructions: [AsmInstruction]) -> ([AsmInstruction], Int) {
        var newInstructions: [AsmInstruction] = []
        var mapping: [String: Int] = [:] // "tmp.0" -> -4
        var nextStackOffset: Int = -4 // Start 4 bytes below RBP

        func mapOperand(_ operand: AsmOperand) -> AsmOperand {
            guard case .pseudoregister(let name) = operand else {
                return operand
            }
            
            if let offset = mapping[name] {
                return .stackOffset(offset)
            } else {
                let offset = nextStackOffset
                mapping[name] = offset
                nextStackOffset -= 4 // Allocate next slot
                return .stackOffset(offset)
            }
        }

        for inst in instructions {
            switch inst {
            case .movl(let src, let dest):
                newInstructions.append(.movl(mapOperand(src), mapOperand(dest)))
            case .negl(let op):
                newInstructions.append(.negl(mapOperand(op)))
            case .notl(let op):
                newInstructions.append(.notl(mapOperand(op)))
            case .addl(let src, let dest):
                newInstructions.append(.addl(mapOperand(src), mapOperand(dest)))
            case .subl(let src, let dest):
                newInstructions.append(.subl(mapOperand(src), mapOperand(dest)))
            case .imull(let src, let dest):
                newInstructions.append(.imull(mapOperand(src), mapOperand(dest)))
            case .idivl(let op):
                newInstructions.append(.idivl(mapOperand(op)))
            case .cdq:
                newInstructions.append(.cdq)
            case .cmpl(let src, let dest):
                newInstructions.append(.cmpl(mapOperand(src), mapOperand(dest)))
            case .setz(let op):
                newInstructions.append(.setz(mapOperand(op)))
            case .setnz(let op):
                newInstructions.append(.setnz(mapOperand(op)))
            case .setl(let op):
                newInstructions.append(.setl(mapOperand(op)))
            case .setle(let op):
                newInstructions.append(.setle(mapOperand(op)))
            case .setg(let op):
                newInstructions.append(.setg(mapOperand(op)))
            case .setge(let op):
                newInstructions.append(.setge(mapOperand(op)))
            default:
                newInstructions.append(inst) // .ret, etc.
            }
        }
        
        let stackSize = (nextStackOffset + 4) * -1
        return (newInstructions, stackSize)
    }
    
    // --- Pass 3: Fix Up Illegal Instructions ---
    private func fixUpInstructions(_ instructions: [AsmInstruction]) -> [AsmInstruction] {
        var finalInstructions: [AsmInstruction] = []
        
        for inst in instructions {
            switch inst {
            // movl mem, mem is illegal. Fix it.
            case .movl(let src, let dest):
                if case .stackOffset = src, case .stackOffset = dest {
                    // movl %src, %r10d
                    finalInstructions.append(.movl(src, .register(.r10d)))
                    // movl %r10d, %dest
                    finalInstructions.append(.movl(.register(.r10d), dest))
                } else {
                    finalInstructions.append(inst)
                }

            // cmpl mem, mem is illegal. Fix it.
            // cmpl *, immediate is illegal (destination cannot be immediate)
            case .cmpl(let src, let dest):
                if case .stackOffset = src, case .stackOffset = dest {
                    // movl %src, %r10d
                    finalInstructions.append(.movl(src, .register(.r10d)))
                    // cmpl %r10d, %dest
                    finalInstructions.append(.cmpl(.register(.r10d), dest))
                } else if case .immediate = dest {
                    // cmpl src, $imm -> illegal. Move dest to reg.
                    finalInstructions.append(.movl(dest, .register(.r10d)))
                    finalInstructions.append(.cmpl(src, .register(.r10d)))
                } else {
                    finalInstructions.append(inst)
                }

            // addl mem, mem is illegal
            case .addl(let src, let dest):
                if case .stackOffset = src, case .stackOffset = dest {
                    finalInstructions.append(.movl(src, .register(.r10d)))
                    finalInstructions.append(.addl(.register(.r10d), dest))
                } else {
                    finalInstructions.append(inst)
                }

            // subl mem, mem is illegal
            case .subl(let src, let dest):
                 if case .stackOffset = src, case .stackOffset = dest {
                    finalInstructions.append(.movl(src, .register(.r10d)))
                    finalInstructions.append(.subl(.register(.r10d), dest))
                } else {
                    finalInstructions.append(inst)
                }

            // imull mem, mem is illegal
            case .imull(let src, let dest):
                 if case .stackOffset = src, case .stackOffset = dest {
                    finalInstructions.append(.movl(src, .register(.r10d)))
                    finalInstructions.append(.imull(.register(.r10d), dest))
                } else if case .stackOffset = dest {
                    // imull src, memory -> illegal. Must be imull src, reg.
                    // Fix:
                    // movl dest, %r11d
                    // imull src, %r11d
                    // movl %r11d, dest
                    
                    finalInstructions.append(.movl(dest, .register(.r10d))) // Use r10d as scratch
                    finalInstructions.append(.imull(src, .register(.r10d)))
                    finalInstructions.append(.movl(.register(.r10d), dest))
                } else {
                    finalInstructions.append(inst)
                }
            
            // idivl imm is illegal
            case .idivl(let op):
                if case .immediate = op {
                    finalInstructions.append(.movl(op, .register(.r10d)))
                    finalInstructions.append(.idivl(.register(.r10d)))
                } else {
                    finalInstructions.append(inst)
                }

            // Other instructions are fine for now
            default:
                finalInstructions.append(inst)
            }
        }
        return finalInstructions
    }

    // --- Add Prologue & Epilogue ---
    private func addPrologueAndEpilogue(_ function: inout AsmFunction) {
        // Round stack size up to nearest 16 bytes for alignment
        let stackSize = (function.stackSize + 15) & ~15
        
        let prologue: [AsmInstruction] = [
            .pushq(.register(.rbp)),
            .movq(.register(.rsp), .register(.rbp)),
            .subq(.immediate(stackSize), .register(.rsp))
        ]
        
        let epilogue: [AsmInstruction] = [
            .movq(.register(.rbp), .register(.rsp)),
            .popq(.register(.rbp)),
            // .ret is now part of the epilogue, not the main instruction list
        ]
        
        // Find the .ret instruction and insert the epilogue before it
        if let retIndex = function.instructions.firstIndex(of: .ret) {
            function.instructions.remove(at: retIndex) // Remove the placeholder .ret
            function.instructions.insert(contentsOf: prologue, at: 0)
            function.instructions.append(contentsOf: epilogue)
            function.instructions.append(.ret) // Add the *real* .ret at the very end
        } else {
            // This should not happen if TACKY generation is correct
            print("Error: No .ret instruction found. Epilogue not added.")
        }
    }
}