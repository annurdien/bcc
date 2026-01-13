import Foundation

enum ParserError: Error, CustomStringConvertible {
    case expectedToken(String, found: Token)
    case expectedExpression(found: Token)
    case unexpectedToken(Token)
    case unsupportedUnaryOperator(Token)

    var description: String {
        switch self {
        case .expectedToken(let expected, let found):
            return "Parser Error: Expected \(expected) but found \(found)"
        case .expectedExpression(let found):
            return "Parser Error: Expected an expression but found \(found)"
        case .unexpectedToken(let found):
            return "Parser Error: Unexpected token \(found) at end of file"
        case .unsupportedUnaryOperator(let found):
            return "Parser Error: Unsupported unary operator \(found)"
        }
    }
}

struct Parser {
    let tokens: [Token]
    var currentIndex: Int = 0

    init(tokens: [Token]) {
        self.tokens = tokens
    }

    private func peek() -> Token {
        guard currentIndex < tokens.count else {
            return tokens.last ?? .eof
        }
        return tokens[currentIndex]
    }

    @discardableResult
    private mutating func advance() -> Token {
        let token = peek()
        if token != .eof {
            currentIndex += 1
        }
        return token
    }

    @discardableResult
    private mutating func consume(_ expected: Token) throws -> Token {
        let token = peek()
        if token == expected {
            return advance()
        } else {
            throw ParserError.expectedToken(String(describing: expected), found: token)
        }
    }

    private mutating func parseExpression(minPrecedence: Int = 0) throws -> Expression {
        var lhs = try parseFactor()
        
        while true {
            let token = peek()
            
            // Handle Assignment specially (Right Associative, Precedence 1)
            // Includes Compound Assignments
            if token == .equal || getCompoundAssignmentOperator(token) != nil {
                if 1 < minPrecedence { break }
                
                let isCompound = (token != .equal)
                let compoundOp = isCompound ? getCompoundAssignmentOperator(token) : nil
                
                advance()
                let rhs = try parseExpression(minPrecedence: 1) 
                
                // Allow assignment to variables or dereferenced pointers (lvalues)
                // We'll relax the check here and let later stages or a specific lvalue check handle validity if needed,
                // but strictly speaking, in C, you can only assign to lvalues.
                // For now, let's allow it and support the new AST structure.
                
                if let op = compoundOp {
                    // Desugar x += y to x = x + y
                    let binaryRhs = Expression.binary(op, lhs, rhs)
                    lhs = .assignment(lhs: lhs, rhs: binaryRhs)
                } else {
                    lhs = .assignment(lhs: lhs, rhs: rhs)
                }
                continue
            }
            
            // Handle Ternary Operator (Right Associative, Precedence 3)
            // Lower than || (5), higher than = (1)
            if token == .questionMark {
                if 3 < minPrecedence { break }
                advance()
                let thenExpr = try parseExpression() 
                try consume(.colon)
                let elseExpr = try parseExpression(minPrecedence: 3)
                lhs = .conditional(condition: lhs, thenExpr: thenExpr, elseExpr: elseExpr)
                continue
            }

            let precedence = getPrecedence(token)
            
            if precedence < minPrecedence || precedence == -1 {
                break
            }
            
            guard let op = getBinaryOperator(token) else {
                break
            }
            
            advance() // Consume operator
            let rhs = try parseExpression(minPrecedence: precedence + 1)
            lhs = .binary(op, lhs, rhs)
        }
        
        return lhs
    }

    private func getPrecedence(_ token: Token) -> Int {
        switch token {
        case .star, .slash, .percent:
            return 50
        case .plus, .minus:
            return 45
        case .lessThanLessThan, .greaterThanGreaterThan:
            return 40
        case .lessThan, .lessThanEqual, .greaterThan, .greaterThanEqual:
            return 35
        case .equalEqual, .exclamationEqual:
            return 30
        case .ampersand:
            return 25
        case .caret:
            return 20
        case .pipe:
            return 15
        case .ampersandAmpersand:
            return 10
        case .pipePipe:
            return 5
        default:
            return -1
        }
    }
    
    private func getBinaryOperator(_ token: Token) -> BinaryOperator? {
        switch token {
        case .plus: return .add
        case .minus: return .subtract
        case .star: return .multiply
        case .slash: return .divide
        case .percent: return .remainder
        case .lessThanLessThan: return .shiftLeft
        case .greaterThanGreaterThan: return .shiftRight
        case .lessThan: return .lessThan
        case .lessThanEqual: return .lessThanOrEqual
        case .greaterThan: return .greaterThan
        case .greaterThanEqual: return .greaterThanOrEqual
        case .equalEqual: return .equal
        case .exclamationEqual: return .notEqual
        case .ampersand: return .bitwiseAnd
        case .caret: return .bitwiseXor
        case .pipe: return .bitwiseOr
        case .ampersandAmpersand: return .logicalAnd
        case .pipePipe: return .logicalOr
        default: return nil
        }
    }
    
    private func getCompoundAssignmentOperator(_ token: Token) -> BinaryOperator? {
        switch token {
        case .plusEqual: return .add
        case .minusEqual: return .subtract
        case .starEqual: return .multiply
        case .slashEqual: return .divide
        case .percentEqual: return .remainder
        case .ampersandEqual: return .bitwiseAnd
        case .pipeEqual: return .bitwiseOr
        case .caretEqual: return .bitwiseXor
        case .lessThanLessThanEqual: return .shiftLeft
        case .greaterThanGreaterThanEqual: return .shiftRight
        default: return nil
        }
    }

    private mutating func parseFactor() throws -> Expression {
        let token = peek()
        var left: Expression
        
        switch token {
        case .integerLiteral(let value):
            advance()
            left = .constant(value)

        case .identifier(let name):
            advance()
            if peek() == .openParen {
                try consume(.openParen)
                var args: [Expression] = []
                if peek() != .closeParen {
                    args.append(try parseExpression())
                    while peek() == .comma {
                         advance()
                         args.append(try parseExpression())
                    }
                }
                try consume(.closeParen)
                left = .functionCall(name: name, arguments: args)
            } else {
                left = .variable(name)
            }
            
        case .openParen:
            advance()
            left = try parseExpression()
            try consume(.closeParen)
            
        case .plusPlus:
            advance()
            let inner = try parseFactor()
            if case .variable(let name) = inner {
                return .assignment(lhs: inner, rhs: .binary(.add, inner, .constant(1)))
            } else {
                throw ParserError.expectedExpression(found: token)
            }
        
        case .minusMinus:
            advance()
            let inner = try parseFactor()
            if case .variable(let name) = inner {
                return .assignment(lhs: inner, rhs: .binary(.subtract, inner, .constant(1)))
            } else {
                throw ParserError.expectedExpression(found: token)
            }

        case .minus:
            advance()
            let innerExp = try parseFactor()
            return .unary(.negate, innerExp)
        
        case .tilde:
            advance()
            let innerExp = try parseFactor()
            return .unary(.complement, innerExp)

        case .exclamation:
            advance()
            let innerExp = try parseFactor()
            return .unary(.logicalNot, innerExp)

        case .star:
            advance()
            let innerExp = try parseFactor()
            return .unary(.dereference, innerExp)

        case .ampersand:
            advance()
            let innerExp = try parseFactor()
            return .unary(.addressOf, innerExp)
        
        default:
            throw ParserError.expectedExpression(found: token)
        }
        
        // Postfix operators
        while true {
            let next = peek()
            if next == .plusPlus {
                advance()
                if case .variable = left {
                    left = .unary(.postIncrement, left)
                } else {
                    throw ParserError.expectedExpression(found: next)
                }
            } else if next == .minusMinus {
                advance()
                if case .variable = left {
                    left = .unary(.postDecrement, left)
                } else {
                    throw ParserError.expectedExpression(found: next)
                }
            } else {
                break
            }
        }
        
        return left
    }

    private mutating func parseStatement() throws -> Statement {
        let token = peek()
        if token == .keywordReturn {
            advance()
            let expression = try parseExpression()
            try consume(.semicolon)
            return .return(expression)
        } else if token == .keywordIf {
            advance()
            try consume(.openParen)
            let condition = try parseExpression()
            try consume(.closeParen)
            let thenStmt = try parseStatement()
            var elseStmt: Statement? = nil
            if peek() == .keywordElse {
                advance()
                elseStmt = try parseStatement()
            }
            return .if(condition: condition, then: thenStmt, else: elseStmt)
        } else if token == .openBrace {
            advance()
            var items: [BlockItem] = []
            while peek() != .closeBrace && peek() != .eof {
                items.append(try parseBlockItem())
            }
            try consume(.closeBrace)
            return .compound(items)
        } else if token == .keywordBreak {
            advance()
            try consume(.semicolon)
            return .break
        } else if token == .keywordContinue {
            advance()
            try consume(.semicolon)
            return .continue
        } else if token == .keywordWhile {
            advance()
            try consume(.openParen)
            let condition = try parseExpression()
            try consume(.closeParen)
            let body = try parseStatement()
            return .while(condition: condition, body: body)
        } else if token == .keywordDo {
            advance()
            let body = try parseStatement()
            try consume(.keywordWhile)
            try consume(.openParen)
            let condition = try parseExpression()
            try consume(.closeParen)
            try consume(.semicolon)
            return .doWhile(body: body, condition: condition)
        } else if token == .keywordFor {
            advance()
            try consume(.openParen)
            
            // Init clause (can be declaration or expression or empty)
            let initClause: ForInit
            // Check for type start (int, long, static)
            if peek() == .keywordInt || peek() == .keywordLong || peek() == .keywordStatic {
                initClause = .declaration(try parseDeclaration())
            } else {
                if peek() == .semicolon {
                    initClause = .expression(nil)
                    try consume(.semicolon) // Consumed by the "expression" parsing logic? No, we handle semicolon here.
                    // Wait, if it's expression(nil), we must consume the semicolon explicitly here
                    // If it is expression(expr), parseExpression usually doesn't consume semicolon.
                } else {
                    let expr = try parseExpression()
                    try consume(.semicolon)
                    initClause = .expression(expr)
                }
            }
            
            // Condition clause
            var condition: Expression? = nil
            if peek() != .semicolon {
                condition = try parseExpression()
            }
            try consume(.semicolon)
            
            // Post clause
            var post: Expression? = nil
            if peek() != .closeParen {
                post = try parseExpression()
            }
            try consume(.closeParen)
            
            let body = try parseStatement()
            return .for(initial: initClause, condition: condition, post: post, body: body)
            
        } else {
            let expression = try parseExpression()
            try consume(.semicolon)
            return .expression(expression)
        }
    }
    
    // declaration = ["static"] "int" identifier [ "=" expression ] ";"
    private mutating func parseType() throws -> CType {
        if peek() == .keywordInt {
            advance()
            return .int
        } else if peek() == .keywordLong {
            advance()
            return .long
        } else if peek() == .keywordUnsigned {
            advance()
            if peek() == .keywordInt {
                advance()
                return .unsignedInt
            } else if peek() == .keywordLong {
                advance()
                return .unsignedLong
            }
            return .unsignedInt // Default 'unsigned' is 'unsigned int'
        } else {
             // Fallback for better error
             throw ParserError.expectedToken("type specifier (int, long, unsigned)", found: peek())
        }
    }

    // declaration = ["static"] type identifier [ "=" expression ] ";"
    private mutating func parseDeclaration() throws -> Declaration {
        var isStatic = false
        if peek() == .keywordStatic {
            advance()
            isStatic = true
        }
        
        var type = try parseType()
        
        while peek() == .star {
            advance()
            type = .pointer(type)
        }
        
        guard case .identifier(let name) = peek() else {
            throw ParserError.expectedToken("identifier", found: peek())
        }
        advance()
        
        var initializer: Expression? = nil
        if peek() == .equal {
            advance()
            initializer = try parseExpression()
        }
        
        try consume(.semicolon)
        return Declaration(name: name, type: type, initializer: initializer, isStatic: isStatic)
    }

    private mutating func parseBlockItem() throws -> BlockItem {
        if peek() == .keywordInt || peek() == .keywordLong || peek() == .keywordStatic || peek() == .keywordUnsigned {
            return .declaration(try parseDeclaration())
        } else {
            return .statement(try parseStatement())
        }
    }

    private mutating func parseFunction() throws -> FunctionDeclaration {
        // [static] type name ( ...
        if peek() == .keywordStatic {
             advance()
        }
    
        var returnType = try parseType()
        while peek() == .star {
            advance()
            returnType = .pointer(returnType)
        }

        let nameToken = peek()
        guard case .identifier(let name) = nameToken else {
            throw ParserError.expectedToken("identifier", found: nameToken)
        }
        advance()

        try consume(.openParen)
        
        var parameters: [String] = []
        var parameterTypes: [CType] = []
        if peek() != .closeParen {
            // Handle 'void' specially? int main(void)
            if peek() == .keywordVoid {
                 advance()
                 // If it is void, it must be the only thing
                 if peek() != .closeParen {
                     throw ParserError.expectedToken(")", found: peek())
                 }
            } else {
                 // Parse first parameter
                 var type1 = try parseType()
                 while peek() == .star {
                     advance()
                     type1 = .pointer(type1)
                 }
                 
                 guard case .identifier(let paramName) = peek() else {
                     throw ParserError.expectedToken("identifier", found: peek())
                 }
                 advance()
                 parameters.append(paramName)
                 parameterTypes.append(type1)
                 
                 while peek() == .comma {
                     advance()
                     var typeN = try parseType()
                     while peek() == .star {
                         advance()
                         typeN = .pointer(typeN)
                     }
                     
                     guard case .identifier(let paramNameN) = peek() else {
                         throw ParserError.expectedToken("identifier", found: peek())
                     }
                     advance()
                     parameters.append(paramNameN)
                     parameterTypes.append(typeN)
                 }
            }
        }
        try consume(.closeParen)
        try consume(.openBrace)

        var bodyItems: [BlockItem] = []
        while peek() != .closeBrace && peek() != .eof {
            bodyItems.append(try parseBlockItem())
        }

        try consume(.closeBrace)

        return FunctionDeclaration(name: name, returnType: returnType, parameters: parameters, parameterTypes: parameterTypes, body: .compound(bodyItems))
    }

    mutating func parse() throws -> Program {
        var items: [TopLevelItem] = []
        
        while peek() != .eof {
            // Distinguish between function and variable declaration
            var lookaheadIndex = currentIndex
            
            // Skip 'static'
            if lookaheadIndex < tokens.count && tokens[lookaheadIndex] == .keywordStatic {
                lookaheadIndex += 1
            }
            
            // Skip type
            if lookaheadIndex < tokens.count {
                if tokens[lookaheadIndex] == .keywordInt || tokens[lookaheadIndex] == .keywordLong {
                     lookaheadIndex += 1
                } else if tokens[lookaheadIndex] == .keywordUnsigned {
                     lookaheadIndex += 1
                     if lookaheadIndex < tokens.count && (tokens[lookaheadIndex] == .keywordInt || tokens[lookaheadIndex] == .keywordLong) {
                         lookaheadIndex += 1
                     }
                } else if tokens[lookaheadIndex] == .keywordVoid {
                     lookaheadIndex += 1
                }
            }
            
            // Skip pointers (*)
            while lookaheadIndex < tokens.count && tokens[lookaheadIndex] == .star {
                lookaheadIndex += 1
            }
            
            // Skip identifier
            if lookaheadIndex < tokens.count {
                if case .identifier = tokens[lookaheadIndex] {
                     lookaheadIndex += 1
                }
            }
            
            // Check for '('
            if lookaheadIndex < tokens.count && tokens[lookaheadIndex] == .openParen {
                items.append(.function(try parseFunction()))
            } else {
                items.append(.variable(try parseDeclaration()))
            }
        }

        return Program(items: items)
    }
}
