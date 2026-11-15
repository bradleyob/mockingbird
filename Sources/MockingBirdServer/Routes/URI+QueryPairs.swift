import HummingbirdCore

extension URI {
    /// Decoded query parameters in request order, as plain strings.
    var queryPairs: [(name: String, value: String)] {
        queryParameters.map { (name: String($0.key), value: String($0.value)) }
    }
}
