import Foundation

var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ label: String) {
    precondition(condition(), label)
    checks += 1
}

let state = UUID().uuidString
check(GogOAuthPolicy.permitsNavigation(URL(string: "https://auth.gog.com/login")!, isMainFrame: true), "GOG login navigation")
check(!GogOAuthPolicy.permitsNavigation(URL(string: "https://auth.gog.com.attacker.invalid/login")!, isMainFrame: true), "foreign main frame")
check(!GogOAuthPolicy.permitsNavigation(URL(string: "http://auth.gog.com/login")!, isMainFrame: true), "HTTP navigation")
let prefix = "https://embed.gog.com/on_login_success?origin=client&state=\(state)&code=INERT"
check(GogOAuthPolicy.code(from: URL(string: prefix)!, state: state, isMainFrame: true) == "INERT", "valid callback")
check(GogOAuthPolicy.code(from: URL(string: prefix)!, state: state, isMainFrame: false) == nil, "iframe")
for address in [
    prefix.replacingOccurrences(of: "embed.gog.com", with: "gog.com.attacker.invalid"),
    prefix.replacingOccurrences(of: "embed.gog.com", with: "notgog.com"),
    prefix.replacingOccurrences(of: "https:", with: "http:"),
    prefix.replacingOccurrences(of: "/on_login_success", with: "/other"),
    prefix.replacingOccurrences(of: state, with: "other-session"),
    prefix.replacingOccurrences(of: "state=\(state)&", with: ""),
    prefix + "&state=\(state)",
    prefix + "&code=OTHER",
    prefix + "#fragment",
    prefix.replacingOccurrences(of: "embed.gog.com", with: "embed.gog.com:444"),
    prefix.replacingOccurrences(of: "embed.gog.com", with: "user@embed.gog.com"),
] {
    check(GogOAuthPolicy.code(from: URL(string: address)!, state: state, isMainFrame: true) == nil, address)
}
let request = URLComponents(url: GogOAuthPolicy.authorizationURL(state: state), resolvingAgainstBaseURL: false)!
check(request.queryItems!.contains(URLQueryItem(name: "state", value: state)), "request carries state")
check(UpdatePolicy.failure(downloaded: "1.4", current: "1.3.1", expected: "1.4.0") == nil, "new signed version")
for values in [
    ("1.0", "1.3.1", "99.0"),
    ("1.3.1", "1.3.1", "1.3.1"),
    ("1.2", "1.3.1", "1.2"),
    ("1.4", "1.3.1", "1.5"),
    ("invalid", "1.3.1", "1.4"),
] {
    check(UpdatePolicy.failure(downloaded: values.0, current: values.1, expected: values.2) != nil, "reject mismatch or downgrade")
}
print("Passed \(checks) Swift security policy checks")
