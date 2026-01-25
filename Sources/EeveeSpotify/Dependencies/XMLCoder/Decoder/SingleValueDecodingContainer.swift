import Foundation

// Solo la conformità + metodi richiesti
extension XMLDecoderImplementation: SingleValueDecodingContainer {
    public func decodeNil() -> Bool {
        (try? topContainer().isNull) ?? true
    }

    public func decode(_: Bool.Type) throws -> Bool { try unbox(try topContainer()) }

    public func decode<T: BinaryInteger & SignedInteger & Decodable>(_: T.Type) throws -> T {
        try unbox(try topContainer())
    }
    public func decode<T: BinaryInteger & UnsignedInteger & Decodable>(_: T.Type) throws -> T {
        try unbox(try topContainer())
    }

    public func decode(_: Float.Type) throws -> Float { try unbox(try topContainer()) }
    public func decode(_: Double.Type) throws -> Double { try unbox(try topContainer()) }
    public func decode(_: String.Type) throws -> String { try unbox(try topContainer()) }

    public func decode<T: Decodable>(_: T.Type) throws -> T { try unbox(try topContainer()) }
}

// Overload opzionali fuori dalla conformità → niente warning
extension XMLDecoderImplementation {
    public func decode(_: Date.Type) throws -> Date { try unbox(try topContainer()) }
    public func decode(_: Data.Type) throws -> Data { try unbox(try topContainer()) }
    public func decode(_: Decimal.Type) throws -> Decimal { try unbox(try topContainer()) }
}
