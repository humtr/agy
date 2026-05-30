# 🚀 agy native Termux runtime

> Termux/Android 환경에서 Linux(glibc)용 Antigravity CLI(`agy`)를 `agy` 단일 명령 표면으로 구동하기 위한 네이티브 런타임 이식 레이어입니다.

---

## 📦 기본 구조 및 아키텍처

이 프로젝트는 안드로이드의 `Bionic` 환경과 리눅스의 `glibc` 환경을 네이티브 링커 패치 기법으로 연결합니다. 사용자가 직접 사용하는 공개 명령은 `agy` 하나입니다.

```text
~/.local/lib/agy/native/raw/agy        # [불변 원본] Upstream 공식 Linux ARM64 바이너리
~/.local/lib/agy/native/runtime/agy    # [패치 런타임] fd 33 resolver 경로로 조정한 바이너리
~/bin/agy                              # [공개 진입점] Bionic ELF launcher 또는 shell fallback
~/.local/bin/agy                       # [호환 shim] ~/bin/agy로 위임
$PREFIX/bin/agy                        # [PATH shim] ~/bin/agy로 위임
```

### ⚙️ 핵심 원칙

- **단일 사용자 표면**: 정상 사용, 바이너리 업데이트, wrapper 동기화, 로컬 복구는 모두 `agy` 명령으로 진입합니다.
- **네이티브 실행 체인**: `Compiled Launcher ➔ FD 33 Resolver ➔ Glibc Loader ➔ Patched Runtime` 구조로 부하를 최소화합니다.
- **안전한 샌드박싱**: 자식 Bionic 프로세스의 링커 오염을 막기 위해 실행 직전 `LD_PRELOAD`, `LD_LIBRARY_PATH`를 제거합니다.
- **업데이트 격리**: `agy update`는 공식 agy 바이너리 변경만 Termux 전용 트랜잭션 검증 파이프라인으로 라우팅합니다.
- **관리 표면 제거**: `agy-t`, `agy-termux` 같은 별도 공개 제어 명령은 설치하지 않습니다.

---

## ⚡ 빠른 설치 / 복구

Termux 터미널에서 다음 명령을 실행합니다. 같은 명령은 재실행해도 되며, 설치된 wrapper/runtime 지원 파일을 복구하는 idempotent bootstrap 역할을 합니다.

```bash
curl -fsSL https://raw.githubusercontent.com/humtr/agy/main/install.sh | bash
```

---

## 🛠️ 사용자 명령

| 명령어 | 역할 |
| :--- | :--- |
| `agy` | Antigravity CLI 일반 실행 |
| `agy update` | 업스트림 manifest 확인, checksum 검증, raw→patched 후보 빌드, smoke test 후 공식 agy 바이너리 교체 |
| `agy sync` | 이 Termux wrapper/repo/runtime support를 현재 `main`과 동기화 |
| `agy repair` | 네트워크 없이 기존 raw 바이너리에서 patched runtime을 재빌드하는 로컬 복구 |
| `agy --version` | 설치된 runtime 버전 확인 |

`agy repair`는 OAuth 세션이나 사용자 토큰을 건드리지 않습니다. raw 공식 바이너리가 없거나 glibc/CA/resolver 전제 조건이 깨진 경우에는 위 bootstrap 명령을 다시 실행하세요.

---

## 🛡️ 폴백 및 안전 장치

- **자동 셸 fallback**: compiled launcher가 초기 dispatch, fd33 바인딩, loader exec 단계에서 실패하면 `~/.local/lib/agy/native/runtime/agy-shell-wrapper.sh`로 복구 경로를 시도합니다.
- **오프라인 repair**: `agy repair`는 네트워크 없이 기존 raw 바이너리에서 runtime copy를 다시 생성합니다.
- **wrapper sync**: `agy sync`는 네트워크를 사용해 현재 `main`의 설치 스크립트를 다시 실행하고 wrapper/runtime support를 갱신합니다.
- **인증 무보존 원칙**: 설치, 복구, 업데이트는 사용자의 OAuth 세션 및 토큰 파일(`~/.config` 내)을 삭제하거나 재로그인하지 않습니다.
- **진단 산출물 최소화**: 실패 시 진단 case는 로컬 상태 확인용으로만 생성되며, 자동으로 외부 LLM 도구에 전송하지 않습니다.

---

## 📚 관련 문서

- 📖 [호환성 결정 이력 및 설계 원칙](docs/COMPATIBILITY_DECISIONS.md)
- 📖 [네이티브 이식 아키텍처 및 런타임 가이드](docs/AGY_TERMUX_NATIVE_GUIDE.md)
- 📖 [Bionic ELF 런처 명세 및 로딩 기법](docs/AGY_TERMUX_COMPILED_LAUNCHER.md)
