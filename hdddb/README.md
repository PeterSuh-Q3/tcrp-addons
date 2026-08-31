# syno-hdd-db (HDD/SSD/NVMe DB Patch Script)

`syno-hdd-db.sh` is a lightweight, on-device version of the drive-compatibility
database patcher used in this repository. It scans the drives currently
attached to the running DSM system (SATA, SAS, and NVMe) and, for any drive
model that is not already listed in Synology's host compatibility database,
appends a "supported" entry for it to `/etc/disk_db.json` so that DSM stops
reporting the drive as unsupported/incompatible.

## Credit

This script is based on and ported from **[007revad/Synology_HDD_db](https://github.com/007revad/Synology_HDD_db)**.
Core logic — such as detecting installed drives from `/sys/block`, cleaning up
vendor-prefixed or suffixed drive model strings (`fixdrivemodel`), and reading
drive model/firmware information to build compatibility entries — is adapted
directly from that project's `syno_hdd_db.sh`.

All credit for the original design, drive-model quirks handling, and ongoing
research into Synology's disk compatibility database goes to
[@007revad](https://github.com/007revad). Please refer to the upstream
repository for the full-featured, actively maintained version of this tool,
including support for expansion units, M.2 PCIe cards, SAS/SCSI enclosures,
and many additional edge cases that this simplified script does not attempt
to cover.

If you are looking for a general-purpose, standalone HDD/SSD/NVMe database
patcher to run on a normal DSM installation, use the upstream script instead:
https://github.com/007revad/Synology_HDD_db

## What this script does

1. Detects the NAS model from `uname -u` and locates the matching host
   compatibility database file under `/var/lib/disk-compatibility/`
   (`*_host_v7.db`).
2. Iterates over every block device under `/sys/block/*` and classifies it as:
   - `sd*`, `hd*`, `sata*`, `sas*` → SATA/SAS drive
   - `nvme*` → NVMe drive
3. Skips any device that is mounted via USB.
4. Reads the drive model (`/sys/block/<dev>/device/model`) and firmware
   revision:
   - SATA/SAS: via `hdparm -I` (or a fixed value for SAS drives).
   - NVMe: via `/sys/block/<dev>/device/firmware_rev`.
5. Cleans up the raw model string (`fixdrivemodel`) by stripping known vendor
   prefixes (`WDC `, `HGST `, `TOSHIBA `, `Hitachi `, `SAMSUNG `, `FUJISTU `,
   `APPLE HDD `) and known Samsung/Lenovo SSD suffixes (` 00Y...`).
6. If the model is already present in the host `*_host_v7.db` file, it is
   skipped. Otherwise, a new `"support"` compatibility entry is written (or
   merged) into `/etc/disk_db.json` for that model/firmware combination.

## Usage

Run the script as root on a booted DSM/redpill system:

```bash
./syno-hdd-db.sh
```

The resulting `/etc/disk_db.json` can then be reviewed and merged into the
active compatibility database as needed.

## Limitations

This is a minimal, repository-local adaptation intended for use inside the
tinycore-redpill build/boot environment. It does not implement all the
features, drive-model edge cases, or safety checks found in the upstream
[007revad/Synology_HDD_db](https://github.com/007revad/Synology_HDD_db)
project. For production use on a regular DSM installation, prefer the
upstream script.

---

# syno-hdd-db (HDD/SSD/NVMe DB 패치 스크립트)

`syno-hdd-db.sh`는 이 저장소에서 사용하는, 드라이브 호환성 데이터베이스를
패치하는 경량화된 온디바이스 버전 스크립트입니다. 현재 부팅된 DSM 시스템에
연결된 드라이브(SATA, SAS, NVMe)를 스캔하여, Synology 호환성 데이터베이스에
아직 등록되지 않은 드라이브 모델이 있으면 `/etc/disk_db.json`에 "지원됨"
항목을 추가해서 DSM이 해당 드라이브를 미지원/비호환으로 표시하지 않도록
만들어 줍니다.

## 출처 및 크레딧

이 스크립트는 **[007revad/Synology_HDD_db](https://github.com/007revad/Synology_HDD_db)**
저장소를 참조하여 포팅한 것입니다. `/sys/block`에서 설치된 드라이브를
탐지하는 방식, 벤더 접두어/접미어가 붙은 드라이브 모델명을 정리하는
`fixdrivemodel` 로직, 드라이브 모델/펌웨어 정보를 읽어 호환성 항목을
구성하는 핵심 로직은 해당 프로젝트의 `syno_hdd_db.sh`에서 그대로 가져와
적용한 것입니다.

원본 설계, 드라이브 모델별 예외 처리, 그리고 Synology 디스크 호환성
데이터베이스에 대한 지속적인 리서치는 모두 [@007revad](https://github.com/007revad)의
공로입니다. 확장 유닛, M.2 PCIe 카드, SAS/SCSI 인클로저 등 이 축약 스크립트가
다루지 않는 다양한 예외 케이스까지 포함한 정식 기능의, 지속적으로 유지보수되는
버전을 원하신다면 upstream 저장소를 참고하시기 바랍니다.

일반적인 DSM 설치 환경에서 사용할 범용 독립형 HDD/SSD/NVMe 데이터베이스
패처가 필요하시다면, 이 스크립트 대신 upstream 스크립트를 사용하세요:
https://github.com/007revad/Synology_HDD_db

## 스크립트가 하는 일

1. `uname -u`로 NAS 모델을 감지하고, `/var/lib/disk-compatibility/` 아래에서
   일치하는 호스트 호환성 데이터베이스 파일(`*_host_v7.db`)을 찾습니다.
2. `/sys/block/*` 아래의 모든 블록 디바이스를 순회하며 다음과 같이 분류합니다.
   - `sd*`, `hd*`, `sata*`, `sas*` → SATA/SAS 드라이브
   - `nvme*` → NVMe 드라이브
3. USB로 마운트된 디바이스는 건너뜁니다.
4. 드라이브 모델명(`/sys/block/<dev>/device/model`)과 펌웨어 버전을
   읽어옵니다.
   - SATA/SAS: `hdparm -I`를 통해 읽음(SAS 드라이브는 고정값 사용).
   - NVMe: `/sys/block/<dev>/device/firmware_rev`를 통해 읽음.
5. `fixdrivemodel` 함수로 원본 모델명 문자열을 정리합니다. 알려진 벤더
   접두어(`WDC `, `HGST `, `TOSHIBA `, `Hitachi `, `SAMSUNG `, `FUJISTU `,
   `APPLE HDD `)와 일부 Samsung/Lenovo SSD 접미어(` 00Y...`)를 제거합니다.
6. 해당 모델이 이미 호스트 `*_host_v7.db` 파일에 존재하면 건너뛰고, 존재하지
   않으면 해당 모델/펌웨어 조합에 대한 `"support"` 호환성 항목을
   `/etc/disk_db.json`에 새로 작성(또는 병합)합니다.

## 사용법

부팅된 DSM/redpill 시스템에서 root 권한으로 실행합니다.

```bash
./syno-hdd-db.sh
```

생성된 `/etc/disk_db.json`을 검토한 뒤 필요에 따라 실제 사용 중인 호환성
데이터베이스에 병합하면 됩니다.

## 한계

이 스크립트는 tinycore-redpill 빌드/부팅 환경 내에서 사용하기 위해 최소한의
기능만 담아 저장소에 맞게 조정한 버전입니다. upstream인
[007revad/Synology_HDD_db](https://github.com/007revad/Synology_HDD_db)
프로젝트가 제공하는 모든 기능, 드라이브 모델별 예외 처리, 안전장치를
포함하고 있지 않습니다. 일반 DSM 설치 환경에서 정식으로 사용하려면 upstream
스크립트 사용을 권장합니다.

