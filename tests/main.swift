import Foundation

var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ label: String) {
    precondition(condition(), label)
    checks += 1
}

let state = UUID().uuidString
let prefix = "https://embed.gog.com/on_login_success?origin=client&state=\(state)&code=INERT"
check(GogOAuthPolicy.code(from: URL(string: prefix)!, state: state) == "INERT", "valid callback")
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
    check(GogOAuthPolicy.code(from: URL(string: address)!, state: state) == nil, address)
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
func callback(for attempt: GogBrowserSignInAttempt) -> String {
    "https://embed.gog.com/on_login_success?origin=client&state=\(attempt.state)&code=INERT"
}
var attempt = GogBrowserSignInAttempt()
check(attempt.consume(callback(for: attempt)) == nil, "callback before browser opened")
attempt.browserDidOpen()
check(attempt.consume(prefix) == nil, "callback from another attempt")
check(attempt.consume("INERT") == nil, "raw code is not a complete callback")
check(attempt.consume(String(repeating: "x", count: 8193)) == nil, "oversized callback")
let returnedURL = callback(for: attempt)
check(attempt.consume("  " + returnedURL + "\n") == "INERT", "callback entered after browser login")
check(attempt.consume(returnedURL) == nil, "callback is consumed only once")
let otherAttempt = GogBrowserSignInAttempt()
check(otherAttempt.state != attempt.state, "new attempt uses a fresh nonce")
let browserRequest = URLComponents(url: attempt.authorizationURL, resolvingAgainstBaseURL: false)!
check(browserRequest.host == "auth.gog.com", "browser starts at GOG")
check(browserRequest.queryItems!.contains(URLQueryItem(name: "state", value: attempt.state)), "browser request carries attempt nonce")
print("Passed \(checks) Swift security policy checks")
