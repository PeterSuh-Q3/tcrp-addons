# sensors addon

Ported from [RROrg/rr-addons sensors](https://github.com/RROrg/rr-addons/tree/main/sensors).
The original 2022 Ing copyright and MIT notices are retained in both shell
scripts. The bundled `sensors-7.1.tgz` is the unmodified RR binary archive;
its contained programs and libraries retain their respective upstream licenses.

MSHELL changes are limited to the installer: read the three payload files from
the extension working directory, use the existing MSHELL Scheduler database
payload from `beep`, and store the installer under `/usr/mshell/addons`.
Neither the RR manifest nor these scripts use a second (`$2`) parameter.

This addon installs `sensors`, `sensors-detect`, and `fancontrol`. It also
enables the RR fan-control service and modifies DSM fan-support settings when
fan inputs are detected. Select it only after validating the motherboard's
sensor-to-PWM mapping; it is not a read-only sensor-display addon.
