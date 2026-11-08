import Foundation

/// Fetches the body of a URL. Production uses `URLSessionFetcher`; tests substitute a fake.
public protocol HTTPFetching: Sendable {
    func data(from url: URL) async throws -> Data
}

/// A response whose status code is outside 2xx.
public enum HTTPFetchError: Error, Equatable {
    case badStatus(Int)
}

/// Fetches with `URLSession`, a 12 second timeout and the project's User-Agent.
public struct URLSessionFetcher: HTTPFetching {
    private static let timeoutSeconds: Double = 12
    private static let userAgent = "ktv-lyrics/0.1"
    private static let successStatusRange = 200..<300

    public init() {}

    public func data(from url: URL) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: Self.timeoutSeconds)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !Self.successStatusRange.contains(http.statusCode) {
            throw HTTPFetchError.badStatus(http.statusCode)
        }
        return data
    }
}

extension URL {
    /// `base` with `pairs` as its query string, in the order given. Throws when the result is not a valid URL.
    static func endpoint(_ base: String, query pairs: KeyValuePairs<String, String>) throws -> URL {
        var components = URLComponents(string: base)
        components?.queryItems = pairs.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components?.url else { throw URLError(.badURL) }
        return url
    }
}
