//
//  AppVersionManager.swift
//  ray
//
//  Created by Dylan Karunanayake on 12/10/2026.
//

import Foundation

struct UpdateConfig {
    static let githubAccount = "dylankaru"
    static let githubRepo = "ray"
    static let githubRepoLink = URL(string: "https://github.com/\(UpdateConfig.githubAccount)/\(UpdateConfig.githubRepo)/releases/latest")

    static let checkInterval: TimeInterval = 6 * 60 * 60

    static let forceMarker = "[force]"

    static let loggingEnabled = true

    static var mockLatestVersion: String? = nil
    static var simulateForceUpdate: Bool = false
}

private func updateLog(_ message: String) {
    guard UpdateConfig.loggingEnabled else { return }
    print("[Update] \(message)")
}

struct AppVersionManager {
    public static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    static func isNewer(_ latest: String, than current: String) -> Bool {
        let l = components(latest)
        let c = components(current)
        for i in 0..<max(l.count, c.count) {
            let a = i < l.count ? l[i] : 0
            let b = i < c.count ? c[i] : 0
            if a != b { return a > b }
        }
        return false
    }

    private static func components(_ version: String) -> [Int] {
        var v = version.trimmingCharacters(in: .whitespacesAndNewlines)
        if v.lowercased().hasPrefix("v") { v.removeFirst() }
        if let dash = v.firstIndex(where: { $0 == "-" || $0 == "+" }) {
            v = String(v[..<dash])
        }
        return v.split(separator: ".").map { Int($0) ?? 0 }
    }
}

final class AppUpdateChecker {
    static let shared = AppUpdateChecker()
    private init() {}

    enum UpdateStatus {
        case upToDate
        case updateAvailable(version: String, downloadURL: URL?, isForced: Bool)
    }

    private enum FetchError: Error {
        case badURL
        case notHTTP
        case rateLimited(status: Int, resetsAt: Date?)
        case notFound
        case unexpectedStatus(Int)
        case decoding(Error)
        case transport(URLError)
        case cancelled
        case other(Error)
    }

    private struct GitHubRelease: Decodable {
        let tagName: String
        let htmlURL: URL
        let body: String?

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case body
        }
    }

    private struct CachedRelease: Codable {
        let version: String
        let url: String
        let isForced: Bool
    }

    private let defaults = UserDefaults.standard
    private let lastCheckKey = "ray_update_last_check"
    private let cacheKey = "ray_update_cached_release"

    func checkAppUpdate(force: Bool = false) async -> UpdateStatus {
        let current = AppVersionManager.currentVersion
        updateLog("Starting check. Installed version: \(current), force: \(force)")

        // Debug mock
        if let mock = UpdateConfig.mockLatestVersion {
            updateLog("MOCK mode on. Pretending latest is \(mock), forced: \(UpdateConfig.simulateForceUpdate)")
            return evaluate(current: current,
                            latest: mock,
                            downloadURL: UpdateConfig.githubRepoLink,
                            isForced: UpdateConfig.simulateForceUpdate)
        }

        let lastCheck = defaults.double(forKey: lastCheckKey)
        let age = Date().timeIntervalSince1970 - lastCheck
        let withinThrottle = lastCheck > 0 && age < UpdateConfig.checkInterval

        if force {
            updateLog("Throttle bypassed (force = true)")
        } else if withinThrottle {
            let remaining = Int(UpdateConfig.checkInterval - age)
            if let cached = loadCache() {
                updateLog("Throttled: last check \(Int(age))s ago, next real check in \(remaining)s. Using cached release \(cached.version)")
                return evaluate(current: current,
                                latest: cached.version,
                                downloadURL: URL(string: cached.url),
                                isForced: cached.isForced)
            } else {
                updateLog("Throttled: last check \(Int(age))s ago, next real check in \(remaining)s. Nothing cached, treating as up to date")
                return .upToDate
            }
        } else if lastCheck > 0 {
            updateLog("Throttle window expired (last check \(Int(age))s ago). Checking GitHub")
        } else {
            updateLog("No previous check recorded. Checking GitHub")
        }

        // Real network check
        do {
            let release = try await fetchLatestRelease()
            let version = Self.cleanTag(release.tagName)
            let isForced = (release.body ?? "").localizedCaseInsensitiveContains(UpdateConfig.forceMarker)

            updateLog("GitHub returned release tag '\(release.tagName)' (parsed version \(version)), force marker present: \(isForced)")

            defaults.set(Date().timeIntervalSince1970, forKey: lastCheckKey)
            saveCache(CachedRelease(version: version, url: release.htmlURL.absoluteString, isForced: isForced))
            updateLog("Saved result to cache and recorded check time")

            return evaluate(current: current,
                            latest: version,
                            downloadURL: release.htmlURL,
                            isForced: isForced)
        } catch {
            logFailure(error)

            if let cached = loadCache() {
                updateLog("Falling back to cached release \(cached.version)")
                return evaluate(current: current,
                                latest: cached.version,
                                downloadURL: URL(string: cached.url),
                                isForced: cached.isForced)
            }
            updateLog("No cached release to fall back on. Result: upToDate")
            return .upToDate
        }
    }

    func checkAppUpdate(force: Bool = false, completion: @escaping (UpdateStatus) -> Void) {
        Task {
            let status = await checkAppUpdate(force: force)
            await MainActor.run { completion(status) }
        }
    }

    private func evaluate(current: String, latest: String, downloadURL: URL?, isForced: Bool) -> UpdateStatus {
        if AppVersionManager.isNewer(latest, than: current) {
            updateLog("RESULT: update available. \(current) -> \(latest), forced: \(isForced), url: \(downloadURL?.absoluteString ?? "none")")
            return .updateAvailable(version: latest, downloadURL: downloadURL, isForced: isForced)
        }

        if latest == current || !AppVersionManager.isNewer(current, than: latest) {
            updateLog("RESULT: up to date. Installed \(current), latest \(latest)")
        } else {
            updateLog("RESULT: up to date (installed \(current) is NEWER than latest release \(latest), probably a dev build)")
        }
        return .upToDate
    }

    private func fetchLatestRelease() async throws -> GitHubRelease {
        let urlString = "https://api.github.com/repos/\(UpdateConfig.githubAccount)/\(UpdateConfig.githubRepo)/releases/latest"
        guard let url = URL(string: urlString) else { throw FetchError.badURL }

        updateLog("GET \(urlString)")

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("RayUpdateChecker", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw FetchError.cancelled
        } catch let error as URLError {
            throw FetchError.transport(error)
        } catch is CancellationError {
            throw FetchError.cancelled
        } catch {
            throw FetchError.other(error)
        }

        guard let http = response as? HTTPURLResponse else { throw FetchError.notHTTP }

        updateLog("HTTP \(http.statusCode), \(data.count) bytes. Rate limit remaining: \(http.value(forHTTPHeaderField: "x-ratelimit-remaining") ?? "unknown")")

        switch http.statusCode {
        case 200:
            do {
                return try JSONDecoder().decode(GitHubRelease.self, from: data)
            } catch {
                throw FetchError.decoding(error)
            }
        case 403, 429:
            let reset = http.value(forHTTPHeaderField: "x-ratelimit-reset")
                .flatMap { TimeInterval($0) }
                .map { Date(timeIntervalSince1970: $0) }
            throw FetchError.rateLimited(status: http.statusCode, resetsAt: reset)
        case 404:
            throw FetchError.notFound
        default:
            throw FetchError.unexpectedStatus(http.statusCode)
        }
    }

    private func logFailure(_ error: Error) {
        guard let fetchError = error as? FetchError else {
            updateLog("FAILED: unknown error: \(error)")
            return
        }

        switch fetchError {
        case .badURL:
            updateLog("FAILED: could not build the GitHub URL.")
        case .notHTTP:
            updateLog("FAILED: response was not an HTTP response")
        case .rateLimited(let status, let resetsAt):
            let when = resetsAt.map { "resets at \($0.formatted(date: .omitted, time: .standard))" } ?? "reset time unknown"
            updateLog("FAILED: GitHub rate limit hit (HTTP \(status)), \(when)")
        case .notFound:
            updateLog("FAILED: HTTP 404. Either the repo is private/misspelled, or it has no published (non-draft, non-prerelease) release yet")
        case .unexpectedStatus(let code):
            updateLog("FAILED: unexpected HTTP status \(code)")
        case .decoding(let underlying):
            updateLog("FAILED: could not decode GitHub's JSON: \(underlying)")
        case .transport(let urlError):
            switch urlError.code {
            case .notConnectedToInternet:
                updateLog("FAILED: no internet connection")
            case .timedOut:
                updateLog("FAILED: request timed out")
            case .cannotFindHost, .dnsLookupFailed:
                updateLog("FAILED: could not resolve api.github.com (DNS)")
            case .networkConnectionLost:
                updateLog("FAILED: connection dropped mid-request")
            case .secureConnectionFailed, .serverCertificateUntrusted:
                updateLog("FAILED: TLS/certificate problem (\(urlError.code.rawValue))")
            default:
                updateLog("FAILED: network error \(urlError.code.rawValue): \(urlError.localizedDescription)")
            }
        case .cancelled:
            updateLog("CANCELLED: the check was cancelled (view disappeared or task cancelled)")
        case .other(let underlying):
            updateLog("FAILED: \(underlying)")
        }
    }

    private static func cleanTag(_ tag: String) -> String {
        tag.lowercased().hasPrefix("v") ? String(tag.dropFirst()) : tag
    }

    private func loadCache() -> CachedRelease? {
        guard let data = defaults.data(forKey: cacheKey) else { return nil }
        do {
            return try JSONDecoder().decode(CachedRelease.self, from: data)
        } catch {
            updateLog("Cache exists but could not be decoded, ignoring it: \(error)")
            return nil
        }
    }

    private func saveCache(_ release: CachedRelease) {
        do {
            defaults.set(try JSONEncoder().encode(release), forKey: cacheKey)
        } catch {
            updateLog("Could not save cache: \(error)")
        }
    }
}
