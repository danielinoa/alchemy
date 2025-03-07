import Foundation

/// A builder with useful functions for creating a table.
public class CreateTableBuilder {
    /// The grammar with which this builder will compile SQL
    /// statements.
    let grammar: Grammar
    
    /// Any indexes that should be created.
    var createIndexes: [CreateIndex] = []
    
    /// All the columns to create on this table.
    var createColumns: [CreateColumn] {
        self.columnBuilders.map { $0.toCreate() }
    }
    
    /// Create a table builder with the given grammar.
    ///
    /// - Parameter grammar: The grammar with which this builder will
    ///   compile SQL statements.
    init(grammar: Grammar) {
        self.grammar = grammar
    }
    
    /// References to the builders for all the columns on this table.
    /// Need to store these since they may be modified via column
    /// builder functions.
    private var columnBuilders: [ColumnBuilderErased] = []
    
    /// Add an index.
    ///
    /// It's name will be `<tableName>_<columnName1>_<columnName2>...`
    /// suffixed with `key` if it's unique or `idx` if not.
    ///
    /// - Parameters:
    ///   - columns: The names of the column(s) in this index.
    ///   - isUnique: Whether this index will be unique.
    public func addIndex(columns: [String], isUnique: Bool) {
        self.createIndexes.append(CreateIndex(columns: columns, isUnique: isUnique))
    }
    
    /// Adds an auto-incrementing `Int` column.
    ///
    /// - Parameter column: The name of the column to add.
    /// - Returns: A builder for adding modifiers to the column.
    @discardableResult public func increments(_ column: String) -> CreateColumnBuilder<Int> {
        self.appendAndReturn(builder: CreateColumnBuilder(grammar: self.grammar, name: column, type: .increments))
    }
    
    /// Adds an `Int` column.
    ///
    /// - Parameter column: The name of the column to add.
    /// - Returns: A builder for adding modifiers to the column.
    @discardableResult public func int(_ column: String) -> CreateColumnBuilder<Int> {
        self.appendAndReturn(builder: CreateColumnBuilder(grammar: self.grammar, name: column, type: .int))
    }
    
    /// Adds a big int column.
    ///
    /// - Parameter column: The name of the column to add.
    /// - Returns: A builder for adding modifiers to the column.
    @discardableResult public func bigInt(_ column: String) -> CreateColumnBuilder<Int> {
        self.appendAndReturn(builder: CreateColumnBuilder(grammar: self.grammar, name: column, type: .bigInt))
    }
    
    /// Adds a `Double` column.
    ///
    /// - Parameter column: The name of the column to add.
    /// - Returns: A builder for adding modifiers to the column.
    @discardableResult public func double(_ column: String) -> CreateColumnBuilder<Double> {
        self.appendAndReturn(builder: CreateColumnBuilder(grammar: self.grammar, name: column, type: .double))
    }
    
    /// Adds an `String` column.
    ///
    /// - Parameter column: The name of the column to add.
    /// - Parameter length: The max length of this string. Defaults to
    ///   `.limit(255)`.
    /// - Returns: A builder for adding modifiers to the column.
    @discardableResult public func string(
        _ column: String,
        length: StringLength = .limit(255)
    ) -> CreateColumnBuilder<String> {
        self.appendAndReturn(builder: CreateColumnBuilder(grammar: self.grammar, name: column, type: .string(length)))
    }
    
    /// Adds a `UUID` column.
    ///
    /// - Parameter column: The name of the column to add.
    /// - Returns: A builder for adding modifiers to the column.
    @discardableResult public func uuid(_ column: String) -> CreateColumnBuilder<UUID> {
        let builder = CreateColumnBuilder<UUID>(grammar: self.grammar, name: column, type: .uuid)
        return self.appendAndReturn(builder: builder)
    }
    
    /// Adds a `Bool` column.
    ///
    /// - Parameter column: The name of the column to add.
    /// - Returns: A builder for adding modifiers to the column.
    @discardableResult public func bool(_ column: String) -> CreateColumnBuilder<Bool> {
        let builder = CreateColumnBuilder<Bool>(grammar: self.grammar, name: column, type: .bool)
        return self.appendAndReturn(builder: builder)
    }
    
    /// Adds a `Date` column.
    ///
    /// - Parameter column: The name of the column to add.
    /// - Returns: A builder for adding modifiers to the column.
    @discardableResult public func date(_ column: String) -> CreateColumnBuilder<Date> {
        let builder = CreateColumnBuilder<Date>(grammar: self.grammar, name: column, type: .date)
        return self.appendAndReturn(builder: builder)
    }
    
    /// Adds a JSON column.
    ///
    /// - Parameter column: The name of the column to add.
    /// - Returns: A builder for adding modifiers to the column.
    @discardableResult public func json(_ column: String) -> CreateColumnBuilder<SQLJSON> {
        let builder = CreateColumnBuilder<SQLJSON>(grammar: self.grammar, name: column, type: .json)
        return self.appendAndReturn(builder: builder)
    }
    
    /// Adds `created_at` and `updated_at` `Date` columns. These will
    /// default to `NOW()`.
    public func timestamps() {
        let createdAt = CreateColumnBuilder<Date>(grammar: grammar, name: "created_at", type: .date).defaultNow()
        let updatedAt = CreateColumnBuilder<Date>(grammar: grammar, name: "updated_at", type: .date).defaultNow()
        _ = appendAndReturn(builder: createdAt)
        _ = appendAndReturn(builder: updatedAt)
    }
    
    /// Adds a column builder to this table builder & returns it.
    ///
    /// - Parameter builder: The column builder to add to this table
    ///   builder.
    /// - Returns: The passed in `builder`.
    private func appendAndReturn<T: Sequelizable>( builder: CreateColumnBuilder<T>) -> CreateColumnBuilder<T> {
        self.columnBuilders.append(builder)
        return builder
    }
}

/// A type for keeping track of data associated with creating an
/// index.
public struct CreateIndex {
    /// The columns that make up this index.
    let columns: [String]
    
    /// Whether this index is unique or not.
    let isUnique: Bool
    
    /// Generate an SQL string for creating this index on a given
    /// table.
    ///
    /// - Parameter table: The name of the table this index will be
    ///   created on.
    /// - Returns: An SQL string for creating this index on the given
    ///   table.
    func toSQL(table: String) -> String {
        let indexType = self.isUnique ? "UNIQUE INDEX" : "INDEX"
        let indexName = self.name(table: table)
        let indexColumns = "(\(self.columns.map(\.sqlEscaped).joined(separator: ", ")))"
        return "CREATE \(indexType) \(indexName) ON \(table) \(indexColumns)"
    }
    
    /// Generate the name of this index given the table it will be
    /// created on.
    ///
    /// - Parameter table: The table this index will be created on.
    /// - Returns: The name of this index.
    private func name(table: String) -> String {
        ([table] + self.columns + [self.nameSuffix]).joined(separator: "_")
    }
    
    /// The suffix of the index name. "key" if it's a unique index,
    /// "idx" if not.
    private var nameSuffix: String {
        self.isUnique ? "key" : "idx"
    }
}

/// A type for keeping track of data associated with creating an
/// column.
public struct CreateColumn {
    /// The name.
    let column: String
    
    /// The type string.
    let type: ColumnType
    
    /// Any constraints.
    let constraints: [ColumnConstraint]
}

extension String {
    var sqlEscaped: String {
        "\"\(self)\""
    }
}
