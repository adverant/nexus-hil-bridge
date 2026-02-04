/**
 * Local HTTP Server
 *
 * Provides a local REST API for the browser to communicate directly with
 * the HIL Bridge when WebSocket proxy isn't available or for faster local ops.
 *
 * Endpoints:
 * - GET  /health          - Health check
 * - GET  /status          - Bridge status
 * - GET  /devices         - List connected devices
 * - POST /devices/scan    - Trigger device scan
 * - POST /devices/:id/connect     - Connect to device
 * - POST /devices/:id/disconnect  - Disconnect from device
 * - GET  /devices/:id/capture     - Get latest capture data
 *
 * Port: 31415 (default, configurable)
 */

import Foundation
import Network
import Logging

// MARK: - Local HTTP Server

class LocalHTTPServer {

    // MARK: - Singleton

    static let shared = LocalHTTPServer()

    // MARK: - Properties

    private let logger = Logger(label: "ai.adverant.hil-bridge.http")
    private var listener: NWListener?
    private var connections: [NWConnection] = []

    private var port: UInt16 {
        UInt16(UserDefaults.standard.integer(forKey: "localServerPort")) == 0
            ? 31415
            : UInt16(UserDefaults.standard.integer(forKey: "localServerPort"))
    }

    var isRunning: Bool {
        listener?.state == .ready
    }

    // MARK: - Server Lifecycle

    func start() {
        guard listener == nil else {
            logger.warning("Server already running")
            return
        }

        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true

            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
            listener?.stateUpdateHandler = { [weak self] state in
                self?.handleStateChange(state)
            }
            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleNewConnection(connection)
            }
            listener?.start(queue: .main)

            logger.info("Local HTTP server starting on port \(port)")
        } catch {
            logger.error("Failed to start server: \(error)")
        }
    }

    func stop() {
        logger.info("Stopping local HTTP server")
        listener?.cancel()
        listener = nil
        connections.forEach { $0.cancel() }
        connections.removeAll()
    }

    // MARK: - Connection Handling

    private func handleStateChange(_ state: NWListener.State) {
        switch state {
        case .ready:
            logger.info("Server ready on port \(port)")
        case .failed(let error):
            logger.error("Server failed: \(error)")
            stop()
            // Retry after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                self?.start()
            }
        case .cancelled:
            logger.info("Server cancelled")
        default:
            break
        }
    }

    private func handleNewConnection(_ connection: NWConnection) {
        connections.append(connection)

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.receiveRequest(from: connection)
            case .failed, .cancelled:
                self?.connections.removeAll { $0 === connection }
            default:
                break
            }
        }

        connection.start(queue: .main)
    }

    // MARK: - Request Handling

    private func receiveRequest(from connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            if let data = data, !data.isEmpty {
                self?.handleRequest(data, connection: connection)
            }

            if isComplete || error != nil {
                connection.cancel()
            }
        }
    }

    private func handleRequest(_ data: Data, connection: NWConnection) {
        guard let requestString = String(data: data, encoding: .utf8) else {
            sendResponse(connection: connection, status: 400, body: ["error": "Invalid request"])
            return
        }

        // Parse HTTP request
        let lines = requestString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            sendResponse(connection: connection, status: 400, body: ["error": "Invalid request"])
            return
        }

        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else {
            sendResponse(connection: connection, status: 400, body: ["error": "Invalid request"])
            return
        }

        let method = parts[0]
        let path = parts[1]

        logger.debug("Request: \(method) \(path)")

        // Extract request body for POST requests
        var requestBody: Data? = nil
        if let bodyStart = requestString.range(of: "\r\n\r\n") {
            let bodyString = String(requestString[bodyStart.upperBound...])
            requestBody = bodyString.data(using: .utf8)
        }

        // Route request
        routeRequest(method: method, path: path, body: requestBody, connection: connection)
    }

    private func routeRequest(method: String, path: String, body: Data?, connection: NWConnection) {
        // Add CORS headers for browser access
        let corsHeaders = [
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
            "Access-Control-Allow-Headers": "Content-Type, Authorization"
        ]

        // Handle OPTIONS (CORS preflight)
        if method == "OPTIONS" {
            sendResponse(connection: connection, status: 200, headers: corsHeaders, body: [:])
            return
        }

        switch (method, path) {

        // Health Check
        case ("GET", "/health"):
            sendResponse(connection: connection, status: 200, headers: corsHeaders, body: [
                "status": "healthy",
                "version": "1.0.0",
                "uptime": ProcessInfo.processInfo.systemUptime
            ])

        // Bridge Status
        case ("GET", "/status"):
            let status: [String: Any] = [
                "bridgeId": UserDefaults.standard.string(forKey: "bridgeId") ?? "unknown",
                "machineName": Host.current().localizedName ?? "unknown",
                "cloudConnected": CloudWebSocketClient.shared.isConnected,
                "deviceCount": HardwareManager.shared.devices.count,
                "version": "1.0.0"
            ]
            sendResponse(connection: connection, status: 200, headers: corsHeaders, body: status)

        // List Devices
        case ("GET", "/devices"):
            let devices = HardwareManager.shared.devices.map { $0.toJSON() }
            sendResponse(connection: connection, status: 200, headers: corsHeaders, body: ["devices": devices])

        // Scan for Devices
        case ("POST", "/devices/scan"):
            HardwareManager.shared.rescan()
            sendResponse(connection: connection, status: 202, headers: corsHeaders, body: [
                "status": "scanning",
                "message": "Device scan initiated"
            ])

        // Connect to Device
        case let (_, p) where method == "POST" && p.hasPrefix("/devices/") && p.hasSuffix("/connect"):
            let deviceId = extractDeviceId(from: p, suffix: "/connect")
            if let device = HardwareManager.shared.connect(deviceId: deviceId) {
                sendResponse(connection: connection, status: 200, headers: corsHeaders, body: device.toJSON())
            } else {
                sendResponse(connection: connection, status: 404, headers: corsHeaders, body: ["error": "Device not found"])
            }

        // Disconnect from Device
        case let (_, p) where method == "POST" && p.hasPrefix("/devices/") && p.hasSuffix("/disconnect"):
            let deviceId = extractDeviceId(from: p, suffix: "/disconnect")
            HardwareManager.shared.disconnect(deviceId: deviceId)
            sendResponse(connection: connection, status: 200, headers: corsHeaders, body: ["status": "disconnected"])

        // Get Device Info
        case let (_, p) where method == "GET" && p.hasPrefix("/devices/") && !p.contains("/"):
            let deviceId = String(p.dropFirst("/devices/".count))
            if let device = HardwareManager.shared.getDevice(id: deviceId) {
                sendResponse(connection: connection, status: 200, headers: corsHeaders, body: device.toJSON())
            } else {
                sendResponse(connection: connection, status: 404, headers: corsHeaders, body: ["error": "Device not found"])
            }

        // Start Capture
        case let (_, p) where method == "POST" && p.hasPrefix("/devices/") && p.hasSuffix("/capture/start"):
            let deviceId = extractDeviceId(from: p, suffix: "/capture/start")
            if let body = body,
               let config = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                let result = HardwareManager.shared.startCapture(
                    deviceId: deviceId,
                    channels: config["channels"] as? [Int] ?? [0],
                    sampleRate: config["sample_rate"] as? Double ?? 1000,
                    duration: config["duration"] as? Double ?? 1.0
                )
                if result {
                    sendResponse(connection: connection, status: 200, headers: corsHeaders, body: ["status": "capturing"])
                } else {
                    sendResponse(connection: connection, status: 500, headers: corsHeaders, body: ["error": "Failed to start capture"])
                }
            } else {
                sendResponse(connection: connection, status: 400, headers: corsHeaders, body: ["error": "Invalid request body"])
            }

        // Stop Capture
        case let (_, p) where method == "POST" && p.hasPrefix("/devices/") && p.hasSuffix("/capture/stop"):
            let deviceId = extractDeviceId(from: p, suffix: "/capture/stop")
            HardwareManager.shared.stopCapture(deviceId: deviceId)
            sendResponse(connection: connection, status: 200, headers: corsHeaders, body: ["status": "stopped"])

        // Get Latest Capture Data
        case let (_, p) where method == "GET" && p.hasPrefix("/devices/") && p.hasSuffix("/capture"):
            let deviceId = extractDeviceId(from: p, suffix: "/capture")
            if let data = HardwareManager.shared.getLatestCapture(deviceId: deviceId) {
                sendResponse(connection: connection, status: 200, headers: corsHeaders, body: data)
            } else {
                sendResponse(connection: connection, status: 404, headers: corsHeaders, body: ["error": "No capture data"])
            }

        // 404 - Not Found
        default:
            sendResponse(connection: connection, status: 404, headers: corsHeaders, body: ["error": "Not found"])
        }
    }

    // MARK: - Response Helpers

    private func sendResponse(connection: NWConnection, status: Int, headers: [String: String] = [:], body: [String: Any]) {
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: body)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"

            var headerString = "HTTP/1.1 \(status) \(httpStatusText(status))\r\n"
            headerString += "Content-Type: application/json\r\n"
            headerString += "Content-Length: \(jsonData.count)\r\n"

            for (key, value) in headers {
                headerString += "\(key): \(value)\r\n"
            }

            headerString += "\r\n"
            headerString += jsonString

            if let responseData = headerString.data(using: .utf8) {
                connection.send(content: responseData, completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
        } catch {
            logger.error("Failed to send response: \(error)")
            connection.cancel()
        }
    }

    private func httpStatusText(_ code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 202: return "Accepted"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        case 500: return "Internal Server Error"
        default: return "Unknown"
        }
    }

    private func extractDeviceId(from path: String, suffix: String) -> String {
        let withoutPrefix = path.dropFirst("/devices/".count)
        let withoutSuffix = withoutPrefix.dropLast(suffix.count)
        return String(withoutSuffix)
    }
}

// Extension for checking connection state
extension CloudWebSocketClient {
    var isConnected: Bool {
        // This would need to be properly implemented
        return true // Placeholder
    }
}
