/**
 * Cloud WebSocket Client
 *
 * Maintains persistent WebSocket connection to Nexus cloud for:
 * - Receiving commands (scan, configure, capture, etc.)
 * - Streaming real-time data back to cloud
 * - Reporting device status changes
 */

import Foundation
import Starscream
import SwiftyJSON
import Logging

// MARK: - Cloud WebSocket Client

class CloudWebSocketClient: WebSocketDelegate {

    // MARK: - Singleton

    static let shared = CloudWebSocketClient()

    // MARK: - Properties

    private let logger = Logger(label: "ai.adverant.hil-bridge.websocket")
    private var socket: WebSocket?
    private var connectionActive = false
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 10
    private var reconnectTimer: Timer?
    private var heartbeatTimer: Timer?

    // Configuration
    private var cloudURL: URL {
        let baseURL = UserDefaults.standard.string(forKey: "cloudWebSocketURL")
            ?? "wss://api.adverant.ai/ee-design/ws/hil-bridge"
        return URL(string: baseURL)!
    }

    private var authToken: String? {
        UserDefaults.standard.string(forKey: "authToken")
    }

    private var bridgeId: String {
        // Generate or retrieve a stable bridge ID for this machine
        if let existingId = UserDefaults.standard.string(forKey: "bridgeId") {
            return existingId
        }
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: "bridgeId")
        return newId
    }

    // Callbacks
    var onConnectionStatusChanged: ((ConnectionStatus) -> Void)?
    var onCommandReceived: ((HILCommand) -> Void)?

    // MARK: - Connection Management

    func connect() {
        guard socket == nil else { return }

        logger.info("Connecting to cloud: \(cloudURL.absoluteString)")
        onConnectionStatusChanged?(.connecting)

        var request = URLRequest(url: cloudURL)
        request.timeoutInterval = 30

        // Add authentication headers
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.setValue(bridgeId, forHTTPHeaderField: "X-Bridge-ID")
        request.setValue(getMachineName(), forHTTPHeaderField: "X-Machine-Name")
        request.setValue("1.0.0", forHTTPHeaderField: "X-Bridge-Version")

        socket = WebSocket(request: request)
        socket?.delegate = self
        socket?.connect()
    }

    func disconnect() {
        logger.info("Disconnecting from cloud")
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        socket?.disconnect()
        socket = nil
        connectionActive = false
        onConnectionStatusChanged?(.disconnected)
    }

    func reconnect() {
        disconnect()
        reconnectAttempts = 0
        connect()
    }

    private func scheduleReconnect() {
        guard reconnectAttempts < maxReconnectAttempts else {
            logger.error("Max reconnect attempts reached")
            onConnectionStatusChanged?(.error("Max reconnect attempts reached"))
            return
        }

        let delay = min(pow(2.0, Double(reconnectAttempts)), 60.0) // Exponential backoff, max 60s
        logger.info("Scheduling reconnect in \(delay) seconds (attempt \(reconnectAttempts + 1))")

        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.reconnectAttempts += 1
            self?.connect()
        }
    }

    // MARK: - WebSocket Delegate

    func didReceive(event: WebSocketEvent, client: WebSocketClient) {
        switch event {
        case .connected(let headers):
            logger.info("Connected to cloud. Headers: \(headers)")
            connectionActive = true
            reconnectAttempts = 0
            onConnectionStatusChanged?(.connected)
            startHeartbeat()
            sendRegistration()

        case .disconnected(let reason, let code):
            logger.warning("Disconnected from cloud: \(reason) (code: \(code))")
            connectionActive = false
            heartbeatTimer?.invalidate()
            onConnectionStatusChanged?(.disconnected)
            scheduleReconnect()

        case .text(let text):
            handleMessage(text)

        case .binary(let data):
            handleBinaryMessage(data)

        case .ping(_):
            break

        case .pong(_):
            break

        case .viabilityChanged(let isViable):
            logger.debug("Connection viability changed: \(isViable)")

        case .reconnectSuggested(let shouldReconnect):
            if shouldReconnect {
                logger.info("Reconnect suggested by server")
                reconnect()
            }

        case .cancelled:
            logger.warning("Connection cancelled")
            connectionActive = false
            onConnectionStatusChanged?(.disconnected)

        case .error(let error):
            logger.error("WebSocket error: \(error?.localizedDescription ?? "Unknown")")
            connectionActive = false
            onConnectionStatusChanged?(.error(error?.localizedDescription ?? "Unknown error"))
            scheduleReconnect()

        case .peerClosed:
            logger.warning("Peer closed connection")
            connectionActive = false
            onConnectionStatusChanged?(.disconnected)
            scheduleReconnect()
        }
    }

    // MARK: - Message Handling

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        let json = JSON(data)

        let eventType = json["type"].stringValue
        logger.debug("Received message: \(eventType)")

        switch eventType {
        case "command":
            if let command = parseCommand(json["payload"]) {
                onCommandReceived?(command)
            }

        case "ping":
            sendPong()

        case "config_update":
            handleConfigUpdate(json["payload"])

        case "auth_required":
            logger.warning("Authentication required")
            onConnectionStatusChanged?(.error("Authentication required"))

        default:
            logger.warning("Unknown message type: \(eventType)")
        }
    }

    private func handleBinaryMessage(_ data: Data) {
        // Handle binary data (e.g., firmware uploads)
        logger.debug("Received binary message: \(data.count) bytes")
    }

    private func parseCommand(_ json: JSON) -> HILCommand? {
        let commandType = json["command"].stringValue

        switch commandType {
        case "scan_devices":
            return .scanDevices

        case "connect_device":
            return .connectDevice(deviceId: json["device_id"].stringValue)

        case "disconnect_device":
            return .disconnectDevice(deviceId: json["device_id"].stringValue)

        case "configure_channel":
            return .configureChannel(
                deviceId: json["device_id"].stringValue,
                channel: json["channel"].intValue,
                config: json["config"].dictionaryObject ?? [:]
            )

        case "start_capture":
            return .startCapture(
                deviceId: json["device_id"].stringValue,
                channels: json["channels"].arrayObject as? [Int] ?? [],
                sampleRate: json["sample_rate"].doubleValue,
                duration: json["duration"].doubleValue
            )

        case "stop_capture":
            return .stopCapture(deviceId: json["device_id"].stringValue)

        case "set_output":
            return .setOutput(
                deviceId: json["device_id"].stringValue,
                channel: json["channel"].intValue,
                value: json["value"].doubleValue
            )

        default:
            logger.warning("Unknown command: \(commandType)")
            return nil
        }
    }

    private func handleConfigUpdate(_ json: JSON) {
        // Update local configuration from cloud
        if let wsURL = json["websocket_url"].string {
            UserDefaults.standard.set(wsURL, forKey: "cloudWebSocketURL")
        }
    }

    // MARK: - Sending Messages

    func send<T: Encodable>(_ message: HILMessage<T>) {
        guard connectionActive else {
            logger.warning("Cannot send message - not connected")
            return
        }

        do {
            let data = try JSONEncoder().encode(message)
            if let text = String(data: data, encoding: .utf8) {
                socket?.write(string: text)
            }
        } catch {
            logger.error("Failed to encode message: \(error)")
        }
    }

    func sendDeviceStatus(_ devices: [HardwareDevice]) {
        let message = HILMessage(
            type: "device_status",
            payload: DeviceStatusPayload(
                bridgeId: bridgeId,
                devices: devices.map { $0.toJSON() }
            )
        )
        send(message)
    }

    func sendCaptureData(_ data: CaptureData) {
        let message = HILMessage(
            type: "capture_data",
            payload: data
        )
        send(message)
    }

    func sendMeasurement(_ measurement: Measurement) {
        let message = HILMessage(
            type: "measurement",
            payload: measurement
        )
        send(message)
    }

    private func sendRegistration() {
        let registration = HILMessage(
            type: "bridge_registration",
            payload: BridgeRegistration(
                bridgeId: bridgeId,
                machineName: getMachineName(),
                version: "1.0.0",
                capabilities: getCapabilities()
            )
        )
        send(registration)
    }

    private func sendPong() {
        let pong = HILMessage(type: "pong", payload: EmptyPayload())
        send(pong)
    }

    // MARK: - Heartbeat

    private func startHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            let heartbeat = HILMessage(type: "heartbeat", payload: HeartbeatPayload(
                bridgeId: self?.bridgeId ?? "",
                timestamp: Date().timeIntervalSince1970
            ))
            self?.send(heartbeat)
        }
    }

    // MARK: - Utilities

    private func getMachineName() -> String {
        Host.current().localizedName ?? ProcessInfo.processInfo.hostName
    }

    private func getCapabilities() -> [String] {
        var caps = ["basic_io", "waveform_capture"]

        // Check for available drivers
        if FileManager.default.fileExists(atPath: "/Library/Frameworks/nidaqmx.framework") {
            caps.append("ni_daq")
        }

        // Saleae Logic 2 check
        if FileManager.default.fileExists(atPath: "/Applications/Logic 2.app") {
            caps.append("saleae_logic")
        }

        // PyVISA/SCPI capable
        caps.append("visa_scpi")

        return caps
    }
}

// MARK: - Messages

struct HILMessage<T: Encodable>: Encodable {
    let type: String
    let payload: T
    let timestamp: TimeInterval = Date().timeIntervalSince1970
}

struct EmptyPayload: Encodable {}

struct BridgeRegistration: Encodable {
    let bridgeId: String
    let machineName: String
    let version: String
    let capabilities: [String]
}

struct HeartbeatPayload: Encodable {
    let bridgeId: String
    let timestamp: TimeInterval
}

struct DeviceStatusPayload: Encodable {
    let bridgeId: String
    let devices: [[String: Any]]

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(bridgeId, forKey: .bridgeId)
        // Convert devices to JSON string for encoding
        let data = try JSONSerialization.data(withJSONObject: devices)
        let string = String(data: data, encoding: .utf8) ?? "[]"
        try container.encode(string, forKey: .devices)
    }

    enum CodingKeys: String, CodingKey {
        case bridgeId, devices
    }
}

struct CaptureData: Encodable {
    let deviceId: String
    let channelId: Int
    let timestamp: TimeInterval
    let samples: [Double]
    let sampleRate: Double
}

struct Measurement: Encodable {
    let deviceId: String
    let channelId: Int
    let timestamp: TimeInterval
    let value: Double
    let unit: String
}

// MARK: - Commands

enum HILCommand {
    case scanDevices
    case connectDevice(deviceId: String)
    case disconnectDevice(deviceId: String)
    case configureChannel(deviceId: String, channel: Int, config: [String: Any])
    case startCapture(deviceId: String, channels: [Int], sampleRate: Double, duration: Double)
    case stopCapture(deviceId: String)
    case setOutput(deviceId: String, channel: Int, value: Double)
}
