# Barista

![Barista](Resources/Barista-preview.png)

메뉴 막대를 커피콩 버튼 하나로 정돈하는 작은 macOS 앱입니다.

- `⌘ + 드래그`로 아이콘 순서를 바꾸고, Barista 왼쪽의 앱을 접거나 펼칩니다.
- 클릭으로 접기·펼치기, 우클릭 또는 Control + 클릭으로 메뉴를 엽니다.
- 커피콩 · 얇은 화살표 · 두 점 · 캡슐 · 원형을 미리 보고 선택합니다.
- 자동 접기 시간을 3 · 5 · 15 · 30초로 선택하고 로그인 시 실행할 수 있습니다.
- 배치 안내는 설정 하단의 `?`에 있습니다. `완료`는 설정을 닫습니다.

macOS 기본 메뉴 간격을 유지합니다. 다른 앱이 정한 아이콘 폭까지 강제로 같게 만들지는 않습니다.

## 호환성

| 환경 | 지원 범위 |
| --- | --- |
| macOS 27.0.1 · Apple Silicon | 개발·빌드·사용자 접기/펼치기 확인 환경 |
| macOS 27의 다른 버전 · Apple Silicon | 실행 대상이나 각 버전 실기 검증은 하지 않음 |
| macOS 26 및 이전 | 지원하지 않음. 최소 실행 버전은 27.0 |
| Intel Mac | 이 배포 파일은 arm64 전용이므로 지원하지 않음 |
| 여러 모니터 / 장시간 실행 / 재부팅 후 복원 | 추가 실기 검증 필요 |

현재 숨김 구현은 macOS 27의 비공개 `MenuBarClientCore.framework`에 의존합니다. 하위 macOS용 대체 구현은 없습니다. 업데이트로 해당 API가 바뀌면 숨김 기능이 작동하지 않을 수 있습니다. API가 없거나 적용이 실패하면 모두 표시하도록 복구합니다.

macOS 27 지원 기기는 [Apple 호환 목록](https://support.apple.com/en-ca/127255)을 참고하세요. 본 프로젝트의 검증 범위는 위 표와 같습니다.

## 설치

[Releases](https://github.com/willofi/Barista/releases)에서 ZIP을 받아 압축을 풀고 **Barista.app을 /Applications로 이동**한 뒤 실행하세요. 개발 폴더에서 실행했을 때 자기 버튼이 사라지는 현상이 있어 표준 설치 위치를 권장합니다.

현재 Preview는 **ad-hoc 서명**이며 Developer ID 서명·Apple 공증이 없습니다. macOS가 다운로드한 앱 실행을 차단할 수 있습니다. 출처를 확인한 뒤 Apple의 [앱 열기 안내](https://support.apple.com/en-us/102445)를 참고하세요. 시스템 보안 기능을 전체 비활성화할 필요는 없습니다.

1. 다른 메뉴 막대 관리자를 종료합니다.
2. Barista 설정에서 손쉬운 사용 설정을 열고 Barista를 허용합니다.
3. 목록에 없다면 `+` → `⌘⇧G` → `/Applications/Barista.app`으로 추가합니다.
4. 펼친 상태에서 `⌘ + 드래그`로 숨길 앱은 Barista 왼쪽, 계속 표시할 앱은 오른쪽에 둡니다.
5. Barista를 클릭해 접습니다. 우클릭 메뉴의 ‘아이콘 모양’에서 디자인을 고릅니다.

```text
숨길 앱들    ☕ Barista    계속 표시할 앱들    시스템 아이콘
```

개발 빌드를 다시 서명하면 기존 권한이 적용되지 않을 수 있습니다. 설정의 권한 표시를 확인하고 필요하면 시스템 설정에서 기존 항목을 제거한 뒤 **현재 설치된 앱**을 다시 추가하세요.

버튼을 찾을 수 없으면 Finder에서 Barista를 다시 실행하면 모두 펼치고 설정을 엽니다. `Control + F8`도 모두 펼칩니다. 키보드 설정에 따라 Fn 키가 필요할 수 있습니다. 종료하면 표시 제한을 해제합니다.

## 동작과 제한

- 위치를 읽기 위한 손쉬운 사용 권한만 요청합니다. 화면 녹화·전체 디스크 접근 권한은 요청하지 않습니다. 앱 자체는 네트워크 통신이나 화면 캡처를 하지 않습니다.
- 숨김은 앱 단위입니다. 한 앱의 여러 아이콘이 버튼 양쪽에 걸쳐 있거나 위치를 읽을 수 없으면 해당 앱을 계속 표시합니다. Apple 시스템 아이콘과 Barista는 숨김 대상에서 제외합니다.
- 비공개 표시 제한은 알림 센터에도 영향을 줍니다. 시계·제어 센터 영역에 마우스가 들어가면 잠시 모두 표시하고 나온 뒤 복구합니다. 다른 경로로 알림 센터를 사용할 때는 먼저 펼쳐 주세요.
- 자동 접기는 설정 창이나 메뉴가 열려 있거나 드래그 중이면 미룹니다.
- 앱 순서 변경은 macOS의 기본 `⌘ + 드래그`를 사용합니다. 재부팅 후 순서를 강제로 복원하지 않습니다.

## 개발

macOS 27 실행 환경, macOS 27 SDK와 Swift 6 컴파일러가 필요합니다. 외부 패키지 의존성은 없습니다.

```sh
zsh scripts/check.sh
zsh scripts/build.sh
zsh scripts/release.sh
```

앱은 `build/Barista.app`, 배포 ZIP과 체크섬은 `dist/`에 생성됩니다. Xcode에서는 `Package.swift`를 열어 편집할 수 있습니다. 실제 설치·로그인 실행 테스트는 스크립트가 만든 앱 번들로 진행하세요.

[검토 및 검증 기록](docs/REVIEW.md) · [릴리즈 절차](docs/RELEASING.md) · [변경 기록](CHANGELOG.md)

## 참고

비공개 API 시그니처와 시계 좌표 처리는 [MenuBarHider](https://github.com/happy666End/MenuBarHider)의 MIT 구현을 참고·일부 변형했습니다. 해당 저작권 고지는 [ThirdPartyNotices](Resources/ThirdPartyNotices.txt)와 배포 앱에 포함합니다. 초기 방식 조사에는 [Hidden Bar](https://github.com/dwarvesf/hidden)를 참고했습니다.
