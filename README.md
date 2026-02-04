# Nexus HIL Bridge

<p align="center">
  <img src="docs/images/hil-bridge-icon.png" alt="Nexus HIL Bridge" width="128"/>
</p>

**Nexus HIL Bridge** is a native macOS application that connects your local hardware test instruments to the [Adverant Nexus](https://nexus.adverant.ai) cloud platform, enabling Hardware-in-the-Loop (HIL) testing directly from your browser.

## Features

- **🔌 Auto-Discovery**: Automatically detects connected USB instruments
- **🌐 Cloud Integration**: Seamless WebSocket connection to Nexus EE Design Partner
- **📊 Real-Time Streaming**: Stream waveform data, measurements, and captures to the cloud
- **🔒 Local HTTP API**: Browser-accessible API at `localhost:31415` for direct integration
- **🖥️ Menubar App**: Lightweight system tray application with status display

## Supported Hardware

| Category | Instruments | Protocol |
|----------|-------------|----------|
| **Logic Analyzers** | Saleae Logic Pro 8/16, sigrok-compatible | Saleae SDK, CLI |
| **Oscilloscopes** | Rigol DS/MSO, Tektronix 5-Series | PyVISA/SCPI |
| **Power Supplies** | Rigol DP832, Keysight E36xxA | SCPI |
| **DAQ Systems** | NI USB-6xxx | nidaqmx |
| **CAN Analyzers** | PEAK PCAN-USB | python-can |

## System Requirements

- macOS 13.0 (Ventura) or later
- Apple Silicon (M1/M2/M3) or Intel Mac
- Internet connection for cloud features

## Installation

### Download

Download the latest release from the [Releases](https://github.com/adverant/nexus-hil-bridge/releases/latest) page:

- **macOS**: [NexusHILBridge-macOS.dmg](https://github.com/adverant/nexus-hil-bridge/releases/latest/download/NexusHILBridge-macOS.dmg)

### Install

1. Open the downloaded DMG file
2. Drag **Nexus HIL Bridge** to your Applications folder
3. Launch from Applications or Spotlight

### First Launch

On first launch, macOS may show a security warning. To allow the app:

1. Go to **System Settings → Privacy & Security**
2. Click **Open Anyway** next to the Nexus HIL Bridge message
3. Or right-click the app and select **Open**

## Usage

### Quick Start

1. Launch Nexus HIL Bridge from Applications
2. The app icon appears in your menubar (top-right of screen)
3. Connect your hardware instruments via USB
4. Open [nexus.adverant.ai](https://nexus.adverant.ai) and navigate to **EE Design Partner → HIL Testing**
5. The dashboard will automatically detect your bridge and show connected devices

### Local API

The bridge runs a local HTTP server at `http://localhost:31415` with the following endpoints:

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/status` | GET | Bridge status and device count |
| `/devices` | GET | List connected devices |
| `/devices/:id` | GET | Get device details |
| `/devices/:id/capture` | POST | Start data capture |
| `/devices/:id/measure` | GET | Get current measurement |

#### Example: Check Status

```bash
curl http://localhost:31415/status
```

```json
{
  "bridgeId": "ABC123",
  "machineName": "MacBook Pro",
  "version": "1.0.0",
  "cloudConnected": true,
  "deviceCount": 2
}
```

### Cloud Connection

The bridge maintains a persistent WebSocket connection to:
```
wss://api.adverant.ai/ee-design/ws/hil-bridge
```

This enables:
- Remote device discovery and configuration
- Real-time data streaming to the cloud dashboard
- Coordinated test sequences from the EE Design Partner UI

## Building from Source

### Prerequisites

- Xcode 15+ with Swift 5.9
- macOS 13.0+ SDK

### Build

```bash
# Clone the repository
git clone https://github.com/adverant/nexus-hil-bridge.git
cd nexus-hil-bridge

# Build release
./build-release.sh

# Output: .build/release/NexusHILBridge.app
# Output: .build/release/NexusHILBridge-macOS.dmg
```

### Development Build

```bash
swift build
.build/debug/NexusHILBridge
```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                   Nexus Cloud Dashboard                      │
│              nexus.adverant.ai/ee-design/hil                │
└─────────────────────────┬───────────────────────────────────┘
                          │ WebSocket (wss://)
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                    Nexus HIL Bridge                          │
│  ┌──────────────┐  ┌───────────────┐  ┌─────────────────┐  │
│  │ Cloud WS     │  │ Local HTTP    │  │ Hardware        │  │
│  │ Client       │  │ Server:31415  │  │ Manager         │  │
│  └──────┬───────┘  └───────┬───────┘  └────────┬────────┘  │
│         │                  │                    │           │
│         └──────────────────┼────────────────────┘           │
└─────────────────────────────┼───────────────────────────────┘
                              │ USB/Serial
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    Hardware Instruments                      │
│    Saleae  │  Rigol Scope  │  NI DAQ  │  Power Supply       │
└─────────────────────────────────────────────────────────────┘
```

## Configuration

Configuration is stored in `~/Library/Preferences/ai.adverant.hil-bridge.plist`:

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `cloudWebSocketURL` | String | `wss://api.adverant.ai/ee-design/ws/hil-bridge` | Cloud WebSocket URL |
| `authToken` | String | - | Authentication token |
| `bridgeId` | String | Auto-generated | Unique bridge identifier |
| `localPort` | Int | 31415 | Local HTTP server port |

## Troubleshooting

### Bridge not detected in dashboard

1. Ensure the app is running (check menubar)
2. Check that `http://localhost:31415/status` responds
3. Verify internet connection for cloud sync

### Device not appearing

1. Check USB connection
2. Ensure device drivers are installed
3. Try unplugging and reconnecting the device

### Cloud connection issues

1. Check network connectivity
2. Verify authentication token in settings
3. Check firewall isn't blocking WebSocket connections

## License

MIT License - see [LICENSE](LICENSE) for details.

## Contributing

Contributions are welcome! Please read our [Contributing Guide](CONTRIBUTING.md) for details.

## Support

- **Documentation**: [docs.adverant.ai/hil-bridge](https://docs.adverant.ai/hil-bridge)
- **Issues**: [GitHub Issues](https://github.com/adverant/nexus-hil-bridge/issues)
- **Email**: support@adverant.ai

---

<p align="center">
  Made with ❤️ by <a href="https://adverant.ai">Adverant AI</a>
</p>
