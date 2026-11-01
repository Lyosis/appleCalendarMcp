/// A whole number read from a tool's arguments.
enum WholeNumber {

    /// Nil when absent. A value that is not a whole number is an error, not
    /// rounded and not replaced by a default: either would answer a different
    /// question than the one asked. `unit` names what it counts, for the
    /// message.
    static func read(_ arguments: JSONValue, _ key: String, unit: String) throws -> Int? {
        guard let value = arguments[key] else { return nil }
        guard let number = value.doubleValue,
              number.rounded() == number,
              let whole = Int(exactly: number)
        else {
            throw ToolFailure("\(key) must be a whole number of \(unit).")
        }
        return whole
    }
}
