import Foundation

enum SemanticError: Error, CustomStringConvertible {
    case breakOutsideLoop
    case continueOutsideLoop
    case undeclaredVariable(String)
    case functionRedefinition(String)
    case undeclaredFunction(String)
    case wrongArgumentCount(function: String, expected: Int, got: Int)

    var description: String {
        switch self {
        case .breakOutsideLoop: return "Semantic Error: 'break' statement outside of loop"
        case .continueOutsideLoop: return "Semantic Error: 'continue' statement outside of loop"
        case .undeclaredVariable(let name): return "Semantic Error: Variable '\(name)' undeclared"
        case .functionRedefinition(let name): return "Semantic Error: Redefinition of function '\(name)'"
        case .undeclaredFunction(let name): return "Semantic Error: Function '\(name)' undeclared"
        case .wrongArgumentCount(let funcName, let expected, let got):
            return "Semantic Error: Function '\(funcName)' expects \(expected) arguments, got \(got)"
        }
    }
}

struct TACKYGenerator {
    private var tempCounter = 0
    private var labelCounter = 0
    
    // Stack of (continueLabel, breakLabel) for loop resolution
    private var loopStack: [(String, String)] = []
    
    // Map function name to argument count
    private var functionSignatures: [String: Int] = [:]
    
    // Map from original variable name to current unique TACKY variable name
    // e.g. "x" -> "x.0"
    private var variableMap: [String: String] = [:]
    
    private var declaredVariables: Set<String> = []

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
    // For now we just use the name directly
    private mutating func resolveVariable(name: String) throws -> String {
        guard declaredVariables.contains(name) else {
            throw SemanticError.undeclaredVariable(name)
        }
        return name
    }

    mutating func generate(program: Program) throws -> TackyProgram {
        var tackyFunctions: [TackyFunction] = []
        functionSignatures.removeAll()
        
        for function in program.functions {
            if functionSignatures[function.name] != nil {
                throw SemanticError.functionRedefinition(function.name)
            }
            functionSignatures[function.name] = function.parameters.count
            tackyFunctions.append(try generate(function: function))
        }
        
        return TackyProgram(functions: tackyFunctions)
    }

    private mutating func generate(function: FunctionDeclaration) throws -> TackyFunction {
        var instructions: [TackyInstruction] = []
        
        // Reset state for new function
        variableMap.removeAll() 
        declaredVariables.removeAll()
        
        // Add parameters to declared variables
        for param in function.parameters {
            declaredVariables.insert(param)
        }
        
        try generate(statement: function.body, into: &instructions)
        
        // Add a default return 0 just in case (e.g. implicitly at end of void/int func)
        instructions.append(.return(.constant(0)))
        
        return TackyFunction(name: function.name, parameters: function.parameters, body: instructions)
    }

    private mutating func generate(blockItem: BlockItem, into instructions: inout [TackyInstruction]) throws {
        switch blockItem {
        case .statement(let stmt):
            try generate(statement: stmt, into: &instructions)
        case .declaration(let decl):
            if let initExpr = decl.initializer {
                let initVal = try generate(expression: initExpr, into: &instructions)
                instructions.append(.copy(src: initVal, dest: .variable(decl.name)))
            } else {
                // Uninitialized int.
            }
            declaredVariables.insert(decl.name)
        }
    }

    private mutating func generate(statement: Statement, into instructions: inout [TackyInstruction]) throws {
        switch statement {
        case .return(let expression):
            let val = try generate(expression: expression, into: &instructions)
            instructions.append(.return(val))
        
        case .expression(let expression):
            _ = try generate(expression: expression, into: &instructions)
            
        case .compound(let items):
            for item in items {
                try generate(blockItem: item, into: &instructions)
            }
            
        case .if(let cond, let thenStmt, let elseStmt):
            let condVal = try generate(expression: cond, into: &instructions)
            let elseLabel = makeLabel(suffix: "_else")
            let endLabel = makeLabel(suffix: "_end")
            
            // If cond is false (0), jump to else (or end if no else)
            instructions.append(.jumpIfZero(condition: condVal, target: elseStmt != nil ? elseLabel : endLabel))
            
            // Then block
            try generate(statement: thenStmt, into: &instructions)
            if elseStmt != nil {
                 instructions.append(.jump(target: endLabel)) // Skip else block
            }
            
            // Else block
            if let elseStmt = elseStmt {
                instructions.append(.label(elseLabel))
                try generate(statement: elseStmt, into: &instructions)
            }
            
            instructions.append(.label(endLabel))
            
        case .break:
            guard let (_, breakLabel) = loopStack.last else {
                 throw SemanticError.breakOutsideLoop
            }
            instructions.append(.jump(target: breakLabel))
            
        case .continue:
            guard let (continueLabel, _) = loopStack.last else {
                 throw SemanticError.continueOutsideLoop
            }
            instructions.append(.jump(target: continueLabel))
            
        case .doWhile(let body, let cond):
            let startLabel = makeLabel(suffix: "_do_start")
            let continueLabel = makeLabel(suffix: "_do_continue") // used for 'continue'
            let breakLabel = makeLabel(suffix: "_do_break")
            
            loopStack.append((continueLabel, breakLabel))
            
            instructions.append(.label(startLabel))
            try generate(statement: body, into: &instructions)
            
            instructions.append(.label(continueLabel))
            let condVal = try generate(expression: cond, into: &instructions)
            // If true, jump back to start
            instructions.append(.jumpIfNotZero(condition: condVal, target: startLabel))
            
            instructions.append(.label(breakLabel))
            loopStack.removeLast()
            
        case .while(let cond, let body):
            let continueLabel = makeLabel(suffix: "_while_continue")
            let breakLabel = makeLabel(suffix: "_while_break")
            // startLabel not strictly needed if we jump to continueLabel then eval cond
            // But typical while: 
            // label_continue:
            //   if (!cond) goto label_break
            //   body
            //   goto label_continue
            // label_break:
            
            loopStack.append((continueLabel, breakLabel))
            
            instructions.append(.label(continueLabel)) 
            
            let condVal = try generate(expression: cond, into: &instructions)
            instructions.append(.jumpIfZero(condition: condVal, target: breakLabel))
            
            try generate(statement: body, into: &instructions)
            instructions.append(.jump(target: continueLabel))
            
            instructions.append(.label(breakLabel))
            loopStack.removeLast()
            
        case .for(let initClause, let cond, let post, let body):
            let startLabel = makeLabel(suffix: "_for_start")
            let continueLabel = makeLabel(suffix: "_for_continue")
            let breakLabel = makeLabel(suffix: "_for_break")
            
            // 1. Initialization
            switch initClause {
            case .declaration(let decl):
                try generate(blockItem: .declaration(decl), into: &instructions)
            case .expression(let expr):
                if let expr = expr {
                     _ = try generate(expression: expr, into: &instructions)
                }
            }
            
            loopStack.append((continueLabel, breakLabel))
            
            instructions.append(.label(startLabel))
            
            // 2. Condition
            if let cond = cond {
                let condVal = try generate(expression: cond, into: &instructions)
                instructions.append(.jumpIfZero(condition: condVal, target: breakLabel))
            }
            
            // 3. Body
            try generate(statement: body, into: &instructions)
            
            // 4. Continue target (Post-expression)
            instructions.append(.label(continueLabel))
            if let post = post {
                _ = try generate(expression: post, into: &instructions)
            }
            instructions.append(.jump(target: startLabel))
            
            instructions.append(.label(breakLabel))
            loopStack.removeLast()
        }
    }

    private mutating func generate(expression: Expression, into instructions: inout [TackyInstruction]) throws -> TackyValue {
        switch expression {
        case .constant(let value):
            return .constant(value)
        
        case .variable(let name):
             let varName = try resolveVariable(name: name)
             return .variable(varName)
            
        case .conditional(let cond, let thenExpr, let elseExpr):
            let condVal = try generate(expression: cond, into: &instructions)
            let result = makeTemporary()
            let elseLabel = makeLabel(suffix: "_ternary_else")
            let endLabel = makeLabel(suffix: "_ternary_end")
            
            instructions.append(.jumpIfZero(condition: condVal, target: elseLabel))
            
            let thenVal = try generate(expression: thenExpr, into: &instructions)
            instructions.append(.copy(src: thenVal, dest: result))
            instructions.append(.jump(target: endLabel))
            
            instructions.append(.label(elseLabel))
            let elseVal = try generate(expression: elseExpr, into: &instructions)
            instructions.append(.copy(src: elseVal, dest: result))
            
            instructions.append(.label(endLabel))
            return result
        
        case .functionCall(let name, let args):
            guard let expectedCount = functionSignatures[name] else {
                throw SemanticError.undeclaredFunction(name)
            }
            
            if args.count != expectedCount {
                throw SemanticError.wrongArgumentCount(function: name, expected: expectedCount, got: args.count)
            }
            
            var argValues: [TackyValue] = []
            for arg in args {
                argValues.append(try generate(expression: arg, into: &instructions))
            }
            
            let dest = makeTemporary()
            instructions.append(.call(name: name, args: argValues, dest: dest))
            return dest

        case .assignment(let name, let expr):
            let val = try generate(expression: expr, into: &instructions)
            let varName = try resolveVariable(name: name)
            instructions.append(.copy(src: val, dest: .variable(varName)))
            return .variable(varName)

        case .unary(let op, let innerExpression):
            let sourceValue = try generate(expression: innerExpression, into: &instructions)
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
                
                let lhs = try generate(expression: lhsExp, into: &instructions)
                instructions.append(.jumpIfZero(condition: lhs, target: falseLabel))
                
                let rhs = try generate(expression: rhsExp, into: &instructions)
                instructions.append(.jumpIfZero(condition: rhs, target: falseLabel))
                
                instructions.append(.copy(src: .constant(1), dest: dest))
                instructions.append(.jump(target: endLabel))
                
                instructions.append(.label(falseLabel))
                instructions.append(.copy(src: .constant(0), dest: dest))
                
                instructions.append(.label(endLabel))
                return dest
                
            case .logicalOr:
                let dest = makeTemporary()
                let trueLabel = makeLabel(suffix: "_true")
                let endLabel = makeLabel(suffix: "_end")
                
                let lhs = try generate(expression: lhsExp, into: &instructions)
                instructions.append(.jumpIfNotZero(condition: lhs, target: trueLabel))
                
                let rhs = try generate(expression: rhsExp, into: &instructions)
                instructions.append(.jumpIfNotZero(condition: rhs, target: trueLabel))
                
                instructions.append(.copy(src: .constant(0), dest: dest))
                instructions.append(.jump(target: endLabel))
                
                instructions.append(.label(trueLabel))
                instructions.append(.copy(src: .constant(1), dest: dest))
                
                instructions.append(.label(endLabel))
                return dest
                
            default:
                let lhs = try generate(expression: lhsExp, into: &instructions)
                let rhs = try generate(expression: rhsExp, into: &instructions)
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
                         fatalError("Unreachable")
                }

                instructions.append(.binary(op: tackyOp, lhs: lhs, rhs: rhs, dest: dest))
                return dest
            }
        }
    }
}
