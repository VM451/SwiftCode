import Foundation
import Logging
import NIOCore
import NIOHTTP1
import NIOPosix
import SwiftCodeCore

/// Non-blocking SwiftNIO HTTP & Unix Domain Socket server for webhooks and local CLI/GUI IPC (FR-8.3).
public actor DaemonServer {
    private let host: String
    private let port: Int
    private let socketPath: String?
    private let webhookSecret: String?
    private let dispatcher: DaemonTaskDispatcher
    private let statusProvider: @Sendable () async -> DaemonStatusSnapshot
    private let logger = Logger(label: "dev.swiftcode.daemon.server")

    private var group: MultiThreadedEventLoopGroup?
    private var tcpChannel: (any Channel)?
    private var unixChannel: (any Channel)?

    public private(set) var boundPort: Int?

    public init(
        host: String = "127.0.0.1",
        port: Int = 8787,
        socketPath: String? = nil,
        webhookSecret: String? = nil,
        dispatcher: @escaping DaemonTaskDispatcher,
        statusProvider: @escaping @Sendable () async -> DaemonStatusSnapshot = {
            DaemonStatusSnapshot(running: true, activeBridges: [], processedTasks: 0, uptimeSeconds: 0, residentMemoryMB: 0)
        }
    ) {
        self.host = host
        self.port = port
        self.socketPath = socketPath.map { ($0 as NSString).expandingTildeInPath }
        self.webhookSecret = webhookSecret
        self.dispatcher = dispatcher
        self.statusProvider = statusProvider
    }

    public func start() async throws {
        guard group == nil else { return }
        let elg = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        self.group = elg

        let secret = self.webhookSecret
        let taskDispatcher = self.dispatcher
        let statusFn = self.statusProvider

        let bootstrap = ServerBootstrap(group: elg)
            .serverChannelOption(.backlog, value: 256)
            .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline().flatMap {
                    channel.pipeline.addHandler(DaemonHTTPHandler(
                        webhookSecret: secret,
                        dispatcher: taskDispatcher,
                        statusProvider: statusFn
                    ))
                }
            }
            .childChannelOption(.socketOption(.so_reuseaddr), value: 1)

        let boundTCP = try await bootstrap.bind(host: host, port: port).get()
        self.tcpChannel = boundTCP
        self.boundPort = boundTCP.localAddress?.port
        logger.info("SwiftNIO webhook server listening on \(host):\(self.boundPort ?? port)")

        if let socketPath {
            let sockURL = URL(fileURLWithPath: socketPath)
            try? FileManager.default.createDirectory(at: sockURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.removeItem(atPath: socketPath)
            let boundUnix = try await bootstrap.bind(unixDomainSocketPath: socketPath).get()
            self.unixChannel = boundUnix
            logger.info("SwiftNIO Unix IPC socket listening at \(socketPath)")
        }
    }

    public func stop() async {
        try? await tcpChannel?.close().get()
        try? await unixChannel?.close().get()
        if let socketPath {
            try? FileManager.default.removeItem(atPath: socketPath)
        }
        try? await group?.shutdownGracefully()
        tcpChannel = nil
        unixChannel = nil
        group = nil
        boundPort = nil
    }
}

private final class DaemonHTTPHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let webhookSecret: String?
    private let dispatcher: DaemonTaskDispatcher
    private let statusProvider: @Sendable () async -> DaemonStatusSnapshot

    private var head: HTTPRequestHead?
    private var bodyBuffer = ByteBuffer()

    init(
        webhookSecret: String?,
        dispatcher: @escaping DaemonTaskDispatcher,
        statusProvider: @escaping @Sendable () async -> DaemonStatusSnapshot
    ) {
        self.webhookSecret = webhookSecret
        self.dispatcher = dispatcher
        self.statusProvider = statusProvider
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)
        switch part {
        case .head(let requestHead):
            head = requestHead
            bodyBuffer.clear()
        case .body(var buf):
            bodyBuffer.writeBuffer(&buf)
        case .end:
            guard let requestHead = head else { return }
            let bodyData = Data(bodyBuffer.readableBytesView)
            handleCompletedRequest(head: requestHead, body: bodyData, context: context)
        }
    }

    private func handleCompletedRequest(head: HTTPRequestHead, body: Data, context: ChannelHandlerContext) {
        let loopBoundContext = NIOLoopBound(context, eventLoop: context.eventLoop)
        let uri = head.uri.split(separator: "?").first.map(String.init) ?? head.uri

        Task { [webhookSecret, dispatcher, statusProvider] in
            let (status, payload) = await route(
                method: head.method,
                uri: uri,
                headers: head.headers,
                body: body,
                secret: webhookSecret,
                dispatcher: dispatcher,
                statusProvider: statusProvider
            )
            loopBoundContext.eventLoop.execute {
                let ctx = loopBoundContext.value
                let channel = ctx.channel
                var headers = HTTPHeaders()
                headers.add(name: "Content-Type", value: "application/json")
                headers.add(name: "Content-Length", value: "\(payload.count)")
                headers.add(name: "Connection", value: "close")
                let respHead = HTTPResponseHead(version: head.version, status: status, headers: headers)
                ctx.write(self.wrapOutboundOut(.head(respHead)), promise: nil)
                var outBuf = channel.allocator.buffer(capacity: payload.count)
                outBuf.writeBytes(payload)
                ctx.write(self.wrapOutboundOut(.body(.byteBuffer(outBuf))), promise: nil)
                ctx.writeAndFlush(self.wrapOutboundOut(.end(nil))).whenComplete { _ in
                    channel.close(promise: nil)
                }
            }
        }
    }

    private func route(
        method: HTTPMethod,
        uri: String,
        headers: HTTPHeaders,
        body: Data,
        secret: String?,
        dispatcher: DaemonTaskDispatcher,
        statusProvider: @Sendable () async -> DaemonStatusSnapshot
    ) async -> (HTTPResponseStatus, Data) {
        switch (method, uri) {
        case (.GET, "/health"):
            return (.ok, Data("{\"status\":\"ok\"}".utf8))

        case (.GET, "/status"):
            let snapshot = await statusProvider()
            let data = (try? JSONEncoder().encode(snapshot)) ?? Data("{}".utf8)
            return (.ok, data)

        case (.POST, "/tasks"):
            guard let task = try? JSONDecoder().decode(InboundAgentTask.self, from: body) else {
                return (.badRequest, Data("{\"error\":\"Invalid task JSON\"}".utf8))
            }
            let res = await dispatcher(task)
            return (.accepted, (try? JSONEncoder().encode(res)) ?? Data("{}".utf8))

        case (.POST, "/webhooks/github"):
            if let secret, !secret.isEmpty {
                let sig = headers.first(name: "X-Hub-Signature-256") ?? ""
                guard WebhookSigner.verify(payload: body, signatureHeader: sig, secret: secret) else {
                    return (.unauthorized, Data("{\"error\":\"Invalid HMAC signature\"}".utf8))
                }
            }
            let eventName = headers.first(name: "X-GitHub-Event") ?? "webhook"
            let rawText = String(data: body, encoding: .utf8) ?? "{}"
            let task = InboundAgentTask(
                source: "github:\(eventName)",
                prompt: "Triage GitHub event '\(eventName)':\n\(rawText.prefix(4000))",
                mode: .plan
            )
            let res = await dispatcher(task)
            return (.accepted, (try? JSONEncoder().encode(res)) ?? Data("{}".utf8))

        default:
            return (.notFound, Data("{\"error\":\"Not found\"}".utf8))
        }
    }
}
