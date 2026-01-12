import Foundation

struct TACKYGenerator {
    private var tempCounter = 0
    private var labelCounter = 0
    
    // Map from original variable name to current unique TACKY variable name
    // e.g. "x" -> "x.0"
    private var variableMap: [String: String] = [:]

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
    
    // Rename user variable to unique TACKY variable to handle shadowing later
    // For now we just use the name directly or append an index if we want SSA-like behavior,
    // but basic stack allocation doesn't require SSA. 
    // However, to distinguish separate variables with same name in different scopes (if we had them),
    // we should map them. For Stage 5 (Function scope), just name is fine? 
    // Actually, TACKY usually assumes unique names for all variables.
    // Let's generate "var.name.count"
    private mutating func resolveVariable(name: String) -> String {
        // For Stage 5, we assume variables are declared once per function (no nested scopes yet in Parser)
        // But to be safe and future proof, let's just use the name.
        // Wait, 'variableMap' is needed if we want to support shadowing.
        // If we just use the name "x", and we have "int x" inside a loop later, it clashes.
        // Let's stick to using the user name for now as we don't have nested blocks implemented yet.
        return name
    }

    mutating func generate(program: Program) -> TackyProgram {
        let tackyFunction = generate(function: program.function)
        return TackyProgram(function: tackyFunction)
    }

    private mutating func generate(function: FunctionDeclaration) -> TackyFunction {
        var instructions: [TackyInstruction] = []
        
        // Reset state for new function
        variableMap.removeAll() 
        
        for item in function.body {
            generate(blockItem: item, into: &instructions)
        }
        
        // Add a default return 0 if main? Or just return 0. 
        // C standard says main returns 0 if no return, but let's rely on user valid code for now.
        // Or append a return 0 just in case.
        instructions.append(.return(.constant(0)))
        
        return TackyFunction(name: function.name, body: instructions)
    }

    private mutating func generate(blockItem: BlockItem, into instructions: inout [TackyInstruction]) {
        switch blockItem {
        case .statement(let stmt):
            generate(statement: stmt, into: &instructions)
        case .declaration(let decl):
            if let initExpr = decl.initializer {
                let initVal = generate(expression: initExpr, into: &instructions)
                instructions.append(.copy(src: initVal, dest: .variable(decl.name)))
            } else {
                // Uninitialized int. Optionally zero it, or leave it. 
                // C doesn't initialize local variables.
            }
        }
    }

    private mutating func generate(statement: Statement, into instructions: inout [TackyInstruction]) {
        switch statement {
            case .return(let expression):
                let val = generate(expression: expression, into: &instructions)
                instructions.append(.return(val))
            case .expression(let expression):
                _ = generate(expression: expression, into: &instructions)
            case .compound(let items):
                for item in items {
                    generate(blockItem: item, into: &instructions)
                }
            case .if(let cond, let thenStmt, let elseStmt):
                let condVal = generate(expression: cond, into: &instructions)
                let elseLabel = makeLabel(suffix: "_else")
                let endLabel = makeLabel(suffix: "_end")
                
                // If cond is false (0), jump to else (or end if no else)
                instructions.append(.jumpIfZero(condition: condVal, target: elseStmt != nil ? elseLabel : endLabel))
                
                // Then block
                generate(statement: thenStmt, into: &instructions)
                if elseStmt != nil {
                     instructions.append(.jump(target: endLabel)) // Skip else block
                }
                
                // Else block
                if let elseStmt = elseStmt {
                    instructions.append(.label(elseLabel))
                    generate(statement: elseStmt, into: &instructions)
                }
                
                instructions.append(.label(endLabel))
        }
    }

    private mutating func generate(expression: Expression, into instructions: inout [TackyInstruction]) -> TackyValue {
        switch expression {
        case .constant(let value):
            return .constant(value)
        
        case .variable(let name):
            return .variable(name)
            
        case .conditional(let cond, let thenExpr, let elseExpr):
            let condVal = generate(expression: cond, into: &instructions)
            let result = makeTemporary()
            let elseLabel = makeLabel(suffix: "_ternary_else")
            let endLabel = makeLabel(suffix: "_ternary_end")
            
            instructions.append(.jumpIfZero(condition: condVal, target: elseLabel))
            
            let thenVal = generate(expression: thenExpr, into: &instructions)
            instructions.append(.copy(src: thenVal, dest: result))
            instructions.append(.jump(target: endLabel))
            
            instructions.append(.label(elseLabel))
            let elseVal = generate(expression: elseExpr, into: &instructions)
            instructions.append(.copy(src: elseVal, dest: result))
            
            instructions.append(.label(endLabel))
            return result

        case .assignment(let name, let expr):
            let val = generate(expression: expr, into: &instructions)
            instructions.append(.copy(src: val, dest: .variable(name)))
            return .variable(name)

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