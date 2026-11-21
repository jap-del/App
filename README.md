# 막차 알림

집을 설정해 두면 현재 위치에서 집까지 가는 막차 시간을 알려주고, 출발해야 할 때 알림을 보내는 앱입니다. Flutter로 만들었고, **iOS(App Store)에 먼저 출시**합니다. Android 코드도 그대로 두어 나중에 Google Play에 낼 수 있습니다.

## 현재 상태

- 집 설정 (현재 위치를 집으로 저장)
- 막차 시간과 남은 시간 표시
- 출발 알림 예약 (5분 전부터 30분 전까지 선택)
- 잠금화면 막차 시간: Android는 고정 알림, iOS는 일반 알림 (iOS 라이브 액티비티는 다음 작업)
- 홈 화면 아래 배너 광고, 지도 화면을 닫을 때 전면 영상 광고 (AdMob 비맞춤형, 지금은 테스트 광고)
- 설정의 광고 제거: 인앱 결제(영구), 보상형 영상 광고 시청(24시간), 구매 복원
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

ODsay 길찾기는 호출마다 돈이 들어서(무료 요금제는 하루 30번), 앱은 두 가지로 호출을 아낍니다.

- 같은 자리에서 10분 안에 다시 물으면 앞의 결과를 다시 씁니다.
- 서버가 찾아 준 경로(`savedPaths`)를 기기에 7일 동안 저장해 두고, 같은 곳(300m 안)에서 같은 집으로 물으면 좌표 없이 경로만 서버에 보내(`POST /last-route`) 시간표로만 다시 계산합니다. ODsay는 처음 가 보는 곳에서만 부릅니다.

교통 API 키는 앱에 넣지 않고 서버에만 둡니다.

## 광고

지금은 Google의 테스트용 광고 ID가 들어 있어서 수익이 나지 않습니다. 출시 전에 [AdMob](https://admob.google.com)에서 **iOS 앱**을 추가하고 광고 단위 3개(배너, 전면, 보상형)를 만든 뒤 바꿉니다.

- iOS 앱 ID: `ios/Runner/Info.plist`의 `GADApplicationIdentifier`
- iOS 광고 단위 ID: 빌드할 때 넘깁니다.

```sh
flutter build ipa --dart-define=AD_BANNER_IOS=ca-app-pub-... --dart-define=AD_INTERSTITIAL_IOS=ca-app-pub-... --dart-define=AD_REWARDED_IOS=ca-app-pub-...
```

- Android로 낼 때는 `AndroidManifest.xml`의 `APPLICATION_ID`와 `AD_BANNER_ANDROID`, `AD_INTERSTITIAL_ANDROID`, `AD_REWARDED_ANDROID`를 같은 방식으로 넣습니다.
- 맞춤형 광고를 요청하지 않으므로 iOS 추적 허용(ATT) 팝업은 띄우지 않습니다.

전면 영상 광고는 지도 화면을 닫을 때만, 30분에 한 번까지, 출발 30분 전부터는 띄우지 않습니다 (`lib/services/ad_free.dart`의 `shouldShowInterstitial`).

### 광고 제거 결제

App Store Connect에서 이 앱의 **수익화 > 앱 내 구입**에 상품 ID `remove_ads`로 **비소모품** 상품을 만들면 설정 화면에 가격이 나옵니다. 그 전에 App Store Connect의 **비즈니스**에서 유료 앱 계약, 세금, 은행 계좌 정보를 끝내야 상품이 앱에 보입니다. 구매 기록은 기기에 저장하고, 재설치하면 "구매 복원"으로 되살립니다(App Store 심사에서 복원 버튼이 필요합니다). 지금은 영수증을 서버에서 검증하지 않습니다. Android로 낼 때는 Google Play Console에 같은 ID로 만듭니다.

### 출시 전 확인 (ODsay 약관)

ODsay 이용약관 제6조는 API를 비상업적 목적으로만 쓰고, 광고와 같은 화면에 붙여 두지 말라고 합니다. 유료 요금제에서 광고가 있는 iOS 앱이 허용되는지 ODsay에 서면으로 확인한 뒤 출시합니다. 안 된다고 하면 막차 화면의 배너를 경로 결과가 없는 화면으로 옮깁니다.

개발 중에는 반드시 테스트 ID를 쓰세요. 실제 광고를 직접 누르면 AdMob 계정이 정지될 수 있습니다.

## iOS 출시 준비

- 지금은 iPhone 전용입니다 (iPad를 빼서 iPad 스크린샷과 iPad 심사가 필요 없습니다). 세로·가로 화면을 지원합니다.
- Apple Developer Program 가입 (연간 비용 있음), App Store Connect에서 번들 ID `com.japdel.lastTrain`으로 앱 만들기.
- 앱 개인정보 보호(영양 성분표): AdMob이 수집하는 기기 ID, 광고 데이터, 사용 데이터, 진단 정보와 "대략적·정확한 위치"(막차 계산용, 이용자와 연결되지 않음)를 표시합니다.
- 개인정보처리방침 URL: 아래 GitHub Pages 주소를 App Store Connect에 넣습니다.
- `Info.plist`에 암호화 면제(`ITSAppUsesNonExemptEncryption`)와 Google 광고의 SKAdNetwork ID를 넣어 두었습니다.
- 출시 전 지도 타일 제공자 교체 (OpenStreetMap 공개 타일은 배포 앱에서 쓸 수 없음), ODsay 상업 이용 확인.

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
