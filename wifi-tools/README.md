# Optional WPA2 Personal Wi-Fi

Run `bash tools/configure-wifi.sh user_config.json` in tinycore-redpill.
The terminal prompts for SSID and a hidden password. An empty SSID disables
Wi-Fi. Install the wifi-tools addon and rebuild the loader after changes.
No menu changes are required.

The paired functions files stage /addons/mshell-wifi.conf with mode 0600.
The passphrase is converted to a derived PSK. That key is still a credential:
neither user_config.json nor the initrd should be published or shared.

The wifi-tools addon starts an asynchronous worker at rcExit. It waits up to 300 seconds for
a wireless interface, starts WPA2 authentication, and leaves DHCP, DNS and
routing to DSM. It does not load drivers or firmware. Those must already be
present and compatible. WPA3-only, enterprise authentication and open networks
are not supported by this configuration interface.

After starting the supplicant, the worker waits up to five minutes for a
non-link-local IPv4 address and saves a diagnostic snapshot plus the WPA
supplicant log to `wifi-diagnostics/` on loader P3. P3 is located using the
loader filesystem UUIDs `6234-C863` or `8765-4321`, following the loader
partition discovery used by the boot addons. The capture includes interface,
route, driver and relevant kernel-message state; it does not copy the Wi-Fi
configuration or passphrase. If P3 cannot be found or mounted, the failure is
sent to the system logger and the snapshot remains only in volatile `/run`.

On an epyc7002 DSM 7.4.1 junior pilot, the addon was copied manually and its
mktemp-free startup path connected a BCM43602 device using separately staged
pilot drivers and firmware. WPA2 authentication, DHCP and gateway reachability
were verified. This is not an end-to-end rebuilt-loader or cross-platform test.

wifi-tools.tgz contains an isolated Alpine 3.20 x86-64 musl runtime; it does
not overwrite DSM libraries. Rebuild with `sh wifi-tools/build-wifi-tools.sh` from
the repository root, or run the manual `Build Wi-Fi tools` workflow.
The workflow always uploads a test artifact; its `publish` option also commits
the archive and updates the recipe hash. PACKAGES and PACKAGE-INFO record
installed package metadata, not complete source or license documentation.
Third-party license texts and package-version notices are included; see
`THIRD-PARTY-NOTICES.md`. The separately generated `wifi-tools-sources.tgz`
contains matching upstream source archives and Alpine patches, verified using
the SHA-512 checksums from each exact Alpine recipe. Run
`sh wifi-tools/build-sources.sh` to generate it. Publish the source archive
alongside the binary archive; it is not downloaded during normal addon setup.

## 한국어

메뉴 대신 위 설정 스크립트에서 SSID와 비밀번호를 입력한 뒤 로더를
재빌드합니다. wifi-tools addon을 설치하면 부팅 시 자동으로 연결을 시작하며 DHCP는 DSM에
맡깁니다. 무선 드라이버와 펌웨어는 별도로 준비되어 있어야 합니다.
설정 파일과 initrd에는 접속 가능한 자격정보가 있으므로 공개하지 마세요.
연결 시도 뒤 최대 5분간 상태를 확인하고, 링크 로컬 주소가 아닌 IPv4 주소를
얻지 못하면 진단 스냅샷과 WPA 로그를 부트로더 P3의 `wifi-diagnostics/`에
저장합니다. P3는 부트로더 UUID로 찾으며 Wi-Fi 설정/비밀번호는 로그에 복사하지
않습니다. P3를 찾거나 마운트하지 못하면 시스템 로그에 실패 사유를 남기고,
진단 파일은 휘발성 `/run`에만 남습니다.
epyc7002 DSM 7.4.1 주니어에 수동 복사하고 별도 준비한 BCM43602 드라이버와
펌웨어를 사용해 WPA2 연결·DHCP·게이트웨이 통신을 확인했습니다. 로더
재빌드부터의 전체 흐름과 다른 플랫폼은 아직 검증하지 않았습니다.
소스 묶음은 바이너리와
함께 별도로 공개해야 하며, 일반 addon 설치 시 내려받지 않습니다.
