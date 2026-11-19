# 막차 알림 API 서버

앱 대신 공공 교통 API를 불러주는 작은 서버입니다. Cloudflare Workers에서 무료로 돌아가고, 인증키는 Cloudflare에만 저장됩니다.

## 처음 배포하기 (Mac 터미널)

한 줄씩 입력하세요.

1. Node.js 설치 (처음 한 번만)
   ```sh
   brew install node
   ```
2. 서버 폴더로 이동하고 필요한 도구 설치
   ```sh
   cd ~/App/server
   ```
   ```sh
   npm install
   ```
3. Cloudflare 로그인 (브라우저가 열리면 가입 또는 로그인 후 Allow)
   ```sh
   npx wrangler login
   ```
4. 배포
   ```sh
   npx wrangler deploy
   ```
   마지막에 나오는 `https://last-train-api.○○○.workers.dev` 주소가 서버 주소입니다.
5. 인증키 저장 (붙여넣어도 화면에 보이지 않는 게 정상)
   ```sh
   npx wrangler secret put DATA_GO_KR_KEY
   ```
   공공데이터포털 마이페이지의 **일반 인증키(Decoding)** 를 붙여넣습니다.
   ```sh
   npx wrangler secret put SEOUL_SUBWAY_KEY
   ```
   서울 열린데이터광장의 **실시간 지하철 인증키**를 붙여넣습니다.
   ```sh
   npx wrangler secret put ODSAY_KEY
   ```
   ODsay LAB에서 플랫폼을 **URI**로, 주소를 이 서버 주소(`https://last-train-api.○○○.workers.dev`)로 등록해 받은 키를 붙여넣습니다.

## 확인

브라우저에서 아래 주소를 열어 JSON이 나오면 성공입니다. `○○○`은 본인 주소로 바꾸세요.

- `https://last-train-api.○○○.workers.dev/health`
- `https://last-train-api.○○○.workers.dev/seoul/arrivals?station=강남`
- `https://last-train-api.○○○.workers.dev/tago/SubwayInfo/GetKwrdFndSubwaySttnList?subwayStationName=서울역`

## 주소 목록

| 주소 | 내용 |
| --- | --- |
| `/health` | 서버 상태 |
| `/seoul/arrivals?station=역이름` | 서울 지하철 역별 실시간 도착정보 |
| `/seoul/positions?line=2호선` | 서울 지하철 노선별 실시간 열차 위치 |
| `/tago/{서비스}/{기능}?...` | 공공데이터포털 TAGO API (지하철 시간표, 버스 도착·위치·정류소·노선) |
| `/odsay/{API}?...` | ODsay (길찾기, 지하철 시간표, 버스 노선 상세) |

## 지키는 것

- 인증키는 코드나 저장소에 쓰지 않고 `wrangler secret`으로만 넣습니다.
- 요청 로그 수집(observability)을 꺼서 이용자 위치가 남지 않게 합니다.
- 오류 응답에 인증키가 섞이지 않게 합니다.

## 테스트

```sh
npm test
```
