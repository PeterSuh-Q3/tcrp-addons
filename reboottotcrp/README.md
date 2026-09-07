# reboottotcrp

## Deprecated addon

The `reboottotcrp` addon is no longer used for new MSHELL deployments.
Its reboot-to-TCRP scheduler function is now provided by **MSHELL Manager**.

Keep this addon only for compatibility with existing loaders that still
reference it. New loader builds should use the MSHELL Manager implementation
instead of adding `reboottotcrp`.

The scheduler database fallback was removed from this addon. The early-loaded
`beep` addon now provides the bundled `esynoscheduler.db` when the DSM
scheduler database is not yet available.

## 사용 중단 안내

`reboottotcrp`의 재부팅 후 TCRP 진입 기능은 이제 **MSHELL Manager**에서
제공합니다. 따라서 신규 MSHELL 로더에서는 이 애드온을 사용하지 않습니다.

기존 로더와의 호환성을 위해 소스는 보존하지만, 신규 빌드에서는
MSHELL Manager의 구현을 사용해야 합니다. 스케줄러 DB fallback 복사 기능도
제거되었으며, DSM 스케줄러 DB가 아직 없을 때 필요한 기본 DB는 먼저 로딩되는
`beep` 애드온이 제공합니다.
