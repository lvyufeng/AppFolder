import Foundation

/// A fetched suggestion, not a saved edit. `finalURL` describes the source only:
/// it must never replace the website's original launch address.
public struct WebsiteMetadata: Sendable {
    public let title: String?
    public let icon: CustomIcon?
    public let finalURL: URL
    public let iconSourceURL: URL?

    public init(title: String?, icon: CustomIcon?, finalURL: URL, iconSourceURL: URL?) {
        self.title = title
        self.icon = icon
        self.finalURL = finalURL
        self.iconSourceURL = iconSourceURL
    }
}

public enum WebsiteMetadataError: Error, Equatable, Sendable {
    case invalidURL, unsupportedResponse, responseTooLarge, tooManyRedirects, timedOut, invalidResponse
}

/// Only an explicit editor action calls this API. It neither saves suggestions
/// nor shares the browser's cookies, credentials, cache, or JavaScript context.
public enum WebsiteMetadataFetcher {
    public static func fetch(_ url: URL) async throws -> WebsiteMetadata {
        try await fetch(url, configuration: configuration())
    }

    static func configuration() -> URLSessionConfiguration {
        // Apple documents that ephemeral storage is memory-only. Disable even
        // those in-memory stores so redirects cannot establish a login session.
        let value = URLSessionConfiguration.ephemeral
        value.urlCache = nil
        value.urlCredentialStorage = nil
        value.httpCookieStorage = nil
        value.httpShouldSetCookies = false
        value.httpCookieAcceptPolicy = .never
        value.requestCachePolicy = .reloadIgnoringLocalCacheData
        value.timeoutIntervalForRequest = 8
        value.timeoutIntervalForResource = 20
        value.httpMaximumConnectionsPerHost = 1
        return value
    }

    /// Configuration injection is internal and used for deterministic URLProtocol
    /// tests; the shipping API always creates the isolated configuration above.
    static func fetch(_ url: URL, configuration: URLSessionConfiguration,
                      limits: WebsiteMetadataLimits = .init()) async throws -> WebsiteMetadata {
        guard WebsiteURL.validated(url.absoluteString) != nil else { throw WebsiteMetadataError.invalidURL }
        try Task.checkCancellation()
        let deadline = ContinuousClock.now.advanced(by: .seconds(limits.totalSeconds))
        var budget = WebsiteMetadataRequestBudget(limits: limits, deadline: deadline)
        let page = try await request(url, kind: .html, configuration: configuration, budget: &budget)
        guard let html = WebsiteMetadataHTML.decode(page.data, encodingName: page.response.textEncodingName) else {
            throw WebsiteMetadataError.unsupportedResponse
        }
        let parsed = WebsiteMetadataHTML.parse(html, baseURL: page.url)
        if page.truncated && parsed.title == nil && parsed.icons.isEmpty {
            throw WebsiteMetadataError.responseTooLarge
        }
        var candidates = Array(parsed.icons.prefix(limits.maximumDeclaredIcons))
        if let fallback = URL(string: "/favicon.ico", relativeTo: page.url)?.absoluteURL,
           WebsiteURL.validated(fallback.absoluteString) != nil, !candidates.contains(fallback) {
            candidates.append(fallback)
        }
        for candidate in candidates {
            try Task.checkCancellation()
            guard ContinuousClock.now < deadline, budget.requests < limits.maximumRequests else { break }
            do {
                let fetched = try await request(candidate, kind: .image, configuration: configuration, budget: &budget)
                if let icon = try WebsiteMetadataArtwork.decode(fetched.data) {
                    return WebsiteMetadata(title: parsed.title, icon: icon, finalURL: page.url,
                                           iconSourceURL: fetched.url)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // A failed icon does not discard a usable title. All attempts
                // share the same request, redirect, and wall-clock budgets.
                try Task.checkCancellation()
            }
        }
        try Task.checkCancellation()
        return WebsiteMetadata(title: parsed.title, icon: nil, finalURL: page.url, iconSourceURL: nil)
    }

    private static func request(_ initial: URL, kind: WebsiteMetadataResponseKind,
                                configuration: URLSessionConfiguration,
                                budget: inout WebsiteMetadataRequestBudget) async throws -> WebsiteMetadataHTTPResponse {
        var destination = initial
        while true {
            try Task.checkCancellation()
            guard let checked = WebsiteURL.validated(destination.absoluteString) else {
                throw WebsiteMetadataError.invalidURL
            }
            let remaining = ContinuousClock.now.duration(to: budget.deadline)
            let seconds = Double(remaining.components.seconds) + Double(remaining.components.attoseconds) / 1e18
            guard seconds > 0 else { throw WebsiteMetadataError.timedOut }
            guard budget.requests < budget.limits.maximumRequests else { throw WebsiteMetadataError.tooManyRedirects }
            budget.requests += 1
            var request = URLRequest(url: checked, cachePolicy: .reloadIgnoringLocalCacheData,
                                     timeoutInterval: min(8, seconds))
            request.httpShouldHandleCookies = false
            request.setValue(kind == .html ? "text/html, application/xhtml+xml;q=0.9" : "image/png,image/jpeg,image/x-icon,image/vnd.microsoft.icon;q=0.9,*/*;q=0.1",
                             forHTTPHeaderField: "Accept")
            let client = WebsiteMetadataHTTPClient(configuration: configuration, kind: kind,
                                                  byteLimit: kind == .html ? budget.limits.htmlBytes : budget.limits.imageBytes,
                                                  seconds: seconds)
            let result = try await client.load(request)
            if [301, 302, 303, 307, 308].contains(result.response.statusCode) {
                guard budget.redirects < budget.limits.maximumRedirects else { throw WebsiteMetadataError.tooManyRedirects }
                guard let location = result.response.value(forHTTPHeaderField: "Location"),
                      let next = URL(string: location, relativeTo: checked)?.absoluteURL,
                      WebsiteURL.validated(next.absoluteString) != nil else { throw WebsiteMetadataError.invalidURL }
                budget.redirects += 1
                destination = next
                continue
            }
            guard (200..<300).contains(result.response.statusCode) else { throw WebsiteMetadataError.invalidResponse }
            return result
        }
    }
}

struct WebsiteMetadataLimits: Sendable {
    var htmlBytes = 1_024 * 1_024
    var imageBytes = 2 * 1_024 * 1_024
    var maximumDeclaredIcons = 3
    var maximumRedirects = 5
    var maximumRequests = 10
    var totalSeconds: Double = 20
}

private struct WebsiteMetadataRequestBudget {
    let limits: WebsiteMetadataLimits
    let deadline: ContinuousClock.Instant
    var requests = 0
    var redirects = 0
}

enum WebsiteMetadataResponseKind: Sendable { case html, image }

struct WebsiteMetadataHTTPResponse: Sendable {
    let data: Data
    let response: HTTPURLResponse
    let url: URL
    let truncated: Bool
}

/// One bounded request. Redirects are declined here and followed explicitly by
/// the caller, so each new destination is validated before any network request.
final class WebsiteMetadataHTTPClient: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private struct State {
        var continuation: CheckedContinuation<WebsiteMetadataHTTPResponse, any Error>?
        var task: URLSessionDataTask?
        var session: URLSession?
        var timeout: Task<Void, Never>?
        var response: HTTPURLResponse?
        var data = Data()
        var finished = false
        var cancelled = false
    }
    private let lock = NSLock()
    private var state = State()
    private let configuration: URLSessionConfiguration
    private let kind: WebsiteMetadataResponseKind
    private let byteLimit: Int
    private let seconds: Double

    init(configuration: URLSessionConfiguration, kind: WebsiteMetadataResponseKind, byteLimit: Int, seconds: Double) {
        self.configuration = configuration
        self.kind = kind
        self.byteLimit = byteLimit
        self.seconds = seconds
    }

    func load(_ request: URLRequest) async throws -> WebsiteMetadataHTTPResponse {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let config = configuration.copy() as! URLSessionConfiguration
                config.timeoutIntervalForResource = max(0.01, seconds)
                let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
                let task = session.dataTask(with: request)
                let cancelled = lock.withLock {
                    state.continuation = continuation
                    state.session = session
                    state.task = task
                    return state.cancelled
                }
                let timeout = Task { [weak self, seconds] in
                    do {
                        try await Task.sleep(for: .seconds(seconds))
                        self?.finish(.failure(WebsiteMetadataError.timedOut))
                    } catch { }
                }
                let alreadyFinished = lock.withLock {
                    if state.finished { return true }
                    state.timeout = timeout
                    return false
                }
                if alreadyFinished { timeout.cancel() }
                if cancelled { finish(.failure(CancellationError())) }
                else { task.resume() }
            }
        } onCancel: {
            self.lock.withLock { self.state.cancelled = true }
            self.finish(.failure(CancellationError()))
        }
    }

    private func finish(_ result: Result<WebsiteMetadataHTTPResponse, any Error>) {
        let completed = lock.withLock { () -> (CheckedContinuation<WebsiteMetadataHTTPResponse, any Error>, URLSession?, Task<Void, Never>?)? in
            guard !state.finished, let continuation = state.continuation else { return nil }
            state.finished = true
            state.continuation = nil
            state.task = nil
            state.data = Data()
            let session = state.session
            state.session = nil
            let timeout = state.timeout
            state.timeout = nil
            return (continuation, session, timeout)
        }
        guard let (continuation, session, timeout) = completed else { return }
        timeout?.cancel()
        session?.invalidateAndCancel()
        continuation.resume(with: result)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        completionHandler(challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust
                          ? .performDefaultHandling : .cancelAuthenticationChallenge, nil)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        guard let response = response as? HTTPURLResponse, let url = response.url,
              WebsiteURL.validated(url.absoluteString) != nil else {
            completionHandler(.cancel)
            finish(.failure(WebsiteMetadataError.invalidResponse))
            return
        }
        if [301, 302, 303, 307, 308].contains(response.statusCode) {
            completionHandler(.cancel)
            finish(.success(.init(data: Data(), response: response, url: url, truncated: false)))
            return
        }
        let type = response.mimeType?.lowercased()
        guard (200..<300).contains(response.statusCode),
              kind != .html || type == "text/html" || type == "application/xhtml+xml" || type == nil else {
            completionHandler(.cancel)
            finish(.failure(WebsiteMetadataError.unsupportedResponse))
            return
        }
        if kind == .image && response.expectedContentLength > byteLimit {
            completionHandler(.cancel)
            finish(.failure(WebsiteMetadataError.responseTooLarge))
            return
        }
        lock.withLock { state.response = response }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let result = lock.withLock { () -> Result<WebsiteMetadataHTTPResponse, any Error>? in
            guard !state.finished, let response = state.response, let url = response.url else { return nil }
            let remaining = byteLimit - state.data.count
            if data.count > remaining {
                guard kind == .html else { return .failure(WebsiteMetadataError.responseTooLarge) }
                state.data.append(data.prefix(remaining))
                return .success(.init(data: state.data, response: response, url: url, truncated: true))
            }
            state.data.append(data)
            return nil
        }
        if let result { finish(result) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        if let error {
            if (error as? URLError)?.code == .timedOut { finish(.failure(WebsiteMetadataError.timedOut)) }
            else { finish(.failure(error)) }
            return
        }
        let result = lock.withLock { () -> WebsiteMetadataHTTPResponse? in
            guard !state.finished, let response = state.response, let url = response.url else { return nil }
            return .init(data: state.data, response: response, url: url, truncated: false)
        }
        if let result { finish(.success(result)) }
        else { finish(.failure(WebsiteMetadataError.invalidResponse)) }
    }
}
