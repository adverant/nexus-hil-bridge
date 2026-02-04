/**
 * Hardware Manager
 *
 * Discovers and manages connected hardware instruments:
 * - USB device enumeration via IOKit
 * - Network device discovery (mDNS/Bonjour)
 * - Driver loading and initialization
 * - Capture coordination
 */

import Foundation
import IOKit
import IOKit.usb
import Logging

// MARK: - Hardware Manager

class HardwareManager {

    // MARK: - Singleton

    static let shared = HardwareManager()

    // MARK: - Properties

    private let logger = Logger(label: "ai.adverant.hil-bridge.hardware")
    private var discoveryTimer: Timer?
    private var isScanning = false

    private(set) var devices: [HardwareDevice] = []
    private var drivers: [String: HardwareDriver] = [:]
    private var activeCaptures: [String: CaptureSession] = [:]

    // Callbacks
    var onDevicesChanged: (([HardwareDevice]) -> Void)?

    // Known USB Vendor/Product IDs
    private let knownDevices: [(vendorId: Int, productId: Int, type: DeviceType, name: String)] = [
        // National Instruments DAQ
        (0x3923, 0x717A, .daq, "NI USB-6361"),
        (0x3923, 0x7254, .daq, "NI USB-6363"),
        (0x3923, 0x71BC, .daq, "NI USB-6001"),
        (0x3923, 0x71BD, .daq, "NI USB-6002"),

        // Saleae Logic Analyzers
        (0x21A9, 0x1001, .logicAnalyzer, "Saleae Logic Pro 8"),
        (0x21A9, 0x1002, .logicAnalyzer, "Saleae Logic Pro 16"),
        (0x21A9, 0x1003, .logicAnalyzer, "Saleae Logic 8"),
        (0x21A9, 0x1004, .logicAnalyzer, "Saleae Logic 4"),

        // Rigol Oscilloscopes (USB-TMC)
        (0x1AB1, 0x04CE, .oscilloscope, "Rigol DS1054Z"),
        (0x1AB1, 0x04B0, .oscilloscope, "Rigol DS2072A"),
        (0x1AB1, 0x0588, .oscilloscope, "Rigol DS1102E"),

        // Rigol Power Supplies
        (0x1AB1, 0x0E11, .powerSupply, "Rigol DP832"),
        (0x1AB1, 0x0E12, .powerSupply, "Rigol DP832A"),

        // PEAK CAN Analyzers
        (0x0C72, 0x000C, .canAnalyzer, "PEAK PCAN-USB"),

        // Tektronix
        (0x0699, 0x0401, .oscilloscope, "Tektronix TBS1052B"),

        // LabJack
        (0x0CD5, 0x0007, .daq, "LabJack U3-HV"),
        (0x0CD5, 0x0009, .daq, "LabJack U6"),
        (0x0CD5, 0x000D, .daq, "LabJack T7"),
    ]

    // MARK: - Discovery

    func startDiscovery() {
        logger.info("Starting hardware discovery")
        rescan()

        // Periodic rescan
        discoveryTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.rescan()
        }

        // Also watch for USB device changes
        setupUSBNotifications()
    }

    func stopDiscovery() {
        logger.info("Stopping hardware discovery")
        discoveryTimer?.invalidate()
        discoveryTimer = nil
    }

    func rescan() {
        guard !isScanning else { return }
        isScanning = true

        logger.debug("Scanning for hardware devices...")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            var foundDevices: [HardwareDevice] = []

            // Scan USB devices
            foundDevices.append(contentsOf: self.scanUSBDevices())

            // Scan network devices (VISA over TCP, LXI)
            foundDevices.append(contentsOf: self.scanNetworkDevices())

            // Check for Saleae Logic 2 app running
            foundDevices.append(contentsOf: self.scanSaleaeLogic())

            // Merge with existing device states
            let updatedDevices = self.mergeDeviceStates(foundDevices)

            DispatchQueue.main.async {
                self.devices = updatedDevices
                self.isScanning = false
                self.onDevicesChanged?(updatedDevices)

                // Notify cloud
                CloudWebSocketClient.shared.sendDeviceStatus(updatedDevices)
            }
        }
    }

    // MARK: - USB Scanning

    private func scanUSBDevices() -> [HardwareDevice] {
        var devices: [HardwareDevice] = []

        let matchingDict = IOServiceMatching(kIOUSBDeviceClassName)
        var iterator: io_iterator_t = 0

        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &iterator)
        guard result == KERN_SUCCESS else {
            logger.error("Failed to get USB device iterator")
            return devices
        }

        defer { IOObjectRelease(iterator) }

        var device: io_object_t = IOIteratorNext(iterator)
        while device != 0 {
            defer {
                IOObjectRelease(device)
                device = IOIteratorNext(iterator)
            }

            // Get vendor and product IDs
            guard let vendorId = getUSBProperty(device: device, key: "idVendor") as? Int,
                  let productId = getUSBProperty(device: device, key: "idProduct") as? Int else {
                continue
            }

            // Check if it's a known device
            if let knownDevice = knownDevices.first(where: { $0.vendorId == vendorId && $0.productId == productId }) {
                let serialNumber = getUSBProperty(device: device, key: "USB Serial Number") as? String ?? "Unknown"
                let locationId = getUSBProperty(device: device, key: "locationID") as? Int ?? 0

                let hwDevice = HardwareDevice(
                    id: "usb-\(String(format: "%04x", vendorId))-\(String(format: "%04x", productId))-\(locationId)",
                    name: knownDevice.name,
                    type: knownDevice.type,
                    connectionType: .usb,
                    connectionAddress: "usb://\(String(format: "%04x", vendorId)):\(String(format: "%04x", productId))/\(locationId)",
                    serialNumber: serialNumber,
                    firmwareVersion: nil,
                    isConnected: false,
                    capabilities: getCapabilities(for: knownDevice.type)
                )

                devices.append(hwDevice)
                logger.info("Found USB device: \(knownDevice.name) (SN: \(serialNumber))")
            }
        }

        return devices
    }

    private func getUSBProperty(device: io_object_t, key: String) -> Any? {
        IORegistryEntryCreateCFProperty(device, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    private func setupUSBNotifications() {
        // Set up IOKit notifications for USB device attach/detach
        // This would require more complex IOKit notification setup
        // For now, we rely on periodic scanning
    }

    // MARK: - Network Scanning

    private func scanNetworkDevices() -> [HardwareDevice] {
        var devices: [HardwareDevice] = []

        // Common VISA/LXI ports to check
        let visaPorts = [5025, 5555]  // Standard LXI/SCPI ports

        // Check common instrument IP ranges (user can configure these)
        let ipRanges = UserDefaults.standard.stringArray(forKey: "instrumentIPRanges") ?? ["192.168.1"]

        for range in ipRanges {
            for host in 1...254 {
                let ip = "\(range).\(host)"

                for port in visaPorts {
                    if let device = probeNetworkDevice(ip: ip, port: port) {
                        devices.append(device)
                    }
                }
            }
        }

        return devices
    }

    private func probeNetworkDevice(ip: String, port: Int) -> HardwareDevice? {
        // Quick TCP connection test with IDN query
        // This would need proper async implementation for production

        // For now, return nil - network scanning should be done asynchronously
        return nil
    }

    // MARK: - Saleae Logic 2

    private func scanSaleaeLogic() -> [HardwareDevice] {
        var devices: [HardwareDevice] = []

        // Check if Logic 2 is running by trying to connect to its automation server
        let socket = CFSocketCreate(nil, PF_INET, SOCK_STREAM, IPPROTO_TCP, 0, nil, nil)
        guard socket != nil else { return devices }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = CFSwapInt16HostToBig(10430) // Saleae Logic 2 automation port
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let addressData = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: UInt8.self, capacity: MemoryLayout<sockaddr_in>.size) {
                CFDataCreate(nil, $0, MemoryLayout<sockaddr_in>.size)
            }
        }

        // Try quick connect
        let result = CFSocketConnectToAddress(socket, addressData, 1.0)
        CFSocketInvalidate(socket)

        if result == .success {
            // Saleae Logic 2 is running
            let device = HardwareDevice(
                id: "saleae-logic2-local",
                name: "Saleae Logic 2",
                type: .logicAnalyzer,
                connectionType: .socket,
                connectionAddress: "tcp://127.0.0.1:10430",
                serialNumber: "Logic2-App",
                firmwareVersion: nil,
                isConnected: false,
                capabilities: DeviceCapabilities(
                    analogInputs: 8,
                    digitalInputs: 16,
                    analogOutputs: 0,
                    digitalOutputs: 0,
                    maxSampleRate: 500_000_000,
                    adcResolution: 12,
                    protocols: ["spi", "i2c", "uart", "can", "1wire"]
                )
            )
            devices.append(device)
            logger.info("Found Saleae Logic 2 automation server")
        }

        return devices
    }

    // MARK: - Device Management

    func connect(deviceId: String) -> HardwareDevice? {
        guard let index = devices.firstIndex(where: { $0.id == deviceId }) else {
            return nil
        }

        var device = devices[index]

        // Load appropriate driver
        if let driver = loadDriver(for: device) {
            do {
                try driver.connect()
                device.isConnected = true
                device.firmwareVersion = try? driver.getFirmwareVersion()
                drivers[deviceId] = driver
                devices[index] = device

                logger.info("Connected to device: \(device.name)")
                onDevicesChanged?(devices)
                CloudWebSocketClient.shared.sendDeviceStatus(devices)

                return device
            } catch {
                logger.error("Failed to connect to device: \(error)")
            }
        }

        return nil
    }

    func disconnect(deviceId: String) {
        guard let index = devices.firstIndex(where: { $0.id == deviceId }) else {
            return
        }

        if let driver = drivers[deviceId] {
            driver.disconnect()
            drivers.removeValue(forKey: deviceId)
        }

        var device = devices[index]
        device.isConnected = false
        devices[index] = device

        logger.info("Disconnected from device: \(device.name)")
        onDevicesChanged?(devices)
        CloudWebSocketClient.shared.sendDeviceStatus(devices)
    }

    func getDevice(id: String) -> HardwareDevice? {
        devices.first { $0.id == id }
    }

    // MARK: - Capture Operations

    func startCapture(deviceId: String, channels: [Int], sampleRate: Double, duration: Double) -> Bool {
        guard let driver = drivers[deviceId] else {
            logger.error("No driver loaded for device: \(deviceId)")
            return false
        }

        do {
            let session = try driver.startCapture(channels: channels, sampleRate: sampleRate, duration: duration)
            activeCaptures[deviceId] = session

            // Set up streaming callback
            session.onDataReceived = { [weak self] data in
                self?.handleCaptureData(deviceId: deviceId, data: data)
            }

            logger.info("Started capture on device: \(deviceId)")
            return true
        } catch {
            logger.error("Failed to start capture: \(error)")
            return false
        }
    }

    func stopCapture(deviceId: String) {
        if let session = activeCaptures[deviceId] {
            session.stop()
            activeCaptures.removeValue(forKey: deviceId)
            logger.info("Stopped capture on device: \(deviceId)")
        }
    }

    func getLatestCapture(deviceId: String) -> [String: Any]? {
        activeCaptures[deviceId]?.latestData
    }

    private func handleCaptureData(deviceId: String, data: CaptureData) {
        // Stream to cloud
        CloudWebSocketClient.shared.sendCaptureData(data)
    }

    // MARK: - Driver Management

    private func loadDriver(for device: HardwareDevice) -> HardwareDriver? {
        switch device.type {
        case .daq:
            if device.name.contains("NI") {
                return NIDAQDriver(device: device)
            } else if device.name.contains("LabJack") {
                return LabJackDriver(device: device)
            }

        case .logicAnalyzer:
            if device.name.contains("Saleae") {
                return SaleaeDriver(device: device)
            }

        case .oscilloscope:
            return VISASCPIDriver(device: device)

        case .powerSupply:
            return VISASCPIDriver(device: device)

        case .canAnalyzer:
            return PCANDriver(device: device)

        default:
            break
        }

        return nil
    }

    // MARK: - Utilities

    private func mergeDeviceStates(_ newDevices: [HardwareDevice]) -> [HardwareDevice] {
        var merged: [HardwareDevice] = []

        for newDevice in newDevices {
            if let existingIndex = devices.firstIndex(where: { $0.id == newDevice.id }) {
                // Preserve connection state
                var device = newDevice
                device.isConnected = devices[existingIndex].isConnected
                merged.append(device)
            } else {
                merged.append(newDevice)
            }
        }

        return merged
    }

    private func getCapabilities(for type: DeviceType) -> DeviceCapabilities {
        switch type {
        case .daq:
            return DeviceCapabilities(
                analogInputs: 16,
                digitalInputs: 24,
                analogOutputs: 2,
                digitalOutputs: 24,
                maxSampleRate: 2_000_000,
                adcResolution: 16,
                protocols: []
            )

        case .logicAnalyzer:
            return DeviceCapabilities(
                analogInputs: 0,
                digitalInputs: 16,
                analogOutputs: 0,
                digitalOutputs: 0,
                maxSampleRate: 500_000_000,
                adcResolution: 0,
                protocols: ["spi", "i2c", "uart", "can"]
            )

        case .oscilloscope:
            return DeviceCapabilities(
                analogInputs: 4,
                digitalInputs: 0,
                analogOutputs: 0,
                digitalOutputs: 0,
                maxSampleRate: 1_000_000_000,
                adcResolution: 8,
                protocols: []
            )

        case .powerSupply:
            return DeviceCapabilities(
                analogInputs: 0,
                digitalInputs: 0,
                analogOutputs: 3,
                digitalOutputs: 0,
                maxSampleRate: 0,
                adcResolution: 0,
                protocols: []
            )

        case .canAnalyzer:
            return DeviceCapabilities(
                analogInputs: 0,
                digitalInputs: 0,
                analogOutputs: 0,
                digitalOutputs: 0,
                maxSampleRate: 1_000_000,
                adcResolution: 0,
                protocols: ["can", "canfd"]
            )

        default:
            return DeviceCapabilities(
                analogInputs: 0,
                digitalInputs: 0,
                analogOutputs: 0,
                digitalOutputs: 0,
                maxSampleRate: 0,
                adcResolution: 0,
                protocols: []
            )
        }
    }
}

// MARK: - Capture Session

class CaptureSession {
    let deviceId: String
    let channels: [Int]
    let sampleRate: Double
    let duration: Double

    var onDataReceived: ((CaptureData) -> Void)?
    var latestData: [String: Any]?

    private var isRunning = false

    init(deviceId: String, channels: [Int], sampleRate: Double, duration: Double) {
        self.deviceId = deviceId
        self.channels = channels
        self.sampleRate = sampleRate
        self.duration = duration
    }

    func start() {
        isRunning = true
    }

    func stop() {
        isRunning = false
    }
}
