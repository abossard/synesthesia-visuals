// URLSessionHTTPClient.swift - URLSession adapter
// Following Grokking Simplicity: action (side effects)

import Foundation

/// Real HTTP client using URLSession
public final class URLSessionHTTPClient: HTTPClient, @unchecked Sendable {
    private let session: URLSession
    
    public init(session: URLSession = .shared) {
        self.session = session
    }
    
    public func execute(
        method: String,
        url urlString: String,
        headers: [String: String],
        body: Data?,
        timeoutMs: Int
    ) async throws -> (statusCode: Int, body: Data) {
        guard let url = URL(string: urlString) else {
            throw HTTPError.invalidURL(urlString)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = TimeInterval(timeoutMs) / 1000.0
        
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        if let body = body {
            request.httpBody = body
        }
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw HTTPError.invalidResponse
            }
            
            return (httpResponse.statusCode, data)
        } catch let error as URLError {
            throw HTTPError.networkError(error.localizedDescription)
        } catch {
            throw HTTPError.unknown(error.localizedDescription)
        }
    }
}

public enum HTTPError: Error, LocalizedError {
    case invalidURL(String)
    case invalidResponse
    case networkError(String)
    case unknown(String)
    
    public var errorDescription: String? {
        switch self {
        case .invalidURL(let url): return "Invalid URL: \(url)"
        case .invalidResponse: return "Invalid HTTP response"
        case .networkError(let msg): return "Network error: \(msg)"
        case .unknown(let msg): return "Unknown error: \(msg)"
        }
    }
}
