import Foundation
import Network

/// 极简本地 HTTP 服务器: 把 App 内置的 www 目录以 http://127.0.0.1:PORT/ 暴露给 WKWebView
/// (WKWebView 对 file:// 的 XHR 有限制, 走本地 http 最稳)
final class LocalHTTPServer {

    private let root: URL
    private let port: UInt16
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.xingchen.shell.http")

    init(root: URL, port: UInt16) throws {
        self.root = root
        self.port = port
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .init(rawValue: port)!)
        params.allowLocalEndpointReuse = true
        listener = try NWListener(using: params)
    }

    func start() {
        listener?.newConnectionHandler = { [weak self] conn in
            self?.handle(conn)
        }
        listener?.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handle(_ conn: NWConnection) {
        conn.start(queue: queue)
        receive(conn, buffer: Data())
    }

    private func receive(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            var buf = buffer
            if let d = data { buf.append(d) }
            if let range = buf.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(data: buf.subdata(in: 0..<range.lowerBound), encoding: .utf8) ?? ""
                self.respond(conn, head: head)
                return
            }
            if error != nil || isComplete {
                conn.cancel()
                return
            }
            self.receive(conn, buffer: buf)
        }
    }

    private func respond(_ conn: NWConnection, head: String) {
        let lines = head.components(separatedBy: "\r\n")
        guard let first = lines.first else { conn.cancel(); return }
        let parts = first.components(separatedBy: " ")
        guard parts.count >= 2 else { conn.cancel(); return }
        let method = parts[0]
        var path = parts[1]
        if let q = path.firstIndex(of: "?") { path = String(path[..<q]) }
        path = path.removingPercentEncoding ?? path
        while path.hasPrefix("/") { path.removeFirst() }
        if path.isEmpty { path = "index.html" }
        if path.hasSuffix("/") { path += "index.html" }

        var rangeHeader: String? = nil
        for l in lines.dropFirst() {
            if l.lowercased().hasPrefix("range:") {
                rangeHeader = l.dropFirst(6).trimmingCharacters(in: .whitespaces)
            }
        }

        if path.contains("..") {
            sendText(conn, status: "403 Forbidden")
            return
        }

        let fileURL = root.appendingPathComponent(path)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let total = (attrs[.size] as? NSNumber)?.int64Value,
              FileManager.default.fileExists(atPath: fileURL.path) else {
            sendText(conn, status: "404 Not Found")
            return
        }

        var start: Int64 = 0
        var end: Int64 = total - 1
        var partial = false
        if let rh = rangeHeader, rh.hasPrefix("bytes=") {
            let spec = rh.dropFirst(6).split(separator: "-", omittingEmptySubsequences: false)
            if spec.count == 2 {
                if let s = Int64(spec[0]) { start = s }
                if let e = Int64(spec[1]) { end = e }
                if end >= total { end = total - 1 }
                if start <= end && start >= 0 { partial = true }
            }
        }
        let length = end - start + 1

        var header = partial ? "HTTP/1.1 206 Partial Content\r\n" : "HTTP/1.1 200 OK\r\n"
        header += "Content-Type: \(mime(path))\r\n"
        header += "Content-Length: \(length)\r\n"
        header += "Accept-Ranges: bytes\r\n"
        if partial {
            header += "Content-Range: bytes \(start)-\(end)/\(total)\r\n"
        }
        header += "Cache-Control: no-cache\r\n"
        header += "Connection: close\r\n\r\n"

        conn.send(content: Data(header.utf8), completion: .contentProcessed { _ in
            if method.uppercased() == "HEAD" {
                conn.cancel()
                return
            }
            guard let fh = try? FileHandle(forReadingFrom: fileURL) else {
                conn.cancel()
                return
            }
            do { try fh.seek(toOffset: UInt64(start)) } catch { conn.cancel(); return }
            var remain = length
            func pump() {
                if remain <= 0 {
                    try? fh.close()
                    conn.cancel()
                    return
                }
                let chunkSize = Int(min(Int64(256 * 1024), remain))
                let data = fh.readData(ofLength: chunkSize)
                if data.isEmpty {
                    try? fh.close()
                    conn.cancel()
                    return
                }
                remain -= Int64(data.count)
                conn.send(content: data, completion: .contentProcessed { err in
                    if err != nil {
                        try? fh.close()
                        conn.cancel()
                    } else {
                        pump()
                    }
                })
            }
            pump()
        })
    }

    private func sendText(_ conn: NWConnection, status: String) {
        let resp = "HTTP/1.1 \(status)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        conn.send(content: Data(resp.utf8), completion: .contentProcessed { _ in conn.cancel() })
    }

    private func mime(_ path: String) -> String {
        let p = path.lowercased()
        if p.hasSuffix(".html") || p.hasSuffix(".htm") { return "text/html; charset=utf-8" }
        if p.hasSuffix(".js") { return "application/javascript; charset=utf-8" }
        if p.hasSuffix(".json") { return "application/json; charset=utf-8" }
        if p.hasSuffix(".css") { return "text/css; charset=utf-8" }
        if p.hasSuffix(".png") { return "image/png" }
        if p.hasSuffix(".jpg") || p.hasSuffix(".jpeg") { return "image/jpeg" }
        if p.hasSuffix(".webp") { return "image/webp" }
        if p.hasSuffix(".gif") { return "image/gif" }
        if p.hasSuffix(".mp3") { return "audio/mpeg" }
        if p.hasSuffix(".ogg") { return "audio/ogg" }
        if p.hasSuffix(".wav") { return "audio/wav" }
        if p.hasSuffix(".m4a") { return "audio/mp4" }
        if p.hasSuffix(".mp4") { return "video/mp4" }
        if p.hasSuffix(".ttf") { return "font/ttf" }
        if p.hasSuffix(".woff") || p.hasSuffix(".woff2") { return "font/woff" }
        if p.hasSuffix(".svg") { return "image/svg+xml" }
        if p.hasSuffix(".txt") || p.hasSuffix(".atlas") { return "text/plain; charset=utf-8" }
        if p.hasSuffix(".plist") { return "text/xml; charset=utf-8" }
        return "application/octet-stream"
    }
}
