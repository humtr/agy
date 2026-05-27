# 🚀 agy-termux

> Termux/Android 환경에서 Linux(glibc)용 Antigravity CLI(`agy`)를 안정적이고 네이티브에 준하는 속도로 구동하기 위한 이식 레이어입니다.

---

## 📦 기본 구조 및 아키텍처

`agy-termux`는 안드로이드의 `Bionic` 환경과 리눅스의 `glibc` 환경을 네이티브 링커 패치 기법을 통해 매끄럽게 연결합니다.

```text
~/.local/bin/agy                   # [불변 원본] Upstream 공식 바이너리
~/.local/lib/agy-termux/agy        # [패치 런타임] resolv.conf 경로를 fd/33으로 조정한 바이너리
~/bin/agy (및 $PREFIX/bin/agy)    # [컴파일 런처] 최초 진입 및 환경 제어를 관리하는 Bionic ELF 런처
~/bin/agy-termux                   # [제어 평면] 진단, 롤백, 수동 패치용 컨트롤러
```

### ⚙️ 핵심 원칙
- **네이티브 실행 체인**: `Compiled Launcher ➔ FD 33 Resolver ➔ Glibc Loader ➔ Patched Runtime` 구조로 부하를 최소화합니다.
- **안전한 샌드박싱**: 자식 Bionic 프로세스의 링커 오염을 완방하기 위해 실행 직전 `LD_PRELOAD`, `LD_LIBRARY_PATH`를 완전히 제거합니다.
- **업데이트 격리**: `agy update` 등 자체 바이너리 변경 명령을 Termux 전용 트랜잭션 검증 파이프라인으로 안전하게 라우팅합니다.

---

## ⚡ 빠른 설치 (One-Line)

Termux 터미널에서 다음 명령을 실행하여 부트스트랩을 즉시 진행합니다.

```bash
curl -fsSL https://raw.githubusercontent.com/humtr/agy/main/install.sh | bash
```

---

## 🛠️ 제어 평면 운영 명령어 (`agy-termux`)

운영 및 트러블슈팅을 지원하는 핵심 도구 세트입니다.

| 명령어 | 역할 | 비고 |
| :--- | :--- | :--- |
| `agy-termux status` | 현재 raw/patched 상태 및 해시 검증 | 무중단 링커 감시 |
| `agy-termux doctor` | 셸 환경 링커 오염(parent LD) 및 리졸버 검사 | 자가 진단 |
| `agy-termux repair` | raw 바이너리로부터 복사본 재빌드 및 재패치 수행 | 강제 복구 |
| `agy-termux update` | 업스트림 매네페스트 체크 및 트랜잭션 기반 교체 | `--dry-run` 지원 |
| `agy-termux rollback` | 직전 빌드로 안전하게 회귀 | `--dry-run` 지원 |
| `agy-termux test-native` | 네이티브 fd 33 리졸버 DNS 연동 연기 테스트 | 45초 타임아웃 |
| `agy-termux test-proot` | diagnostic 전용 proot 백업 동작 여부 확인 | 폴백 검증 |

---

## 🛡️ 폴백 및 안전 장치

- **자동 셸 래퍼 복구**: 컴파일된 런처가 초기 디스패치나 fd33 바인딩 단계에서 비정상 종료되는 경우, `~/.local/lib/agy-termux/agy-shell-wrapper.sh`로 자동 백업 기동합니다.
- **인증 무보존 원칙**: 자가 치료나 수동 복구(`repair`), 업데이트 시 사용자의 OAuth 세션 및 토큰 파일(`~/.config` 내)은 절대 보존하며 훼손하지 않습니다.

---

## 📚 관련 문서

자세한 내부 구현 사양이나 원리는 아래 링크들을 참조해 주시기 바랍니다.

- 📖 [호환성 결정 이력 및 설계 원칙](docs/COMPATIBILITY_DECISIONS.md)
- 📖 [네이티브 이식 아키텍처 및 런타임 가이드](docs/AGY_TERMUX_NATIVE_GUIDE.md)
- 📖 [Bionic ELF 런처 명세 및 로딩 기법](docs/AGY_TERMUX_COMPILED_LAUNCHER.md)
