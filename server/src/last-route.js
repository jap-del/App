// 막차 계산.
//
// 1. ODsay 길찾기로 집까지 가는 경로 후보를 받는다.
// 2. 경로의 마지막 구간부터 거꾸로, 다음 구간에 늦지 않게 탈 수 있는 가장 늦은 차를 고른다.
//    지하철은 TAGO 역별 시간표로 정확히, 버스는 ODsay 노선 막차 시간으로 추정한다.
// 3. 집을 향해 가장 늦게 출발할 수 있는 경로를 고른다.
//
// 시간은 모두 "운행일 0시부터 몇 분"으로 다룬다. 새벽 3시 전은 전날 운행으로 보므로
// 00:30 막차는 24 * 60 + 30 = 1470분이 된다.

import { HOLIDAYS } from './holidays.js';

export const DAY_START_HOUR = 3;
const KST_OFFSET_MS = 9 * 60 * 60 * 1000;
const MINUTE_MS = 60 * 1000;

/** 역에 들어가 타는 곳까지 가는 여유 시간(분). */
export const BOARD_BUFFER = { subway: 3, bus: 1 };

/** 버스 막차가 우리 정류장에 오는 시각을 추정할 때 쓰는 보정. 늦게 잡으면 놓치므로 짧게 잡는다. */
const BUS_OFFSET_FACTOR = 0.8;

/** 한 번 요청에 살펴볼 경로 수. ODsay 호출 수를 아끼기 위해 버스 경로는 더 적게 본다. */
export const MAX_SUBWAY_PATHS = 3;
/** 버스만 타는 경로. 서울 버스는 무료 API로 정류소 시각을 보므로 넉넉히 본다. */
export const MAX_BUS_PATHS = 6;
/** 버스와 지하철을 함께 타는 경로. 바깥 API 호출이 많아서 여유가 있을 때만 본다. */
export const MAX_MIXED_PATHS = 2;
const MIXED_BUDGET_LEFT = 15;

/** 막차 계산에는 저녁 이후 열차만 있으면 된다. 계산량을 줄이려고 그 전 열차는 버린다. */
export const SCHEDULE_FROM_MIN = 17 * 60;

/** 지금 시각이 속한 운행일과 시간표 종류. */
export function serviceDay(now = new Date()) {
  const kst = new Date(now.getTime() + KST_OFFSET_MS);
  let nowMin = kst.getUTCHours() * 60 + kst.getUTCMinutes() + kst.getUTCSeconds() / 60;
  let dayMs = Date.UTC(kst.getUTCFullYear(), kst.getUTCMonth(), kst.getUTCDate());
  if (kst.getUTCHours() < DAY_START_HOUR) {
    dayMs -= 24 * 60 * MINUTE_MS;
    nowMin += 24 * 60;
  }
  const day = new Date(dayMs);
  const date = day.toISOString().slice(0, 10);
  const weekday = day.getUTCDay();
  const dayType = HOLIDAYS.has(date) || weekday === 0 ? 'holiday' : weekday === 6 ? 'saturday' : 'weekday';
  return { date, dayType, nowMin, midnightMs: dayMs - KST_OFFSET_MS };
}

export function toIso(day, minutes) {
  return new Date(day.midnightMs + Math.round(minutes * 60) * 1000).toISOString();
}

/** "HH:MM" 꼴 표시. 24시 넘은 시각도 00:30처럼 보여준다. */
export function clock(minutes) {
  const m = Math.floor(minutes);
  const h = Math.floor(m / 60) % 24;
  return `${String(h).padStart(2, '0')}:${String(m % 60).padStart(2, '0')}`;
}

/** TAGO 시간 "HHMMSS"를 운행일 기준 분으로. */
export function parseHms(text) {
  const m = /^(\d{2})(\d{2})(\d{2})$/.exec(String(text ?? ''));
  if (!m) return null;
  let h = Number(m[1]);
  if (h < DAY_START_HOUR) h += 24;
  return h * 60 + Number(m[2]) + Number(m[3]) / 60;
}

/** ODsay 시간 "HH:MM" 또는 "HHMM"을 운행일 기준 분으로. */
export function parseClock(text) {
  const m = /^(\d{1,2}):?(\d{2})$/.exec(String(text ?? '').trim());
  if (!m) return null;
  let h = Number(m[1]);
  if (h < DAY_START_HOUR) h += 24;
  return h * 60 + Number(m[2]);
}

/** 공공데이터포털 응답에서 item 배열을 꺼낸다. 하나일 때 객체, 없을 때 빈 문자열로 온다. */
export function tagoItems(data) {
  const item = data?.response?.body?.items?.item;
  if (!item) return [];
  return Array.isArray(item) ? item : [item];
}

/** TAGO 역별 시간표를 운행일 기준 분으로 바꾼다. */
export function parseTagoSchedule(items, fromMin = SCHEDULE_FROM_MIN) {
  const runs = [];
  for (const it of items) {
    const dep = parseHms(it.depTime);
    const arr = parseHms(it.arrTime) ?? dep;
    if (dep == null && arr == null) continue;
    if ((dep ?? arr) < fromMin) continue;
    runs.push({
      dep: dep ?? arr,
      arr: arr ?? dep,
      end: String(it.endSubwayStationId ?? ''),
      endName: it.endSubwayStationNm ?? '',
    });
  }
  return runs.sort((a, b) => a.dep - b.dep);
}

export const TAGO_DAY_CODE = { weekday: '01', saturday: '02', holiday: '03' };

export function normalizeStationName(name) {
  return String(name ?? '')
    .replace(/\(.*?\)/g, '')
    .replace(/\s/g, '')
    .replace(/역$/, '');
}

/** "수도권 수인.분당선" → "수인분당", "부산 1호선" → "부산1호", "공항철도" → "공항". */
export function normalizeLineName(name) {
  return String(name ?? '')
    .replace(/\(.*?\)/g, '')
    .replace(/^수도권/, '')
    .replace(/[\s.\-·]/g, '')
    .replace(/(경전철|철도|선)$/, '');
}

const ODSAY_CITY = { 1000: 'capital', 3000: 'daejeon', 4000: 'daegu', 5000: 'gwangju', 7000: 'busan' };

export function tagoCity(stationId) {
  if (/^MTR(BS|BG)/.test(stationId)) return 'busan';
  if (/^MTRDG/.test(stationId)) return 'daegu';
  if (/^MTRDJ/.test(stationId)) return 'daejeon';
  if (/^MTRGJ/.test(stationId)) return 'gwangju';
  return 'capital';
}

/**
 * TAGO 역 검색 결과에서 ODsay 구간의 역과 노선에 맞는 역을 고른다.
 * candidates: [{subwayStationId, subwayStationName, subwayRouteName}]
 */
export function pickStation(candidates, stationName, lane) {
  const want = normalizeStationName(stationName);
  const line = normalizeLineName(lane?.name);
  const city = ODSAY_CITY[lane?.subwayCityCode];
  let best = null;
  let bestScore = 0;
  for (const c of candidates) {
    if (normalizeStationName(c.subwayStationName) !== want) continue;
    const route = normalizeLineName(c.subwayRouteName);
    let score = 0;
    if (route && route === line) score = 4;
    else if (route && line && (line.endsWith(route) || route.endsWith(line))) score = 2;
    else continue;
    if (city && tagoCity(c.subwayStationId) === city) score += 1;
    if (score > bestScore) {
      best = c;
      bestScore = score;
    }
  }
  return best ? { id: String(best.subwayStationId), name: best.subwayStationName } : null;
}

/**
 * 출발역과 바로 다음 역의 시간표를 비교해 상행(U)과 하행(D) 중 실제로 가는 방향을 고른다.
 * ODsay의 wayCode와 TAGO의 상하행 표기는 노선마다 다르게 대응해서 시간표로 확인한다.
 * 맞는 방향이면 출발역을 떠난 열차가 몇 분 뒤 다음 역에 같은 종착역으로 나타난다.
 */
export function directionScore(startRuns, nextRuns, nextId, perStation) {
  const evening = startRuns.filter((r) => r.dep >= 20 * 60 && r.end !== nextId);
  const sample = evening.length >= 5 ? evening : startRuns.filter((r) => r.end !== nextId);
  if (!sample.length) return 0;
  const limit = Math.max(perStation, 1) + 2;
  let hit = 0;
  for (const s of sample) {
    if (nextRuns.some((n) => n.end === s.end && n.arr - s.dep >= 0 && n.arr - s.dep <= limit)) hit += 1;
  }
  return hit / sample.length;
}

/**
 * 출발역 시간표와 도착역 시간표에서 같은 열차를 짝지어 [출발, 도착] 목록을 만든다.
 * 도착역에 같은 종착역으로 나타나지 않는 열차(중간에서 끝나거나 다른 지선으로 가는 열차)는 뺀다.
 */
export function matchTrips(startRuns, endRuns, endId, sectionTime) {
  const trips = [];
  const lo = Math.max(0, sectionTime * 0.6 - 2);
  const hi = sectionTime * 1.4 + 3;
  // 앞선 열차가 이미 짝지은 도착 기록은 다시 쓰지 않는다 (급행이 끼어 있을 때 엉뚱한 짝을 막는다).
  const claimed = new Set();
  for (const s of startRuns) {
    if (s.end === endId) {
      trips.push({ dep: s.dep, arr: s.dep + sectionTime, endName: s.endName });
      continue;
    }
    let best = -1;
    for (let j = 0; j < endRuns.length; j += 1) {
      const e = endRuns[j];
      if (claimed.has(j) || e.end !== s.end) continue;
      const d = e.arr - s.dep;
      if (d < lo || d > hi) continue;
      if (best < 0 || Math.abs(d - sectionTime) < Math.abs(endRuns[best].arr - s.dep - sectionTime)) best = j;
    }
    if (best >= 0) {
      claimed.add(best);
      trips.push({ dep: s.dep, arr: endRuns[best].arr, endName: s.endName });
    }
  }
  return trips;
}

/** deadline까지 도착할 수 있는 가장 늦은 열차와, 그게 오늘 마지막 열차인지. */
export function latestTrip(trips, deadline) {
  let best = null;
  let last = null;
  for (const t of trips) {
    if (!last || t.dep > last.dep) last = t;
    if (t.arr <= deadline && (!best || t.dep > best.dep)) best = t;
  }
  if (!best) return null;
  return { ...best, isLast: best === last };
}

const noLog = () => {};

/**
 * 지하철 구간에서 탈 수 있는 열차 목록을 만든다 (출발, 도착 시각). 데이터가 없으면 null.
 * 다음 구간 시각과 상관없이 불러올 수 있어서 모든 구간을 한꺼번에 준비한다.
 */
async function prepareSubway(sp, day, data, log) {
  const lane = sp.lane?.[0];
  const stations = sp.passStopList?.stations ?? [];
  const nextName = stations[1]?.stationName ?? sp.endName;
  const [from, next, to] = await Promise.all([
    data.findSubwayStation(sp.startName, lane),
    data.findSubwayStation(nextName, lane),
    data.findSubwayStation(sp.endName, lane),
  ]);
  log(`역 찾기 ${lane?.name}: ${sp.startName}=${from?.id} ${nextName}=${next?.id} ${sp.endName}=${to?.id}`);
  if (!from || !next || !to) return null;

  const sameEnd = to.id === next.id;
  const [startU, startD, nextU, nextD, endU, endD] = await Promise.all([
    data.subwaySchedule(from.id, day.dayType, 'U'),
    data.subwaySchedule(from.id, day.dayType, 'D'),
    data.subwaySchedule(next.id, day.dayType, 'U'),
    data.subwaySchedule(next.id, day.dayType, 'D'),
    sameEnd ? null : data.subwaySchedule(to.id, day.dayType, 'U'),
    sameEnd ? null : data.subwaySchedule(to.id, day.dayType, 'D'),
  ]);
  const perStation = (sp.sectionTime ?? 2) / Math.max(sp.stationCount ?? 1, 1);
  const scoreU = directionScore(startU, nextU, next.id, perStation);
  const scoreD = directionScore(startD, nextD, next.id, perStation);
  log(`방향 점수 U=${scoreU.toFixed(2)} D=${scoreD.toFixed(2)} (열차 수 출발 U${startU.length}/D${startD.length}, 다음 역 U${nextU.length}/D${nextD.length})`);
  if (Math.max(scoreU, scoreD) < 0.6 || Math.abs(scoreU - scoreD) < 0.2) return null;
  const dir = scoreU > scoreD ? 'U' : 'D';
  const startRuns = dir === 'U' ? startU : startD;
  const endRuns = dir === 'U' ? (sameEnd ? nextU : endU) : (sameEnd ? nextD : endD);
  const trips = matchTrips(startRuns, endRuns, to.id, sp.sectionTime ?? 0);
  log(`${sp.startName}→${sp.endName} ${dir} 방향 짝지은 열차 ${trips.length}개 (도착역 ${endRuns.length}개)`);
  return { trips };
}

function subwayTripFrom(prepared, deadline) {
  const trip = prepared && latestTrip(prepared.trips, deadline);
  return trip ? { ...trip, estimated: false } : null;
}

/** 추정한 버스 막차 시각에서 빼는 여유(분). 추정이 늦으면 막차를 놓치므로 일찍 잡는다. */
export const BUS_SAFETY_MIN = 5;
/** 배차 간격을 모를 때 쓰는 값(분). */
const DEFAULT_BUS_INTERVAL = 15;

/** 심야버스(N26, N75 등)인지. */
export function isNightBus(lane) {
  return /^N\d/i.test(String(lane?.busNo ?? '').trim()) || String(lane?.busNo ?? '').includes('심야');
}

/**
 * 첫차보다 막차가 이르면 자정을 넘어 끝나는 노선(심야버스)이라 막차에 하루를 더한다.
 * 예: 첫차 23:40, 막차 04:10 → 막차는 다음 날 04:10 (운행일 기준 28:10).
 */
export function wrapStopTimes(stop) {
  if (stop.first != null && stop.last < stop.first) return { ...stop, last: stop.last + 24 * 60 };
  return stop;
}

/**
 * 서울 버스의 "정류소별 첫차/막차" 시각("HH:MM", "HHMMSS", "20261119233000" 등)을
 * 운행일 기준 분으로.
 */
export function parseSeoulBusTime(text) {
  const digits = String(text ?? '').replace(/\D/g, '');
  let hh;
  let mm;
  if (digits.length >= 12) {
    hh = digits.slice(8, 10);
    mm = digits.slice(10, 12);
  } else if (digits.length === 4 || digits.length === 6) {
    hh = digits.slice(0, 2);
    mm = digits.slice(2, 4);
  } else if (digits.length === 3) {
    hh = digits.slice(0, 1);
    mm = digits.slice(1, 3);
  } else {
    return null;
  }
  let h = Number(hh);
  const m = Number(mm);
  if (!(h >= 0 && h <= 29 && m >= 0 && m < 60)) return null;
  if (h < DAY_START_HOUR) h += 24;
  return h * 60 + m;
}

function busInterval(detail, dayType) {
  const text = {
    weekday: detail?.bus_Interval_Week,
    saturday: detail?.bus_Interval_Sat,
    holiday: detail?.bus_Interval_Sun,
  }[dayType] ?? detail?.busInterval;
  return Math.min(Math.max(parseInt(text, 10) || DEFAULT_BUS_INTERVAL, 3), 30);
}

/**
 * 우리 정류장의 첫차·막차 시각으로 버스 구간을 계산한다.
 * 막차를 타면 되면 막차를, 다음 구간 때문에 더 일찍 타야 하면
 * 배차 간격만큼 기다릴 수 있다고 보고 그만큼 일찍 정류장에 가게 한다.
 */
export function busTripAtStop({ first, last, interval, estimated }, section, deadline) {
  if (last + section <= deadline) {
    return { dep: last, arr: last + section, isLast: true, estimated };
  }
  const dep = deadline - section - interval;
  if (dep < first) return null;
  return { dep, arr: deadline, isLast: false, estimated };
}

/** ODsay 노선 정보에서 우리 정류장 위치. 회차 지점을 지난 정류장이면 returning이 true. */
export function busStopPosition(sp, detail) {
  const stops = detail?.station ?? [];
  const idx = stops.findIndex((st) => String(st.stationID) === String(sp.startID));
  if (idx < 0) return { idx, returning: false };
  const stop = stops[idx];
  const turn = Number(detail.turningPointIdx);
  const returning = Number(stop.stationDirection) === 2 ||
    (Number.isFinite(turn) && turn > 0 && Number(stop.idx ?? idx) > turn);
  return { idx, returning };
}

/**
 * 정류장별 시간표가 없는 버스는 노선의 기점 막차 시각에 기점부터 우리 정류장까지
 * 가는 시간을 더해 추정한다. 늦게 잡으면 막차를 놓치므로 버스가 빠르게(밤 기준
 * 시속 25km 이상) 달린다고 보고 짧게 잡고, 여유 시간을 더 뺀다.
 * 회차 지점을 지난 정류장은 막차가 거기까지 오는지 알 수 없어서 추정하지 않는다.
 */
export function estimateBusStop(sp, detail, dayType = 'weekday') {
  const last = parseClock(detail?.busLastTime);
  if (last == null) return { reason: '노선 막차 시각 없음' };
  const { returning } = busStopPosition(sp, detail);
  if (returning) return { reason: '회차 지점 뒤 정류장이라 추정하지 않음' };
  const first = parseClock(detail?.busFirstTime) ?? 0;
  const offset = busOffset(sp, detail);
  const wrapped = wrapStopTimes({ first, last });
  return {
    stop: {
      first: first + offset,
      last: wrapped.last + offset - BUS_SAFETY_MIN,
      interval: busInterval(detail, dayType),
      estimated: true,
    },
  };
}

/** 예전 이름 호환: 추정으로 버스 구간을 계산한다. */
export function busTripFromLane(sp, detail, deadline, dayType = 'weekday') {
  const { stop } = estimateBusStop(sp, detail, dayType);
  return stop ? busTripAtStop(stop, sp.sectionTime ?? 0, deadline) : null;
}

const MIN_BUS_SPEED_M_PER_MIN = 25000 / 60;

/** 기점에서 우리 정류장까지 걸리는 시간(분) 추정. */
export function busOffset(sp, detail) {
  const stops = detail?.station ?? [];
  const idx = stops.findIndex((s) => String(s.stationID) === String(sp.startID));
  if (idx <= 0) return 0;
  const distance = Number(stops[idx].stationDistance);
  if (Number.isFinite(distance) && distance > 0) {
    const legSpeed = sp.distance > 0 && sp.sectionTime > 0 ? sp.distance / sp.sectionTime : 0;
    return distance / Math.max(legSpeed, MIN_BUS_SPEED_M_PER_MIN);
  }
  const perStop = (sp.sectionTime ?? 0) / Math.max(sp.stationCount ?? 1, 1);
  return idx * perStop * BUS_OFFSET_FACTOR;
}

/**
 * 버스 구간의 정류장 첫차·막차를 준비한다 (최대 두 노선).
 * 서울 버스는 서울시 정류소별 막차 시각(정확)을 먼저 쓰고, 없을 때만 ODsay 노선 정보로 추정한다.
 * ODsay는 무료 호출 수가 적어서 서울 시각이 있으면 부르지 않는다.
 */
async function prepareBus(sp, day, data, log) {
  const lanes = (sp.lane ?? []).filter((l) => l.busID != null || l.busLocalBlID).slice(0, 2);
  const digits = (v) => String(v ?? '').replace(/\D/g, '');
  const pathArsId = digits(sp.startArsID ?? sp.passStopList?.stations?.[0]?.arsID);
  const options = await Promise.all(lanes.map(async (lane) => {
    const seoul = lane.busLocalBlID && Number(lane.busCityCode) === 1000 && data.seoulBusTime;
    const tryExact = async (arsId) => {
      const exact = await data.seoulBusTime(arsId, String(lane.busLocalBlID));
      if (!exact) {
        log(`버스 ${lane.busNo}: 서울 정류소(${arsId}) 막차 시각 없음`);
        return null;
      }
      log(`버스 ${lane.busNo}: 서울 정류소(${arsId}) 막차 ${clock(exact.last)} (정확)`);
      return { lane, stop: wrapStopTimes({ ...exact, interval: DEFAULT_BUS_INTERVAL, estimated: false }) };
    };
    if (seoul && pathArsId) {
      const exact = await tryExact(pathArsId);
      if (exact) return exact;
    }
    if (lane.busID == null) return null;
    const detail = await data.busLane(lane.busID);
    if (!detail) {
      log(`버스 ${lane.busNo}: 노선 정보 없음 (조회 한도 또는 오류)`);
      return null;
    }
    if (seoul && !pathArsId) {
      // 길찾기 결과에 정류소 번호가 없으면 노선 정보에서 찾는다.
      const { idx } = busStopPosition(sp, detail);
      const arsId = idx >= 0 ? digits(detail.station[idx].arsID) : '';
      if (arsId && arsId !== '0') {
        const exact = await tryExact(arsId);
        if (exact) return exact;
      }
    }
    const { stop, reason } = estimateBusStop(sp, detail, day.dayType);
    log(stop
      ? `버스 ${lane.busNo}: 기점 막차 ${detail.busLastTime}, 정류장 막차 추정 ${clock(stop.last)}`
      : `버스 ${lane.busNo}: ${reason}`);
    return stop ? { lane, stop } : null;
  }));
  return options.filter(Boolean);
}

function busTripFrom(sp, options, deadline) {
  let best = null;
  for (const { lane, stop } of options ?? []) {
    const trip = busTripAtStop(stop, sp.sectionTime ?? 0, deadline);
    if (trip && (!best || trip.dep > best.dep)) best = { ...trip, busNo: lane.busNo, night: isNightBus(lane) };
  }
  return best;
}

/**
 * 경로 하나의 막차 출발 시각을 계산한다. 탈 수 없으면 null.
 * 반환: { departBy, arriveAt, estimated, legs }
 */
export async function planPath(path, day, data, log = data.log ?? noLog) {
  const subs = path.subPath ?? [];
  if (!subs.length || subs.some((s) => ![1, 2, 3].includes(s.trafficType))) return null;
  const prepared = await Promise.all(subs.map((sp) => {
    if (sp.trafficType === 1) return prepareSubway(sp, day, data, log);
    if (sp.trafficType === 2) return prepareBus(sp, day, data, log);
    return null;
  }));
  const trips = new Array(subs.length);
  let deadline = Infinity;
  for (let i = subs.length - 1; i >= 0; i -= 1) {
    const sp = subs[i];
    if (sp.trafficType === 3) {
      if (Number.isFinite(deadline)) deadline -= sp.sectionTime ?? 0;
      continue;
    }
    const mode = sp.trafficType === 1 ? 'subway' : 'bus';
    const trip = mode === 'subway'
      ? subwayTripFrom(prepared[i], deadline)
      : busTripFrom(sp, prepared[i], deadline);
    if (!trip) return null;
    trips[i] = trip;
    deadline = trip.dep - BOARD_BUFFER[mode];
  }
  if (!Number.isFinite(deadline)) return null;

  const lastTransit = trips.findLastIndex((t) => t);
  let arriveAt = trips[lastTransit].arr;
  for (let i = lastTransit + 1; i < subs.length; i += 1) arriveAt += subs[i].sectionTime ?? 0;

  return {
    departBy: deadline,
    arriveAt,
    estimated: trips.some((t) => t?.estimated),
    night: trips.some((t) => t?.night),
    legs: describeLegs(subs, trips),
  };
}

function stationLabel(name) {
  return String(name ?? '').endsWith('역') ? name : `${name}역`;
}

function describeLegs(subs, trips) {
  const legs = [];
  subs.forEach((sp, i) => {
    if (sp.trafficType === 3) {
      const minutes = sp.sectionTime ?? 0;
      if (minutes <= 0) return;
      const next = subs.slice(i + 1).find((s) => s.trafficType !== 3);
      const prev = subs.slice(0, i).some((s) => s.trafficType !== 3);
      let description;
      if (!next) description = `집까지 걸어서 ${minutes}분`;
      else if (!prev) description = `${next.trafficType === 1 ? stationLabel(next.startName) : `${next.startName} 정류장`}까지 걸어서 ${minutes}분`;
      else description = `갈아타러 걸어서 ${minutes}분`;
      legs.push({ mode: 'walk', description, minutes });
      return;
    }
    const t = trips[i];
    if (sp.trafficType === 1) {
      const line = String(sp.lane?.[0]?.name ?? '지하철').replace(/^수도권\s*/, '');
      legs.push({
        mode: 'subway',
        description: `${line} ${stationLabel(sp.startName)} ${clock(t.dep)} 출발 → ${stationLabel(sp.endName)} ${clock(t.arr)} 도착${t.isLast ? ' (막차)' : ''}`,
        line,
        from: sp.startName,
        to: sp.endName,
        departMin: t.dep,
        arriveMin: t.arr,
        isLast: t.isLast,
        estimated: false,
      });
    } else {
      const bus = `${t.busNo ?? sp.lane?.[0]?.busNo ?? ''}번 ${t.night ? '심야버스' : '버스'}`;
      const note = t.estimated ? ' (추정)' : '';
      const when = t.isLast
        ? `${clock(t.dep)}${t.estimated ? '쯤' : ''} 막차${note}`
        : `${clock(t.dep)}까지 정류장 도착${note}`;
      legs.push({
        mode: 'bus',
        description: `${bus} ${sp.startName} ${when} → ${sp.endName}`,
        line: bus,
        from: sp.startName,
        to: sp.endName,
        departMin: t.dep,
        arriveMin: t.arr,
        isLast: t.isLast,
        estimated: t.estimated,
      });
    }
  });
  return legs;
}

/**
 * 경로 후보 가운데 가장 늦게 출발해도 되는 경로를 고른다.
 * 반환: { status: 'ok', plan } | { status: 'missed' } (오늘 막차가 이미 지남) | { status: 'unknown' }
 */
export async function findLastRoute(paths, day, data) {
  const subwayOnly = paths.filter((p) => p.pathType === 1).slice(0, MAX_SUBWAY_PATHS);
  const busOnly = paths.filter((p) => p.pathType === 2).slice(0, MAX_BUS_PATHS);
  const mixed = paths.filter((p) => p.pathType !== 1 && p.pathType !== 2).slice(0, MAX_MIXED_PATHS);
  const baseLog = data.log ?? noLog;
  let count = 0;
  const run = async (path) => {
    count += 1;
    const id = count;
    const log = (line) => baseLog(`#${id} ${line}`);
    const summary = (path.subPath ?? [])
      .filter((s) => s.trafficType !== 3)
      .map((s) => (s.trafficType === 1 ? s.lane?.[0]?.name : `${s.lane?.[0]?.busNo}번`) ?? `종류${s.trafficType}`)
      .join(' > ');
    log(`경로 [${summary}]`);
    try {
      const plan = await planPath(path, day, data, log);
      log(plan ? `→ ${clock(plan.departBy)}까지 출발${plan.night ? ' (심야버스)' : ''}` : '→ 계산 못 함');
      return plan;
    } catch (e) {
      // 한 경로의 데이터가 없어도 다른 경로는 계속 본다.
      log(`→ 오류: ${e?.message ?? e}`);
      return null;
    }
  };
  // 경로마다 데이터를 한꺼번에 불러와 기다리는 시간을 줄인다.
  const results = await Promise.all([...subwayOnly, ...busOnly].map(run));
  // 버스+지하철 경로는 바깥 API를 많이 불러서, 한도가 남았을 때만 본다.
  const left = data.budgetLeft ? data.budgetLeft() : Infinity;
  if (mixed.length && left >= MIXED_BUDGET_LEFT) results.push(...(await Promise.all(mixed.map(run))));
  else if (mixed.length) baseLog(`버스+지하철 경로 ${mixed.length}개는 호출 한도 때문에 건너뜀`);

  const plans = results.filter(Boolean);
  if (!plans.length) return { status: 'unknown' };
  const upcoming = plans.filter((p) => p.departBy >= day.nowMin).sort((a, b) => b.departBy - a.departBy);
  if (!upcoming.length) return { status: 'missed' };
  // 화면과 알림은 일반 막차 기준으로 하고, 그 뒤에 심야버스가 있으면 따로 알려준다.
  const regular = upcoming.find((p) => !p.night);
  const night = upcoming.find((p) => p.night);
  const plan = regular ?? night;
  const later = regular && night && night.departBy > regular.departBy ? night : null;
  return { status: 'ok', plan, later };
}

/** 앱으로 보낼 JSON. 앱의 LastRoute.fromJson과 맞춘다. */
export function toResponse(plan, day, later = null) {
  const body = {
    departBy: toIso(day, plan.departBy),
    arriveAt: toIso(day, plan.arriveAt),
    estimated: plan.estimated,
    night: Boolean(plan.night),
    serviceDate: day.date,
    dayType: day.dayType,
    legs: legsJson(plan.legs, day),
    sources: ['ODsay', '국토교통부(TAGO)', '서울특별시'],
  };
  if (later) {
    body.nightBus = {
      departBy: toIso(day, later.departBy),
      arriveAt: toIso(day, later.arriveAt),
      buses: later.legs.filter((l) => l.mode === 'bus').map((l) => l.line.replace(/번 (심야버스|버스)$/, '')),
      legs: legsJson(later.legs, day),
    };
  }
  return body;
}

function legsJson(legs, day) {
  return legs.map(({ departMin, arriveMin, ...leg }) => ({
    ...leg,
    ...(departMin != null ? { departAt: toIso(day, departMin) } : {}),
    ...(arriveMin != null ? { arriveAt: toIso(day, arriveMin) } : {}),
  }));
}
