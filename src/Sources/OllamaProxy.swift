import Foundation
import Network

/// Ollama-compatible proxy server on port 11434 that translates between
/// Ollama API format and OpenAI API format, forwarding to ThinkingProxy (8317).
class OllamaProxy {
    private var listener: NWListener?
    let proxyPort: UInt16 = 11434
    private let targetPort: UInt16 = 8317
    private let targetHost = "127.0.0.1"
    private(set) var isRunning = false
    private let stateQueue = DispatchQueue(label: "io.automaze.vibeproxy.ollama-proxy-state")

    /// Whether we're translating a /api/chat or /api/generate request
    private enum ResponseMode {
        case chat
        case generate
    }

    /// Tracks partial SSE data across receive callbacks for streaming translation
    private final class StreamTranslationState {
        var buffer = ""
        var model = ""
        var mode: ResponseMode = .chat
    }

    func start() {
        guard !isRunning else {
            NSLog("[OllamaProxy] Already running")
            return
        }

        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            // Restrict listener to loopback only (never bind to 0.0.0.0)
            parameters.requiredInterfaceType = .loopback

            guard let port = NWEndpoint.Port(rawValue: proxyPort) else {
                NSLog("[OllamaProxy] Invalid port: %d", proxyPort)
                return
            }
            listener = try NWListener(using: parameters, on: port)

            listener?.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    DispatchQueue.main.async { self?.isRunning = true }
                    NSLog("[OllamaProxy] Listening on port %d", self?.proxyPort ?? 0)
                case .failed(let error):
                    NSLog("[OllamaProxy] Failed: %@", "\(error)")
                    DispatchQueue.main.async { self?.isRunning = false }
                case .cancelled:
                    NSLog("[OllamaProxy] Cancelled")
                    DispatchQueue.main.async { self?.isRunning = false }
                default:
                    break
                }
            }

            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }

            listener?.start(queue: .global(qos: .userInitiated))
        } catch {
            NSLog("[OllamaProxy] Failed to start: %@", "\(error)")
        }
    }

    func stop() {
        stateQueue.sync {
            guard isRunning else { return }
            listener?.cancel()
            listener = nil
            DispatchQueue.main.async { [weak self] in
                self?.isRunning = false
            }
            NSLog("[OllamaProxy] Stopped")
        }
    }

    // MARK: - Connection handling

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        receiveRequest(from: connection, accumulatedData: Data())
    }

    private func receiveRequest(from connection: NWConnection, accumulatedData: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1048576) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            if let error = error {
                NSLog("[OllamaProxy] Receive error: %@", "\(error)")
                connection.cancel()
                return
            }

            guard let data = data, !data.isEmpty else {
                if isComplete { connection.cancel() }
                return
            }

            var accumulated = accumulatedData
            accumulated.append(data)

            guard let requestString = String(data: accumulated, encoding: .utf8),
                  let headerEndRange = requestString.range(of: "\r\n\r\n") else {
                if !isComplete {
                    self.receiveRequest(from: connection, accumulatedData: accumulated)
                } else {
                    self.processRequest(data: accumulated, connection: connection)
                }
                return
            }

            // Check Content-Length to see if body is complete
            let headerEndIndex = requestString.distance(from: requestString.startIndex, to: headerEndRange.upperBound)
            let headerPart = String(requestString.prefix(headerEndIndex))
            if let clLine = headerPart.components(separatedBy: "\r\n").first(where: { $0.lowercased().starts(with: "content-length:") }),
               let cl = Int(clLine.components(separatedBy: ":")[1].trimmingCharacters(in: .whitespaces)) {
                let currentBodyLength = accumulated.count - headerEndIndex
                if currentBodyLength < cl {
                    self.receiveRequest(from: connection, accumulatedData: accumulated)
                    return
                }
            }

            self.processRequest(data: accumulated, connection: connection)
        }
    }

    // MARK: - Request processing

    private func processRequest(data: Data, connection: NWConnection) {
        guard let requestString = String(data: data, encoding: .utf8) else {
            sendError(to: connection, statusCode: 400, message: "Invalid request")
            return
        }

        let lines = requestString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            sendError(to: connection, statusCode: 400, message: "Invalid request line")
            return
        }

        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else {
            sendError(to: connection, statusCode: 400, message: "Invalid request format")
            return
        }

        let method = parts[0]
        let path = parts[1]
        NSLog("[OllamaProxy] %@ %@", method, path)

        // Extract body
        var bodyString = ""
        if let bodyRange = requestString.range(of: "\r\n\r\n") {
            bodyString = String(requestString[bodyRange.upperBound...])
        }

        // Route endpoints
        if method == "GET" && (path == "/" || path == "/api" || path == "/api/") {
            sendPlainText(to: connection, text: "Ollama is running")
            return
        }

        if method == "GET" && path == "/api/tags" {
            forwardModelList(connection: connection)
            return
        }

        if method == "POST" && path == "/api/chat" {
            handleChatRequest(body: bodyString, connection: connection)
            return
        }

        if method == "POST" && path == "/api/generate" {
            handleGenerateRequest(body: bodyString, connection: connection)
            return
        }

        sendError(to: connection, statusCode: 404, message: "Not Found")
    }

    // MARK: - /api/tags → /v1/models

    private func forwardModelList(connection: NWConnection) {
        guard let port = NWEndpoint.Port(rawValue: targetPort) else {
            sendError(to: connection, statusCode: 500, message: "Internal error")
            return
        }

        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(targetHost), port: port)
        let targetConnection = NWConnection(to: endpoint, using: .tcp)

        targetConnection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                let request = "GET /v1/models HTTP/1.1\r\nHost: \(self.targetHost):\(self.targetPort)\r\nConnection: close\r\n\r\n"
                targetConnection.send(content: request.data(using: .utf8), completion: .contentProcessed({ error in
                    if let error = error {
                        NSLog("[OllamaProxy] Send models error: %@", "\(error)")
                        targetConnection.cancel()
                        connection.cancel()
                    } else {
                        self.receiveFullResponse(from: targetConnection) { responseData in
                            self.translateModelListResponse(responseData: responseData, connection: connection)
                        }
                    }
                }))
            case .failed(let error):
                NSLog("[OllamaProxy] Models connection failed: %@", "\(error)")
                self.sendError(to: connection, statusCode: 502, message: "Bad Gateway")
                targetConnection.cancel()
            default:
                break
            }
        }

        targetConnection.start(queue: .global(qos: .userInitiated))
    }

    private func translateModelListResponse(responseData: Data, connection: NWConnection) {
        guard let responseString = String(data: responseData, encoding: .utf8),
              let bodyRange = responseString.range(of: "\r\n\r\n") else {
            sendError(to: connection, statusCode: 502, message: "Bad upstream response")
            return
        }

        var bodyStr = String(responseString[bodyRange.upperBound...])

        // Handle chunked transfer encoding - de-chunk the body
        let headerPart = String(responseString[..<bodyRange.lowerBound]).lowercased()
        if headerPart.contains("transfer-encoding: chunked") {
            bodyStr = deChunk(bodyStr)
        }

        guard let bodyData = bodyStr.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
              let dataArray = json["data"] as? [[String: Any]] else {
            sendError(to: connection, statusCode: 502, message: "Invalid upstream model response")
            return
        }

        let now = ISO8601DateFormatter().string(from: Date())
        // Filter out Codex models — this proxy is for chat clients
        let filtered = dataArray.filter { item in
            let id = (item["id"] as? String ?? "").lowercased()
            return !id.contains("codex")
        }

        let models: [[String: Any]] = filtered.map { item in
            let id = item["id"] as? String ?? "unknown"
            return [
                "name": id,
                "model": id,
                "modified_at": now,
                "size": 0,
                "digest": "sha256:" + id,
                "details": [
                    "parent_model": "",
                    "format": "gguf",
                    "family": "unknown",
                    "families": [String](),
                    "parameter_size": "unknown",
                    "quantization_level": "unknown"
                ]
            ] as [String: Any]
        }

        let ollamaResponse: [String: Any] = ["models": models]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: ollamaResponse),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            sendError(to: connection, statusCode: 500, message: "JSON encoding failed")
            return
        }

        sendJSON(to: connection, json: jsonString)
    }

    // MARK: - /api/chat → /v1/chat/completions

    private func handleChatRequest(body: String, connection: NWConnection) {
        guard let bodyData = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] else {
            sendError(to: connection, statusCode: 400, message: "Invalid JSON")
            return
        }

        let translated = translateChatToOpenAI(json)
        let streaming = translated["stream"] as? Bool ?? true

        guard let translatedData = try? JSONSerialization.data(withJSONObject: translated),
              let translatedBody = String(data: translatedData, encoding: .utf8) else {
            sendError(to: connection, statusCode: 500, message: "Translation failed")
            return
        }

        let model = json["model"] as? String ?? "unknown"
        forwardToOpenAI(path: "/v1/chat/completions", body: translatedBody, model: model, mode: .chat, streaming: streaming, connection: connection)
    }

    // MARK: - /api/generate → /v1/chat/completions

    private func handleGenerateRequest(body: String, connection: NWConnection) {
        guard let bodyData = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] else {
            sendError(to: connection, statusCode: 400, message: "Invalid JSON")
            return
        }

        let translated = translateGenerateToOpenAI(json)
        let streaming = translated["stream"] as? Bool ?? true

        guard let translatedData = try? JSONSerialization.data(withJSONObject: translated),
              let translatedBody = String(data: translatedData, encoding: .utf8) else {
            sendError(to: connection, statusCode: 500, message: "Translation failed")
            return
        }

        let model = json["model"] as? String ?? "unknown"
        forwardToOpenAI(path: "/v1/chat/completions", body: translatedBody, model: model, mode: .generate, streaming: streaming, connection: connection)
    }

    // MARK: - Request translation

    private func translateChatToOpenAI(_ ollama: [String: Any]) -> [String: Any] {
        var openai: [String: Any] = [:]
        openai["model"] = ollama["model"]
        openai["messages"] = ollama["messages"]
        openai["stream"] = ollama["stream"] ?? true

        // Flatten options
        if let options = ollama["options"] as? [String: Any] {
            for (key, value) in options {
                openai[key] = value
            }
        }

        // Copy known top-level params
        for key in ["temperature", "top_p", "top_k", "seed", "stop"] {
            if let v = ollama[key] { openai[key] = v }
        }

        return openai
    }

    private func translateGenerateToOpenAI(_ ollama: [String: Any]) -> [String: Any] {
        var openai: [String: Any] = [:]
        openai["model"] = ollama["model"]
        openai["stream"] = ollama["stream"] ?? true

        var messages: [[String: Any]] = []
        if let system = ollama["system"] as? String, !system.isEmpty {
            messages.append(["role": "system", "content": system])
        }
        if let prompt = ollama["prompt"] as? String {
            messages.append(["role": "user", "content": prompt])
        }
        openai["messages"] = messages

        // Flatten options
        if let options = ollama["options"] as? [String: Any] {
            for (key, value) in options {
                openai[key] = value
            }
        }

        for key in ["temperature", "top_p", "top_k", "seed", "stop"] {
            if let v = ollama[key] { openai[key] = v }
        }

        return openai
    }

    // MARK: - Forward to OpenAI (ThinkingProxy)

    private func forwardToOpenAI(path: String, body: String, model: String, mode: ResponseMode, streaming: Bool, connection: NWConnection) {
        guard let port = NWEndpoint.Port(rawValue: targetPort) else {
            sendError(to: connection, statusCode: 500, message: "Internal error")
            return
        }

        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(targetHost), port: port)
        let targetConnection = NWConnection(to: endpoint, using: .tcp)

        targetConnection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                let contentLength = body.utf8.count
                let request = "POST \(path) HTTP/1.1\r\n" +
                    "Host: \(self.targetHost):\(self.targetPort)\r\n" +
                    "Content-Type: application/json\r\n" +
                    "Content-Length: \(contentLength)\r\n" +
                    "Connection: close\r\n" +
                    "\r\n" +
                    body

                targetConnection.send(content: request.data(using: .utf8), completion: .contentProcessed({ error in
                    if let error = error {
                        NSLog("[OllamaProxy] Forward send error: %@", "\(error)")
                        targetConnection.cancel()
                        connection.cancel()
                        return
                    }

                    if streaming {
                        self.receiveStreamingResponse(from: targetConnection, model: model, mode: mode, connection: connection)
                    } else {
                        self.receiveFullResponse(from: targetConnection) { responseData in
                            self.translateNonStreamingResponse(responseData: responseData, model: model, mode: mode, connection: connection)
                        }
                    }
                }))

            case .failed(let error):
                NSLog("[OllamaProxy] Forward connection failed: %@", "\(error)")
                self.sendError(to: connection, statusCode: 502, message: "Bad Gateway")
                targetConnection.cancel()
            default:
                break
            }
        }

        targetConnection.start(queue: .global(qos: .userInitiated))
    }

    // MARK: - Non-streaming response translation

    private func translateNonStreamingResponse(responseData: Data, model: String, mode: ResponseMode, connection: NWConnection) {
        guard let responseString = String(data: responseData, encoding: .utf8),
              let bodyRange = responseString.range(of: "\r\n\r\n") else {
            sendError(to: connection, statusCode: 502, message: "Bad upstream response")
            return
        }

        var bodyStr = String(responseString[bodyRange.upperBound...])

        let headerPart = String(responseString[..<bodyRange.lowerBound]).lowercased()
        if headerPart.contains("transfer-encoding: chunked") {
            bodyStr = deChunk(bodyStr)
        }

        guard let bodyData = bodyStr.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any] else {
            sendError(to: connection, statusCode: 502, message: "Invalid upstream response")
            return
        }

        let content = message["content"] as? String ?? ""
        let role = message["role"] as? String ?? "assistant"
        let responseModel = json["model"] as? String ?? model

        var ollamaResponse: [String: Any] = [
            "model": responseModel,
            "done": true,
            "done_reason": "stop",
            "created_at": ISO8601DateFormatter().string(from: Date())
        ]

        switch mode {
        case .chat:
            ollamaResponse["message"] = ["role": role, "content": content]
        case .generate:
            ollamaResponse["response"] = content
        }

        // Add usage if available
        if let usage = json["usage"] as? [String: Any] {
            ollamaResponse["prompt_eval_count"] = usage["prompt_tokens"]
            ollamaResponse["eval_count"] = usage["completion_tokens"]
        }

        guard let jsonData = try? JSONSerialization.data(withJSONObject: ollamaResponse),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            sendError(to: connection, statusCode: 500, message: "JSON encoding failed")
            return
        }

        sendJSON(to: connection, json: jsonString)
    }

    // MARK: - Streaming response translation (SSE → NDJSON)

    private func receiveStreamingResponse(from targetConnection: NWConnection, model: String, mode: ResponseMode, connection: NWConnection) {
        let state = StreamTranslationState()
        state.model = model
        state.mode = mode

        // Send initial HTTP response headers for NDJSON (no Content-Length, no chunked — just stream and close)
        let responseHeaders = "HTTP/1.1 200 OK\r\n" +
            "Content-Type: application/x-ndjson\r\n" +
            "Connection: close\r\n" +
            "\r\n"

        connection.send(content: responseHeaders.data(using: .utf8), completion: .contentProcessed({ [weak self] error in
            if let error = error {
                NSLog("[OllamaProxy] Send streaming headers error: %@", "\(error)")
                targetConnection.cancel()
                connection.cancel()
                return
            }
            self?.streamTranslateNextChunk(from: targetConnection, to: connection, state: state, headersParsed: false, headerBuffer: Data())
        }))
    }

    private func streamTranslateNextChunk(from targetConnection: NWConnection, to connection: NWConnection, state: StreamTranslationState, headersParsed: Bool, headerBuffer: Data) {
        targetConnection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            if let error = error {
                NSLog("[OllamaProxy] Stream receive error: %@", "\(error)")
                targetConnection.cancel()
                connection.cancel()
                return
            }

            guard let data = data, !data.isEmpty else {
                if isComplete {
                    // Send final done line if not already sent
                    self.sendStreamDone(to: connection, state: state)
                    targetConnection.cancel()
                }
                return
            }

            if !headersParsed {
                // Accumulate upstream HTTP headers, skip them
                var buf = headerBuffer
                buf.append(data)
                if let str = String(data: buf, encoding: .utf8),
                   let headerEnd = str.range(of: "\r\n\r\n") {
                    // Headers parsed — feed remaining data as SSE
                    let afterHeaders = String(str[headerEnd.upperBound...])
                    state.buffer += afterHeaders
                    self.processSSEBuffer(state: state, connection: connection)

                    if isComplete {
                        self.sendStreamDone(to: connection, state: state)
                        targetConnection.cancel()
                    } else {
                        self.streamTranslateNextChunk(from: targetConnection, to: connection, state: state, headersParsed: true, headerBuffer: Data())
                    }
                } else if !isComplete {
                    self.streamTranslateNextChunk(from: targetConnection, to: connection, state: state, headersParsed: false, headerBuffer: buf)
                }
                return
            }

            // Already past headers — accumulate SSE data
            if let text = String(data: data, encoding: .utf8) {
                state.buffer += text
            }

            self.processSSEBuffer(state: state, connection: connection)

            if isComplete {
                self.sendStreamDone(to: connection, state: state)
                targetConnection.cancel()
            } else {
                self.streamTranslateNextChunk(from: targetConnection, to: connection, state: state, headersParsed: true, headerBuffer: Data())
            }
        }
    }

    /// Process complete SSE events from the buffer, translate each to NDJSON
    private func processSSEBuffer(state: StreamTranslationState, connection: NWConnection) {
        // Normalize line endings
        state.buffer = state.buffer.replacingOccurrences(of: "\r\n", with: "\n")

        // Extract complete SSE events (separated by double newline)
        while let range = state.buffer.range(of: "\n\n") {
            let event = String(state.buffer[..<range.lowerBound])
            state.buffer = String(state.buffer[range.upperBound...])

            // Process each line in the event
            for line in event.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("data:") else { continue }
                let payload = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)

                if payload == "[DONE]" {
                    // Will be handled by sendStreamDone
                    continue
                }

                guard let payloadData = payload.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
                      let choices = json["choices"] as? [[String: Any]],
                      let choice = choices.first,
                      let delta = choice["delta"] as? [String: Any] else {
                    continue
                }

                let textContent = delta["content"] as? String ?? ""
                let reasoningContent = delta["reasoning_content"] as? String ?? ""

                // Skip reasoning_content chunks — only emit actual content
                let content: String
                if !textContent.isEmpty {
                    content = textContent
                } else if !reasoningContent.isEmpty {
                    // Drop reasoning — client doesn't support thinking display
                    continue
                } else {
                    content = ""
                }
                let role = delta["role"] as? String ?? "assistant"
                let responseModel = json["model"] as? String ?? state.model

                var ollamaChunk: [String: Any] = [
                    "model": responseModel,
                    "created_at": ISO8601DateFormatter().string(from: Date()),
                    "done": false
                ]

                switch state.mode {
                case .chat:
                    ollamaChunk["message"] = ["role": role, "content": content]
                case .generate:
                    ollamaChunk["response"] = content
                }

                if let jsonData = try? JSONSerialization.data(withJSONObject: ollamaChunk),
                   var jsonLine = String(data: jsonData, encoding: .utf8) {
                    jsonLine += "\n"
                    if let lineData = jsonLine.data(using: .utf8) {
                        connection.send(content: lineData, completion: .contentProcessed({ _ in }))
                    }
                }
            }
        }
    }

    private func sendStreamDone(to connection: NWConnection, state: StreamTranslationState) {
        var doneChunk: [String: Any] = [
            "model": state.model,
            "created_at": ISO8601DateFormatter().string(from: Date()),
            "done": true,
            "done_reason": "stop"
        ]

        switch state.mode {
        case .chat:
            doneChunk["message"] = ["role": "assistant", "content": ""]
        case .generate:
            doneChunk["response"] = ""
        }

        if let jsonData = try? JSONSerialization.data(withJSONObject: doneChunk),
           var jsonLine = String(data: jsonData, encoding: .utf8) {
            jsonLine += "\n"
            if let lineData = jsonLine.data(using: .utf8) {
                connection.send(content: lineData, isComplete: true, completion: .contentProcessed({ _ in
                    connection.cancel()
                }))
            }
        }
    }

    // MARK: - Helpers

    private func receiveFullResponse(from connection: NWConnection, accumulated: Data = Data(), completion: @escaping (Data) -> Void) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            var acc = accumulated
            if let data = data { acc.append(data) }

            if isComplete || error != nil {
                connection.cancel()
                completion(acc)
            } else {
                self.receiveFullResponse(from: connection, accumulated: acc, completion: completion)
            }
        }
    }

    private func deChunk(_ body: String) -> String {
        var result = ""
        var remaining = body

        while !remaining.isEmpty {
            // Find chunk size line
            guard let lineEnd = remaining.range(of: "\r\n") ?? remaining.range(of: "\n") else { break }
            let sizeLine = String(remaining[..<lineEnd.lowerBound]).trimmingCharacters(in: .whitespaces)
            remaining = String(remaining[lineEnd.upperBound...])

            guard let size = UInt(sizeLine, radix: 16), size > 0 else { break }

            let chunkContent = String(remaining.prefix(Int(size)))
            result += chunkContent
            remaining = String(remaining.dropFirst(Int(size)))

            // Skip trailing \r\n
            if remaining.hasPrefix("\r\n") {
                remaining = String(remaining.dropFirst(2))
            } else if remaining.hasPrefix("\n") {
                remaining = String(remaining.dropFirst(1))
            }
        }

        return result
    }

    private func sendPlainText(to connection: NWConnection, text: String) {
        guard let bodyData = text.data(using: .utf8) else {
            connection.cancel()
            return
        }
        let response = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: \(bodyData.count)\r\nConnection: close\r\n\r\n"
        var responseData = Data()
        responseData.append(response.data(using: .utf8)!)
        responseData.append(bodyData)
        connection.send(content: responseData, completion: .contentProcessed({ _ in
            connection.cancel()
        }))
    }

    private func sendJSON(to connection: NWConnection, json: String) {
        guard let bodyData = json.data(using: .utf8) else {
            connection.cancel()
            return
        }
        let response = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(bodyData.count)\r\nConnection: close\r\n\r\n"
        var responseData = Data()
        responseData.append(response.data(using: .utf8)!)
        responseData.append(bodyData)
        connection.send(content: responseData, completion: .contentProcessed({ _ in
            connection.cancel()
        }))
    }

    private func sendError(to connection: NWConnection, statusCode: Int, message: String) {
        guard let bodyData = message.data(using: .utf8) else {
            connection.cancel()
            return
        }
        let headers = "HTTP/1.1 \(statusCode) \(message)\r\nContent-Type: text/plain\r\nContent-Length: \(bodyData.count)\r\nConnection: close\r\n\r\n"
        var responseData = Data()
        responseData.append(headers.data(using: .utf8)!)
        responseData.append(bodyData)
        connection.send(content: responseData, completion: .contentProcessed({ _ in
            connection.cancel()
        }))
    }
}
