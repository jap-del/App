// 막차 알림 API 서버.
//
// 앱 대신 공공 교통 API를 불러주는 역할만 한다. 인증키는 Cloudflare
// 비밀 값(env)으로만 보관하고, 이용자의 위치는 저장하거나 로그에 남기지 않는다.

import {
  TAGO_DAY_CODE,
  findLastRoute,
  normalizeStationName,
  parseSeoulBusTime,
  parseTagoSchedule,
  pickStation,
  serviceDay,
  tagoItems,
  toResponse,
} from './last-route.js';

const TAGO_BASE = 'https://apis.data.go.kr/1613000';
const SEOUL_BASE = 'http://swopenapi.seoul.go.kr/api/subway';
const ODSAY_BASE = 'https://api.odsay.com/v1/api';
const SEOUL_BUS_BASE = 'http://ws.bus.go.kr/api/rest';

/**
 * 앱이 부를 수 있는 ODsay API와 캐시 시간(초).
 * 좌표가 들어가는 길찾기는 캐시하지 않는다 (이용자 위치를 남기지 않기 위해).
 */
export const ODSAY_APIS = {
  searchPubTransPathT: 0, // 대중교통 길찾기
  searchSubwaySchedule: 6 * 60 * 60, // 지하철역 전체 시간표
  subwayTimeTable: 6 * 60 * 60, // 지하철역 전체 시간표(구)
  subwayStationInfo: 6 * 60 * 60, // 지하철역 세부 정보
  busLaneDetail: 6 * 60 * 60, // 버스 노선 상세 (첫차, 막차)
  busStationInfo: 60 * 60, // 버스 정류장 세부 정보
};

/** 앱이 부를 수 있는 TAGO 서비스 목록. 이 밖의 요청은 막는다. */
export const TAGO_SERVICES = new Set([
  'SubwayInfo', // 지하철역 검색(GetKwrdFndSubwaySttnList), 역별 시간표(GetSubwaySttnAcctoSchdulList)
  'ArvlInfoInqireService', // 버스 도착 예정 정보
  'BusLcInfoInqireService', // 버스 위치 정보
  'BusSttnInfoInqireService', // 버스 정류소 정보
  'BusRouteInfoInqireService', // 버스 노선 정보 (첫차, 막차)
]);

/** 데이터가 자주 바뀌지 않는 서비스는 캐시해 호출 횟수를 아낀다 (초). */
const CACHE_SECONDS = {
  SubwayInfo: 6 * 60 * 60,
  BusRouteInfoInqireService: 6 * 60 * 60,
  BusSttnInfoInqireService: 60 * 60,
};

export default {
  async fetch(request, env) {
    if (request.method !== 'GET') {
      return json({ error: 'GET 요청만 받습니다.' }, 405);
    }
    const url = new URL(request.url);
    const parts = url.pathname.split('/').filter(Boolean);
    try {
      if (parts.length === 1 && parts[0] === 'health') {
        return json({ ok: true });
      }
      if (parts[0] === 'tago' && parts.length === 3) {
        return await tago(parts[1], parts[2], url.searchParams, env);
      }
      if (parts[0] === 'seoul' && parts.length === 2) {
        return await seoul(parts[1], url.searchParams, env);
      }
      if (parts[0] === 'odsay' && parts.length === 2) {
        return await odsay(parts[1], url.searchParams, env, url.origin);
      }
      if (parts.length === 1 && parts[0] === 'last-route') {
        return await lastRoute(url.searchParams, env, url.origin);
      }
      return json({ error: '없는 주소입니다.' }, 404);
    } catch (e) {
      // 오류 메시지에 인증키가 섞이지 않도록 내용은 돌려주지 않는다.
      return json({ error: '교통 정보를 가져오지 못했습니다.' }, 502);
    }
  },
};

/**
 * 공공데이터포털 TAGO API를 불러 응답을 그대로 돌려준다.
 * 예: /tago/SubwayInfo/GetKwrdFndSubwaySttnList?subwayStationName=서울역
 * 지하철은 새 주소(SubwayInfo, 대문자 Get), 버스는 기존 주소(...InqireService, 소문자 get)를 쓴다.
 */
async function tago(service, operation, params, env) {
  if (!TAGO_SERVICES.has(service) || !/^[Gg]et[A-Za-z]+$/.test(operation)) {
    return json({ error: '지원하지 않는 서비스입니다.' }, 404);
  }
  if (!env.DATA_GO_KR_KEY) {
    return json({ error: '서버에 공공데이터포털 키가 없습니다.' }, 500);
  }
  const upstream = new URL(`${TAGO_BASE}/${service}/${operation}`);
  for (const [k, v] of params) {
    if (k !== 'serviceKey') upstream.searchParams.set(k, v);
  }
  upstream.searchParams.set('_type', 'json');
  // 공공데이터포털의 "일반 인증키(Decoding)"를 넣는다. URL 인코딩은 여기서 한다.
  upstream.searchParams.set('serviceKey', env.DATA_GO_KR_KEY);
  return forward(upstream, CACHE_SECONDS[service] ?? 0);
}

/**
 * 서울 열린데이터광장 실시간 지하철 API.
 * /seoul/arrivals?station=강남  → 역별 실시간 도착정보
 * /seoul/positions?line=2호선   → 노선별 실시간 열차 위치
 */
async function seoul(kind, params, env) {
  const operations = {
    arrivals: ['realtimeStationArrival', params.get('station')],
    positions: ['realtimePosition', params.get('line')],
  };
  const op = operations[kind];
  if (!op) return json({ error: '없는 주소입니다.' }, 404);
  const [operation, name] = op;
  if (!name) return json({ error: '역 이름이나 노선 이름이 필요합니다.' }, 400);
  if (!env.SEOUL_SUBWAY_KEY) {
    return json({ error: '서버에 서울 실시간 지하철 키가 없습니다.' }, 500);
  }
  const key = encodeURIComponent(env.SEOUL_SUBWAY_KEY);
  const upstream = new URL(
    `${SEOUL_BASE}/${key}/json/${operation}/0/100/${encodeURIComponent(name)}`,
  );
  return forward(upstream, 0);
}

/**
 * ODsay API. 키는 ODsay에 이 서버 주소(URI)로 등록하고, 요청에 서버 주소를
 * Referer로 붙인다. 예: /odsay/searchPubTransPathT?SX=126.97&SY=37.55&EX=127.02&EY=37.49
 */
async function odsay(api, params, env, origin) {
  if (!Object.hasOwn(ODSAY_APIS, api)) {
    return json({ error: '지원하지 않는 서비스입니다.' }, 404);
  }
  if (!env.ODSAY_KEY) {
    return json({ error: '서버에 ODsay 키가 없습니다.' }, 500);
  }
  const upstream = new URL(`${ODSAY_BASE}/${api}`);
  for (const [k, v] of params) {
    if (k !== 'apiKey') upstream.searchParams.set(k, v);
  }
  upstream.searchParams.set('apiKey', env.ODSAY_KEY);
  return forward(upstream, ODSAY_APIS[api], { referer: `${origin}/` });
}

/**
 * 집까지 가는 오늘 막차. 앱의 BackendTransitService가 부른다.
 * /last-route?fromLat=37.55&fromLng=126.97&toLat=37.49&toLng=127.02
 * 확인용으로 at=2026-11-19T23:00:00+09:00 처럼 기준 시각을 줄 수 있다.
 * 위치는 계산에만 쓰고 저장하거나 캐시하지 않는다.
 */
async function lastRoute(params, env, origin) {
  if (params.get('debug') === '1') return lastRouteDebug(params, env, origin);
  return lastRouteResponse(params, env, origin);
}

/**
 * 개발용: 계산 과정을 함께 보여주고 항상 200으로 답한다 (확인 도구가 오류 응답 본문을 못 읽어서).
 * 좌표와 키는 기록에 넣지 않는다.
 */
async function lastRouteDebug(params, env, origin) {
  const trace = [];
  let res;
  try {
    res = await lastRouteResponse(params, env, origin, (line) => trace.push(line));
  } catch (e) {
    return json({ status: 500, error: String(e?.message ?? e), trace });
  }
  return json({ status: res.status, body: await res.json(), trace });
}

async function lastRouteResponse(params, env, origin, log) {
  const coords = ['fromLat', 'fromLng', 'toLat', 'toLng'].map((k) => Number(params.get(k)));
  const [fromLat, fromLng, toLat, toLng] = coords;
  if (coords.some((n) => !Number.isFinite(n)) || !inKorea(fromLat, fromLng) || !inKorea(toLat, toLng)) {
    return json({ error: '출발지와 집 좌표가 필요합니다.' }, 400);
  }
  if (!env.ODSAY_KEY || !env.DATA_GO_KR_KEY) {
    return json({ error: '서버에 교통 API 키가 없습니다.' }, 500);
  }
  const now = params.has('at') ? new Date(params.get('at')) : new Date();
  if (Number.isNaN(now.getTime())) return json({ error: '시각 형식이 잘못됐습니다.' }, 400);

  const day = serviceDay(now);
  const data = createData(env, origin);
  if (log) data.log = log;
  log?.(`운행일 ${day.date} ${day.dayType}, 지금 ${Math.floor(day.nowMin / 60)}시 ${Math.floor(day.nowMin % 60)}분`);
  let paths;
  try {
    const result = await data.odsay('searchPubTransPathT', {
      SX: fromLng, SY: fromLat, EX: toLng, EY: toLat,
    });
    paths = result.path ?? [];
    log?.(`길찾기 경로 ${paths.length}개 (지하철 ${paths.filter((p) => p.pathType === 1).length}, 버스 ${paths.filter((p) => p.pathType === 2).length}, 버스+지하철 ${paths.filter((p) => p.pathType === 3).length})`);
  } catch (e) {
    if (e.code === '-98') {
      return json({ error: '집이 아주 가까워요. 걸어서 갈 수 있어요.', reason: 'too-close' }, 404);
    }
    if (e.code === '-99') {
      return json({ error: '집까지 가는 대중교통 경로가 없어요.', reason: 'no-route' }, 404);
    }
    throw e;
  }
  const found = await findLastRoute(paths, day, data);
  log?.(`바깥 API 호출 ${data.subrequests()}번`);
  if (found.status === 'ok') return json(toResponse(found.plan, day, found.later, found.kinds));
  if (found.status === 'missed') {
    return json({ error: '오늘 집에 가는 막차가 이미 끊겼어요.', reason: 'missed' }, 404);
  }
  return json({ error: '이 경로는 막차 시간을 계산하지 못했어요.', reason: 'unknown' }, 503);
}

function inKorea(lat, lng) {
  return lat >= 33 && lat <= 39 && lng >= 124 && lng <= 132;
}

/** 한 요청에서 바깥 API를 부를 수 있는 횟수. Cloudflare 무료 요금제 한도(50) 안에서 쓴다. */
const SUBREQUEST_BUDGET = 45;
/** 한 요청에서 ODsay 버스 노선 정보를 부르는 횟수. ODsay 무료 한도가 하루 30건이라 아낀다. */
const BUS_LOOKUP_BUDGET = 3;

/** 요청 사이에 재사용하는 메모리 캐시 (Worker가 살아 있는 동안만 유지). 위치는 넣지 않는다. */
const memory = new Map();
const MEMORY_LIMIT = 500;

function cached(key, ttlSeconds, load) {
  const hit = memory.get(key);
  if (hit && hit.expires > Date.now()) return hit.value;
  const value = load();
  memory.set(key, { value, expires: Date.now() + ttlSeconds * 1000 });
  if (memory.size > MEMORY_LIMIT) memory.delete(memory.keys().next().value);
  Promise.resolve(value).catch(() => memory.delete(key));
  return value;
}

export function clearMemoryCache() {
  memory.clear();
}

class UpstreamError extends Error {
  constructor(message, code) {
    super(message);
    this.code = code;
  }
}

/** 막차 계산에 필요한 데이터를 불러오는 함수 묶음. */
function createData(env, origin) {
  let subrequests = 0;
  let busLookups = 0;

  async function getJson(upstream, cacheSeconds, headers = {}) {
    if (subrequests >= SUBREQUEST_BUDGET) throw new UpstreamError('budget', 'budget');
    subrequests += 1;
    const init = { headers };
    if (cacheSeconds > 0) init.cf = { cacheTtl: cacheSeconds, cacheEverything: true };
    const res = await fetch(upstream.toString(), init);
    const body = await res.text();
    if (!res.ok) throw new UpstreamError(`status ${res.status}`, String(res.status));
    if (body.trimStart().startsWith('<')) throw new UpstreamError(xmlReason(body), 'xml');
    const data = JSON.parse(body);
    const err = odsayError(data);
    if (err) throw new UpstreamError(err.message, err.code);
    return data;
  }

  function tago(operation, query, cacheSeconds) {
    const upstream = new URL(`${TAGO_BASE}/SubwayInfo/${operation}`);
    for (const [k, v] of Object.entries(query)) upstream.searchParams.set(k, String(v));
    upstream.searchParams.set('_type', 'json');
    upstream.searchParams.set('serviceKey', env.DATA_GO_KR_KEY);
    return getJson(upstream, cacheSeconds);
  }

  return {
    subrequests: () => subrequests,
    budgetLeft: () => SUBREQUEST_BUDGET - subrequests,

    async odsay(api, query) {
      const upstream = new URL(`${ODSAY_BASE}/${api}`);
      for (const [k, v] of Object.entries(query)) upstream.searchParams.set(k, String(v));
      upstream.searchParams.set('apiKey', env.ODSAY_KEY);
      const data = await getJson(upstream, ODSAY_APIS[api] ?? 0, { referer: `${origin}/` });
      return data.result ?? {};
    },

    async findSubwayStation(name, lane) {
      const keyword = normalizeStationName(name);
      if (!keyword) return null;
      const items = await cached(`station:${keyword}`, 24 * 60 * 60, async () =>
        tagoItems(await tago('GetKwrdFndSubwaySttnList', { subwayStationName: keyword, numOfRows: 100 }, 24 * 60 * 60)));
      return pickStation(items, name, lane);
    },

    subwaySchedule(stationId, dayType, dir) {
      const ttl = 6 * 60 * 60;
      return cached(`schedule:${stationId}:${dayType}:${dir}`, ttl, async () =>
        parseTagoSchedule(tagoItems(await tago('GetSubwaySttnAcctoSchdulList', {
          subwayStationId: stationId,
          dailyTypeCode: TAGO_DAY_CODE[dayType],
          upDownTypeCode: dir,
          numOfRows: 500,
          pageNo: 1,
        }, ttl))));
    },

    /**
     * 서울 버스의 우리 정류장 첫차·막차 (공공데이터포털 "서울특별시_정류소정보조회 서비스").
     * 활용신청 전이거나 서울 노선이 아니면 null. 오류는 캐시에 오래 남기지 않는다.
     */
    async seoulBusTime(arsId, routeId) {
      const key = `seoulbus:${arsId}:${routeId}`;
      const hit = memory.get(key);
      if (hit && hit.expires > Date.now()) return hit.value;
      let value = null;
      try {
        const upstream = new URL(`${SEOUL_BUS_BASE}/stationinfo/getBustimeByStation`);
        upstream.searchParams.set('arsId', arsId);
        upstream.searchParams.set('busRouteId', routeId);
        upstream.searchParams.set('resultType', 'json');
        upstream.searchParams.set('serviceKey', env.DATA_GO_KR_KEY);
        const data = await getJson(upstream, 0);
        // JSON 응답은 XML과 달리 ServiceResult 없이 msgHeader, msgBody가 바로 올 수 있다.
        const result = data?.ServiceResult ?? data;
        const code = String(result?.msgHeader?.headerCd ?? '');
        const list = result?.msgBody?.itemList;
        const items = Array.isArray(list) ? list : list ? [list] : [];
        const item = items.find((i) => String(i.busRouteId) === routeId) ?? (items.length === 1 ? items[0] : null);
        const last = parseSeoulBusTime(item?.lastBusTm);
        if (last != null) {
          value = { first: parseSeoulBusTime(item.firstBusTm) ?? 0, last };
        } else {
          // 원인을 찾을 수 있게 응답 모양만 남긴다 (키나 위치는 들어 있지 않다).
          this.log?.(`서울 버스 정류소 응답: 코드 ${code || '없음'} ${result?.msgHeader?.headerMsg ?? ''}, 항목 ${items.length}개` +
            (item ? `, 막차 값 "${item.lastBusTm}"` : '') +
            (!result?.msgHeader ? `, 최상위 키 ${Object.keys(data ?? {}).join('/')}` : ''));
        }
      } catch (e) {
        this.log?.(`서울 버스 정류소 시각 오류: ${e?.message ?? e}`);
      }
      const ttl = value ? 6 * 60 * 60 : 10 * 60;
      memory.set(key, { value, expires: Date.now() + ttl * 1000 });
      return value;
    },

    busLane(busID) {
      const key = `bus:${busID}`;
      const hit = memory.get(key);
      if (hit && hit.expires > Date.now()) return hit.value;
      if (busLookups >= BUS_LOOKUP_BUDGET) return null;
      busLookups += 1;
      return cached(key, 24 * 60 * 60, () => this.odsay('busLaneDetail', { busID }));
    },
  };
}

/** ODsay 오류 객체({error: {...}} 또는 {error: [{...}]})에서 코드와 메시지를 꺼낸다. */
function odsayError(data) {
  if (!data || typeof data !== 'object' || !data.error) return null;
  const err = Array.isArray(data.error) ? data.error[0] : data.error;
  if (!err) return null;
  return { code: String(err.code ?? ''), message: String(err.message ?? err.msg ?? '') };
}

async function forward(upstream, cacheSeconds, headers = {}) {
  const init = { headers };
  if (cacheSeconds > 0) init.cf = { cacheTtl: cacheSeconds, cacheEverything: true };
  const res = await fetch(upstream.toString(), init);
  const body = await res.text();
  if (!res.ok) {
    return json({ error: '교통 정보 서버가 응답하지 않습니다.', status: res.status }, 502);
  }
  // ODsay는 오류도 200으로 돌려준다. 오류 내용에 키가 들어가지 않게 원인만 남긴다.
  const odsayError = odsayReason(body);
  if (odsayError) {
    return json({ error: '길찾기 서버가 오류를 돌려줬습니다.', detail: odsayError }, 502);
  }
  // 공공데이터포털은 키 오류일 때도 200으로 XML을 돌려준다.
  if (body.trimStart().startsWith('<')) {
    return json({ error: '교통 정보 서버가 오류를 돌려줬습니다.', detail: xmlReason(body) }, 502);
  }
  return new Response(body, {
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'cache-control': cacheSeconds > 0 ? `public, max-age=${cacheSeconds}` : 'no-store',
    },
  });
}

/** ODsay 오류 응답이면 코드와 메시지를, 아니면 null을 돌려준다. */
export function odsayReason(body) {
  if (!body.includes('"error"')) return null;
  try {
    const data = JSON.parse(body);
    const err = Array.isArray(data.error) ? data.error[0] : data.error;
    if (!err) return null;
    return `${err.code ?? ''} ${err.message ?? err.msg ?? ''}`.trim() || 'unknown';
  } catch {
    return null;
  }
}

/** XML 오류 응답에서 원인 문구만 꺼낸다 (예: SERVICE_KEY_IS_NOT_REGISTERED_ERROR). */
export function xmlReason(xml) {
  const m = xml.match(/<returnAuthMsg>([^<]*)<\/returnAuthMsg>/) ??
    xml.match(/<resultMsg>([^<]*)<\/resultMsg>/) ??
    xml.match(/<MESSAGE>([^<]*)<\/MESSAGE>/);
  return m ? m[1].trim() : 'unknown';
}

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' },
  });
}
