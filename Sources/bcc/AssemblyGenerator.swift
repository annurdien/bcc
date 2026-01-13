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
                // We should track global types but for now we rely on destination to infer copy size
                return .int 
            }
        }

        func is64Bit(_ val: TackyValue) -> Bool {
            let t = getType(val)
            return t == .long || t == .ulong
        }
        
        func isUnsigned(_ val: TackyValue) -> Bool {
            let t = getType(val)
            return t == .uint || t == .ulong
        }

        for tackyInst in function.body {
            switch tackyInst {
            case .load(let srcPtr, let dest):
                let destOp = convert(dest)
                let srcOp = convert(srcPtr)
                let is64 = is64Bit(dest)
                
                // Load address into RAX
                instructions.append(.movq(srcOp, .register(.rax)))
                // Load value from (RAX) to dest
                if is64 {
                    if case .register(_) = destOp {
                         instructions.append(.movq(.indirect(.rax), destOp))
                    } else {
                         // Mem to mem invalid. Load to RDX first.
                         instructions.append(.movq(.indirect(.rax), .register(.rdx)))
                         instructions.append(.movq(.register(.rdx), destOp))
                    }
                } else {
                    if case .register(_) = destOp {
                         instructions.append(.movl(.indirect(.rax), destOp))
                    } else {
                         instructions.append(.movl(.indirect(.rax), .register(.edx)))
                         instructions.append(.movl(.register(.edx), destOp))
                    }
                }

            case .store(let srcVal, let dstPtr):
                let valOp = convert(srcVal)
                let ptrOp = convert(dstPtr)
                let is64 = is64Bit(srcVal)
                
                // Load address into RAX
                instructions.append(.movq(ptrOp, .register(.rax)))
                
                // Move value to (RAX)
                if is64 {
                    if case .immediate(_) = valOp {
                        instructions.append(.movq(valOp, .indirect(.rax)))
                    } else if case .register(_) = valOp {
                        instructions.append(.movq(valOp, .indirect(.rax)))
                    } else {
                        // Mem to mem. Load val to RDX.
                        instructions.append(.movq(valOp, .register(.rdx)))
                        instructions.append(.movq(.register(.rdx), .indirect(.rax)))
                    }
                } else {
                    if case .immediate(_) = valOp {
                        instructions.append(.movl(valOp, .indirect(.rax)))
                    } else if case .register(_) = valOp {
                        instructions.append(.movl(valOp, .indirect(.rax)))
                    } else {
                        instructions.append(.movl(valOp, .register(.edx)))
                        instructions.append(.movl(.register(.edx), .indirect(.rax)))
                    }
                }

            case .getAddress(let src, let dest):
                let srcOp = convert(src)
                let destOp = convert(dest)
                
                // Lea src -> RAX
                instructions.append(.leaq(srcOp, .register(.rax)))
                // Mov RAX -> dest
                instructions.append(.movq(.register(.rax), destOp))

            case .return(let value):
                if is64Bit(value) {
                    instructions.append(.movq(convert(value), .register(.rax)))
                } else {
                    instructions.append(.movl(convert(value), .register(.eax)))
                }
                instructions.append(.ret)
                
            case .unary(let op, let src, let dest):
                let destOp = convert(dest)
                let srcOp = convert(src)
                let is64 = is64Bit(dest)
                
                // Copy src to dest first
                if is64 {
                     instructions.append(.movq(srcOp, destOp))
                } else {
                     instructions.append(.movl(srcOp, destOp))
                }
                
                switch op {
                case .negate:
                    if is64 { instructions.append(.negq(destOp)) } else { instructions.append(.negl(destOp)) }
                case .complement:
                    if is64 { instructions.append(.notq(destOp)) } else { instructions.append(.notl(destOp)) }
                case .logicalNot:
                    // Result is always int (0/1). Src might be long.
                    // If src is long, cmpq $0, src.
                    let srcIs64 = is64Bit(src)
                    if srcIs64 {
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
                
                // For comparisons, operation width matches operands (lhs/rhs), but dest is int (byte setz).
                
                let isComp = (op == .equal || op == .notEqual || op == .lessThan || op == .lessThanOrEqual || op == .greaterThan || op == .greaterThanOrEqual || op == .lessThanU || op == .lessThanOrEqualU || op == .greaterThanU || op == .greaterThanOrEqualU)
                
                if isComp {
                    // Cmp width depends on operands
                    let is64 = is64Bit(lhs) // Assume lhs/rhs match promoted type
                    if is64 {
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
                        case .lessThanU: instructions.append(.setb(destOp))
                        case .lessThanOrEqualU: instructions.append(.setbe(destOp))
                        case .greaterThanU: instructions.append(.seta(destOp))
                        case .greaterThanOrEqualU: instructions.append(.setae(destOp))
                        default: break
                    }
                } else {
                    // Arithmetic
                    let is64 = is64Bit(dest)
                    if is64 {
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
                        case .divideU:
                            instructions.append(.movq(lhsOp, .register(.rax)))
                            instructions.append(.movq(.immediate(0), .register(.rdx))) 
                             instructions.append(.divq(rhsOp))
                             instructions.append(.movq(.register(.rax), destOp))
                        case .remainder:
                            instructions.append(.movq(lhsOp, .register(.rax)))
                            instructions.append(.cqo)
                            instructions.append(.idivq(rhsOp))
                            instructions.append(.movq(.register(.rdx), destOp))
                        case .remainderU:
                            instructions.append(.movq(lhsOp, .register(.rax)))
                            instructions.append(.movq(.immediate(0), .register(.rdx)))
                            instructions.append(.divq(rhsOp))
                            instructions.append(.movq(.register(.rdx), destOp))
                        case .bitwiseAnd: instructions.append(.andq(rhsOp, destOp))
                        case .bitwiseOr: instructions.append(.orq(rhsOp, destOp))
                        case .bitwiseXor: instructions.append(.xorq(rhsOp, destOp))
                        case .shiftLeft: 
                             if case .immediate(_) = rhsOp { instructions.append(.salq(rhsOp, destOp)) }
                             else { instructions.append(.movq(rhsOp, .register(.rcx))); instructions.append(.salq(.register(.rcx), destOp)) }
                        case .shiftRight:
                             if case .immediate(_) = rhsOp { instructions.append(.sarq(rhsOp, destOp)) }
                             else { instructions.append(.movq(rhsOp, .register(.rcx))); instructions.append(.sarq(.register(.rcx), destOp)) }
                        case .shiftRightU:
                             if case .immediate(_) = rhsOp { instructions.append(.shrq(rhsOp, destOp)) }
                             else { instructions.append(.movq(rhsOp, .register(.rcx))); instructions.append(.shrq(.register(.rcx), destOp)) }
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
                        case .divideU:
                            instructions.append(.movl(lhsOp, .register(.eax)))
                            instructions.append(.movl(.immediate(0), .register(.rdx))) 
                            instructions.append(.divl(rhsOp))
                            instructions.append(.movl(.register(.eax), destOp))
                        case .remainder:
                            instructions.append(.movl(lhsOp, .register(.eax)))
                            instructions.append(.cdq)
                            instructions.append(.idivl(rhsOp))
                            instructions.append(.movl(.register(.rdx), destOp))
                        case .remainderU:
                            instructions.append(.movl(lhsOp, .register(.eax)))
                            instructions.append(.movl(.immediate(0), .register(.rdx)))
                            instructions.append(.divl(rhsOp))
                            instructions.append(.movl(.register(.rdx), destOp))
                        case .bitwiseAnd: instructions.append(.andl(rhsOp, destOp))
                        case .bitwiseOr: instructions.append(.orl(rhsOp, destOp))
                        case .bitwiseXor: instructions.append(.xorl(rhsOp, destOp))
                        case .shiftLeft:
                             if case .immediate(_) = rhsOp { instructions.append(.sall(rhsOp, destOp)) }
                             else { instructions.append(.movl(rhsOp, .register(.ecx))); instructions.append(.sall(.register(.ecx), destOp)) }
                        case .shiftRight:
                             if case .immediate(_) = rhsOp { instructions.append(.sarl(rhsOp, destOp)) }
                             else { instructions.append(.movl(rhsOp, .register(.ecx))); instructions.append(.sarl(.register(.ecx), destOp)) }
                        case .shiftRightU: // Logical
                             if case .immediate(_) = rhsOp { instructions.append(.shrl(rhsOp, destOp)) }
                             else { instructions.append(.movl(rhsOp, .register(.ecx))); instructions.append(.shrl(.register(.ecx), destOp)) }
                        default: break
                        }
                    }
                }
                
            case .copy(let src, let dest):
                let destIs64 = is64Bit(dest)
                
                if destIs64 {
                     // Potential upgrade: check if src is 32-bit and explicit sign/zero extend.
                     // Currently we rely on movq (which may be buggy if src is 32-bit mem)
                     instructions.append(.movq(convert(src), convert(dest))) 
                } else {
                     instructions.append(.movl(convert(src), convert(dest)))
                }
                
            case .jump(let target):
                instructions.append(.jmp(target))
            case .jumpIfZero(let cond, let target):
                let isL = is64Bit(cond)
                if isL { instructions.append(.cmpq(.immediate(0), convert(cond))) }
                else { instructions.append(.cmpl(.immediate(0), convert(cond))) }
                instructions.append(.je(target))
            case .jumpIfNotZero(let cond, let target):
                let isL = is64Bit(cond)
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
                     if is64Bit(arg) {
                         instructions.append(.movq(op, .register(.rax)))
                         instructions.append(.pushq(.register(.rax)))
                     } else {
                         instructions.append(.movl(op, .register(.eax)))
                         instructions.append(.pushq(.register(.rax))) // Push 8 bytes anyway
                     }
                 }
                 for (i, arg) in regArgs.enumerated() {
                     let reg = argumentRegisters[i]
                     if is64Bit(arg) { instructions.append(.movq(convert(arg), .register(reg))) }
                     else { instructions.append(.movl(convert(arg), .register(reg))) }
                 }
                 instructions.append(.call(name))
                 let bytesPopped = (stackArgs.count * 8) + stackPadding
                 if bytesPopped > 0 { instructions.append(.addq(.immediate(bytesPopped), .register(.rsp))) }
                 
                 if is64Bit(dest) { instructions.append(.movq(.register(.rax), convert(dest))) }
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
            case .divl(let op): newInstructions.append(.divl(mapOperand(op)))
            case .cmpl(let src, let dest): newInstructions.append(.cmpl(mapOperand(src), mapOperand(dest)))
            case .andl(let src, let dest): newInstructions.append(.andl(mapOperand(src), mapOperand(dest)))
            case .orl(let src, let dest): newInstructions.append(.orl(mapOperand(src), mapOperand(dest)))
            case .xorl(let src, let dest): newInstructions.append(.xorl(mapOperand(src), mapOperand(dest)))
            case .sall(let src, let dest): newInstructions.append(.sall(mapOperand(src), mapOperand(dest)))
            case .sarl(let src, let dest): newInstructions.append(.sarl(mapOperand(src), mapOperand(dest)))
            case .shrl(let src, let dest): newInstructions.append(.shrl(mapOperand(src), mapOperand(dest)))
            
            case .movq(let src, let dest): newInstructions.append(.movq(mapOperand(src), mapOperand(dest)))
            case .leaq(let src, let dest): newInstructions.append(.leaq(mapOperand(src), mapOperand(dest)))
            case .addq(let src, let dest): newInstructions.append(.addq(mapOperand(src), mapOperand(dest)))
            case .subq(let src, let dest): newInstructions.append(.subq(mapOperand(src), mapOperand(dest)))
            case .imulq(let src, let dest): newInstructions.append(.imulq(mapOperand(src), mapOperand(dest)))
            case .idivq(let op): newInstructions.append(.idivq(mapOperand(op)))
            case .divq(let op): newInstructions.append(.divq(mapOperand(op)))
            case .negq(let op): newInstructions.append(.negq(mapOperand(op)))
            case .notq(let op): newInstructions.append(.notq(mapOperand(op)))
            case .cmpq(let src, let dest): newInstructions.append(.cmpq(mapOperand(src), mapOperand(dest)))
            case .andq(let src, let dest): newInstructions.append(.andq(mapOperand(src), mapOperand(dest)))
            case .orq(let src, let dest): newInstructions.append(.orq(mapOperand(src), mapOperand(dest)))
            case .xorq(let src, let dest): newInstructions.append(.xorq(mapOperand(src), mapOperand(dest)))
            case .salq(let src, let dest): newInstructions.append(.salq(mapOperand(src), mapOperand(dest)))
            case .sarq(let src, let dest): newInstructions.append(.sarq(mapOperand(src), mapOperand(dest)))
            case .shrq(let src, let dest): newInstructions.append(.shrq(mapOperand(src), mapOperand(dest)))
            
            case .setz(let op): newInstructions.append(.setz(mapOperand(op)))
            case .setnz(let op): newInstructions.append(.setnz(mapOperand(op)))
            case .setl(let op): newInstructions.append(.setl(mapOperand(op)))
            case .setle(let op): newInstructions.append(.setle(mapOperand(op)))
            case .setg(let op): newInstructions.append(.setg(mapOperand(op)))
            case .setge(let op): newInstructions.append(.setge(mapOperand(op)))
            case .setb(let op): newInstructions.append(.setb(mapOperand(op)))
            case .setbe(let op): newInstructions.append(.setbe(mapOperand(op)))
            case .seta(let op): newInstructions.append(.seta(mapOperand(op)))
            case .setae(let op): newInstructions.append(.setae(mapOperand(op)))
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
            case .andl(let src, let dest):
                 if isMemory(src) && isMemory(dest) {
                    finalInstructions.append(.movl(src, .register(.r10d)))
                    finalInstructions.append(.andl(.register(.r10d), dest))
                 } else { finalInstructions.append(inst) }
            case .orl(let src, let dest):
                 if isMemory(src) && isMemory(dest) {
                    finalInstructions.append(.movl(src, .register(.r10d)))
                    finalInstructions.append(.orl(.register(.r10d), dest))
                 } else { finalInstructions.append(inst) }
            case .xorl(let src, let dest):
                 if isMemory(src) && isMemory(dest) {
                    finalInstructions.append(.movl(src, .register(.r10d)))
                    finalInstructions.append(.xorl(.register(.r10d), dest))
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
            case .divl(let op):
                 if case .immediate = op {
                    finalInstructions.append(.movl(op, .register(.r10d)))
                    finalInstructions.append(.divl(.register(.r10d)))
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
            case .andq(let src, let dest):
                if (isMemory(src) && isMemory(dest)) || isLargeImm(src) {
                    finalInstructions.append(.movq(src, .register(.r10)))
                    finalInstructions.append(.andq(.register(.r10), dest))
                } else { finalInstructions.append(inst) }
            case .orq(let src, let dest):
                if (isMemory(src) && isMemory(dest)) || isLargeImm(src) {
                    finalInstructions.append(.movq(src, .register(.r10)))
                    finalInstructions.append(.orq(.register(.r10), dest))
                } else { finalInstructions.append(inst) }
            case .xorq(let src, let dest):
                if (isMemory(src) && isMemory(dest)) || isLargeImm(src) {
                    finalInstructions.append(.movq(src, .register(.r10)))
                    finalInstructions.append(.xorq(.register(.r10), dest))
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
            case .divq(let op):
                 if case .immediate = op {
                    finalInstructions.append(.movq(op, .register(.r10)))
                    finalInstructions.append(.divq(.register(.r10)))
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
