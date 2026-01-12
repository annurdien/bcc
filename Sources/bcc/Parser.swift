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
            if token == .equal {
                if 1 < minPrecedence { break }
                advance()
                let rhs = try parseExpression(minPrecedence: 1) 
                
                if case .variable(let name) = lhs {
                    lhs = .assignment(name: name, expression: rhs)
                    continue
                } else {
                    throw ParserError.expectedExpression(found: token)
                }
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
        case .star, .slash:
            return 50
        case .plus, .minus:
            return 40
        case .lessThan, .lessThanEqual, .greaterThan, .greaterThanEqual:
            return 30
        case .equalEqual, .exclamationEqual:
            return 20
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
        case .lessThan: return .lessThan
        case .lessThanEqual: return .lessThanOrEqual
        case .greaterThan: return .greaterThan
        case .greaterThanEqual: return .greaterThanOrEqual
        case .equalEqual: return .equal
        case .exclamationEqual: return .notEqual
        case .ampersandAmpersand: return .logicalAnd
        case .pipePipe: return .logicalOr
        default: return nil
        }
    }

    private mutating func parseFactor() throws -> Expression {
        let token = peek()

        switch token {
        case .integerLiteral(let value):
            advance()
            return .constant(value)

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
        
        case .openParen:
            advance()
            let innerExp = try parseExpression()
            try consume(.closeParen)
            return innerExp
        
        case .minusMinus:
            throw ParserError.unexpectedToken(token)

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
                return .functionCall(name: name, arguments: args)
            }
            return .variable(name)

        default:
            throw ParserError.expectedExpression(found: token)
        }
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
            if peek() == .keywordInt {
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
    
    // declaration = "int" identifier [ "=" expression ] ";"
    private mutating func parseDeclaration() throws -> Declaration {
        try consume(.keywordInt)
        
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
        return Declaration(name: name, initializer: initializer)
    }

    private mutating func parseBlockItem() throws -> BlockItem {
        if peek() == .keywordInt {
            return .declaration(try parseDeclaration())
        } else {
            return .statement(try parseStatement())
        }
    }

    private mutating func parseFunction() throws -> FunctionDeclaration {
        try consume(.keywordInt)

        let nameToken = peek()
        guard case .identifier(let name) = nameToken else {
            throw ParserError.expectedToken("identifier", found: nameToken)
        }
        advance()

        try consume(.openParen)
        
        var parameters: [String] = []
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
                 try consume(.keywordInt)
                 guard case .identifier(let paramName) = peek() else {
                     throw ParserError.expectedToken("identifier", found: peek())
                 }
                 advance()
                 parameters.append(paramName)
                 
                 while peek() == .comma {
                     advance()
                     try consume(.keywordInt)
                     guard case .identifier(let paramName) = peek() else {
                         throw ParserError.expectedToken("identifier", found: peek())
                     }
                     advance()
                     parameters.append(paramName)
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

        return FunctionDeclaration(name: name, parameters: parameters, body: .compound(bodyItems))
    }

    mutating func parse() throws -> Program {
        var functions: [FunctionDeclaration] = []
        
        while peek() != .eof {
            functions.append(try parseFunction())
        }

        return Program(functions: functions)
    }
}
