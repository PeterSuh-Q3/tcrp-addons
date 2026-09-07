# beep

Installs a standalone PC-speaker `beep` utility and registers DSM Scheduler
tasks for boot and shutdown. A motherboard buzzer and the `pcspeaker` and
`pcspkr` modules from the all-modules pack are required for audible output.

The RR `-m` melodies are the fixed default: Mario at startup and Axel F at
shutdown. TCRP addons do not receive RR-style positional parameters.

`pcspeaker.ko` and `pcspkr.ko` are not duplicated by this addon. They are
loaded during the modules phase by `etc-modules-load`.

## beep

독립 PC speaker `beep` 실행 파일을 설치하고 DSM Scheduler에 부팅·종료 작업을
등록합니다. 실제 소리를 내려면 메인보드 부저와 all-modules 모듈팩의
`pcspeaker`·`pcspkr` 모듈이 필요합니다.

RR의 `-m` 멜로디를 기본값으로 고정했습니다. 부팅 시 Mario, 종료 시 Axel F를
재생하며 TCRP 애드온은 RR 방식의 위치 인수를 받지 않습니다.

이 애드온은 `pcspeaker.ko`, `pcspkr.ko`를 중복 포함하지 않습니다.
두 모듈은 `etc-modules-load`가 modules 단계에서 적재합니다.
