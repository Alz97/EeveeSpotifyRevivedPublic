import Foundation

// MARK: - SingleValueDecodingContainer conformance (solo il minimo indispensabile)
extension XMLDecoderImplementation: SingleValueDecodingContainer {
    public func decodeNil() -> Bool {
        return (try? topContainer().isNull) ?? true
    }

    public func decode<T: Decodable>(_: T.Type) throws -> T {
        return try unbox(try topContainer())
    }
}

// MARK: - Estensione separata con tutte le implementazioni specifiche
extension XMLDecoderImplementation {
    // Questi metodi NON fanno parte della conformance al protocollo
    // ma sono metodi di convenienza che puoi chiamare internamente
    
    public func decodeBool() throws -> Bool {
        return try unbox(try topContainer())
    }
    
    public func decodeDecimal() throws -> Decimal {
        return try unbox(try topContainer())
    }
    
    public func decodeSignedInteger<T: BinaryInteger & SignedInteger & Decodable>() throws -> T {
        return try unbox(try topContainer())
    }
    
    public func decodeUnsignedInteger<T: BinaryInteger & UnsignedInteger & Decodable>() throws -> T {
        return try unbox(try topContainer())
    }
    
    public func decodeFloat() throws -> Float {
        return try unbox(try topContainer())
    }
    
    public func decodeDouble() throws -> Double {
        return try unbox(try topContainer())
    }
    
    public func decodeString() throws -> String {
        return try unbox(try topContainer())
    }
    
    public func decodeDateFromString() throws -> Date {
        let _: String = try decodeString()
        // Logica di conversione
        fatalError("Implement decodeDateFromString")
    }
    
    public func decodeDataFromString() throws -> Data {
        let _: String = try decodeString()
        // Logica di conversione
        fatalError("Implement decodeDataFromString")
    }
}
