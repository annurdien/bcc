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
    var size: Int {
        switch self {
        case .int, .unsignedInt: return 4
        case .long, .unsignedLong: return 8
        case .pointer: return 8
        }
    }

    var tackyType: TackyType {
        switch self {
        case .int: return .int
        case .long: return .long
        case .unsignedInt: return .uint
        case .unsignedLong: return .ulong
        case .pointer: return .ulong // Pointers are 8 bytes (unsigned long)
        }
    }
}

struct TACKYGenerator {
    private var tempCounter = 0
    private var labelCounter = 0
    
    // Stack of (continueLabel, breakLabel) for loop resolution
    private var loopStack: [(String, String)] = []
    
    // Map function name to argument count and return type
    private var functionSignatures: [String: (Int, CType)] = [:]
    
    private var variableMap: [String: String] = [:]
    private var localStaticMap: [String: String] = [:]
    
    private var declaredVariables: Set<String> = []
    private var globalVariables: Set<String> = []
    
    private var collectedGlobals: [TackyGlobal] = []
    
    private var currentVariableTypes: [String: CType] = [:]
    private var globalTypes: [String: CType] = [:]

    private mutating func makeTemporary(type: CType = .int) -> TackyValue {
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
    
    private func getType(of value: TackyValue) -> CType {
        switch value {
        case .constant(let i):
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
                functionSignatures[function.name] = (function.parameters.count, function.returnType)
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
                
                globalVariables.insert(decl.name)
                globalTypes[decl.name] = decl.type
                collectedGlobals.append(TackyGlobal(name: decl.name, type: decl.type.tackyType, initialValue: initVal, isStatic: decl.isStatic))
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
            case .postIncrement, .postDecrement, .addressOf, .dereference: throw SemanticError.nonConstantInitializer(contextName)
            }
        case .binary(let op, let lhs, let rhs):
            let lVal = try evaluateConstant(lhs, contextName: contextName)
            let rVal = try evaluateConstant(rhs, contextName: contextName)
            switch op {
            case .add: return lVal + rVal
            case .subtract: return lVal - rVal
            case .multiply: return lVal * rVal
            case .divide: return (rVal == 0) ? 0 : (lVal / rVal) 
            case .remainder: return (rVal == 0) ? 0 : (lVal % rVal)
            case .equal: return (lVal == rVal) ? 1 : 0
            case .notEqual: return (lVal != rVal) ? 1 : 0
            case .lessThan: return (lVal < rVal) ? 1 : 0
            case .lessThanOrEqual: return (lVal <= rVal) ? 1 : 0
            case .greaterThan: return (lVal > rVal) ? 1 : 0
            case .greaterThanOrEqual: return (lVal >= rVal) ? 1 : 0
            case .logicalAnd: return ((lVal != 0) && (rVal != 0)) ? 1 : 0
            case .logicalOr: return ((lVal != 0) || (rVal != 0)) ? 1 : 0
            case .bitwiseAnd: return lVal & rVal
            case .bitwiseOr: return lVal | rVal
            case .bitwiseXor: return lVal ^ rVal
            case .shiftLeft: return lVal << rVal
            case .shiftRight: return lVal >> rVal
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
            currentVariableTypes[paramName] = paramType
        }
        
        try generate(statement: function.body, into: &instructions)
        
        instructions.append(.return(.constant(0)))
        
        var tackyVarTypes: [String: TackyType] = [:]
        for (k, v) in currentVariableTypes {
            tackyVarTypes[k] = v.tackyType
        }
        
        return TackyFunction(name: function.name, parameters: function.parameters, variableTypes: tackyVarTypes, body: instructions)
    }

    private mutating func generate(blockItem: BlockItem, into instructions: inout [TackyInstruction]) throws {
        switch blockItem {
        case .statement(let stmt):
            try generate(statement: stmt, into: &instructions)
        case .declaration(let decl):
            let type = decl.type
            if decl.isStatic {
                let uniqueName = "\(decl.name).\(labelCounter)_static" // e.g. x.0_static
                _ = makeLabel() 
                
                let initVal: Int?
                if let expr = decl.initializer {
                    initVal = try evaluateConstant(expr, contextName: decl.name)
                } else {
                    initVal = nil 
                }
                
                collectedGlobals.append(TackyGlobal(name: uniqueName, type: type.tackyType, initialValue: initVal, isStatic: true))
                globalTypes[uniqueName] = type
                localStaticMap[decl.name] = uniqueName
            
            } else {
                declaredVariables.insert(decl.name)
                currentVariableTypes[decl.name] = type
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

        case .assignment(let lhs, let rhs):
            let rVal = try generate(expression: rhs, into: &instructions)
            
            if case .variable(let name) = lhs {
                let dest = try resolveVariable(name: name)
                instructions.append(.copy(src: rVal, dest: dest))
                return dest
            } else if case .unary(let op, let inner) = lhs, op == .dereference {
                let ptr = try generate(expression: inner, into: &instructions)
                instructions.append(.store(srcVal: rVal, dstPtr: ptr))
                return rVal
            }
            fatalError("Invalid assignment lvalue")

        case .unary(let op, let innerExpression):
            if op == .addressOf {
                if case .variable(let name) = innerExpression {
                    let varVal = try resolveVariable(name: name)
                    let dest = makeTemporary(type: .pointer(.int))
                    instructions.append(.getAddress(src: varVal, dest: dest))
                    return dest
                }
                fatalError("AddressOf requires variable")
            }
            if op == .dereference {
                let ptr = try generate(expression: innerExpression, into: &instructions)
                let ptrType = getType(of: ptr)
                guard case .pointer(let pointedType) = ptrType else {
                     fatalError("Dereference requires pointer")
                }
                let dest = makeTemporary(type: pointedType)
                instructions.append(.load(srcPtr: ptr, dest: dest))
                return dest
            }

            let sourceValue = try generate(expression: innerExpression, into: &instructions)
            let type = getType(of: sourceValue)
            var resultType = type
            
            if op == .postIncrement || op == .postDecrement {
                let destValue = makeTemporary(type: type)
                instructions.append(.copy(src: sourceValue, dest: destValue))
                
                let one: TackyValue = .constant(1)
                let tackyOp: TackyBinaryOperator = (op == .postIncrement) ? .add : .subtract
                
                instructions.append(.binary(op: tackyOp, lhs: sourceValue, rhs: one, dest: sourceValue))
                return destValue
            }
            
            let tackyOp: TackyUnaryOperator
            switch op {
                case .negate: tackyOp = .negate
                case .complement: tackyOp = .complement
                case .logicalNot: 
                    tackyOp = .logicalNot
                    resultType = .int
                case .postIncrement, .postDecrement, .addressOf, .dereference: fatalError("Handled above")
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
            
            let lCType = getType(of: lhs)
            let rCType = getType(of: rhs)
            
            // Pointer Arithmetic
            if op == .add || op == .subtract {
                var ptr: TackyValue? = nil
                var idx: TackyValue? = nil
                var pType: CType? = nil
                
                if case .pointer(let pt) = lCType {
                     if case .pointer(let rpt) = rCType {
                         // ptr - ptr
                         if op == .subtract {
                             let size = pt.size
                             let dest = makeTemporary(type: .long) // ptrdiff_t
                             // Sub pointers (ulong subtraction)
                             instructions.append(.binary(op: .subtract, lhs: lhs, rhs: rhs, dest: dest))
                             if size > 1 {
                                 instructions.append(.binary(op: .divide, lhs: dest, rhs: .constant(size), dest: dest))
                             }
                             return dest
                         }
                         // ptr + ptr invalid
                     } else {
                         // ptr +/- int
                         ptr = lhs; idx = rhs; pType = pt
                     }
                } else if case .pointer(let pt) = rCType {
                     // int + ptr (commutative). int - ptr is invalid.
                     if op == .add {
                         ptr = rhs; idx = lhs; pType = pt
                     }
                }
                
                if let ptr = ptr, let idx = idx, let pType = pType {
                    let size = pType.size
                    var finalIdx = idx
                    
                    // Promote index to long (pointer width)
                    // Note: Ideally should sign extend if int. Current Copy might zero extends.
                    let promotedIdx = makeTemporary(type: .long)
                    instructions.append(.copy(src: idx, dest: promotedIdx))
                    finalIdx = promotedIdx
                    
                    if size > 1 {
                        let scaledIdx = makeTemporary(type: .long)
                        instructions.append(.binary(op: .multiply, lhs: finalIdx, rhs: .constant(size), dest: scaledIdx))
                        finalIdx = scaledIdx
                    }
                    
                    let dest = makeTemporary(type: .pointer(pType))
                    instructions.append(.binary(op: op == .add ? .add : .subtract, lhs: ptr, rhs: finalIdx, dest: dest))
                    return dest
                }
            }

            let lType = lCType.tackyType
            let rType = rCType.tackyType
            
            var finalL = lhs
            var finalR = rhs
            let resultType: TackyType
            let tackyOp: TackyBinaryOperator
            var isComparison = false
            
            if op == .shiftLeft || op == .shiftRight {
                resultType = lType
                finalL = lhs
                finalR = rhs
                
                let isUnsignedLeft = (lType == .uint || lType == .ulong)
                if op == .shiftLeft {
                    tackyOp = .shiftLeft
                } else {
                    tackyOp = isUnsignedLeft ? .shiftRightU : .shiftRight
                }
            } else {
                var commonType: TackyType = .int
                
                if lType == .ulong || rType == .ulong {
                    commonType = .ulong
                } else if lType == .long || rType == .long {
                     if (lType == .uint || rType == .uint) {
                         commonType = .long
                     } else {
                         commonType = .long
                     }
                } else if lType == .uint || rType == .uint {
                    commonType = .uint
                } else {
                    commonType = .int
                }
                
                resultType = commonType
                
                func toCType(_ t: TackyType) -> CType {
                    switch t {
                    case .int: return .int
                    case .long: return .long
                    case .uint: return .unsignedInt
                    case .ulong: return .unsignedLong
                    }
                }

                if lType != commonType {
                    let tmp = makeTemporary(type: toCType(commonType))
                    instructions.append(.copy(src: lhs, dest: tmp))
                    finalL = tmp
                }
                if rType != commonType {
                    let tmp = makeTemporary(type: toCType(commonType))
                    instructions.append(.copy(src: rhs, dest: tmp))
                    finalR = tmp
                }
                
                let isUnsignedOp = (commonType == .uint || commonType == .ulong)
                switch op {
                    case .add: tackyOp = .add
                    case .subtract: tackyOp = .subtract
                    case .multiply: tackyOp = .multiply
                    case .divide: tackyOp = isUnsignedOp ? .divideU : .divide
                    case .remainder: tackyOp = isUnsignedOp ? .remainderU : .remainder
                    case .bitwiseAnd: tackyOp = .bitwiseAnd
                    case .bitwiseOr: tackyOp = .bitwiseOr
                    case .bitwiseXor: tackyOp = .bitwiseXor
                    case .equal: tackyOp = .equal; isComparison = true
                    case .notEqual: tackyOp = .notEqual; isComparison = true
                    case .lessThan: tackyOp = isUnsignedOp ? .lessThanU : .lessThan; isComparison = true
                    case .lessThanOrEqual: tackyOp = isUnsignedOp ? .lessThanOrEqualU : .lessThanOrEqual; isComparison = true
                    case .greaterThan: tackyOp = isUnsignedOp ? .greaterThanU : .greaterThan; isComparison = true
                    case .greaterThanOrEqual: tackyOp = isUnsignedOp ? .greaterThanOrEqualU : .greaterThanOrEqual; isComparison = true
                    default: fatalError("Shift handled above")
                }
            }

            let cResultType: CType
            if isComparison {
                cResultType = .int
            } else {
                 switch resultType {
                    case .int: cResultType = .int
                    case .long: cResultType = .long
                    case .uint: cResultType = .unsignedInt
                    case .ulong: cResultType = .unsignedLong
                }
            }
            
            let dest = makeTemporary(type: cResultType)
            instructions.append(.binary(op: tackyOp, lhs: finalL, rhs: finalR, dest: dest))
            return dest
        }
    }
}
