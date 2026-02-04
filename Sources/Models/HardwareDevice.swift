/**
 * Hardware Device Model
 *
 * Represents a connected or discovered hardware instrument.
 */

import Foundation

// MARK: - Device Type

enum DeviceType: String, Codable {
    case daq = "daq"
    case oscilloscope = "oscilloscope"
    case logicAnalyzer = "logic_analyzer"
    case powerSupply = "power_supply"
    case canAnalyzer = "can_analyzer"
    case motorEmulator = "motor_emulator"
    case multimeter = "multimeter"
    case signalGenerator = "signal_generator"
    case unknown = "unknown"
}

// MARK: - Connection Type

enum ConnectionType: String, Codable {
    case usb = "usb"
    case ethernet = "ethernet"
    case gpib = "gpib"
    case serial = "serial"
    case socket = "socket"
    case bluetooth = "bluetooth"
}

// MARK: - Device Capabilities

struct DeviceCapabilities: Codable {
    let analogInputs: Int
    let digitalInputs: Int
    let analogOutputs: Int
    let digitalOutputs: Int
    let maxSampleRate: Int
    let adcResolution: Int
    let protocols: [String]

    func toJSON() -> [String: Any] {
        [
            "analog_inputs": analogInputs,
            "digital_inputs": digitalInputs,
            "analog_outputs": analogOutputs,
            "digital_outputs": digitalOutputs,
            "max_sample_rate": maxSampleRate,
            "adc_resolution": adcResolution,
            "protocols": protocols
        ]
    }
}

// MARK: - Hardware Device

struct HardwareDevice: Codable, Identifiable {
    let id: String
    let name: String
    let type: DeviceType
    let connectionType: ConnectionType
    let connectionAddress: String
    let serialNumber: String
    var firmwareVersion: String?
    var isConnected: Bool
    let capabilities: DeviceCapabilities

    func toJSON() -> [String: Any] {
        [
            "id": id,
            "name": name,
            "type": type.rawValue,
            "connection_type": connectionType.rawValue,
            "connection_address": connectionAddress,
            "serial_number": serialNumber,
            "firmware_version": firmwareVersion ?? "Unknown",
            "is_connected": isConnected,
            "capabilities": capabilities.toJSON()
        ]
    }
}
