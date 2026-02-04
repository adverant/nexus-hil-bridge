/**
 * HIL Bridge Application Delegate
 *
 * Manages the menubar app lifecycle, status display, and coordinates
 * between the WebSocket client and hardware manager.
 */

import AppKit
import Foundation
import Logging

// MARK: - App Delegate

class HILBridgeAppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Properties

    private var statusItem: NSStatusItem!
    private var statusMenu: NSMenu!

    private let logger = Logger(label: "ai.adverant.hil-bridge")
    private let hardwareManager = HardwareManager.shared
    private let cloudClient = CloudWebSocketClient.shared
    private let localServer = LocalHTTPServer.shared

    private var connectionStatusItem: NSMenuItem!
    private var hardwareStatusItem: NSMenuItem!
    private var devicesSubmenu: NSMenu!

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("Nexus HIL Bridge starting...")

        setupMenuBar()
        startServices()

        logger.info("Nexus HIL Bridge ready")
    }

    func applicationWillTerminate(_ notification: Notification) {
        logger.info("Nexus HIL Bridge shutting down...")
        stopServices()
    }

    // MARK: - Menu Bar Setup

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "cpu", accessibilityDescription: "HIL Bridge")
            button.image?.isTemplate = true
        }

        statusMenu = NSMenu()

        // Title
        let titleItem = NSMenuItem(title: "Nexus HIL Bridge", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        statusMenu.addItem(titleItem)

        statusMenu.addItem(NSMenuItem.separator())

        // Connection Status
        connectionStatusItem = NSMenuItem(title: "Cloud: Disconnected", action: nil, keyEquivalent: "")
        connectionStatusItem.image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil)
        connectionStatusItem.image?.isTemplate = false
        statusMenu.addItem(connectionStatusItem)

        // Hardware Status
        hardwareStatusItem = NSMenuItem(title: "Hardware: Scanning...", action: nil, keyEquivalent: "")
        statusMenu.addItem(hardwareStatusItem)

        statusMenu.addItem(NSMenuItem.separator())

        // Devices Submenu
        let devicesItem = NSMenuItem(title: "Connected Devices", action: nil, keyEquivalent: "")
        devicesSubmenu = NSMenu()
        devicesItem.submenu = devicesSubmenu
        statusMenu.addItem(devicesItem)

        statusMenu.addItem(NSMenuItem.separator())

        // Actions
        let scanItem = NSMenuItem(title: "Scan for Devices", action: #selector(scanForDevices), keyEquivalent: "r")
        scanItem.target = self
        statusMenu.addItem(scanItem)

        let reconnectItem = NSMenuItem(title: "Reconnect to Cloud", action: #selector(reconnectToCloud), keyEquivalent: "c")
        reconnectItem.target = self
        statusMenu.addItem(reconnectItem)

        statusMenu.addItem(NSMenuItem.separator())

        // Settings
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        statusMenu.addItem(settingsItem)

        let logsItem = NSMenuItem(title: "View Logs", action: #selector(viewLogs), keyEquivalent: "l")
        logsItem.target = self
        statusMenu.addItem(logsItem)

        statusMenu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(title: "Quit HIL Bridge", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        statusMenu.addItem(quitItem)

        statusItem.menu = statusMenu
    }

    // MARK: - Services

    private func startServices() {
        // Start local HTTP server for browser communication
        localServer.start()

        // Start hardware discovery
        hardwareManager.onDevicesChanged = { [weak self] devices in
            self?.updateDevicesMenu(devices)
        }
        hardwareManager.startDiscovery()

        // Connect to cloud
        cloudClient.onConnectionStatusChanged = { [weak self] status in
            self?.updateConnectionStatus(status)
        }
        cloudClient.connect()
    }

    private func stopServices() {
        cloudClient.disconnect()
        hardwareManager.stopDiscovery()
        localServer.stop()
    }

    // MARK: - UI Updates

    private func updateConnectionStatus(_ status: ConnectionStatus) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            switch status {
            case .connected:
                self.connectionStatusItem.title = "Cloud: Connected"
                self.connectionStatusItem.image = self.coloredCircle(.systemGreen)
                self.statusItem.button?.image = NSImage(systemSymbolName: "cpu.fill", accessibilityDescription: nil)

            case .connecting:
                self.connectionStatusItem.title = "Cloud: Connecting..."
                self.connectionStatusItem.image = self.coloredCircle(.systemYellow)

            case .disconnected:
                self.connectionStatusItem.title = "Cloud: Disconnected"
                self.connectionStatusItem.image = self.coloredCircle(.systemRed)
                self.statusItem.button?.image = NSImage(systemSymbolName: "cpu", accessibilityDescription: nil)

            case .error(let message):
                self.connectionStatusItem.title = "Cloud: Error - \(message)"
                self.connectionStatusItem.image = self.coloredCircle(.systemRed)
            }
        }
    }

    private func updateDevicesMenu(_ devices: [HardwareDevice]) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.devicesSubmenu.removeAllItems()

            if devices.isEmpty {
                let noDevicesItem = NSMenuItem(title: "No devices found", action: nil, keyEquivalent: "")
                noDevicesItem.isEnabled = false
                self.devicesSubmenu.addItem(noDevicesItem)
            } else {
                for device in devices {
                    let item = NSMenuItem(title: "\(device.name) (\(device.type.rawValue))", action: nil, keyEquivalent: "")
                    item.image = device.isConnected ? self.coloredCircle(.systemGreen) : self.coloredCircle(.systemGray)
                    self.devicesSubmenu.addItem(item)
                }
            }

            self.hardwareStatusItem.title = "Hardware: \(devices.count) device(s)"
        }
    }

    private func coloredCircle(_ color: NSColor) -> NSImage {
        let size = NSSize(width: 10, height: 10)
        let image = NSImage(size: size)
        image.lockFocus()
        color.setFill()
        NSBezierPath(ovalIn: NSRect(origin: .zero, size: size)).fill()
        image.unlockFocus()
        return image
    }

    // MARK: - Actions

    @objc private func scanForDevices() {
        logger.info("Manual device scan triggered")
        hardwareManager.rescan()
    }

    @objc private func reconnectToCloud() {
        logger.info("Manual cloud reconnect triggered")
        cloudClient.reconnect()
    }

    @objc private func openSettings() {
        // Open settings window
        let alert = NSAlert()
        alert.messageText = "HIL Bridge Settings"
        alert.informativeText = "Settings panel coming soon.\n\nLocal Server: http://localhost:31415"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func viewLogs() {
        // Open log file in Console.app
        let logPath = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Logs/NexusHILBridge/hil-bridge.log")
        NSWorkspace.shared.open(logPath)
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - Connection Status

enum ConnectionStatus {
    case connected
    case connecting
    case disconnected
    case error(String)
}
