# 릴리즈

macOS 27 Apple Silicon에서 실행합니다.

```sh
zsh scripts/check.sh
zsh scripts/build.sh
zsh scripts/release.sh
```

`dist/Barista-<버전>-macos27-arm64.zip`과 `SHA256SUMS`를 업로드합니다. 기본 빌드는 ad-hoc 서명이며 공개 릴리즈에 Preview 표시와 미공증 안내를 유지하세요.

Developer ID 인증서가 있는 환경에서는 다음처럼 빌드합니다.

```sh
BARISTA_SIGNING_IDENTITY='Developer ID Application: YOUR NAME (TEAMID)' zsh scripts/build.sh
zsh scripts/release.sh
xcrun notarytool submit dist/Barista-0.3.0-macos27-arm64.zip --keychain-profile YOUR_PROFILE --wait
xcrun stapler staple build/Barista.app
xcrun stapler validate build/Barista.app
zsh scripts/release.sh
```

공증 성공을 확인한 뒤 티켓을 부착하고 ZIP과 체크섬을 다시 생성합니다. 인증서나 키체인 비밀은 저장소에 추가하지 않습니다.

## 실기 확인

앱을 /Applications에 설치하고 현재 앱의 손쉬운 사용 권한을 확인합니다. 접은 뒤 충분히 기다려 자기 버튼이 남는지, 클릭·우클릭이 가능한지, 5가지 미리보기와 자동 접기 시간, 시계 영역 임시 펼치기, Finder 재실행 복구를 확인합니다. 빌드마다 개발 서명이 바뀔 수 있으므로 모든 빌드를 끝낸 뒤 권한을 재등록하세요.

테스트 중 SetupChecks 실행 파일은 손쉬운 사용 권한이 없는 프로세스여야 합니다. 전체 검사 스크립트는 macOS 27 실행 환경을 요구합니다.
