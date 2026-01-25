import Foundation

// MARK: - SingleValueDecodingContainer conformance (solo i metodi che NON danno warning)
extension XMLDecoderImplementation: SingleValueDecodingContainer {
    public func decodeNil() -> Bool {
        return (try? topContainer().isNull) ?? true
    }

    public func decode(_: Bool.Type) throws -> Bool {
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

// MARK: - Estensione separata per i metodi che causano warning
private extension XMLDecoderImplementation {
    // Metodo per Decimal (causa warning se è nell'estensione del protocollo)
    func decodeDecimal() throws -> Decimal {
        return try unbox(try topContainer())
    }
    
    // Metodo per Date (se necessario)
    func decodeDateFromString() throws -> Date {
        let stringValue: String = try self.decode(String.self)
        // Implementa la tua logica di conversione
        fatalError("Implement decodeDateFromString")
    }
    
    // Metodo per Data (se necessario)
    func decodeDataFromString() throws -> Data {
        let stringValue: String = try self.decode(String.self)
        // Implementa la tua logica di conversione
        fatalError("Implement decodeDataFromString")
    }
}
