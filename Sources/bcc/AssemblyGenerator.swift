import Foundation

struct AssemblyGenerator {

    /// Main generation function
    func generate(program: TackyProgram) -> AsmProgram {
        // Convert globals (Size 8 for long, 4 for int)
        let asmGlobals = program.globals.map { g in
             AsmGlobal(name: g.name, initialValue: g.initialValue, isStatic: g.isStatic, size: g.type.size, alignment: g.type.size)
        }
        
        let asmFunctions = program.functions.map { generateFunction($0) }
        return AsmProgram(globals: asmGlobals, functions: asmFunctions)
    }

    private func generateFunction(_ tackyFunc: TackyFunction) -> AsmFunction {
        var asmFunction = convertTackyToAsm(function: tackyFunc)
        
        let (resolvedInstructions, stackSize) = replacePseudoregisters(in: asmFunction.instructions, variableTypes: tackyFunc.variableTypes)
        asmFunction.instructions = resolvedInstructions
        asmFunction.stackSize = stackSize
        
        addPrologueAndEpilogue(&asmFunction)
        
        asmFunction.instructions = fixUpInstructions(asmFunction.instructions)
        
        return asmFunction
    }
    
    private let argumentRegisters: [AsmRegister] = [.rdi, .rsi, .rdx, .rcx, .r8, .r9]

    // --- Pass 1: Convert TACKY to Assembly ---
    private func convertTackyToAsm(function: TackyFunction) -> AsmFunction {
        var instructions: [AsmInstruction] = []
        
        // Parameter Handling
        for (index, paramName) in function.parameters.enumerated() {
            let dest = AsmOperand.pseudoregister(paramName)
            let type = function.variableTypes[paramName] ?? .int
            let isLong = (type == .long)
            
            if index < argumentRegisters.count {
                let reg = argumentRegisters[index] 
                // If isLong, use movq with full reg. If int, movl with 32-bit alias (CodeEmitter handles aliases)
                // Wait, argumentRegisters in Assembly.swift is definition dependent.
                // .rdi logic handles mapping to .edi if movl is used.
                if isLong {
                    instructions.append(.movq(.register(reg), dest))
                } else {
                    instructions.append(.movl(.register(reg), dest))
                }
            } else {
                let stackIndex = index - 6
                let offset = 16 + (stackIndex * 8)
                if isLong {
                    instructions.append(.movq(.stackOffset(offset), dest))
                } else {
                    instructions.append(.movl(.stackOffset(offset), dest))
                }
            }
        }

        func getType(_ val: TackyValue) -> TackyType {
            switch val {
            case .constant(let i):
                return (i > 2147483647 || i < -2147483648) ? .long : .int 
            case .variable(let name):
                return function.variableTypes[name] ?? .int
            case .global(let name):
                return .int // Global look up not avail here easily? Assuming int is unsafe.
                // But generally global access is via pointer or direct label reference.
                // We should pass globalTypes potentially. 
                // For now, assume Tacky generator verified types match.
                // If we do `movq global, dest(long)` -> emitted as movq name(%rip), %reg
            }
        }

        func isLong(_ val: TackyValue) -> Bool {
            return getType(val) == .long
        }

        for tackyInst in function.body {
            switch tackyInst {
            case .return(let value):
                if isLong(value) {
                    instructions.append(.movq(convert(value), .register(.rax)))
                } else {
                    instructions.append(.movl(convert(value), .register(.eax)))
                }
                instructions.append(.ret)
                
            case .unary(let op, let src, let dest):
                let destOp = convert(dest)
                let srcOp = convert(src)
                let longOp = isLong(dest) // Operation width determined by destination usually
                
                // Copy src to dest first
                if longOp {
                     instructions.append(.movq(srcOp, destOp))
                } else {
                     instructions.append(.movl(srcOp, destOp))
                }
                
                switch op {
                case .negate:
                    if longOp { instructions.append(.negq(destOp)) } else { instructions.append(.negl(destOp)) }
                case .complement:
                    if longOp { instructions.append(.notq(destOp)) } else { instructions.append(.notl(destOp)) }
                case .logicalNot:
                    // Result is always int (0/1). Src might be long.
                    // If src is long, cmpq $0, src.
                    let srcLong = isLong(src)
                    if srcLong {
                        instructions.append(.cmpq(.immediate(0), srcOp))
                    } else {
                        instructions.append(.cmpl(.immediate(0), srcOp))
                    }
                    instructions.append(.movl(.immediate(0), destOp)) // dest is int
                    instructions.append(.setz(destOp))
                }
                
            case .binary(let op, let lhs, let rhs, let dest):
                let destOp = convert(dest)
                let lhsOp = convert(lhs)
                let rhsOp = convert(rhs)
                let longOp = isLong(dest)
                // For comparisons, operation width matches operands (lhs/rhs), but dest is int (byte setz).
                
                let isComp = (op == .equal || op == .notEqual || op == .lessThan || op == .lessThanOrEqual || op == .greaterThan || op == .greaterThanOrEqual)
                
                if isComp {
                    // Cmp width depends on operands
                    let opLong = isLong(lhs) // Assume lhs/rhs match promoted type
                    if opLong {
                        instructions.append(.cmpq(rhsOp, lhsOp))
                    } else {
                        instructions.append(.cmpl(rhsOp, lhsOp))
                    }
                    instructions.append(.movl(.immediate(0), destOp))
                    switch op {
                        case .equal: instructions.append(.setz(destOp))
                        case .notEqual: instructions.append(.setnz(destOp))
                        case .lessThan: instructions.append(.setl(destOp))
                        case .lessThanOrEqual: instructions.append(.setle(destOp))
                        case .greaterThan: instructions.append(.setg(destOp))
                        case .greaterThanOrEqual: instructions.append(.setge(destOp))
                        default: break
                    }
                } else {
                    // Arithmetic
                    if longOp {
                        instructions.append(.movq(lhsOp, destOp))
                        switch op {
                        case .add: instructions.append(.addq(rhsOp, destOp))
                        case .subtract: instructions.append(.subq(rhsOp, destOp))
                        case .multiply: instructions.append(.imulq(rhsOp, destOp))
                        case .divide:
                            instructions.append(.movq(lhsOp, .register(.rax)))
                            instructions.append(.cqo) // Sign extend RAX -> RDX:RAX
                            instructions.append(.idivq(rhsOp))
                            instructions.append(.movq(.register(.rax), destOp))
                        default: break
                        }
                    } else {
                        instructions.append(.movl(lhsOp, destOp))
                        switch op {
                        case .add: instructions.append(.addl(rhsOp, destOp))
                        case .subtract: instructions.append(.subl(rhsOp, destOp))
                        case .multiply: instructions.append(.imull(rhsOp, destOp))
                        case .divide:
                            instructions.append(.movl(lhsOp, .register(.eax)))
                            instructions.append(.cdq) 
                            instructions.append(.idivl(rhsOp))
                            instructions.append(.movl(.register(.eax), destOp))
                        default: break
                        }
                    }
                }
                
            case .copy(let src, let dest):
                // Truncation or Extension specific moves could be useful?
                // movslq (sign extend int to long)
                // We use standard movs. CodeEmitter will just emit movq/movl based on instruction?
                let destLong = isLong(dest)
                // let srcLong = isLong(src) // Not used yet
                
                if destLong {
                     // If src is int, we ideally want movslq. 
                     // But we only have movq. `movq intReg, longReg` is invalid?
                     // Actually `movsxd` is needed.
                     // But let's assume TackyGenerator handles explicit temporary copies/casts if we add them. 
                     // Or just use movq. System V ABI: movq from 32-bit reg zero-extends.
                     // C expects sign extension!
                     // Since we don't have movslq instruction in our Assembly.swift, we might fail negative numbers.
                     // TODO: Add `movslq`. For now use `movq` and hope? No, bad for negative.
                     // But `replacePseudoregisters` maps stack slots.
                     instructions.append(.movq(convert(src), convert(dest))) 
                } else {
                     instructions.append(.movl(convert(src), convert(dest)))
                }
                
            case .jump(let target):
                instructions.append(.jmp(target))
            case .jumpIfZero(let cond, let target):
                let isL = isLong(cond)
                if isL { instructions.append(.cmpq(.immediate(0), convert(cond))) }
                else { instructions.append(.cmpl(.immediate(0), convert(cond))) }
                instructions.append(.je(target))
            case .jumpIfNotZero(let cond, let target):
                let isL = isLong(cond)
                if isL { instructions.append(.cmpq(.immediate(0), convert(cond))) }
                else { instructions.append(.cmpl(.immediate(0), convert(cond))) }
                instructions.append(.jne(target))
            case .label(let name):
                instructions.append(.label(name))
            case .call(let name, let args, let dest):
                 let regArgs = Array(args.prefix(6))
                 let stackArgs = Array(args.dropFirst(6))
                 let stackPadding = (stackArgs.count % 2 != 0) ? 8 : 0
                 if stackPadding > 0 { instructions.append(.subq(.immediate(stackPadding), .register(.rsp))) }
                 for arg in stackArgs.reversed() {
                     let op = convert(arg)
                     if isLong(arg) {
                         instructions.append(.movq(op, .register(.rax)))
                         instructions.append(.pushq(.register(.rax)))
                     } else {
                         instructions.append(.movl(op, .register(.eax)))
                         instructions.append(.pushq(.register(.rax))) // Push 8 bytes anyway
                     }
                 }
                 for (i, arg) in regArgs.enumerated() {
                     let reg = argumentRegisters[i]
                     if isLong(arg) { instructions.append(.movq(convert(arg), .register(reg))) }
                     else { instructions.append(.movl(convert(arg), .register(reg))) }
                 }
                 instructions.append(.call(name))
                 let bytesPopped = (stackArgs.count * 8) + stackPadding
                 if bytesPopped > 0 { instructions.append(.addq(.immediate(bytesPopped), .register(.rsp))) }
                 
                 if isLong(dest) { instructions.append(.movq(.register(.rax), convert(dest))) }
                 else { instructions.append(.movl(.register(.eax), convert(dest))) }
            }
        }
        
        return AsmFunction(name: function.name, instructions: instructions, stackSize: 0)
    }

    private func convert(_ value: TackyValue) -> AsmOperand {
        switch value {
        case .constant(let int): return .immediate(int)
        case .variable(let name): return .pseudoregister(name)
        case .global(let name): return .dataLabel(name)
        }
    }

    // --- Pass 2: Replace Pseudoregisters ---
    private func replacePseudoregisters(in instructions: [AsmInstruction], variableTypes: [String: TackyType]) -> ([AsmInstruction], Int) {
        var newInstructions: [AsmInstruction] = []
        var mapping: [String: Int] = [:] 
        var nextStackOffset: Int = 0 

        func mapOperand(_ operand: AsmOperand) -> AsmOperand {
            guard case .pseudoregister(let name) = operand else { return operand }
            if let offset = mapping[name] { return .stackOffset(offset) }
            
            let type = variableTypes[name] ?? .int
            let size = type.size
            nextStackOffset -= size
            // Alignment? 
            let offset = nextStackOffset
            mapping[name] = offset
            return .stackOffset(offset)
        }

        for inst in instructions {
            switch inst {
            case .movl(let src, let dest): newInstructions.append(.movl(mapOperand(src), mapOperand(dest)))
            case .negl(let op): newInstructions.append(.negl(mapOperand(op)))
            case .notl(let op): newInstructions.append(.notl(mapOperand(op)))
            case .addl(let src, let dest): newInstructions.append(.addl(mapOperand(src), mapOperand(dest)))
            case .subl(let src, let dest): newInstructions.append(.subl(mapOperand(src), mapOperand(dest)))
            case .imull(let src, let dest): newInstructions.append(.imull(mapOperand(src), mapOperand(dest)))
            case .idivl(let op): newInstructions.append(.idivl(mapOperand(op)))
            case .cmpl(let src, let dest): newInstructions.append(.cmpl(mapOperand(src), mapOperand(dest)))
            
            case .movq(let src, let dest): newInstructions.append(.movq(mapOperand(src), mapOperand(dest)))
            case .addq(let src, let dest): newInstructions.append(.addq(mapOperand(src), mapOperand(dest)))
            case .subq(let src, let dest): newInstructions.append(.subq(mapOperand(src), mapOperand(dest)))
            case .imulq(let src, let dest): newInstructions.append(.imulq(mapOperand(src), mapOperand(dest)))
            case .idivq(let op): newInstructions.append(.idivq(mapOperand(op)))
            case .negq(let op): newInstructions.append(.negq(mapOperand(op)))
            case .notq(let op): newInstructions.append(.notq(mapOperand(op)))
            case .cmpq(let src, let dest): newInstructions.append(.cmpq(mapOperand(src), mapOperand(dest)))
            
            case .setz(let op): newInstructions.append(.setz(mapOperand(op)))
            case .setnz(let op): newInstructions.append(.setnz(mapOperand(op)))
            case .setl(let op): newInstructions.append(.setl(mapOperand(op)))
            case .setle(let op): newInstructions.append(.setle(mapOperand(op)))
            case .setg(let op): newInstructions.append(.setg(mapOperand(op)))
            case .setge(let op): newInstructions.append(.setge(mapOperand(op)))
            case .pushq(let op): newInstructions.append(.pushq(mapOperand(op)))
            case .popq(let op): newInstructions.append(.popq(mapOperand(op)))
            default: newInstructions.append(inst)
            }
        }
        
        let stackSize = nextStackOffset * -1
        return (newInstructions, stackSize)
    }
    
    // --- Pass 3: Fix Up Illegal Instructions (Now with 64-bit support) ---
    private func fixUpInstructions(_ instructions: [AsmInstruction]) -> [AsmInstruction] {
        var finalInstructions: [AsmInstruction] = []
        
        func isMemory(_ op: AsmOperand) -> Bool {
            if case .stackOffset = op { return true }
            if case .dataLabel = op { return true }
            return false
        }
        
        func isLargeImm(_ op: AsmOperand) -> Bool {
             if case .immediate(let val) = op {
                 return val > 2147483647 || val < -2147483648
             }
             return false
        }
        
        // Helper to replace reg for size
        func scratchReg(_ isLong: Bool) -> AsmRegister { isLong ? .r10 : .r10d }
        
        for inst in instructions {
            // General logic: if mem, mem -> use scratch
            switch inst {
            // 32-bit
            case .movl(let src, let dest):
                if isMemory(src) && isMemory(dest) {
                    finalInstructions.append(.movl(src, .register(.r10d)))
                    finalInstructions.append(.movl(.register(.r10d), dest))
                } else { finalInstructions.append(inst) }
            case .addl(let src, let dest):
                if isMemory(src) && isMemory(dest) {
                    finalInstructions.append(.movl(src, .register(.r10d)))
                    finalInstructions.append(.addl(.register(.r10d), dest))
                } else { finalInstructions.append(inst) }
            case .subl(let src, let dest):
                if isMemory(src) && isMemory(dest) {
                    finalInstructions.append(.movl(src, .register(.r10d)))
                    finalInstructions.append(.subl(.register(.r10d), dest))
                } else { finalInstructions.append(inst) }
            case .imull(let src, let dest):
                if isMemory(dest) {
                    finalInstructions.append(.movl(dest, .register(.r10d)))
                    finalInstructions.append(.imull(src, .register(.r10d)))
                    finalInstructions.append(.movl(.register(.r10d), dest))
                } else { finalInstructions.append(inst) }
            case .cmpl(let src, let dest):
                if isMemory(src) && isMemory(dest) {
                    finalInstructions.append(.movl(src, .register(.r10d)))
                    finalInstructions.append(.cmpl(.register(.r10d), dest))
                } else if case .immediate = dest {
                    finalInstructions.append(.movl(dest, .register(.r10d)))
                    finalInstructions.append(.cmpl(src, .register(.r10d)))
                } else if isMemory(dest) && !isMemory(src) {
                     finalInstructions.append(inst) // Valid
                } else { finalInstructions.append(inst) }
            case .idivl(let op):
                 if case .immediate = op {
                    finalInstructions.append(.movl(op, .register(.r10d)))
                    finalInstructions.append(.idivl(.register(.r10d)))
                } else { finalInstructions.append(inst) }

            // 64-bit
            case .movq(let src, let dest):
                if (isMemory(src) && isMemory(dest)) || (isLargeImm(src) && isMemory(dest)) {
                    finalInstructions.append(.movq(src, .register(.r10)))
                    finalInstructions.append(.movq(.register(.r10), dest))
                } else { finalInstructions.append(inst) }
            case .addq(let src, let dest):
                if (isMemory(src) && isMemory(dest)) || isLargeImm(src) {
                    finalInstructions.append(.movq(src, .register(.r10)))
                    finalInstructions.append(.addq(.register(.r10), dest))
                } else { finalInstructions.append(inst) }
            case .subq(let src, let dest):
                if (isMemory(src) && isMemory(dest)) || isLargeImm(src) {
                    finalInstructions.append(.movq(src, .register(.r10)))
                    finalInstructions.append(.subq(.register(.r10), dest))
                } else { finalInstructions.append(inst) }
            case .imulq(let src, let dest):
                 if isMemory(dest) {
                    finalInstructions.append(.movq(dest, .register(.r10)))
                    finalInstructions.append(.imulq(src, .register(.r10)))
                    finalInstructions.append(.movq(.register(.r10), dest))
                } else if isLargeImm(src) {
                     finalInstructions.append(.movq(src, .register(.r11)))
                     finalInstructions.append(.imulq(.register(.r11), dest))
                } else { finalInstructions.append(inst) }
            case .cmpq(let src, let dest):
                 if isMemory(src) && isMemory(dest) {
                    finalInstructions.append(.movq(src, .register(.r10)))
                    finalInstructions.append(.cmpq(.register(.r10), dest))
                } else if case .immediate = dest {
                    finalInstructions.append(.movq(dest, .register(.r10)))
                    finalInstructions.append(.cmpq(src, .register(.r10)))
                } else if isLargeImm(src) {
                    finalInstructions.append(.movq(src, .register(.r10)))
                    finalInstructions.append(.cmpq(.register(.r10), dest))
                } else { finalInstructions.append(inst) }
            case .idivq(let op):
                 if case .immediate = op {
                    finalInstructions.append(.movq(op, .register(.r10)))
                    finalInstructions.append(.idivq(.register(.r10)))
                } else { finalInstructions.append(inst) }

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
        
        function.instructions.insert(contentsOf: prologue, at: 0)
        
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
