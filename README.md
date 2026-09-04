# FanCurve

FanCurve is a native macOS menu bar application for monitoring temperatures and applying a custom fan curve on supported Apple Silicon Macs.

It displays CPU, GPU, and battery temperatures, reports current fan speed, and lets you define how fan RPM should change with temperature. When custom control is disabled, fan management is returned to macOS.

> [!WARNING]
> FanCurve uses undocumented AppleSMC interfaces because macOS does not provide a public API for direct fan control. Compatibility can change after a macOS update. Keep the application visible while testing a curve, and disable custom control immediately if readings or fan behavior appear abnormal.

## Features

- CPU, GPU, and battery temperature monitoring.
- Current fan speed reporting.
- Editable temperature-to-RPM curve.
- A special `0 RPM` target for the lower part of the curve.
- One switch to enable or disable custom control.
- Automatic return to macOS fan management when custom control is disabled or a hardware error occurs.
- Configurable menu bar refresh interval.
- Menu bar display with either a temperature icon or temperature and total RPM.
- Temperature display in Celsius or Fahrenheit.
- Dock and `Command-Tab` presence while the main window is open.

## Compatibility

- macOS 14 or later is required by the package.
- Apple Silicon is required by the provided ARM64 release package.
- Sensor reading and fan control depend on AppleSMC keys exposed by each Mac model and macOS version.
- The current prototype has been tested on a MacBook Pro M5 (`Mac17,2`) running macOS 27 beta.

Other Apple Silicon models may work, but they have not been validated. Fan control starts disabled and remains unavailable until the privileged helper responds successfully.

## Install a release

1. Open the repository's [Releases page](https://github.com/Nyzeix/FanCurve/releases) and download `FanCurve-macOS-arm64.zip`.
2. Extract the archive.
3. Move `FanCurve.app` to the `/Applications` folder.
4. On first launch, Control-click `FanCurve.app`, choose **Open**, then confirm. The current automated build is ad-hoc signed and is not notarized with an Apple Developer ID.
5. Open Terminal in the extracted `FanCurve` folder and install the privileged helper:

   ```bash
   chmod +x install-helper.sh
   sudo ./install-helper.sh
   ```

6. Quit and reopen FanCurve.
7. Confirm that the application reports `AppleSMC control available through the privileged helper.` before enabling **Custom control**.

The installation script copies only these two system files:

```text
/Library/PrivilegedHelperTools/com.paink.FanCurve.helper
/Library/LaunchDaemons/com.paink.FanCurve.helper.plist
```

It then loads or restarts the helper with `launchd`.

## Use FanCurve

1. Open FanCurve from `/Applications` or from its menu bar item.
2. Review the CPU, GPU, battery, and fan readings.
3. Select **Temperature unit** and choose Celsius or Fahrenheit. The selected unit is used throughout the dashboard, curve editor, and menu bar.
4. Adjust the points in the **Fan curve** section. Temperatures must increase from left to right, and fan speed must stay level or increase.
5. Select **Save** to validate and store the curve.
6. Enable **Custom control** only after the readings and limits look coherent.
7. Disable **Custom control** to return fan management to macOS.

A `0 RPM` point is accepted from the application's minimum editable temperature of 35 °C (95 °F). Any non-zero target must remain between the hardware minimum and maximum reported for the fan. macOS and the Mac firmware retain their own thermal protections and may override the requested behavior.

## Build from source

Requirements:

- Xcode with Swift 6.1 or later.
- macOS 14 or later.
- An Apple Silicon Mac for the same architecture as the release package.

Clone and test the project:

```bash
git clone https://github.com/Nyzeix/FanCurve.git
cd FanCurve
swift test
```

Build the application bundle:

```bash
Scripts/build-app.sh
open dist/FanCurve.app
```

Install the helper from the source checkout:

```bash
sudo Scripts/install-helper.sh
```

The source installation script rebuilds the application before installing the helper.

## Distribution workflow

The `Build macOS package` GitHub Actions workflow:

- runs the Swift test suite;
- builds the release application and privileged helper on an ARM64 macOS runner;
- verifies the application bundle and helper contents;
- creates `FanCurve-macOS-arm64.zip` and its SHA-256 checksum;
- uploads the package as a workflow artifact;
- publishes both files to a GitHub Release when a tag matching `v*` is pushed.

To publish a release:

```bash
git tag v0.1.0
git push origin v0.1.0
```

## Project structure

```text
Sources/FanCurve/        SwiftUI application, domain, and application services
Sources/FanCurveSMC/     AppleSMC access shared by the app and helper
Sources/FanCurveXPC/     XPC protocol shared by both executables
Sources/FanCurveHelper/  Privileged helper executable
Resources/               Application and launch daemon property lists
Scripts/                 Local build and helper installation scripts
Tests/                   Domain and hardware read-only tests
```

## Security notes

- The helper validates fan identifiers and RPM limits again before writing to AppleSMC.
- Automated tests do not send real fan commands.
- Hardware write behavior must be validated manually for every supported Mac and macOS version.
- The application is not distributed through the Mac App Store.

## License

No license has been selected yet. All rights are reserved unless a license file is added to the repository.
