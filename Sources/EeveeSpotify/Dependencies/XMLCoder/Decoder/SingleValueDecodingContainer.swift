import Foundation

extension XMLDecoderImplementation: SingleValueDecodingContainer {
    // MARK: SingleValueDecodingContainer Methods
    
    public var codingPath: [CodingKey] {
        return []
    }
    
    public func decodeNil() -> Bool {
        return (try? topContainer().isNull) ?? true
    }

    public func decode(_ type: Bool.Type) throws -> Bool {
        return try unbox(try topContainer())
    }

    public func decode(_ type: Decimal.Type) throws -> Decimal {
        return try unbox(try topContainer())
    }

    public func decode<T: BinaryInteger & SignedInteger & Decodable>(_ type: T.Type) throws -> T {
        return try unbox(try topContainer())
    }

    public func decode<T: BinaryInteger & UnsignedInteger & Decodable>(_ type: T.Type) throws -> T {
        return try unbox(try topContainer())
    }

    public func decode(_ type: Float.Type) throws -> Float {
        return try unbox(try topContainer())
    }

    public func decode(_ type: Double.Type) throws -> Double {
        return try unbox(try topContainer())
    }

    public func decode(_ type: String.Type) throws -> String {
        return try unbox(try topContainer())
    }

    public func decode<T: Decodable>(_ type: T.Type) throws -> T {
        return try unbox(try topContainer())
    }
}

// MARK: - Unboxing Methods
extension XMLDecoderImplementation {
    private func unbox<T: Decodable>(_ container: XMLDecodingContainer) throws -> T {
        switch T.self {
        case is Bool.Type:
            return try unboxBool(container) as! T
        case is Decimal.Type:
            return try unboxDecimal(container) as! T
        case is String.Type:
            return try unboxString(container) as! T
        case is Date.Type:
            return try unboxDate(container) as! T
        case is Data.Type:
            return try unboxData(container) as! T
        case is Float.Type:
            return try unboxFloat(container) as! T
        case is Double.Type:
            return try unboxDouble(container) as! T
        case is Int.Type:
            return try unboxInt(container) as! T
        case is Int8.Type:
            return try unboxInt8(container) as! T
        case is Int16.Type:
            return try unboxInt16(container) as! T
        case is Int32.Type:
            return try unboxInt32(container) as! T
        case is Int64.Type:
            return try unboxInt64(container) as! T
        case is UInt.Type:
            return try unboxUInt(container) as! T
        case is UInt8.Type:
            return try unboxUInt8(container) as! T
        case is UInt16.Type:
            return try unboxUInt16(container) as! T
        case is UInt32.Type:
            return try unboxUInt32(container) as! T
        case is UInt64.Type:
            return try unboxUInt64(container) as! T
        default:
            return try decodeDecodable(T.self, from: container)
        }
    }
    
    // MARK: - Type-specific unboxing
    
    private func unboxBool(_ container: XMLDecodingContainer) throws -> Bool {
        guard let node = container.node else {
            throw DecodingError.valueNotFound(
                Bool.self,
                DecodingError.Context(
                    codingPath: codingPath,
                    debugDescription: "Expected Bool but found null"
                )
            )
        }
        
        switch node {
        case .attribute(let value), .element(let value):
            switch value.lowercased() {
            case "true", "1", "yes": return true
            case "false", "0", "no": return false
            default:
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: codingPath,
                        debugDescription: "Expected Bool but found '\(value)'"
                    )
                )
            }
        case .null:
            throw DecodingError.valueNotFound(
                Bool.self,
                DecodingError.Context(
                    codingPath: codingPath,
                    debugDescription: "Expected Bool but found null"
                )
            )
        }
    }
    
    private func unboxDecimal(_ container: XMLDecodingContainer) throws -> Decimal {
        let stringValue = try unboxString(container)
        
        guard let decimal = Decimal(string: stringValue) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: codingPath,
                    debugDescription: "Expected Decimal but found '\(stringValue)'"
                )
            )
        }
        
        return decimal
    }
    
    private func unboxString(_ container: XMLDecodingContainer) throws -> String {
        guard let node = container.node else {
            throw DecodingError.valueNotFound(
                String.self,
                DecodingError.Context(
                    codingPath: codingPath,
                    debugDescription: "Expected String but found null"
                )
            )
        }
        
        switch node {
        case .attribute(let value), .element(let value):
            return value
        case .null:
            throw DecodingError.valueNotFound(
                String.self,
                DecodingError.Context(
                    codingPath: codingPath,
                    debugDescription: "Expected String but found null"
                )
            )
        }
    }
    
    private func unboxDate(_ container: XMLDecodingContainer) throws -> Date {
        let stringValue = try unboxString(container)
        
        guard let date = options.dateDecodingStrategy.date(from: stringValue) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: codingPath,
                    debugDescription: "Expected Date string but found '\(stringValue)'"
                )
            )
        }
        
        return date
    }
    
    private func unboxData(_ container: XMLDecodingContainer) throws -> Data {
        let stringValue = try unboxString(container)
        
        guard let data = options.dataDecodingStrategy.data(from: stringValue) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: codingPath,
                    debugDescription: "Expected Data string but found '\(stringValue)'"
                )
            )
        }
        
        return data
    }
    
    private func unboxFloat(_ container: XMLDecodingContainer) throws -> Float {
        let stringValue = try unboxString(container)
        
        guard let float = Float(stringValue) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: codingPath,
                    debugDescription: "Expected Float but found '\(stringValue)'"
                )
            )
        }
        
        return float
    }
    
    private func unboxDouble(_ container: XMLDecodingContainer) throws -> Double {
        let stringValue = try unboxString(container)
        
        guard let double = Double(stringValue) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: codingPath,
                    debugDescription: "Expected Double but found '\(stringValue)'"
                )
            )
        }
        
        return double
    }
    
    // Integer types
    private func unboxInt(_ container: XMLDecodingContainer) throws -> Int {
        return try unboxNumeric(container, transform: Int.init)
    }
    
    private func unboxInt8(_ container: XMLDecodingContainer) throws -> Int8 {
        return try unboxNumeric(container, transform: Int8.init)
    }
    
    private func unboxInt16(_ container: XMLDecodingContainer) throws -> Int16 {
        return try unboxNumeric(container, transform: Int16.init)
    }
    
    private func unboxInt32(_ container: XMLDecodingContainer) throws -> Int32 {
        return try unboxNumeric(container, transform: Int32.init)
    }
    
    private func unboxInt64(_ container: XMLDecodingContainer) throws -> Int64 {
        return try unboxNumeric(container, transform: Int64.init)
    }
    
    private func unboxUInt(_ container: XMLDecodingContainer) throws -> UInt {
        return try unboxNumeric(container, transform: UInt.init)
    }
    
    private func unboxUInt8(_ container: XMLDecodingContainer) throws -> UInt8 {
        return try unboxNumeric(container, transform: UInt8.init)
    }
    
    private func unboxUInt16(_ container: XMLDecodingContainer) throws -> UInt16 {
        return try unboxNumeric(container, transform: UInt16.init)
    }
    
    private func unboxUInt32(_ container: XMLDecodingContainer) throws -> UInt32 {
        return try unboxNumeric(container, transform: UInt32.init)
    }
    
    private func unboxUInt64(_ container: XMLDecodingContainer) throws -> UInt64 {
        return try unboxNumeric(container, transform: UInt64.init)
    }
    
    private func unboxNumeric<T: LosslessStringConvertible>(
        _ container: XMLDecodingContainer,
        transform: (String) -> T?
    ) throws -> T {
        let stringValue = try unboxString(container)
        
        // Try direct conversion
        if let value = transform(stringValue) {
            return value
        }
        
        // Try removing underscores (e.g., "1_000" -> "1000")
        let cleanedString = stringValue.replacingOccurrences(of: "_", with: "")
        if let value = transform(cleanedString) {
            return value
        }
        
        throw DecodingError.dataCorrupted(
            DecodingError.Context(
                codingPath: codingPath,
                debugDescription: "Expected \(T.self) but found '\(stringValue)'"
            )
        )
    }
    
    private func decodeDecodable<T: Decodable>(_ type: T.Type, from container: XMLDecodingContainer) throws -> T {
        // Se è un tipo Decodable personalizzato, usa il decoder
        let decoder = XMLDecoderImplementation(
            referencing: container,
            options: self.options,
            codingPath: self.codingPath
        )
        
        return try T(from: decoder)
    }
}

// MARK: - Supporting Types and Extensions
extension XMLDecoderImplementation {
    struct Options {
        var dateDecodingStrategy: DateDecodingStrategy = .deferredToDate
        var dataDecodingStrategy: DataDecodingStrategy = .base64
        
        enum DateDecodingStrategy {
            case deferredToDate
            case secondsSince1970
            case millisecondsSince1970
            case iso8601
            case formatted(DateFormatter)
            case custom((String) throws -> Date?)
            
            func date(from string: String) -> Date? {
                switch self {
                case .deferredToDate:
                    // Questo non dovrebbe essere chiamato direttamente
                    return nil
                case .secondsSince1970:
                    guard let interval = TimeInterval(string) else { return nil }
                    return Date(timeIntervalSince1970: interval)
                case .millisecondsSince1970:
                    guard let milliseconds = Double(string) else { return nil }
                    return Date(timeIntervalSince1970: milliseconds / 1000.0)
                case .iso8601:
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    return formatter.date(from: string) ?? ISO8601DateFormatter().date(from: string)
                case .formatted(let formatter):
                    return formatter.date(from: string)
                case .custom(let closure):
                    return try? closure(string)
                }
            }
        }
        
        enum DataDecodingStrategy {
            case deferredToData
            case base64
            case custom((String) throws -> Data?)
            
            func data(from string: String) -> Data? {
                switch self {
                case .deferredToData:
                    // Questo non dovrebbe essere chiamato direttamente
                    return nil
                case .base64:
                    return Data(base64Encoded: string)
                case .custom(let closure):
                    return try? closure(string)
                }
            }
        }
    }
}

// MARK: - XMLDecodingContainer
enum XMLDecodingContainer {
    case element(String)
    case attribute(String)
    case null
    
    var node: XMLDecodingContainer? {
        return self
    }
    
    var isNull: Bool {
        if case .null = self {
            return true
        }
        return false
    }
}
