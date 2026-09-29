# sensors — standalone DSM installer

Install the [RR-derived sensors addon](..) directly on a running DSM system,
without rebuilding the MSHELL loader. The original RR scripts retain their
2022 Ing copyright and MIT notices. The unmodified RR binary archive retains
its own upstream licensing terms.

The default installation provides the `sensors` command and supporting tools.
It does **not** start fan control or alter DSM fan settings. It displays RPM
only when a compatible kernel driver already exposes `fan*_input`.
The `sensors` command wrapper points the unmodified RR binary at the bundled
configuration file, because that binary was built with the RR SPK's config
directory as its default.

```bash
curl -fLsS https://raw.githubusercontent.com/PeterSuh-Q3/tcrp-addons/main/sensors/standalone/install.sh | sudo bash
```

After verifying the board's fan/PWM mapping, opt in to RR automatic fan
control. The installer requires exposed fan and PWM sysfs channels and
preserves an existing `Fancontrol` Scheduler task:

```bash
curl -fLsS https://raw.githubusercontent.com/PeterSuh-Q3/tcrp-addons/main/sensors/standalone/install.sh | sudo bash -s -- --fan-control
```

Fan control may change actual fan speeds. Watch temperatures and RPM on the
first run. Installing this standalone version alongside the loader's sensors
addon is not supported.

To uninstall, download the script and invoke it with `--uninstall`:

```bash
curl -fLsS https://raw.githubusercontent.com/PeterSuh-Q3/tcrp-addons/main/sensors/standalone/install.sh -o /tmp/mshell-sensors-install.sh
sudo bash /tmp/mshell-sensors-install.sh --uninstall
```

The installer backs up files it replaces and restores them on uninstall.
It removes only a Scheduler task it created itself. It deliberately leaves
`/etc/fancontrol` and DSM fan settings unchanged on uninstall; inspect those
settings before adjusting them on a live system.
