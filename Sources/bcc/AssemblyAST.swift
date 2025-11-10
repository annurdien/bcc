
struct AssemblyAST {    
    func generate(program: Program) -> AsmProgram {
        let asmFunction = generate(function: program.function)
        return AsmProgram(function: asmFunction)
    }
    
    private func generate(function: FunctionDeclaration) -> AsmFunction {
        let instructions = generate(statement: function.body)
        return AsmFunction(name: function.name, instructions: instructions)
    }

    private func generate(statement: Statement) -> [AsmInstruction] {
        switch statement {
        case .return(let expression):
            let sourceOperand = generate(expression: expression)
            let destOperand = AsmOperand.register
            return [
                .mov(sourceOperand, destOperand),
                .ret
            ]
        }
    }

    private func generate(expression: Expression) -> AsmOperand {
        switch expression {
        case .constant(let value):
            return .immediate(value)
        }
    }
}