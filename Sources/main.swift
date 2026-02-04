/**
 * Nexus HIL Bridge - Local Hardware Bridge for Cloud HIL Testing
 *
 * This macOS application bridges cloud-based HIL testing UI with local hardware:
 * - Discovers connected instruments (DAQ, oscilloscopes, logic analyzers)
 * - Maintains WebSocket connection to Nexus cloud
 * - Executes hardware commands from cloud
 * - Streams captured data back to cloud in real-time
 *
 * Supported Hardware:
 * - National Instruments DAQ (via NI-DAQmx)
 * - Saleae Logic Analyzers (via Logic 2 automation API)
 * - Rigol/Tektronix Oscilloscopes (via VISA/SCPI)
 * - Rigol Power Supplies (via SCPI)
 * - PEAK CAN Analyzers (via SocketCAN bridge)
 *
 * Copyright 2026 Adverant AI. All rights reserved.
 */

import Foundation
import AppKit

// Start the application
let app = NSApplication.shared
let delegate = HILBridgeAppDelegate()
app.delegate = delegate

// Run as agent (menubar only, no dock icon)
app.setActivationPolicy(.accessory)
app.run()
