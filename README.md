# 막차 알림

집을 설정해 두면 현재 위치에서 집까지 가는 막차 시간을 알려주고, 출발해야 할 때 알림을 보내는 앱입니다. Flutter로 Android와 iOS를 함께 지원합니다.

## 현재 상태

- 집 설정 (현재 위치를 집으로 저장)
- 막차 시간과 남은 시간 표시
- 출발 알림 예약 (5분 전부터 30분 전까지 선택)
- Android 잠금화면 고정 알림

아직 실제 교통 데이터는 연결되지 않았습니다. 서버 주소를 넘기지 않으면 화면에 "예시 데이터"라고 표시되는 가짜 막차 시간이 나옵니다.

## 실행

```sh
flutter pub get
flutter run
```

서버가 준비되면 주소를 넘겨 실제 데이터를 씁니다.

```sh
flutter run --dart-define=API_BASE_URL=https://example.com
```

교통 API 키는 앱에 넣지 않고 서버에만 둡니다.

## 검사

```sh
flutter analyze
flutter test
```

## 구조

- `lib/logic/` 알림 시각 계산
- `lib/models/` 집, 경로 데이터
- `lib/services/` 교통 정보, 위치, 알림, 설정 저장
- `lib/screens/` 화면

## 다음 작업

- 서버: ODsay 길찾기와 공공데이터 API로 전국 막차 경로 계산
- 주소 검색으로 집 설정
- iOS 라이브 액티비티 (잠금화면)
- 버스와 지하철 실시간 위치
