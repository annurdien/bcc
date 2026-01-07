import Foundation

struct TACKYGenerator {
    private var tempCounter = 0

    private mutating func makeTemporary() -> TackyValue {
        let tempName = "tmp.\(tempCounter)"
        tempCounter += 1
        return .variable(tempName)
    }

    mutating func generate(program: Program) -> TackyProgram {
        let tackyFunction = generate(function: program.function)
        return TackyProgram(function: tackyFunction)
    }

    private mutating func generate(function: FunctionDeclaration) -> TackyFunction {
        var instructions: [TackyInstruction] = []
        let finalValue = generate(statement: function.body, into: &instructions)
        instructions.append(.return(finalValue))
        return TackyFunction(name: function.name, body: instructions)
    }

    private mutating func generate(statement: Statement, into instructions: inout [TackyInstruction]) -> TackyValue {
        switch statement {
            case .return(let expression):
                return generate(expression: expression, into: &instructions)
        }
    }

    private mutating func generate(expression: Expression, into instructions: inout [TackyInstruction]) -> TackyValue {
        switch expression {
        case .constant(let value):
            return .constant(value)
        
        case .unary(let op, let innerExpression):
            let sourceValue = generate(expression: innerExpression, into: &instructions)
            let destValue = makeTemporary()

            let tackyOp: TackyUnaryOperator = switch op {
                case .negate: .negate
                case .complement: .complement
                case .logicalNot: .logicalNot
            }

            instructions.append(.unary(op: tackyOp, src: sourceValue, dest: destValue))
            return destValue
        }
    }
}