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
            let precedence = getPrecedence(token)
            
            if precedence < minPrecedence {
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
        
        default:
            throw ParserError.expectedExpression(found: token)
        }
    }

    private mutating func parseStatement() throws -> Statement {
        try consume(.keywordReturn)
        let expression = try parseExpression()
        try consume(.semicolon)

        return .return(expression)
    }

    private mutating func parseFunction() throws -> FunctionDeclaration {
        try consume(.keywordInt)

        let nameToken = peek()
        guard case .identifier(let name) = nameToken else {
            throw ParserError.expectedToken("identifier", found: nameToken)
        }
        advance()

        try consume(.openParen)
        try consume(.keywordVoid)
        try consume(.closeParen)
        try consume(.openBrace)

        let body = try parseStatement()

        try consume(.closeBrace)

        return FunctionDeclaration(name: name, body: body)
    }

    mutating func parse() throws -> Program {
        let function = try parseFunction()

        guard peek() == .eof else {
            throw ParserError.unexpectedToken(peek())
        }

        return Program(function: function)
    }
}
