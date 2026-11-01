# ⚡ NetSpeed — Network Speed Monitor for Windows

**NetSpeed** is a lightweight, customizable, and feature-rich PowerShell / WinForms application for real-time network traffic monitoring. The app displays a compact floating widget on top of other windows with a live speed graph and tracks daily bandwidth usage.

> [!NOTE]
> 🤖 **Note**: This project and its source code were generated with the help of Artificial Intelligence (AI).

https://github.com/user-attachments/assets/bc9da1c2-0953-4030-ada2-343c286e934f

---

## ✨ Features

- 📊 **Real-Time Monitoring**: Track incoming (Download), outgoing (Upload), and combined network speed.
- 📈 **Live Speed Graph**: Clear visual speed dynamics with a dynamic auto-scaling grid.
- 💾 **Traffic Tracking**: Automatically measures and saves daily network bandwidth consumption with a statistics table.
- ⚙️ **Customizable Appearance**:
  - Full color customization (window background, graph background, grid, speed lines, scale text).
  - Configurable line thickness and graph scale (pixels per data point).
  - Window transparency controls for normal and mouse-hover states.
  - Adjustable speed label positions (Top, Bottom, Left, Right) and font sizes.
- 🔄 **Multiple Units**: Toggle between Bytes/s (KB/s, MB/s) and Bits/s (Kbps, Mbps).
- 🌐 **Network Interface Selector**: Monitor all network adapters combined or lock to a specific adapter (Wi-Fi, Ethernet, VPN, etc.).
- 📌 **Convenient UX**:
  - "Always on Top" and "Pin" modes.
  - Click-Through mode (ignore mouse clicks and pass through to background windows).
  - Automatically saves and restores window dimensions and position.
  - System Tray integration (Tray Icon menu).
  - One-click Desktop Shortcut creation.

---

## 🚀 Quick Start

### Option 1: Executable (`.exe`)
1. Run `NetSpeed.exe`.
2. The widget will appear centered on screen and start displaying live network activity immediately.
3. Right-click the widget to open the context menu for settings.

### Option 2: Run via PowerShell (`.ps1`)
Open PowerShell and run the script:
```powershell
powershell -ExecutionPolicy Bypass -File "NetSpeed.ps1"
```

---

## 🛠 Building `.exe` from Source

The repository includes automated build scripts to compile the `.ps1` script into a standalone `.exe` using the `ps2exe` module.

### How to Build:
1. Double-click `build_exe.bat` (or execute `build_exe.ps1` in PowerShell).
2. The script will automatically install `ps2exe` if missing and compile `NetSpeed.exe`.

---

## 📁 Repository Structure

```text
NetSpeed/
├── NetSpeed.ps1            # Main application source code (PowerShell + WinForms)
├── build_exe.ps1           # Build script (.ps1 -> .exe)
├── build_exe.bat           # One-click batch launcher for compilation
├── netspeed_settings.json  # Default settings template
├── .gitignore              # Git ignore rules (traffic logs, binaries)
└── README.md               # Project documentation
```

---

## 📜 License

Distributed under the **MIT License**. Free for personal and commercial use, modification, and distribution.
