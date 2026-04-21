# tcrp-addons — 작업 컨텍스트

## disks addon — Non-DT HBA 디스크 인식 수정 (2026-04)

### 문제
DS918+(apollolake) 같은 Non-DT 플랫폼에서 HBA(mpt3sas/megaraid_sas) 디스크가
DSM Storage Manager에 표시되지 않음. DS3622xs+는 같은 Non-DT인데 정상.

### 근본 원인 (2단계)

1. **DSM pat 이미지에 베이크된 DS918+ 기본값**이 그대로 남음
   - `maxdisks=4`, `internalportcfg=0xf`, `usbportcfg=0x30000`, `esataportcfg=0x10`
   - user_config.json에 portcfg 3종이 없어서 loader가 덮어쓰지 않음
2. **disks.sh `nondtModel()`의 로직 결함**
   - `_check_user_conf "maxdisks"`가 true면 감지값 무시 → vendor 4로 고정
   - USB "최소 6슬롯 확장"이 USB 중간 인덱스(sdf=5)에 적용되면
     HBA 디스크(sdg=6) 비트를 USB로 오분류
   - `nondtUpdate()`는 `_log "TODO"` 스텁이라 핫플러그 시 재계산 없음
3. **late 단계 전파 누락**
   - `install-new.sh late`가 `disks.sh --update`를 인자 없이 호출
   - udev 경로로 빠져 `/tmpRoot/etc/synoinfo.conf` 복사 안 됨

### 해결 커밋 시퀀스

| 커밋 | 변경 |
|---|---|
| [7ae1fb6](https://github.com/PeterSuh-Q3/tcrp-addons/commit/7ae1fb6) | `udevadm settle --timeout=30` 추가, `maxdisks`를 `max(user, detected)` |
| [dc9cffb](https://github.com/PeterSuh-Q3/tcrp-addons/commit/dc9cffb) | `MAXNONUSBIDX` 추적. USB가 non-USB 디스크 아래면 6슬롯 확장 스킵 |
| [8aa9ce9](https://github.com/PeterSuh-Q3/tcrp-addons/commit/8aa9ce9) | `nondtUpdate()` 스텁 → `nondtModel()` 재계산 호출 (핫플러그 대응) |
| [a1f3cb8](https://github.com/PeterSuh-Q3/tcrp-addons/commit/a1f3cb8) | `install-new.sh late`가 `/tmpRoot` 전달. `--update <dir>` 분기 추가 |
| [72b346e](https://github.com/PeterSuh-Q3/tcrp-addons/commit/72b346e) | late 단계에서 재계산 제거 (AHCI/HBA probe 전 타이밍 문제). 파일 복사만 수행 |

### 핵심 설계 원칙

- **portcfg 계산은 `--create`(patches 단계)에서만** 수행
  - 이 시점은 DSM 런타임 컨텍스트라 모든 디스크가 `/sys/block/sd*`에 가시
- **late 단계는 "복사만"**
  - AHCI/HBA 드라이버가 probe 완료 전일 수 있어 재계산하면 잘못된 값 도출
  - canonical values from `--create`를 `/tmpRoot`로 전파
- **USB 6슬롯 확장은 safety guard 조건부로만**
  - non-USB 디스크가 USB보다 위 인덱스에 있으면 확장 금지 (HBA 비트 침범 방지)
- **udev 핫플러그 경로 보존**
  - `--update <DEVNAME>`: udev 룰 (기존)
  - `--update <directory>`: late 단계 /tmpRoot 전파 (신규 분기)

### 검증된 최종 결과 (DVA3219, DS918+ 모델)

```
/sys/block/sd*: sdb(1), sdd(3) = AHCI; sdf(5) = USB boot; sdg(6), ... = HBA

최종 synoinfo.conf:
  maxdisks=16
  internalportcfg=0xe07f  # bits 0-6, 13-15
  usbportcfg=0x1f80       # bits 7-12 (USB 6슬롯)
  esataportcfg=0x00

DSM Storage Manager: AHCI 2장 + HBA 2장 모두 정상 인식
```

### 주요 파일

- [disks/src/disks.sh](disks/src/disks.sh) — nondtModel / nondtUpdate / --update 분기
- [disks/src/install-new.sh](disks/src/install-new.sh) — patches / late 훅
- [disks/recipes/universal.json](disks/recipes/universal.json) — sha256 매니페스트

### 관련 재료

- user_config.json의 `synoinfo` 블록에 `internalportcfg`/`usbportcfg`/`esataportcfg`를
  추가하면 disks.sh 계산이 무시되므로 주의 (필요시 `maxdisks`만 두고 나머지는 생략)
- udev 룰: `/usr/lib/udev/rules.d/04-system-disk-dtb.rules`
  (install-new.sh `copy_files`에서 생성, 핫플러그 시 `--update %E{DEVNAME}` 호출)
