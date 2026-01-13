import Foundation

enum SemanticError: Error, CustomStringConvertible {
    case breakOutsideLoop
    case continueOutsideLoop
    case undeclaredVariable(String)
    case functionRedefinition(String)
    case undeclaredFunction(String)
    case wrongArgumentCount(function: String, expected: Int, got: Int)
    case variableRedefinition(String)
    case nonConstantInitializer(String)

    var description: String {
        switch self {
        case .breakOutsideLoop: return "Semantic Error: 'break' statement outside of loop"
        case .continueOutsideLoop: return "Semantic Error: 'continue' statement outside of loop"
        case .undeclaredVariable(let name): return "Semantic Error: Variable '\(name)' undeclared"
        case .functionRedefinition(let name): return "Semantic Error: Redefinition of function '\(name)'"
        case .undeclaredFunction(let name): return "Semantic Error: Function '\(name)' undeclared"
        case .wrongArgumentCount(let funcName, let expected, let got):
            return "Semantic Error: Function '\(funcName)' expects \(expected) arguments, got \(got)"
        case .variableRedefinition(let name): return "Semantic Error: Redefinition of global variable '\(name)'"
        case .nonConstantInitializer(let name): return "Semantic Error: Initializer for global '\(name)' is not constant"
        }
    }
}

extension CType {
    var tackyType: TackyType {
        switch self {
        case .int: return .int
        case .long: return .long
        case .unsignedInt: return .uint
        case .unsignedLong: return .ulong
        }
    }
}

struct TACKYGenerator {
    private var tempCounter = 0
    private var labelCounter = 0
    
    // Stack of (continueLabel, breakLabel) for loop resolution
    private var loopStack: [(String, String)] = []
    
    // Map function name to argument count and return type
    private var functionSignatures: [String: (Int, TackyType)] = [:]
    
    private var variableMap: [String: String] = [:]
    private var localStaticMap: [String: String] = [:]
    
    private var declaredVariables: Set<String> = []
    private var globalVariables: Set<String> = []
    
    private var collectedGlobals: [TackyGlobal] = []
    
    private var currentVariableTypes: [String: TackyType] = [:]
    private var globalTypes: [String: TackyType] = [:]

    private mutating func makeTemporary(type: TackyType = .int) -> TackyValue {
        let tempName = "tmp.\(tempCounter)"
        tempCounter += 1
        currentVariableTypes[tempName] = type
        return .variable(tempName)
    }

    private mutating func makeLabel(suffix: String = "") -> String {
        let label = "L.\(labelCounter)\(suffix)"
        labelCounter += 1
        return label
    }
    
    private mutating func resolveVariable(name: String) throws -> TackyValue {
        if let staticName = localStaticMap[name] {
            return .global(staticName)
        }
        if declaredVariables.contains(name) {
            return .variable(name)
        }
        if globalVariables.contains(name) {
            return .global(name)
        }
        throw SemanticError.undeclaredVariable(name)
    }
    
    private func getType(of value: TackyValue) -> TackyType {
        switch value {
        case .constant(let i):
            // Simple heuristic to distinguish int vs long constants by value logic 
            // Better logic relies on AST types, but TackyValue lossy.
            if i > 2147483647 || i < -2147483648 {
                return .long
            }
            return .int
        case .variable(let name):
            return currentVariableTypes[name] ?? .int
        case .global(let name):
            return globalTypes[name] ?? .int
        }
    }

    mutating func generate(program: Program) throws -> TackyProgram {
        var tackyFunctions: [TackyFunction] = []
        collectedGlobals = []
        globalTypes.removeAll()
        
        functionSignatures.removeAll()
        globalVariables.removeAll()
        
        for item in program.items {
            switch item {
            case .function(let function):
                if functionSignatures[function.name] != nil || globalVariables.contains(function.name) {
                     throw SemanticError.functionRedefinition(function.name)
                }
                functionSignatures[function.name] = (function.parameters.count, function.returnType.tackyType)
                tackyFunctions.append(try generate(function: function))
                
            case .variable(let decl):
                if functionSignatures[decl.name] != nil || globalVariables.contains(decl.name) {
                     throw SemanticError.variableRedefinition(decl.name)
                }
                
                let initVal: Int?
                if let expr = decl.initializer {
                    initVal = try evaluateConstant(expr, contextName: decl.name)
                } else {
                    initVal = nil
                }
                
                let tType = decl.type.tackyType
                globalVariables.insert(decl.name)
                globalTypes[decl.name] = tType
                collectedGlobals.append(TackyGlobal(name: decl.name, type: tType, initialValue: initVal, isStatic: decl.isStatic))
            }
        }
        
        return TackyProgram(globals: collectedGlobals, functions: tackyFunctions)
    }
    
    private func evaluateConstant(_ expr: Expression, contextName: String) throws -> Int {
        switch expr {
        case .constant(let val):
            return val
        case .unary(let op, let subExpr):
            let val = try evaluateConstant(subExpr, contextName: contextName)
            switch op {
            case .negate: return -val
            case .complement: return ~val
            case .logicalNot: return (val == 0) ? 1 : 0
            }
        case .binary(let op, let lhs, let rhs):
            let lVal = try evaluateConstant(lhs, contextName: contextName)
            let rVal = try evaluateConstant(rhs, contextName: contextName)
            switch op {
            case .add: return lVal + rVal
            case .subtract: return lVal - rVal
            case .multiply: return lVal * rVal
            case .divide: return (rVal == 0) ? 0 : (lVal / rVal) 
            case .equal: return (lVal == rVal) ? 1 : 0
            case .notEqual: return (lVal != rVal) ? 1 : 0
            case .lessThan: return (lVal < rVal) ? 1 : 0
            case .lessThanOrEqual: return (lVal <= rVal) ? 1 : 0
            case .greaterThan: return (lVal > rVal) ? 1 : 0
            case .greaterThanOrEqual: return (lVal >= rVal) ? 1 : 0
            case .logicalAnd: return ((lVal != 0) && (rVal != 0)) ? 1 : 0
            case .logicalOr: return ((lVal != 0) || (rVal != 0)) ? 1 : 0
            }
        case .conditional(let cond, let thenExpr, let elseExpr):
            let condVal = try evaluateConstant(cond, contextName: contextName)
            if condVal != 0 {
                return try evaluateConstant(thenExpr, contextName: contextName)
            } else {
                return try evaluateConstant(elseExpr, contextName: contextName)
            }
        default:
             throw SemanticError.nonConstantInitializer(contextName)
        }
    }

    private mutating func generate(function: FunctionDeclaration) throws -> TackyFunction {
        var instructions: [TackyInstruction] = []
        
        variableMap.removeAll() 
        localStaticMap.removeAll()
        declaredVariables.removeAll()
        currentVariableTypes.removeAll()
        
        // Add parameters
        for i in 0..<function.parameters.count {
            let paramName = function.parameters[i]
            let paramType = function.parameterTypes.indices.contains(i) ? function.parameterTypes[i] : .int
            declaredVariables.insert(paramName)
            currentVariableTypes[paramName] = paramType.tackyType
        }
        
        try generate(statement: function.body, into: &instructions)
        
        instructions.append(.return(.constant(0)))
        
        return TackyFunction(name: function.name, parameters: function.parameters, variableTypes: currentVariableTypes, body: instructions)
    }

    private mutating func generate(blockItem: BlockItem, into instructions: inout [TackyInstruction]) throws {
        switch blockItem {
        case .statement(let stmt):
            try generate(statement: stmt, into: &instructions)
        case .declaration(let decl):
            let tType = decl.type.tackyType
            if decl.isStatic {
                let uniqueName = "\(decl.name).\(labelCounter)_static" // e.g. x.0_static
                _ = makeLabel() 
                
                let initVal: Int?
                if let expr = decl.initializer {
                    initVal = try evaluateConstant(expr, contextName: decl.name)
                } else {
                    initVal = nil 
                }
                
                collectedGlobals.append(TackyGlobal(name: uniqueName, type: tType, initialValue: initVal, isStatic: true))
                globalTypes[uniqueName] = tType
                localStaticMap[decl.name] = uniqueName
            
            } else {
                declaredVariables.insert(decl.name)
                currentVariableTypes[decl.name] = tType
                if let initExpr = decl.initializer {
                    let initVal = try generate(expression: initExpr, into: &instructions)
                    instructions.append(.copy(src: initVal, dest: .variable(decl.name)))
                }
            }
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
            
            instructions.append(.jumpIfZero(condition: condVal, target: elseStmt != nil ? elseLabel : endLabel))
            
            try generate(statement: thenStmt, into: &instructions)
            if elseStmt != nil {
                 instructions.append(.jump(target: endLabel)) 
            }
            
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
            let continueLabel = makeLabel(suffix: "_do_continue") 
            let breakLabel = makeLabel(suffix: "_do_break")
            
            loopStack.append((continueLabel, breakLabel))
            
            instructions.append(.label(startLabel))
            try generate(statement: body, into: &instructions)
            
            instructions.append(.label(continueLabel))
            let condVal = try generate(expression: cond, into: &instructions)
            instructions.append(.jumpIfNotZero(condition: condVal, target: startLabel))
            
            instructions.append(.label(breakLabel))
            loopStack.removeLast()
            
        case .while(let cond, let body):
            let continueLabel = makeLabel(suffix: "_while_continue")
            let breakLabel = makeLabel(suffix: "_while_break")
            
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
            
            if let cond = cond {
                let condVal = try generate(expression: cond, into: &instructions)
                instructions.append(.jumpIfZero(condition: condVal, target: breakLabel))
            }
            
            try generate(statement: body, into: &instructions)
            
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
             return try resolveVariable(name: name)
            
        case .conditional(let cond, let thenExpr, let elseExpr):
            let condVal = try generate(expression: cond, into: &instructions)
            let result = makeTemporary(type: .long) // Use long to be safe, implicit cast via copy
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
            guard let (expectedCount, returnType) = functionSignatures[name] else {
                throw SemanticError.undeclaredFunction(name)
            }
            
            if args.count != expectedCount {
                throw SemanticError.wrongArgumentCount(function: name, expected: expectedCount, got: args.count)
            }
            
            var argValues: [TackyValue] = []
            for arg in args {
                argValues.append(try generate(expression: arg, into: &instructions))
            }
            
            let dest = makeTemporary(type: returnType)
            instructions.append(.call(name: name, args: argValues, dest: dest))
            return dest

        case .assignment(let name, let expr):
            let val = try generate(expression: expr, into: &instructions)
            let dest = try resolveVariable(name: name)
            instructions.append(.copy(src: val, dest: dest))
            return dest

        case .unary(let op, let innerExpression):
            let sourceValue = try generate(expression: innerExpression, into: &instructions)
            let type = getType(of: sourceValue)
            var resultType = type
            
            let tackyOp: TackyUnaryOperator
            switch op {
                case .negate: tackyOp = .negate
                case .complement: tackyOp = .complement
                case .logicalNot: 
                    tackyOp = .logicalNot
                    resultType = .int
            }

            let destValue = makeTemporary(type: resultType)
            instructions.append(.unary(op: tackyOp, src: sourceValue, dest: destValue))
            return destValue

        case .binary(let op, let lhsExp, let rhsExp):
            if op == .logicalAnd || op == .logicalOr {
                 // Logical always returns int
                 let dest = makeTemporary(type: .int)
                 let endLabel = makeLabel(suffix: "_end")
                 
                 if op == .logicalAnd {
                    let falseLabel = makeLabel(suffix: "_false")
                    let lhs = try generate(expression: lhsExp, into: &instructions)
                    instructions.append(.jumpIfZero(condition: lhs, target: falseLabel))
                    let rhs = try generate(expression: rhsExp, into: &instructions)
                    instructions.append(.jumpIfZero(condition: rhs, target: falseLabel))
                    instructions.append(.copy(src: .constant(1), dest: dest))
                    instructions.append(.jump(target: endLabel))
                    instructions.append(.label(falseLabel))
                    instructions.append(.copy(src: .constant(0), dest: dest))
                 } else { // Or
                    let trueLabel = makeLabel(suffix: "_true")
                    let lhs = try generate(expression: lhsExp, into: &instructions)
                    instructions.append(.jumpIfNotZero(condition: lhs, target: trueLabel))
                    let rhs = try generate(expression: rhsExp, into: &instructions)
                    instructions.append(.jumpIfNotZero(condition: rhs, target: trueLabel))
                    instructions.append(.copy(src: .constant(0), dest: dest))
                    instructions.append(.jump(target: endLabel))
                    instructions.append(.label(trueLabel))
                    instructions.append(.copy(src: .constant(1), dest: dest))
                 }
                 instructions.append(.label(endLabel))
                 return dest
            }
        
            let lhs = try generate(expression: lhsExp, into: &instructions)
            let rhs = try generate(expression: rhsExp, into: &instructions)
            
            let lType = getType(of: lhs)
            let rType = getType(of: rhs)
            
            var finalL = lhs
            var finalR = rhs
            let resultType: TackyType
            
            // Type Promotion Logic
            // Hierarchy: ulong > long > uint > int
            // (Note: C Standard says if long can hold all uint, use long (signed). LP64: long is 64, uint is 32. So long > uint.)
            
            var commonType: TackyType = .int
            
            if lType == .ulong || rType == .ulong {
                commonType = .ulong
            } else if lType == .long || rType == .long {
                // If one is long and other is uint:
                // long size (8) > uint size (4). So convert uint to long.
                commonType = .long
            } else if lType == .uint || rType == .uint {
                commonType = .uint
            } else {
                commonType = .int
            }
            
            resultType = commonType
            
            // Cast operands via copy (which creates movs/movz in backend ideally)
            // Currently .copy assumes sign extension for int->long? We need explicit zero extension?
            // Backend `isLong(src)` vs `isLong(dest)`.
            // We might need explicit cast instructions in TACKY if copy semantics are ambiguous. 
            
            if lType != commonType {
                let tmp = makeTemporary(type: commonType)
                // For uint -> long, we need zero extension.
                // For int -> long, we need sign extension.
                // Our backend 'copy' treats everything as movq/movl based on DEST size.
                // If movq src(32), dest(64):
                //   If src is 'int' (signed 32), we want movsxd (sign extend).
                //   If src is 'uint' (unsigned 32), we want mov (zero extend).
                // Current backend just calls 'movslq' or similar? NO it calls `movq`.
                // If strictness required, we'll need backend support.
                // Assuming backend handles it or we fix it later.
                instructions.append(.copy(src: lhs, dest: tmp))
                finalL = tmp
            }
            if rType != commonType {
                let tmp = makeTemporary(type: commonType)
                instructions.append(.copy(src: rhs, dest: tmp))
                finalR = tmp
            }

            let tackyOp: TackyBinaryOperator
            var isComparison = false
            let isUnsignedOp = (commonType == .uint || commonType == .ulong)

            switch op {
                case .add: tackyOp = .add
                case .subtract: tackyOp = .subtract
                case .multiply: tackyOp = .multiply
                case .divide: tackyOp = isUnsignedOp ? .divideU : .divide
                case .equal: tackyOp = .equal; isComparison = true
                case .notEqual: tackyOp = .notEqual; isComparison = true
                case .lessThan: tackyOp = isUnsignedOp ? .lessThanU : .lessThan; isComparison = true
                case .lessThanOrEqual: tackyOp = isUnsignedOp ? .lessThanOrEqualU : .lessThanOrEqual; isComparison = true
                case .greaterThan: tackyOp = isUnsignedOp ? .greaterThanU : .greaterThan; isComparison = true
                case .greaterThanOrEqual: tackyOp = isUnsignedOp ? .greaterThanOrEqualU : .greaterThanOrEqual; isComparison = true
                default: fatalError("Unreach")
            }

            // Comparison always results in int
            let dest = makeTemporary(type: isComparison ? .int : resultType)
            instructions.append(.binary(op: tackyOp, lhs: finalL, rhs: finalR, dest: dest))
            return dest
        }
    }
}
