# agy-termux

Termux/Android에서 Linux(glibc)용 `agy`를 안정적으로 실행하기 위한 이식 레이어입니다.

기본 구조:
- `raw agy`: upstream 원본 바이너리 보존
- `patched runtime`: `~/.local/lib/agy-termux/agy` (resolver 문자열을 `/proc/self/fd/33`로 치환)
- `compiled launcher`: `~/bin/agy` (Termux/Bionic ELF)
- `control plane`: `~/bin/agy-termux`

## 핵심 원칙

- 기본 실행 경로는 `compiled launcher -> fd33 resolver -> glibc loader -> patched runtime`
- `agy update|upgrade|self-update`는 upstream self-update로 보내지 않고 Termux update pipeline으로 라우팅
- `LD_PRELOAD`, `LD_LIBRARY_PATH`는 child 실행 직전에 제거
- glibc 라이브러리 경로는 loader `--library-path` 인자로만 전달
- `proot`은 기본 경로가 아니라 진단 fallback 전용

## 설치/상태

```bash
bash bin/install-runtime.sh --install-wrappers
bash bin/install-runtime.sh --repair
bash bin/install-runtime.sh --status
```

## 운영 명령

```bash
agy-termux status
agy-termux doctor
agy-termux update --dry-run
agy-termux repair
agy-termux rollback --dry-run
agy-termux test-native
agy-termux test-proot
```

## 폴백

- 런처가 control dispatch, fd33 open, loader exec 단계에서 실패하면
  `~/.local/lib/agy-termux/agy-shell-wrapper.sh`로 자동 재시도합니다.
- shell fallback에서도 `agy update`는 Termux update broker로 처리됩니다.

## 문서

- [docs/AGY_TERMUX_NATIVE_GUIDE.md](docs/AGY_TERMUX_NATIVE_GUIDE.md)
- [docs/AGY_TERMUX_COMPILED_LAUNCHER.md](docs/AGY_TERMUX_COMPILED_LAUNCHER.md)
- [docs/COMPATIBILITY_DECISIONS.md](docs/COMPATIBILITY_DECISIONS.md)
