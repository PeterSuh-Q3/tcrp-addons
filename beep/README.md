# beep

Installs a standalone PC-speaker `beep` utility and registers DSM Scheduler
tasks for boot and shutdown. A motherboard buzzer and the `pcspeaker` and
`pcspkr` modules from the all-modules pack are required for audible output.

Use the optional `-m` parameter for a short startup/shutdown melody.

`pcspeaker.ko` and `pcspkr.ko` are not duplicated by this addon. They are
loaded during the modules phase by `etc-modules-load`.

## beep

독립 PC speaker `beep` 실행 파일을 설치하고 DSM Scheduler에 부팅·종료 작업을
등록합니다. 실제 소리를 내려면 메인보드 부저와 all-modules 모듈팩의
`pcspeaker`·`pcspkr` 모듈이 필요합니다.

선택 인수 `-m`을 사용하면 짧은 부팅·종료 멜로디를 등록합니다.

이 애드온은 `pcspeaker.ko`, `pcspkr.ko`를 중복 포함하지 않습니다.
두 모듈은 `etc-modules-load`가 modules 단계에서 적재합니다.
