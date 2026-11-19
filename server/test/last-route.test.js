import assert from 'node:assert/strict';
import { afterEach, beforeEach, describe, it } from 'node:test';
import worker, { clearMemoryCache } from '../src/index.js';
import {
  busTripFromLane,
  clock,
  directionScore,
  findLastRoute,
  latestTrip,
  matchTrips,
  normalizeLineName,
  parseClock,
  parseHms,
  pickStation,
  planPath,
  serviceDay,
} from '../src/last-route.js';

/** 운행일 기준 분 → TAGO "HHMMSS". */
function hms(minutes) {
  const m = Math.round(minutes * 60);
  const h = Math.floor(m / 3600) % 24;
  return [h, Math.floor(m / 60) % 60, m % 60].map((n) => String(n).padStart(2, '0')).join('');
}

/**
 * 가짜 노선 S1-S2-S3-S4-S5. 역 사이 2분.
 * 하행(D): S1 출발 20:00부터 10분마다 01:00까지. 세 번째마다 S3에서 끝난다.
 * 상행(U): S5 출발 20:05부터 10분마다.
 */
const STATIONS = ['S1', 'S2', 'S3', 'S4', 'S5'];
function fakeSchedule(stationId, dir) {
  const pos = STATIONS.indexOf(stationId);
  const items = [];
  for (let k = 0; k <= 30; k += 1) {
    if (dir === 'D') {
      const end = k % 3 === 2 ? 'S3' : 'S5';
      if (pos > STATIONS.indexOf(end)) continue;
      const t = 20 * 60 + 10 * k + 2 * pos;
      items.push({ depTime: hms(t), arrTime: hms(t), endSubwayStationId: end, endSubwayStationNm: end });
    } else {
      const t = 20 * 60 + 5 + 10 * k + 2 * (4 - pos);
      items.push({ depTime: hms(t), arrTime: hms(t), endSubwayStationId: 'S1', endSubwayStationNm: 'S1' });
    }
  }
  return items;
}

function runs(stationId, dir) {
  return fakeSchedule(stationId, dir).map((it) => ({
    dep: parseHms(it.depTime),
    arr: parseHms(it.arrTime),
    end: it.endSubwayStationId,
    endName: it.endSubwayStationNm,
  })).sort((a, b) => a.dep - b.dep);
}

const subwayLeg = {
  trafficType: 1,
  sectionTime: 4,
  stationCount: 2,
  lane: [{ name: '수도권 9호선', subwayCode: 9, subwayCityCode: 1000 }],
  startName: 'S2',
  endName: 'S4',
  wayCode: 1,
  passStopList: { stations: [{ stationName: 'S2' }, { stationName: 'S3' }, { stationName: 'S4' }] },
};

function fakeData({ bus } = {}) {
  const calls = { bus: 0 };
  return {
    calls,
    async findSubwayStation(name) {
      return STATIONS.includes(name) ? { id: name, name } : null;
    },
    async subwaySchedule(id, _dayType, dir) {
      return runs(id, dir);
    },
    async busLane() {
      calls.bus += 1;
      return bus ?? null;
    },
  };
}

const weekdayEvening = serviceDay(new Date('2026-11-19T18:00:00+09:00'));

describe('운행일 계산', () => {
  it('오후는 오늘 평일 시간표', () => {
    const day = serviceDay(new Date('2026-11-19T15:00:00+09:00'));
    assert.equal(day.date, '2026-11-19');
    assert.equal(day.dayType, 'weekday');
    assert.equal(day.nowMin, 15 * 60);
  });

  it('새벽 3시 전은 전날 운행으로 본다', () => {
    const day = serviceDay(new Date('2026-11-20T00:30:00+09:00'));
    assert.equal(day.date, '2026-11-19');
    assert.equal(day.nowMin, 24 * 60 + 30);
  });

  it('토요일, 일요일, 공휴일을 구분한다', () => {
    assert.equal(serviceDay(new Date('2026-11-21T12:00:00+09:00')).dayType, 'saturday');
    assert.equal(serviceDay(new Date('2026-11-22T12:00:00+09:00')).dayType, 'holiday');
    assert.equal(serviceDay(new Date('2026-12-25T12:00:00+09:00')).dayType, 'holiday');
  });
});

describe('시간 읽기', () => {
  it('자정 넘은 시간표는 전날 운행 시간으로 바꾼다', () => {
    assert.equal(parseHms('000030'), 24 * 60 + 0.5);
    assert.equal(parseHms('235330'), 23 * 60 + 53.5);
    assert.equal(parseClock('23:10'), 23 * 60 + 10);
    assert.equal(parseClock('00:40'), 24 * 60 + 40);
    assert.equal(clock(24 * 60 + 5.9), '00:05');
  });
});

describe('TAGO 역 고르기', () => {
  const seoul = [
    { subwayStationId: 'MTRARA1A01', subwayStationName: '서울역', subwayRouteName: '공항' },
    { subwayStationId: 'MTRKRK4P313', subwayStationName: '서울역', subwayRouteName: '경의중앙' },
    { subwayStationId: 'MTRS11150', subwayStationName: '서울역', subwayRouteName: '1호선' },
    { subwayStationId: 'MTRS14426', subwayStationName: '서울역', subwayRouteName: '4호선' },
    { subwayStationId: 'MTRS1426', subwayStationName: '서울대입구', subwayRouteName: '2호선' },
  ];

  it('역 이름과 노선으로 고른다', () => {
    assert.equal(pickStation(seoul, '서울역', { name: '수도권 4호선', subwayCityCode: 1000 }).id, 'MTRS14426');
    assert.equal(pickStation(seoul, '서울역', { name: '수도권 공항철도', subwayCityCode: 1000 }).id, 'MTRARA1A01');
    assert.equal(pickStation(seoul, '서울역', { name: '수도권 경의중앙선', subwayCityCode: 1000 }).id, 'MTRKRK4P313');
  });

  it('같은 이름의 다른 도시 역은 도시로 가린다', () => {
    const banwoldang = [
      { subwayStationId: 'MTRDG10130', subwayStationName: '반월당', subwayRouteName: '1호선' },
      { subwayStationId: 'MTRDG20230', subwayStationName: '반월당', subwayRouteName: '2호선' },
    ];
    assert.equal(pickStation(banwoldang, '반월당', { name: '대구 2호선', subwayCityCode: 4000 }).id, 'MTRDG20230');
    const cityHall = [
      { subwayStationId: 'MTRBS10122', subwayStationName: '시청(연제)', subwayRouteName: '1호선' },
      { subwayStationId: 'MTRDJ10011', subwayStationName: '시청', subwayRouteName: '1호선' },
      { subwayStationId: 'MTRS11151', subwayStationName: '시청', subwayRouteName: '1호선' },
    ];
    assert.equal(pickStation(cityHall, '시청', { name: '수도권 1호선', subwayCityCode: 1000 }).id, 'MTRS11151');
    assert.equal(pickStation(cityHall, '시청', { name: '대전 1호선', subwayCityCode: 3000 }).id, 'MTRDJ10011');
    assert.equal(pickStation(cityHall, '시청', { name: '부산 1호선', subwayCityCode: 7000 }).id, 'MTRBS10122');
  });

  it('노선 이름을 맞춰 읽는다', () => {
    assert.equal(normalizeLineName('수도권 수인.분당선'), '수인분당');
    assert.equal(normalizeLineName('수인분당'), '수인분당');
    assert.equal(normalizeLineName('의정부경전철'), '의정부');
    assert.equal(normalizeLineName('2호선'), normalizeLineName('수도권 2호선'));
  });
});

describe('지하철 방향과 열차 짝짓기', () => {
  it('다음 역 시간표로 실제 방향을 찾는다', () => {
    const down = directionScore(runs('S2', 'D'), runs('S3', 'D'), 'S3', 2);
    const up = directionScore(runs('S2', 'U'), runs('S3', 'U'), 'S3', 2);
    assert.ok(down > 0.9, `down ${down}`);
    assert.ok(up < 0.2, `up ${up}`);
  });

  it('중간에서 끝나는 열차는 빼고 가장 늦은 열차를 고른다', () => {
    const trips = matchTrips(runs('S2', 'D'), runs('S4', 'D'), 'S4', 4);
    assert.ok(trips.every((t) => t.endName === 'S5'));
    const last = latestTrip(trips, Infinity);
    // k=30은 S3에서 끝나서(30 % 3 = 0 → S5) ... k=30은 S5행, 출발 20:00 + 300 + 2 = 01:02
    assert.equal(clock(last.dep), '01:02');
    assert.equal(last.arr - last.dep, 4);
    assert.equal(last.isLast, true);
  });

  it('다음 구간 시각에 맞춰 더 이른 열차를 고른다', () => {
    const trips = matchTrips(runs('S2', 'D'), runs('S4', 'D'), 'S4', 4);
    const trip = latestTrip(trips, 23 * 60 + 30);
    assert.ok(trip.arr <= 23 * 60 + 30);
    assert.equal(trip.isLast, false);
  });
});

describe('버스 막차 추정', () => {
  const sp = { trafficType: 2, sectionTime: 20, stationCount: 10, startID: 30, lane: [{ busNo: '402', busID: 1 }] };
  const detail = {
    busFirstTime: '04:30',
    busLastTime: '22:40',
    busInterval: '10',
    station: Array.from({ length: 40 }, (_, i) => ({ stationID: i * 10, idx: i + 1 })),
  };

  it('거리 정보가 없으면 정류장 수로 짧게 잡아 더한다', () => {
    // 정류장 3번째(인덱스 3), 정류장당 2분, 보정 0.8 → 4.8분
    const trip = busTripFromLane(sp, detail, Infinity);
    assert.equal(trip.isLast, true);
    assert.equal(trip.estimated, true);
    assert.equal(Math.round(trip.dep * 10) / 10, 22 * 60 + 40 + 4.8);
  });

  it('기점부터 거리로 추정하고, 밤 버스는 시속 25km 이상으로 본다', () => {
    // 402번: 장지 막차 24:05, 서울역 정류장까지 27,715m. 길찾기 구간은 9km를 34분(시속 16km).
    const lane = {
      busFirstTime: '04:00',
      busLastTime: '24:05',
      bus_Interval_Week: '9',
      bus_Interval_Sun: '13',
      station: [{ stationID: 127479, stationDistance: 0 }, { stationID: 166790, stationDistance: 27715 }],
    };
    const leg = { trafficType: 2, sectionTime: 34, distance: 9000, stationCount: 15, startID: 166790 };
    const trip = busTripFromLane(leg, lane, Infinity);
    assert.equal(clock(trip.dep), '01:11');
    // 다음 구간 때문에 일찍 타야 하면 요일별 배차 간격을 쓴다.
    const sunday = busTripFromLane(leg, lane, 24 * 60, 'holiday');
    assert.equal(sunday.dep, 24 * 60 - 34 - 13);
  });

  it('다음 구간 때문에 일찍 타야 하면 배차 간격만큼 일찍 정류장에 가게 한다', () => {
    const trip = busTripFromLane(sp, detail, 22 * 60);
    assert.equal(trip.isLast, false);
    assert.equal(trip.dep, 22 * 60 - 20 - 10);
  });

  it('막차 시간이 없으면 계산하지 않는다', () => {
    assert.equal(busTripFromLane(sp, { station: [] }, Infinity), null);
  });
});

describe('경로 막차 계산', () => {
  it('도보와 지하철 경로의 출발 시각을 거꾸로 계산한다', async () => {
    const path = {
      pathType: 1,
      subPath: [{ trafficType: 3, sectionTime: 5 }, subwayLeg, { trafficType: 3, sectionTime: 2 }],
    };
    const plan = await planPath(path, weekdayEvening, fakeData());
    // 막차 01:02 출발, 역 여유 3분, 도보 5분 → 00:54
    assert.equal(clock(plan.departBy), '00:54');
    assert.equal(clock(plan.arriveAt), '01:08');
    assert.equal(plan.estimated, false);
    assert.deepEqual(plan.legs.map((l) => l.mode), ['walk', 'subway', 'walk']);
    assert.match(plan.legs[0].description, /S2역까지 걸어서 5분/);
    assert.match(plan.legs[1].description, /9호선 S2역 01:02 출발 → S4역 01:06 도착 \(막차\)/);
    assert.match(plan.legs[2].description, /집까지 걸어서 2분/);
  });

  it('지하철에서 버스로 갈아탈 때 버스 막차에 맞춰 지하철을 고른다', async () => {
    const path = {
      pathType: 3,
      subPath: [
        subwayLeg,
        { trafficType: 3, sectionTime: 3 },
        { trafficType: 2, sectionTime: 10, stationCount: 5, startID: 0, startName: 'A', endName: 'B', lane: [{ busNo: '7', busID: 9 }] },
      ],
    };
    const bus = { busFirstTime: '05:00', busLastTime: '23:30', busInterval: '15', station: [{ stationID: 0 }] };
    const plan = await planPath(path, weekdayEvening, fakeData({ bus }));
    // 버스 막차 23:30, 탑승 여유 1분, 도보 3분 → 지하철은 23:26까지 S4 도착
    const subway = plan.legs.find((l) => l.mode === 'subway');
    assert.ok(subway.arriveMin <= 23 * 60 + 26);
    assert.ok(subway.arriveMin > 23 * 60 + 10);
    assert.equal(plan.estimated, true);
    assert.match(plan.legs.at(-1).description, /7번 버스 A 23:30쯤 막차 \(추정\) → B/);
  });

  it('여러 경로 중 가장 늦게 출발해도 되는 경로를 고른다', async () => {
    const early = {
      pathType: 2,
      subPath: [{ trafficType: 2, sectionTime: 10, stationCount: 5, startID: 0, startName: 'A', endName: 'B', lane: [{ busNo: '7', busID: 9 }] }],
    };
    const late = { pathType: 1, subPath: [subwayLeg] };
    const bus = { busFirstTime: '05:00', busLastTime: '22:00', station: [] };
    const found = await findLastRoute([early, late], weekdayEvening, fakeData({ bus }));
    assert.equal(found.status, 'ok');
    assert.equal(clock(found.plan.departBy), '00:59');
  });

  it('막차가 이미 지났으면 missed', async () => {
    const day = serviceDay(new Date('2026-11-20T01:30:00+09:00'));
    const found = await findLastRoute([{ pathType: 1, subPath: [subwayLeg] }], day, fakeData());
    assert.equal(found.status, 'missed');
  });

  it('시간표가 없으면 unknown', async () => {
    const leg = { ...subwayLeg, startName: '없는역' };
    const found = await findLastRoute([{ pathType: 1, subPath: [leg] }], weekdayEvening, fakeData());
    assert.equal(found.status, 'unknown');
  });

  it('고속버스나 열차가 섞인 경로는 건너뛴다', async () => {
    const found = await findLastRoute([{ pathType: 11, subPath: [{ trafficType: 4 }] }], weekdayEvening, fakeData());
    assert.equal(found.status, 'unknown');
  });
});

describe('/last-route', () => {
  const realFetch = globalThis.fetch;
  const env = { DATA_GO_KR_KEY: 'k', ODSAY_KEY: 'o', SEOUL_SUBWAY_KEY: 's' };
  let calls;

  function tagoResponse(items) {
    return { response: { header: { resultCode: '00' }, body: { items: items.length ? { item: items } : '' } } };
  }

  beforeEach(() => {
    clearMemoryCache();
    calls = [];
  });

  afterEach(() => {
    globalThis.fetch = realFetch;
  });

  function stub(odsayResult) {
    globalThis.fetch = async (input, init) => {
      const url = new URL(String(input));
      calls.push({ url, init });
      let body;
      if (url.hostname === 'api.odsay.com') {
        body = odsayResult;
      } else if (url.pathname.endsWith('GetKwrdFndSubwaySttnList')) {
        const name = url.searchParams.get('subwayStationName');
        body = tagoResponse(STATIONS.includes(name)
          ? [{ subwayStationId: name, subwayStationName: name, subwayRouteName: '9호선' }]
          : []);
      } else if (url.pathname.endsWith('GetSubwaySttnAcctoSchdulList')) {
        body = tagoResponse(fakeSchedule(url.searchParams.get('subwayStationId'), url.searchParams.get('upDownTypeCode')));
      } else {
        throw new Error(`unexpected ${url}`);
      }
      return new Response(JSON.stringify(body));
    };
  }

  function call(query) {
    return worker.fetch(new Request(`https://api.example.com/last-route?${query}`), env);
  }

  const coords = 'fromLat=37.55&fromLng=126.97&toLat=37.49&toLng=127.02';

  it('막차 출발 시각과 구간을 앱 형식으로 돌려준다', async () => {
    stub({ result: { path: [{ pathType: 1, subPath: [{ trafficType: 3, sectionTime: 5 }, subwayLeg] }] } });
    const res = await call(`${coords}&at=2026-11-19T18:00:00%2B09:00`);
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.departBy, '2026-11-19T15:54:00.000Z'); // 00:54 KST
    assert.equal(body.serviceDate, '2026-11-19');
    assert.equal(body.legs[1].mode, 'subway');
    assert.equal(body.legs[1].departAt, '2026-11-19T16:02:00.000Z');
    assert.equal(res.headers.get('cache-control'), 'no-store');

    const search = calls.find((c) => c.url.hostname === 'api.odsay.com');
    assert.equal(search.url.searchParams.get('SX'), '126.97');
    assert.equal(search.url.searchParams.get('SY'), '37.55');
    assert.equal(search.init.headers.referer, 'https://api.example.com/');
    assert.equal(search.init.cf, undefined, '길찾기는 캐시하지 않는다');
  });

  it('좌표가 없거나 한국 밖이면 400', async () => {
    stub({});
    assert.equal((await call('fromLat=37.5&fromLng=126.9')).status, 400);
    assert.equal((await call('fromLat=10&fromLng=10&toLat=37&toLng=127')).status, 400);
    assert.equal(calls.length, 0);
  });

  it('집이 너무 가까우면 404와 이유', async () => {
    stub({ error: { code: '-98', msg: '출발지와 도착지가 700m 이내입니다.' } });
    const res = await call(coords);
    assert.equal(res.status, 404);
    assert.equal((await res.json()).reason, 'too-close');
  });

  it('막차가 끊겼으면 404 missed', async () => {
    stub({ result: { path: [{ pathType: 1, subPath: [subwayLeg] }] } });
    const res = await call(`${coords}&at=2026-11-20T01:30:00%2B09:00`);
    assert.equal(res.status, 404);
    assert.equal((await res.json()).reason, 'missed');
  });
});
