import Foundation

struct AssemblyGenerator {

    func generate(program: TackyProgram) -> AsmProgram {
        var asmFunction = convertTackyToAsm(function: program.function)
        let (finalInstructions, stackSize) = replacePseudoregisters(in: asmFunction.instructions)
        asmFunction.instructions = finalInstructions
        asmFunction.stackSize = stackSize
        
        addPrologueAndEpilogue(&asmFunction)
        
        asmFunction.instructions = fixUpInstructions(asmFunction.instructions)
        
        return AsmProgram(function: asmFunction)
    }
    
    private func convertTackyToAsm(function: TackyFunction) -> AsmFunction {
        var instructions: [AsmInstruction] = []
        
        for tackyInst in function.body {
            switch tackyInst {
            case .return(let value):
                instructions.append(.movl(convert(value), .register(.eax)))
                
            case .unary(let op, let src, let dest):
                let destOperand = convert(dest)
                // movl %src, %dest
                instructions.append(.movl(convert(src), destOperand))
                
                // op %dest
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

    private func convert(_ value: TackyValue) -> AsmOperand {
        switch value {
        case .constant(let int):
            return .immediate(int)
        case .variable(let name):
            return .pseudoregister(name)
        }
    }

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
                nextStackOffset -= 4
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
    
    private func fixUpInstructions(_ instructions: [AsmInstruction]) -> [AsmInstruction] {
        var finalInstructions: [AsmInstruction] = []
        
        for inst in instructions {
            switch inst {
            case .movl(let src, let dest):
                if case .stackOffset = src, case .stackOffset = dest {
                    // movl %src, %r10d
                    finalInstructions.append(.movl(src, .register(.r10d)))
                    // movl %r10d, %dest
                    finalInstructions.append(.movl(.register(.r10d), dest))
                } else {
                    finalInstructions.append(inst)
                }
            
            default:
                finalInstructions.append(inst)
            }
        }
        return finalInstructions
    }

    private func addPrologueAndEpilogue(_ function: inout AsmFunction) {
        let stackSize = (function.stackSize + 15) & ~15
        
        let prologue: [AsmInstruction] = [
            .pushq(.register(.rbp)),
            .movq(.register(.rsp), .register(.rbp)),
            .subq(.immediate(stackSize), .register(.rsp))
        ]
        
        let epilogue: [AsmInstruction] = [
            .movq(.register(.rbp), .register(.rsp)),
            .popq(.register(.rbp)),
            .ret
        ]
        
        if let retIndex = function.instructions.firstIndex(of: .ret) {
            function.instructions.remove(at: retIndex)
            function.instructions.insert(contentsOf: prologue, at: 0)
            function.instructions.append(contentsOf: epilogue)
        }
    }
}