# Barista

메뉴 막대를 정돈하고 필요한 앱 아이콘만 꺼내 주는 작은 macOS 앱.

이름: **Barista** / 바리스타

아이콘은 짙은 에스프레소 녹색 바탕과 크림색 커피콩으로 구성합니다. 가운데 굽은 틈은 접기·펼치기의 흐름을 표현합니다. 메뉴 막대에서는 같은 형태를 단색 템플릿으로 사용하며, 펼치면 커피콩의 방향이 바뀝니다. 기존 화살표 등도 설정에서 선택할 수 있습니다.

- 앱 식별자: `dev.eden.barista`
- Swift 패키지와 실행 파일: `Barista`
- 앱 번들: `build/Barista.app`
- 공통 벡터 원본: `Sources/Barista/CoffeeBeanMark.swift`
- 아이콘 렌더러: `scripts/render-icon.swift`
- 생성: `zsh scripts/icon.sh`
- 배포 아이콘: `Resources/AppIcon.icns`
- 미리보기: `Resources/Barista.png`
