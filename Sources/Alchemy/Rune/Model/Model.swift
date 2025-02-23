import Foundation
import Pluralize

/// An ActiveRecord-esque type used for modeling a table in a
/// relational database. Contains many extensions for making
/// database queries, supporting relationships & much more.
///
/// - Warning: To keep things elegant for the end user, a lot of
///   Rune's under-the-hood querying and saving rely on the compiler
///   synthesized `Codable` functions of a `Model`,
///   `init(from: Decoder)` or `func encode(to: Encoder)`. Override
///   those at your own risk! You might be able to get away with it,
///   but it could also break things in unexpected ways.
public protocol Model: Identifiable, ModelMaybeOptional {
    /// The type of this object's primary key.
    associatedtype Identifier: PrimaryKey
    
    /// The identifier / primary key of this type.
    var id: Self.Identifier? { get set }
    
    /// The table with which this object is associated. Defaults to
    /// the type name, pluralized. Affected by `keyMapping`. This
    /// can be overridden for custom table names.
    ///
    /// ```swift
    /// struct User: Model {
    ///     static var tableName: String = "my_user_table"
    ///
    ///     var id: Int?
    ///     let name: String
    ///     let email: String
    /// }
    /// ```
    static var tableName: String { get }
    
    /// How should the Swift `CodingKey`s be mapped to database
    /// columns? Defaults to `.convertToSnakeCase`. Can be
    /// overridden on a per-type basis.
    static var keyMapping: DatabaseKeyMapping { get }
    
    /// The `JSONDecoder` to use when decoding any JSON fields of this
    /// type. A JSON field is any `Codable` field that doesn't have a
    /// corresponding `DatabaseValue`.
    ///
    /// Defaults to `JSONDecoder()`.
    static var jsonDecoder: JSONDecoder { get }
    
    /// The `JSONEncoder` to use when decoding any JSON fields of this
    /// type. A JSON field is any `Codable` field on this type that
    /// doesn't have a corresponding `DatabaseValue`.
    ///
    /// Defaults to `JSONEncoder()`.
    static var jsonEncoder: JSONEncoder { get }
    
    /// Defines any custom behavior when loading relationships.
    ///
    /// - Parameter mapper: An object with which to customize
    ///   relationship loading behavior.
    static func mapRelations(_ mapper: RelationshipMapper<Self>)
}

extension Model {
    public static var tableName: String {
        let typeName = String(describing: Self.self)
        let mapped = keyMapping.map(input: typeName)
        return mapped.pluralized
    }
    
    public static var keyMapping: DatabaseKeyMapping {
        .convertToSnakeCase
    }
    
    public static var jsonDecoder: JSONDecoder {
        JSONDecoder()
    }
    
    public static var jsonEncoder: JSONEncoder {
        JSONEncoder()
    }
    
    public static func mapRelations(_ mapper: RelationshipMapper<Self>) {}
    
    /// Unwraps the id of this object or throws if it is nil.
    ///
    /// - Throws: A `DatabaseError` if the `id` of this object is nil.
    /// - Returns: The unwrapped `id` value of this database object.
    public func getID() throws -> Self.Identifier {
        try self.id.unwrap(or: DatabaseError("Object of type \(type(of: self)) had a nil id."))
    }
}

/// Represents a type that may be a primary key in a database. Out of
/// the box `UUID`, `String` and `Int` are supported but you can
/// easily support your own by conforming to this protocol.
public protocol PrimaryKey: Hashable, Parameter, Codable {
    /// Initialize this value from a `DatabaseField`.
    ///
    /// - Throws: If there is an error decoding this type from the
    ///   given database value.
    /// - Parameter field: The field with which this type should be
    ///   initialzed from.
    init(field: DatabaseField) throws
}

extension UUID: PrimaryKey {
    public init(field: DatabaseField) throws {
        self = try field.uuid()
    }
}

extension Int: PrimaryKey {
    public init(field: DatabaseField) throws {
        self = try field.int()
    }
}

extension String: PrimaryKey {
    public init(field: DatabaseField) throws {
        self = try field.string()
    }
}
