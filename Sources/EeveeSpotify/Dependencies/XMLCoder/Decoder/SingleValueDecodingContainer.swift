import Foundation

// MARK: - SingleValueDecodingContainer conformance
extension XMLDecoderImplementation: SingleValueDecodingContainer {
    public func decodeNil() -> Bool {
        return (try? topContainer().isNull) ?? true
    }

    public func decode(_: Bool.Type) throws -> Bool {
        return try unbox(try topContainer())
    }

    public func decode(_: Decimal.Type) throws -> Decimal {
        return try unbox(try topContainer())
    }

    public func decode<T: BinaryInteger & SignedInteger & Decodable>(_: T.Type) throws -> T {
        return try unbox(try topContainer())
    }

    public func decode<T: BinaryInteger & UnsignedInteger & Decodable>(_: T.Type) throws -> T {
        return try unbox(try topContainer())
    }

    public func decode(_: Float.Type) throws -> Float {
        return try unbox(try topContainer())
    }

    public func decode(_: Double.Type) throws -> Double {
        return try unbox(try topContainer())
    }

    public func decode(_: String.Type) throws -> String {
        return try unbox(try topContainer())
    }

    public func decode<T: Decodable>(_: T.Type) throws -> T {
        return try unbox(try topContainer())
    }
}

// MARK: - Extension separata con metodi specifici
private extension XMLDecoderImplementation {
    // Questi metodi sono chiamati internamente da unbox
    func unboxDate() throws -> Date {
        // La logica originale che avevi in decode(_: String.Type) -> Date
        return try unbox(try topContainer())
    }
    
    func unboxData() throws -> Data {
        // La logica originale che avevi in decode(_: String.Type) -> Data
        return try unbox(try topContainer())
    }
}
