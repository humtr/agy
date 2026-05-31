# 🚀 agy native Termux runtime

Termux/Android에서 공식 Linux ARM64 Antigravity CLI(`agy`)를 `agy` 단일 명령으로 실행하기 위한 네이티브 런타임 이식 레이어입니다.

## 설치 / 재설치 / 복구

Termux에서 아래 bootstrap을 실행합니다. 같은 명령은 다시 실행해도 되며, wrapper와 runtime support 파일을 현재 `main` 기준으로 덮어쓰는 복구 경로이기도 합니다.

```bash
curl -fsSL https://raw.githubusercontent.com/humtr/agy/main/install.sh | bash
```

## 공개 명령

| 명령어 | 역할 |
| :--- | :--- |
| `agy` | Antigravity CLI 일반 실행. bare 실행은 가벼운 drift 확인과 자동 업데이트 확인을 수행합니다. |
| `agy update` | upstream manifest 확인, checksum 검증, raw→patched 후보 빌드, smoke test, atomic promotion을 수행합니다. |
| `agy sync` | 이 Termux wrapper와 runtime support 파일만 현재 `main`으로 동기화합니다. |
| `agy repair` | 네트워크 없이 기존 raw 바이너리에서 patched runtime을 다시 빌드합니다. |
| `agy doctor` | PATH, wrapper, raw/runtime, glibc loader, resolver fd, CA, state hash를 점검합니다. |
| `agy version` | upstream runtime 바이너리 버전을 출력합니다. |
| `agy info` | upstream runtime 버전과 설치된 wrapper 버전/커밋을 출력합니다. |
| `agy uninstall --yes` | managed wrapper, runtime/raw copy, state/source cache, shim을 제거합니다. |

별도의 공개 관리 명령(`agy-t`, `agy-termux`)은 설치하지 않습니다. 설치 과정에서 과거 shim이 남아 있으면 제거합니다.

## 설치 레이아웃

```text
~/.local/lib/agy/native/raw/agy        # upstream 공식 Linux ARM64 원본 바이너리; 직접 패치하지 않음
~/.local/lib/agy/native/runtime/agy    # raw에서 생성한 Termux용 patched runtime
~/.local/lib/agy/native/runtime/run    # shell exec wrapper
~/.local/lib/agy/native/runtime/lib.sh # update/repair/doctor runtime support
~/bin/agy                              # 공개 진입점: compiled launcher 또는 shell fallback
~/.local/bin/agy                       # ~/bin/agy로 위임하는 compatibility shim
$PREFIX/bin/agy                        # ~/bin/agy로 위임하는 PATH shim
~/.local/share/agy/native/state.json   # raw/runtime hash와 업데이트 상태
```

## 핵심 원칙

- **raw 보존**: 공식 `agy` 바이너리는 `raw/agy`에 보관하고 제자리 패치하지 않습니다.
- **분리된 runtime copy**: 실행용 바이너리는 `runtime/agy`에 생성합니다.
- **fd 33 resolver**: runtime 안의 `/etc/resolv.conf` 참조를 `/proc/self/fd/33`으로 바꾸고, launcher가 `$PREFIX/etc/resolv.conf`를 fd 33으로 열어 전달합니다.
- **LD 격리**: 실행 직전에 `LD_PRELOAD`, `LD_LIBRARY_PATH`를 제거하고 glibc loader `--library-path`만 사용합니다.
- **단일 표면**: 사용자는 `agy`만 호출합니다. version, update, sync, repair, doctor, uninstall도 모두 `agy` 하위 명령입니다.
- **인증 보존**: 설치, 업데이트, repair는 OAuth 세션이나 사용자 토큰을 삭제하지 않고 `agy auth login`을 자동 실행하지 않습니다.
- **repo-pinned fallback 없음**: 레포는 별도 verified agy version 파일을 유지하지 않습니다. `agy update`는 live upstream manifest와 candidate 검증을 통과한 경우에만 promotion하고, 마지막으로 로컬 검증된 설치 버전은 `state.json`에 기록합니다.

## 문제 해결

1. `agy doctor`로 현재 설치 상태를 확인합니다.
2. runtime drift 또는 patched runtime 손상이 보이면 `agy repair`를 실행합니다.
3. wrapper 파일이 낡았거나 bootstrap 파일 자체가 손상된 경우 `agy sync` 또는 위 bootstrap 명령을 다시 실행합니다.
4. raw 바이너리나 glibc 전제 조건이 없으면 bootstrap 명령을 다시 실행합니다.

실패한 `agy` 실행은 로컬 diagnostic case를 `~/.local/share/agy/native/doctor/` 아래에 생성할 수 있습니다. 이 산출물은 자동으로 외부 도구에 전송되지 않습니다.

## 문서

- [Native runtime guide](docs/AGY_TERMUX_NATIVE_GUIDE.md)
- [Compiled launcher guide](docs/AGY_TERMUX_COMPILED_LAUNCHER.md)
