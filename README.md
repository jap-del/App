# 막차 알림

집을 설정해 두면 현재 위치에서 집까지 가는 막차 시간을 알려주고, 출발해야 할 때 알림을 보내는 앱입니다. Flutter로 Android와 iOS를 함께 지원합니다.

## 현재 상태

- 집 설정 (현재 위치를 집으로 저장)
- 막차 시간과 남은 시간 표시
- 출발 알림 예약 (5분 전부터 30분 전까지 선택)
- Android 잠금화면 고정 알림
- 홈 화면 아래 배너 광고 (AdMob 비맞춤형, 지금은 테스트 광고)
- 첫 실행 동의 화면 (만 14세 이상, 위치기반서비스 이용약관, 접근권한 안내)
- 설정: 위치 사용 일시 중지, 동의 철회, 개인정보처리방침, 이용약관, 데이터 출처, 오픈소스 라이선스

- 실제 막차 계산: `server/`의 막차 서버(`/last-route`)에서 ODsay 길찾기와 TAGO 지하철 시간표로 계산 (버스는 추정)

## 실행

```sh
flutter pub get
flutter run
```

기본으로 배포된 막차 서버(`https://last-train-api.lasttrain-japdel.workers.dev`)를 씁니다. 서버 없이 화면만 확인하려면 예시 데이터로 실행합니다.

```sh
flutter run --dart-define=API_BASE_URL=sample
```

ODsay 무료 요금제는 하루 30번까지라서, 앱은 같은 자리에서 10분 안에 다시 물으면 앞의 결과를 다시 씁니다.

교통 API 키는 앱에 넣지 않고 서버에만 둡니다.

## 광고

지금은 Google의 테스트용 광고 ID가 들어 있어서 수익이 나지 않습니다. 출시 전에 [AdMob](https://admob.google.com)에서 앱과 배너 광고 단위를 만든 뒤 바꿉니다.

- 앱 ID: `android/app/src/main/AndroidManifest.xml`의 `APPLICATION_ID`, `ios/Runner/Info.plist`의 `GADApplicationIdentifier`
- 배너 광고 단위 ID: 빌드할 때 `--dart-define=AD_BANNER_ANDROID=...` 와 `--dart-define=AD_BANNER_IOS=...`

개발 중에는 반드시 테스트 ID를 쓰세요. 실제 광고를 직접 누르면 AdMob 계정이 정지될 수 있습니다.

## 법적 문서

`docs/privacy-policy.md`(개인정보처리방침)와 `docs/location-terms.md`(위치기반서비스 이용약관)는 앱 안에서도 보여주고 웹에도 공개합니다. 같은 파일을 쓰니 한 곳만 고치면 됩니다.

출시 전에 할 일:

- 두 문서의 `[운영자 이름]`, `[상호]`, `[사업장 주소]`, `[연락처 이메일]`, `[시행일]`을 실제 값으로 바꿉니다.
- GitHub 저장소의 Settings → Pages에서 `main` 브랜치의 `/docs` 폴더를 공개하면 스토어에 넣을 URL이 생깁니다.
- 약관 내용이 바뀌면 `lib/legal/consent_store.dart`의 `currentConsentVersion`을 올려 다시 동의를 받습니다.

서버를 만들 때 지킬 것 (위치정보법):

- 현재 위치 좌표는 경로 계산에만 쓰고 저장하거나 로그에 남기지 않습니다.
- 위치정보 이용사실 확인자료(일시, 목적, 좌표 제외)는 자동으로 기록하고 보존합니다.
- 외부 API에 좌표를 보낼 때 이용자를 식별할 수 있는 정보를 붙이지 않습니다.

## 검사

```sh
flutter analyze
flutter test
```

## 서버

교통 API 인증키를 숨기기 위한 서버는 `server/` 폴더에 있습니다 (Cloudflare Workers). 배포 방법은 [server/README.md](server/README.md)를 보세요.

## 구조

- `lib/logic/` 알림 시각 계산
- `lib/models/` 집, 경로 데이터
- `lib/services/` 교통 정보, 위치, 알림, 설정 저장
- `lib/screens/` 화면

## 다음 작업

- 주소 검색으로 집 설정
- iOS 라이브 액티비티 (잠금화면)
- 버스와 지하철 실시간 위치
