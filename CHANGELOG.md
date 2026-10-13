# FanCurve release notes

## 0.1.6 — lower background activity

FanCurve 0.1.6 reduces background activity while keeping temperature sampling at one second when Custom control is active.

- Sensor polling adapts to visible windows and the menu bar refresh interval. It pauses in icon-only background mode when Custom control is off.
- Display sleep pauses monitoring when Custom control is off. System sleep returns fan control to macOS; Custom control remains off after wake.
- One monitoring loop replaces the separate sensor and menu bar timers. The menu bar redraws only when its displayed text changes, and an unchanged curve no longer redraws with each sensor update.
- SMC key metadata and selected sensor keys are cached. Temperature and RPM readings remain live.
- Changed fan targets are sent immediately. Identical targets are reasserted every ten seconds.
- Failed returns to macOS automatic control are retried every five seconds until confirmed, including in icon-only mode.
- Rapid OFF/ON changes wait for an in-flight write and restoration to finish before applying the new target.

Existing profiles and preferences are preserved. The release includes an updated privileged helper; run the included `install-helper.sh` with administrator privileges to update the helper as well.

Validation: 29 automated tests passed, including a read-only sensor check on the development Mac. A three-run benchmark of 1,000 sensor polls showed approximately 40% less CPU time for the sensor-reading workload on that Mac; overall battery savings have not been measured.
