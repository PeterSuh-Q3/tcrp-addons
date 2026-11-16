# Optional WPA2 Personal Wi-Fi

Run `bash tools/configure-wifi.sh user_config.json` in tinycore-redpill.
The terminal prompts for SSID and a hidden password. An empty SSID disables
Wi-Fi. Rebuild the loader after changes. No menu changes are required.

The paired functions files stage /addons/mshell-wifi.conf with mode 0600.
The passphrase is converted to a derived PSK. That key is still a credential:
neither user_config.json nor the initrd should be published or shared.

The wifi-tools addon starts an asynchronous worker at rcExit. It waits up to 300 seconds for
a wireless interface, starts WPA2 authentication, and leaves DHCP, DNS and
routing to DSM. It does not load drivers or firmware. Those must already be
present and compatible. WPA3-only, enterprise authentication and open networks
are not supported by this configuration interface.

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
실제 자동접속 실기 검증은 별도로 필요합니다. 소스 묶음은 바이너리와
함께 별도로 공개해야 하며, 일반 addon 설치 시 내려받지 않습니다.
