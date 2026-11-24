# WaveshareUSBCan-Mac

A native macOS app for the **Waveshare USB-CAN-A** CAN bus adapter.

Waveshare ships only a Windows application (`USBCANV2.12.exe`). This is a from-scratch
SwiftUI rewrite for Apple Silicon with the same feature set: a live frame trace,
adapter configuration, manual and timed frame sending, automatic replies, and the
receive-ID filter.

The wire protocol was recovered by reverse engineering the vendor's executable and
verified byte-for-byte against the hardware — see [Wire protocol](#wire-protocol) below.
There is no vendor SDK, DLL or driver shim involved; the app talks to the adapter
directly over the serial port.

> **If you only read one section, read the next one.** On macOS this adapter does not
> work with Apple's built-in driver, and the failure is completely silent.

---

## ⚠️ Read this first: you must install WCH's driver

**Without it the adapter will appear to work and then do nothing at all.** No error,
no warning, no received frames. It looks exactly like broken hardware. It isn't.

### Why

The USB-CAN-A talks to the host over a CH340 bridge at a **fixed 2,000,000 baud**.
macOS `termios` has no standard constant above `B230400`, so anything faster has to be
programmed through the `IOSSIOSPEED` ioctl. **Apple's built-in `AppleUSBCHCOM` driver
computes that divisor incorrectly and delivers almost exactly half the requested rate.**

Measured on macOS 27.2, Apple's driver, 100 KB transfers:

| Requested | Actually on the wire | |
|---|---|---|
| **2,000,000** | **1,012,950** | ❌ **half — broken** |
| 460,800 | 415,998 | ✅ |
| 230,400 | 208,545 | ✅ |
| 115,200 | 105,250 | ✅ |

Only the top of the range is wrong, so nothing reveals the bug until something needs
2 Mbaud. The adapter receives a corrupted bit stream, cannot parse a single command,
and never answers.

**Lowering the baud rate does not help** — the adapter speaks only 2,000,000 baud.

### Get it here

WCH's official GitHub organisation:
**https://github.com/WCHSoftGroup/ch34xser_macos**

Vendor page: http://www.wch.cn/downloads/CH341SER_MAC_ZIP.html

Verify before installing — the package is signed and notarized:

```bash
pkgutil --check-signature CH34xVCPDriver.pkg
# Developer ID Installer: Nanjing Qinheng Microelectronics Co., Ltd. (5JZGQTGU4W)
# Notarization: trusted by the Apple notary service
```

"Nanjing Qinheng Microelectronics" is WCH's legal name. If you don't see that, stop.

### Install it

1. **Run the `.pkg`.** Double-click it — `sudo installer` needs a real TTY and will
   fail from a non-interactive shell.
2. **Open `CH34xVCPDriver` from Launchpad and click Install *inside the app*.**
   This step is the one everybody misses. The pkg only places the app; that button is
   what activates the driver extension.
3. **Approve it** in System Settings → General → Login Items & Extensions →
   Driver Extensions.
4. **Unplug and replug the adapter.** Until you do, the already-enumerated device
   stays bound to Apple's driver and nothing changes.

### Confirm it took

```bash
systemextensionsctl list
# 5JZGQTGU4W  cn.wch.CH34xVCPDriver (1.0/1)  [activated enabled]

ls /dev/cu.*
# /dev/cu.wchusbserial130     <- WCH's driver.  Correct.
# /dev/cu.usbserial-130       <- Apple's driver. 2 Mbaud will NOT work.
```

**The device node name is the quickest tell.** `wchusbserial` means you're fine;
`usbserial` means you are not. This app checks for you and flags it in the port list
and the status bar.

### Uninstalling

Move `CH34xVCPDriver.app` to the Trash and restart. WCH documents nothing more
thorough than that for macOS 11+, so expect the system extension record to linger.

---

## What it does

Feature parity with the Windows application:

| Panel | Features |
|---|---|
| **Trace view** | Row limit, Display receive only, Overlay display, Pause, Clear, Save, Auto Save. Columns: No, Direction, Time, Frame Format, Frame Type, Frame Id, Length, Data |
| **Must be Configured** | Port + Find + Open/Close + serial baud; CAN Mode (Normal / Loop back / Silent / Loop back & Silent), Frame Type, CAN bit rate, SYNC_SEG, BS1, BS2, Prescaler, Manual bit timing, Only Send once, Filter ID, Mask ID, CAN Bus Status, Set and Start; Fixed 20-byte or Variable-length framing |
| **Manually Send** | Add / remove rows, per-row Send, save to file |
| **Automatically Send** | Per-row interval and enable, Send in sequence, Cycle, Stop |
| **Auto Reply** | Reply automatically to a matching receive ID |
| **Special Features** | Change the adapter's bit rate; configure the receive ID filter (Don't upload / Upload only / All Uploaded, max 50 IDs) |
| **Help** | Usage and the driver troubleshooting above |

## Build

Requires Xcode 27+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen          # if needed
xcodegen generate
xcodebuild -project USBCANMac.xcodeproj -scheme USBCANMac -configuration Release build
```

Run the tests:

```bash
xcodebuild -project USBCANMac.xcodeproj -scheme USBCANMac \
  test -destination 'platform=macOS,arch=arm64'
```

`USBCANMac.xcodeproj` is generated from `project.yml` and is not committed.

## Wire protocol

Recovered from `USBCANV2.12.exe` and verified byte-for-byte against a working Python
implementation and against the hardware. All commands share a frame:

```
0xAA 0x55 <cmd> <payload…> <checksum>
checksum = sum of bytes from index 2 up to, but not including, the checksum byte
```

**Settings (0x12), 20 bytes** — sent by "Set and Start":

```
AA 55 12 <speed> <frameType> <filterID x4 LE> <maskID x4 LE>
         <mode> <autoRetransmit> <reserved x4> <checksum>
```

**Fixed 20-byte data frame:**

```
AA 55 01 <1=std|2=ext> <1=data|2=remote> <ID x4 LE> <DLC>
         <data x8, zero padded> <reserved> <checksum>
```

**Variable-length data frame:**

```
AA <0xC0 | ext<<5 | rtr<<4 | dlc> <ID LSB-first, 2 or 4 bytes> <data> 55
length = dlc+5 standard, dlc+7 extended
```

**Receive ID filter (0x10 = All Uploaded, 0x11 = Upload only):**

```
AA 55 <cmd> <count> <ID x4 LE each> <checksum>
```

### Two traps worth knowing

**A payload byte may itself be `0x55`.** Frames must be measured by the length implied
by the type byte, never found by scanning for the terminator.

**The adapter replies in variable-length framing after the `0x12` settings command,
even when the host is sending fixed 20-byte frames.** A decoder pinned to the
configured mode silently discards every reply — which, again, is indistinguishable
from an adapter that is not responding. The decoder here dispatches on the bytes
actually received, not on the configured mode. There is a regression test for this.

## Known gaps

- **CAN Bus Status** sends a request byte that has **not** been confirmed against the
  vendor binary, so the adapter may not answer it. The reply parsing matches the
  vendor application's wording. Everything else here is verified.
- The Fixed/Variable radio selects the **transmit** framing. The settings command has
  no field for it, and how the vendor application switches the adapter's receive
  framing is not yet established — hence the content-driven decoder.

## Licence and attribution

GPL-3.0. See [LICENSE](LICENSE).

Independent software. **Not affiliated with, endorsed by, or supported by Waveshare or
Nanjing Qinheng Microelectronics.** Use at your own risk.

The application icon is Waveshare's own mark, extracted from their distributed
executable so the app is recognisable alongside the hardware. It is their trademark,
not part of this project's licence. If you fork this for anything resembling
distribution under your own name, replace it.

"USB-CAN-A" and "Waveshare" are used only to identify the hardware this software
drives.
