/**
 * Hardware Driver Protocol
 *
 * Base protocol for all hardware instrument drivers.
 */

import Foundation

// MARK: - Hardware Driver Protocol

protocol HardwareDriver {
    var device: HardwareDevice { get }
    var isConnected: Bool { get }

    func connect() throws
    func disconnect()
    func getFirmwareVersion() throws -> String

    func startCapture(channels: [Int], sampleRate: Double, duration: Double) throws -> CaptureSession
    func stopCapture()

    func readAnalogInput(channel: Int) throws -> Double
    func writeAnalogOutput(channel: Int, value: Double) throws
    func readDigitalInput(channel: Int) throws -> Bool
    func writeDigitalOutput(channel: Int, value: Bool) throws
}

// MARK: - Default Implementations

extension HardwareDriver {
    func readAnalogInput(channel: Int) throws -> Double {
        throw DriverError.notSupported("Analog input not supported")
    }

    func writeAnalogOutput(channel: Int, value: Double) throws {
        throw DriverError.notSupported("Analog output not supported")
    }

    func readDigitalInput(channel: Int) throws -> Bool {
        throw DriverError.notSupported("Digital input not supported")
    }

    func writeDigitalOutput(channel: Int, value: Bool) throws {
        throw DriverError.notSupported("Digital output not supported")
    }
}

// MARK: - Driver Errors

enum DriverError: Error, LocalizedError {
    case connectionFailed(String)
    case communicationError(String)
    case notSupported(String)
    case invalidParameter(String)
    case timeout
    case deviceNotFound

    var errorDescription: String? {
        switch self {
        case .connectionFailed(let msg): return "Connection failed: \(msg)"
        case .communicationError(let msg): return "Communication error: \(msg)"
        case .notSupported(let msg): return "Not supported: \(msg)"
        case .invalidParameter(let msg): return "Invalid parameter: \(msg)"
        case .timeout: return "Operation timed out"
        case .deviceNotFound: return "Device not found"
        }
    }
}
