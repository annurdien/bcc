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
                }
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