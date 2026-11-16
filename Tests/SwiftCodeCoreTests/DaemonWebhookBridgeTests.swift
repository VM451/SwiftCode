import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import SwiftCodeCore
@testable import SwiftCodeDaemon

struct DaemonWebhookBridgeTests {
    @Test func cronExpressionMatchesExactAndWildcardFields() throws {
        let expr = try #require(CronExpression("*/15 9 * * 1-5"))
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 11
        comps.day = 16 // Monday -> weekday 2 -> cron 1
        comps.hour = 9
        comps.minute = 30
        let mondayMorning = try #require(Calendar(identifier: .gregorian).date(from: comps))
        #expect(expr.matches(mondayMorning, calendar: Calendar(identifier: .gregorian)))

        comps.minute = 31
        let offMinute = try #require(Calendar(identifier: .gregorian).date(from: comps))
        #expect(expr.matches(offMinute, calendar: Calendar(identifier: .gregorian)) == false)
    }

    @Test func daemonServerServesHealthTasksAndVerifiesGitHubHMAC() async throws {
        let secret = "webhook-test-secret"
        let server = DaemonServer(
            host: "127.0.0.1",
            port: 0,
            webhookSecret: secret,
            dispatcher: { task in
                TaskDispatchResult(accepted: true, summary: "Dispatched \(task.source)", sessionID: UUID().uuidString)
            }
        )
        try await server.start()
        let port = try #require(await server.boundPort)

        let healthURL = URL(string: "http://127.0.0.1:\(port)/health")!
        let (healthData, healthResp) = try await HTTPTransport.shared.data(for: URLRequest(url: healthURL), maxRetries: 0)
        #expect(healthResp.statusCode == 200)
        #expect(String(decoding: healthData, as: UTF8.self).contains("ok"))

        // Unsigned GitHub webhook must be rejected with 401
        let hookURL = URL(string: "http://127.0.0.1:\(port)/webhooks/github")!
        var badReq = URLRequest(url: hookURL)
        badReq.httpMethod = "POST"
        let body = Data("{\"issue\":{\"number\":7}}".utf8)
        badReq.httpBody = body
        badReq.setValue("sha256=deadbeef", forHTTPHeaderField: "X-Hub-Signature-256")
        let (_, badResp) = try await HTTPTransport.shared.data(for: badReq, maxRetries: 0)
        #expect(badResp.statusCode == 401)

        // Properly signed GitHub webhook must be accepted with 202
        var goodReq = URLRequest(url: hookURL)
        goodReq.httpMethod = "POST"
        goodReq.httpBody = body
        goodReq.setValue("issues", forHTTPHeaderField: "X-GitHub-Event")
        goodReq.setValue(WebhookSigner.sign(payload: body, secret: secret), forHTTPHeaderField: "X-Hub-Signature-256")
        let (goodData, goodResp) = try await HTTPTransport.shared.data(for: goodReq, maxRetries: 0)
        #expect(goodResp.statusCode == 202)
        #expect(String(decoding: goodData, as: UTF8.self).contains("github:issues"))

        await server.stop()
    }

    @Test func serviceInstallerGeneratesValidLaunchdOrSystemdManifest() throws {
        let tempHome = FileManager.default.temporaryDirectory.appendingPathComponent("sh-svc-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempHome) }

        let installedURL = try ServiceInstaller.install(
            executablePath: "/usr/local/bin/swiftcode",
            workingDirectory: "/tmp/project",
            homeDirectory: tempHome
        )
        let content = try String(contentsOf: installedURL, encoding: .utf8)
        #expect(content.contains("swiftcode"))
        #expect(content.contains("daemon"))
    }
}
