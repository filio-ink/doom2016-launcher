import Foundation

struct SemanticVersion: Comparable, Equatable {
    var major: Int
    var minor: Int
    var patch: Int
    var prerelease: [String]

    static func parse(_ raw: String) -> SemanticVersion? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if text.first == "v" || text.first == "V" { text.removeFirst() }
        let withoutBuild = text.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)[0]
        let pieces = withoutBuild.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let core = pieces[0].split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(core.count) else { return nil }
        var numbers: [Int] = []
        for part in core {
            guard let value = Int(part), value >= 0, String(value) == part else { return nil }
            numbers.append(value)
        }
        while numbers.count < 3 { numbers.append(0) }
        var prerelease: [String] = []
        if pieces.count == 2 {
            let identifiers = pieces[1].split(separator: ".", omittingEmptySubsequences: false)
            guard !identifiers.isEmpty else { return nil }
            for item in identifiers {
                let identifier = String(item)
                guard isIdentifier(identifier) else { return nil }
                prerelease.append(identifier)
            }
        }
        return SemanticVersion(major: numbers[0], minor: numbers[1], patch: numbers[2], prerelease: prerelease)
    }

    private static func isIdentifier(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        let allowed = text.allSatisfy { character in
            character.isASCII && (character.isLetter || character.isNumber || character == "-")
        }
        guard allowed else { return false }
        if text.allSatisfy(\.isNumber), text.count > 1, text.first == "0" { return false }
        return true
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
        if lhs.prerelease.isEmpty { return false }
        if rhs.prerelease.isEmpty { return true }
        let count = min(lhs.prerelease.count, rhs.prerelease.count)
        for index in 0..<count {
            let left = lhs.prerelease[index]
            let right = rhs.prerelease[index]
            if left == right { continue }
            switch (Self.number(left), Self.number(right)) {
            case let (left?, right?) where left != right:
                return left < right
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            default:
                return left < right
            }
        }
        return lhs.prerelease.count < rhs.prerelease.count
    }

    private static func number(_ text: String) -> Int? {
        guard text.allSatisfy(\.isNumber) else { return nil }
        return Int(text)
    }
}

enum UpdatePolicy {
    static func failure(downloaded: String, current: String, expected: String) -> String? {
        guard let actual = SemanticVersion.parse(downloaded),
              let installed = SemanticVersion.parse(current),
              let offered = SemanticVersion.parse(expected) else {
            return "The update bundle has an invalid version."
        }
        guard actual == offered else {
            return "The signed app version does not match the offered update."
        }
        guard actual > installed else {
            return "The update is not newer than the installed app."
        }
        return nil
    }
}

/// A callback belongs to one sign-in attempt and one exact GOG redirect URI.
enum GogOAuthPolicy {
    static func authorizationURL(state: String) -> URL {
        var parts = URLComponents(string: "https://auth.gog.com/auth")!
        parts.queryItems = [
            URLQueryItem(name: "client_id", value: "46899977096215655"),
            URLQueryItem(name: "redirect_uri", value: "https://embed.gog.com/on_login_success?origin=client"),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "layout", value: "client2"),
            URLQueryItem(name: "state", value: state),
        ]
        return parts.url!
    }

    static func code(from url: URL, state: String) -> String? {
        guard !state.isEmpty,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == "https", parts.host == "embed.gog.com",
              parts.port == nil || parts.port == 443,
              parts.user == nil, parts.password == nil, parts.fragment == nil,
              parts.percentEncodedPath == "/on_login_success" else { return nil }
        let items = parts.queryItems ?? []
        func only(_ name: String) -> String? {
            let matches = items.filter { $0.name == name }
            return matches.count == 1 ? matches.first?.value : nil
        }
        guard only("origin") == "client", only("state") == state,
              let code = only("code"), !code.isEmpty else { return nil }
        return code
    }
}

/// The system browser handles Google/SSO; only a callback for this attempt is consumed.
struct GogBrowserSignInAttempt {
    let state = UUID().uuidString
    private(set) var browserOpened = false
    private(set) var completed = false

    var authorizationURL: URL { GogOAuthPolicy.authorizationURL(state: state) }

    mutating func browserDidOpen() {
        browserOpened = true
    }

    mutating func consume(_ text: String) -> String? {
        guard browserOpened, !completed, text.utf8.count <= 8192,
              let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let code = GogOAuthPolicy.code(from: url, state: state) else { return nil }
        completed = true
        return code
    }
}
