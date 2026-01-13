import Foundation

struct AssemblyGenerator {

    /// Main generation function
    func generate(program: TackyProgram) -> AsmProgram {
        // Convert globals
        let asmGlobals = program.globals.map { g in
             AsmGlobal(name: g.name, initialValue: g.initialValue, isStatic: g.isStatic)
        }
        
        // Iterate over all functions in the program
        let asmFunctions = program.functions.map { generateFunction($0) }
        return AsmProgram(globals: asmGlobals, functions: asmFunctions)
    }

    private func generateFunction(_ tackyFunc: TackyFunction) -> AsmFunction {
        // 1. Convert TACKY implementation to Assembly (with pseudoregisters)
        var asmFunction = convertTackyToAsm(function: tackyFunc)
        
        // 2. Replace Pseudoregisters with Stack Offsets
        let (resolvedInstructions, stackSize) = replacePseudoregisters(in: asmFunction.instructions)
        asmFunction.instructions = resolvedInstructions
        asmFunction.stackSize = stackSize
        
        // 3. Add Prologue and Epilogue
        addPrologueAndEpilogue(&asmFunction)
        
        // 4. Fix Up Illegal Instructions
        asmFunction.instructions = fixUpInstructions(asmFunction.instructions)
        
        return asmFunction
    }
    
    // ABI Argument Registers (First 6) - Using 32-bit accessors
    // Note: We use 32-bit registers (edi, esi...) because TACKY values are 32-bit ints.
    // Writing to these 32-bit registers zeros the upper 32-bits of the full 64-bit registers.
    private let argumentRegisters: [AsmRegister] = [.edi, .esi, .edx, .ecx, .r8d, .r9d]

    // --- Pass 1: Convert TACKY to Assembly (using Pseudoregisters) ---
    private func convertTackyToAsm(function: TackyFunction) -> AsmFunction {
        var instructions: [AsmInstruction] = []
        
        // 1. Parameter Handling (Prologue part that moves args to locals)
        // Move arguments from ABI locations (Regs or Caller Stack) to local storage (Pseudoregisters)
        for (index, paramName) in function.parameters.enumerated() {
            let dest = AsmOperand.pseudoregister(paramName)
            if index < argumentRegisters.count {
                // Register argument: movl %edi, param
                let reg = argumentRegisters[index]
                instructions.append(.movl(.register(reg), dest))
            } else {
                // Stack argument (Caller's stack): movl 16(%rbp), param
                // Arguments start at RBP + 16. The 7th argument (index 6) is at 16.
                let stackIndex = index - 6
                let offset = 16 + (stackIndex * 8)
                instructions.append(.movl(.stackOffset(offset), dest))
            }
        }

        for tackyInst in function.body {
            switch tackyInst {
            case .return(let value):
                instructions.append(.movl(convert(value), .register(.eax)))
                instructions.append(.ret)
                
            case .unary(let op, let src, let dest):
                let destOperand = convert(dest)
                instructions.append(.movl(convert(src), destOperand))
                switch op {
                case .negate:
                    instructions.append(.negl(destOperand))
                case .complement:
                    instructions.append(.notl(destOperand))
                case .logicalNot:
                    instructions.append(.cmpl(.immediate(0), destOperand))
                    instructions.append(.movl(.immediate(0), destOperand))
                    instructions.append(.setz(destOperand))
                }
                
            case .binary(let op, let lhs, let rhs, let dest):
                let destOperand = convert(dest)
                let lhsOperand = convert(lhs)
                let rhsOperand = convert(rhs)
                
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
                    // idivl divides EDX:EAX by operand
                    instructions.append(.movl(lhsOperand, .register(.eax)))
                    instructions.append(.cdq) // Sign extend EAX -> EDX
                    instructions.append(.idivl(rhsOperand))
                    instructions.append(.movl(.register(.eax), destOperand))
                    
                // Comparison Logic
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
                
            case .jumpIfZero(let condition, let target):
                instructions.append(.cmpl(.immediate(0), convert(condition)))
                instructions.append(.je(target))
                
            case .jumpIfNotZero(let condition, let target):
                instructions.append(.cmpl(.immediate(0), convert(condition)))
                instructions.append(.jne(target))
                
            case .label(let name):
                instructions.append(.label(name))
                
            case .call(let name, let args, let dest):
                 // System V AMD64 ABI Calling Convention
                 
                 let regArgs = Array(args.prefix(6))
                 let stackArgs = Array(args.dropFirst(6))
                 
                 // 1. Stack Alignment
                 let stackPadding = (stackArgs.count % 2 != 0) ? 8 : 0
                 if stackPadding > 0 {
                     instructions.append(.subq(.immediate(stackPadding), .register(.rsp)))
                 }
                 
                 // 2. Push Stack Args (Reverse Order)
                 for arg in stackArgs.reversed() {
                     let op = convert(arg)
                     // Move to EAX first to handle memory operands or extension
                     instructions.append(.movl(op, .register(.eax)))
                     // Push RAX (8 bytes) to stack
                     instructions.append(.pushq(.register(.rax)))
                 }
                 
                 // 3. Set Register Args
                 for (i, arg) in regArgs.enumerated() {
                     let reg = argumentRegisters[i]
                     instructions.append(.movl(convert(arg), .register(reg)))
                 }
                 
                 // 4. Call
                 instructions.append(.call(name))
                 
                 // 5. Cleanup Stack
                 let bytesPopped = (stackArgs.count * 8) + stackPadding
                 if bytesPopped > 0 {
                     instructions.append(.addq(.immediate(bytesPopped), .register(.rsp)))
                 }
                 
                 // 6. Store Result
                 instructions.append(.movl(.register(.eax), convert(dest)))
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
        case .global(let name):
             // On macOS it needs _ prefix usually but we handle that in code emitter?
             // Actually, DataLabel is just the name.
             return .dataLabel(name)
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
            
            // Check if it is already mapped to stack
            if let offset = mapping[name] {
                return .stackOffset(offset)
            } 
            
            // NOTE:
            // Since we don't differentiate between Local and Global in TackyValue.variable,
            // we have a heuristic here:
            // Globals are user-defined names.
            // Stack locals are user-defined names (params/locals) OR "tmp.X".
            // If we don't have a list of valid locals for this function, we can't be 100% sure.
            // BUT: TACKYGenerator generates unique names for locals if needed (we aren't doing that fully yet for user vars though).
            // Actually, TACKYGenerator should probably verify variables.
            
            // Wait, standard practice in simple compilers:
            // If the variable is NOT a local or parameter, it is a global.
            // We need the list of locals/params?
            // OR: We treat everything as local unless we find it in a global table?
            // But we don't have access to the global table inside generateFunction unless we pass it.
            
            // Simpler Hack for now:
            // We assume that if `replacePseudoregisters` is called, it should map ALL locals.
            // If we encounter a name that we haven't seen before... is it a new local being defined? 
            // Or a global being referenced?
            // In assembly generation, we allocate stack slots for ALL pseudoregisters we encounter.
            // If we want to support globals, we must NOT turn them into stack slots.
            
            // We need to know which names are Globals.
            // Let's pass 'globalNames' into this function or context.
            // For now, let's just cheat: we won't allocate stack slots for things that look like globals?
            // No, user variables look just like globals.
            
            // Correction: We need to change TackyValue to .global(String) to make it explicit.
            // Let's update TACKY.swift and TACKYGenerator.swift to use .global for globals.
            
             let offset = nextStackOffset
             mapping[name] = offset
             nextStackOffset -= 4 // Allocate next slot
             return .stackOffset(offset)
        }

        for inst in instructions {
            // Map operands in all instructions that use them
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
                
            // Instructions that don't need operand mapping or mapping inside operand wrapper
            case .pushq(let op):
                 newInstructions.append(.pushq(mapOperand(op)))
            case .popq(let op):
                 newInstructions.append(.popq(mapOperand(op)))
            case .movq(let src, let dest):
                 newInstructions.append(.movq(mapOperand(src), mapOperand(dest)))
            case .subq(let src, let dest):
                 newInstructions.append(.subq(mapOperand(src), mapOperand(dest)))
                 
            default:
                newInstructions.append(inst)
            }
        }
        
        let stackSize = (nextStackOffset + 4) * -1
        return (newInstructions, stackSize)
    }
    
    // --- Pass 3: Fix Up Illegal Instructions ---
    private func fixUpInstructions(_ instructions: [AsmInstruction]) -> [AsmInstruction] {
        var finalInstructions: [AsmInstruction] = []
        
        // Helper to check if operand is memory (Stack or Global Label)
        func isMemory(_ op: AsmOperand) -> Bool {
            if case .stackOffset = op { return true }
            if case .dataLabel = op { return true }
            return false
        }
        
        for inst in instructions {
            switch inst {
            // movl mem, mem is illegal.
            case .movl(let src, let dest):
                if isMemory(src) && isMemory(dest) {
                    finalInstructions.append(.movl(src, .register(.r10d)))
                    finalInstructions.append(.movl(.register(.r10d), dest))
                } else {
                    finalInstructions.append(inst)
                }

            // cmpl mem, mem is illegal. Dest cannot be immediate.
            case .cmpl(let src, let dest):
                if isMemory(src) && isMemory(dest) {
                    finalInstructions.append(.movl(src, .register(.r10d)))
                    finalInstructions.append(.cmpl(.register(.r10d), dest))
                } else if case .immediate = dest {
                    finalInstructions.append(.movl(dest, .register(.r10d)))
                    finalInstructions.append(.cmpl(src, .register(.r10d)))
                } else if isMemory(dest) && !isMemory(src) {
                     // cmpl reg/imm, mem is Valid.
                     finalInstructions.append(inst)
                } else {
                    finalInstructions.append(inst)
                }

            // addl mem, mem is illegal
            case .addl(let src, let dest):
                if isMemory(src) && isMemory(dest) {
                    finalInstructions.append(.movl(src, .register(.r10d)))
                    finalInstructions.append(.addl(.register(.r10d), dest))
                } else {
                    finalInstructions.append(inst)
                }

            // subl mem, mem is illegal
            case .subl(let src, let dest):
                 if isMemory(src) && isMemory(dest) {
                    finalInstructions.append(.movl(src, .register(.r10d)))
                    finalInstructions.append(.subl(.register(.r10d), dest))
                } else {
                    finalInstructions.append(inst)
                }

            // imull mem, mem is illegal
            case .imull(let src, let dest):
                 if isMemory(src) && isMemory(dest) {
                    finalInstructions.append(.movl(src, .register(.r10d)))
                    finalInstructions.append(.imull(.register(.r10d), dest))
                } else if isMemory(dest) { 
                    // imull's 2-operand form: dest must be register.
                    finalInstructions.append(.movl(dest, .register(.r10d)))
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
            .ret
        ]
        
        // 1. Insert prologue at the very beginning
        function.instructions.insert(contentsOf: prologue, at: 0)
        
        // 2. Replace all .ret instructions with the epilogue sequence
        // (except if the user wrote unreachable code, but standard returns are replaced)
        var newInstructions: [AsmInstruction] = []
        for inst in function.instructions {
            if inst == .ret {
                newInstructions.append(contentsOf: epilogue)
            } else {
                newInstructions.append(inst)
            }
        }
        function.instructions = newInstructions
    }
}
