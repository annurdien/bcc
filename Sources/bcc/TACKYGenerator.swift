import Foundation

struct TACKYGenerator {
    private var tempCounter = 0
    private var labelCounter = 0

    private mutating func makeTemporary() -> TackyValue {
        let tempName = "tmp.\(tempCounter)"
        tempCounter += 1
        return .variable(tempName)
    }

    private mutating func makeLabel(suffix: String = "") -> String {
        let label = "L.\(labelCounter)\(suffix)"
        labelCounter += 1
        return label
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

        case .binary(let op, let lhsExp, let rhsExp):
            switch op {
            case .logicalAnd:
                let dest = makeTemporary()
                let falseLabel = makeLabel(suffix: "_false")
                let endLabel = makeLabel(suffix: "_end")
                
                // Eval LHS
                let lhs = generate(expression: lhsExp, into: &instructions)
                instructions.append(.jumpIfZero(condition: lhs, target: falseLabel))
                
                // Eval RHS
                let rhs = generate(expression: rhsExp, into: &instructions)
                instructions.append(.jumpIfZero(condition: rhs, target: falseLabel))
                
                // If both true
                instructions.append(.copy(src: .constant(1), dest: dest))
                instructions.append(.jump(target: endLabel))
                
                // If either false
                instructions.append(.label(falseLabel))
                instructions.append(.copy(src: .constant(0), dest: dest))
                
                instructions.append(.label(endLabel))
                return dest
                
            case .logicalOr:
                let dest = makeTemporary()
                let trueLabel = makeLabel(suffix: "_true")
                let endLabel = makeLabel(suffix: "_end")
                
                // Eval LHS
                let lhs = generate(expression: lhsExp, into: &instructions)
                instructions.append(.jumpIfNotZero(condition: lhs, target: trueLabel))
                
                // Eval RHS
                let rhs = generate(expression: rhsExp, into: &instructions)
                instructions.append(.jumpIfNotZero(condition: rhs, target: trueLabel))
                
                // If both false
                instructions.append(.copy(src: .constant(0), dest: dest))
                instructions.append(.jump(target: endLabel))
                
                // If either true
                instructions.append(.label(trueLabel))
                instructions.append(.copy(src: .constant(1), dest: dest))
                
                instructions.append(.label(endLabel))
                return dest
                
            default:
                // Standard binary operators
                let lhs = generate(expression: lhsExp, into: &instructions)
                let rhs = generate(expression: rhsExp, into: &instructions)
                let dest = makeTemporary()

                let tackyOp: TackyBinaryOperator = switch op {
                    case .add: .add
                    case .subtract: .subtract
                    case .multiply: .multiply
                    case .divide: .divide
                    case .equal: .equal
                    case .notEqual: .notEqual
                    case .lessThan: .lessThan
                    case .lessThanOrEqual: .lessThanOrEqual
                    case .greaterThan: .greaterThan
                    case .greaterThanOrEqual: .greaterThanOrEqual
                    case .logicalAnd, .logicalOr:
                         fatalError("Unreachable") // Handled above
                }

                instructions.append(.binary(op: tackyOp, lhs: lhs, rhs: rhs, dest: dest))
                return dest
            }
        }
    }
}