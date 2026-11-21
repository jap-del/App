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
| `/last-route?fromLat=&fromLng=&toLat=&toLng=` | 집까지 오늘 막차 출발 시각과 경로 (앱이 부르는 주소). 응답의 `savedPaths`는 앱이 기기에 저장해 둔다 |
| `POST /last-route` (본문 `{"paths": savedPaths}`) | 저장해 둔 경로로 오늘 막차 계산. 좌표를 받지 않고 길찾기(ODsay)를 부르지 않는다 |
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

## 막차 계산 방법 (`/last-route`)

1. ODsay 길찾기로 경로 후보를 받습니다 (ODsay 호출 1번).
2. 경로의 마지막 구간부터 거꾸로, 다음 구간에 늦지 않게 탈 수 있는 가장 늦은 차를 고릅니다.
   - 지하철: 공공데이터포털 TAGO 역별 시간표로 계산합니다 (무료). 출발역과 다음 역 시간표를
     비교해 방향을 확인하고, 도착역에 같은 종착역 열차가 나타나는지 보고 중간에 끝나거나
     다른 지선으로 가는 열차를 뺍니다.
   - 버스(서울): 공공데이터포털 "서울특별시_정류소정보조회 서비스"의 정류소별 막차 시각을 씁니다 (정확).
     활용신청이 안 돼 있으면 아래 추정으로 넘어갑니다.
   - 버스(그 밖): ODsay 노선 정보의 기점 막차 시각에 기점부터 정류장까지 거리를 시속 25km 이상으로
     달린다고 보고 더한 뒤 5분을 빼서 **추정**합니다. 회차 지점을 지난 정류장은 막차가 거기까지 오는지
     알 수 없어서 추정하지 않습니다. 추정이 섞이면 응답의 `estimated`가 true입니다.
3. 가장 늦게 출발해도 되는 **일반 버스·지하철** 경로를 돌려줍니다. 역에 들어가는 여유로 지하철 3분, 버스 1분을 둡니다.
   그 뒤에도 탈 수 있는 심야버스(N번)가 있으면 `nightBus`로 따로 알려주고, 일반 막차가 끊긴 뒤에는 심야버스 경로를 돌려줍니다.
   심야버스처럼 첫차보다 막차가 이른 노선은 막차를 다음 날 새벽으로 봅니다.
4. 같은 계산을 **지하철만, 버스만, 버스+지하철** 경로마다 따로 해서 `options`에 넣습니다.
   각 항목은 `kind`(`subway`, `bus`, `mixed`)와 `status`(`ok`, `missed` 막차 끊김, `unknown` 계산 못 함,
   `none` 그런 경로 없음)를 갖고, `ok`면 맨 위와 같은 모양(`departBy`, `legs`, `nightBus` 등)입니다.
   맨 위 값은 그중 가장 늦은 막차이고 `kind`로 종류를 알려줍니다 (예전 앱도 그대로 읽습니다).
5. 버스·지하철 구간(`legs`)에는 지나는 역·정류장 좌표 `path: [[위도, 경도], ...]`가 들어 있어 지도에 선으로 그립니다.
   걷는 구간은 좌표가 없고, 앱이 앞뒤 구간과 현재 위치·집 좌표를 이어서 그립니다.

새벽 3시 전은 전날 운행으로 봅니다. 공휴일 목록은 `src/holidays.js`에 있고 2027년까지 들어 있습니다.
ODsay 무료 요금제는 하루 30건이라 한 요청에서 버스 노선 조회는 3번까지만 하고, 서울 정류소 시각이 있으면 부르지 않습니다.
살펴보는 경로는 지하철 3개, 버스 6개, 버스+지하철 2개입니다. Cloudflare 무료 요금제는 요청 하나에서 바깥 API를
50번까지만 부를 수 있어서, 종류마다 같은 서버의 내부 진입점 `Planner`(`src/worker.js`, `wrangler.toml`의 `PLANNER` 연결)에
계산을 맡겨 한도(45번)를 따로 받습니다. `Planner`는 인터넷에서 부를 수 없고, 넘기는 값에 이용자 좌표는 없습니다.
연결이 없거나 실패하면 한 요청 안에서 종류마다 첫 경로를 먼저 계산하고 나머지를 한도 안에서 번갈아 계산합니다.
심야버스는 정류장 시각(서울시)이 없으면 추정하지 않습니다. 밤새 배차가 달라 기점 시각으로 추정하면 크게 틀리기 때문입니다.

계산 과정을 보려면 `&debug=1`을 붙입니다. 좌표 없이 경로별 계산 과정을 함께 돌려주고 항상 200으로 답합니다.

