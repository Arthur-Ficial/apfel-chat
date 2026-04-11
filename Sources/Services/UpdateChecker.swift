import Foundation

struct LatestReleaseInfo: Equatable {
    let version: String
}

protocol UpdateChecking {
    @MainActor
    func fetchLatestRelease(currentVersion: String) async throws -> LatestReleaseInfo
}

enum UpdateCheckerError: LocalizedError {
    case unexpectedResponse

    var errorDescription: String? {
        switch self {
        case .unexpectedResponse:
            return "Unexpected response from GitHub"
        }
    }
}

struct GitHubReleaseUpdateChecker: UpdateChecking {
    let session: URLSession
    let apiURL: URL

    init(
        session: URLSession = .shared,
        apiURL: URL = URL(string: "https://api.github.com/repos/Arthur-Ficial/apfel-chat/releases/latest")!
    ) {
        self.session = session
        self.apiURL = apiURL
    }

    @MainActor
    func fetchLatestRelease(currentVersion: String) async throws -> LatestReleaseInfo {
        var request = URLRequest(url: apiURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("apfel-chat/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        let (data, response) = try await session.data(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw UpdateCheckerError.unexpectedResponse
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tagName = json["tag_name"] as? String else {
            throw UpdateCheckerError.unexpectedResponse
        }

        let latest = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
        return LatestReleaseInfo(version: latest)
    }
}
