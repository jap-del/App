// 막차 알림 API 서버.
//
// 앱 대신 공공 교통 API를 불러주는 역할만 한다. 인증키는 Cloudflare
// 비밀 값(env)으로만 보관하고, 이용자의 위치는 저장하거나 로그에 남기지 않는다.

const TAGO_BASE = 'https://apis.data.go.kr/1613000';
const SEOUL_BASE = 'http://swopenapi.seoul.go.kr/api/subway';

/** 앱이 부를 수 있는 TAGO 서비스 목록. 이 밖의 요청은 막는다. */
export const TAGO_SERVICES = new Set([
  'SubwayInfoService', // 지하철역 검색, 역별 시간표
  'ArvlInfoInqireService', // 버스 도착 예정 정보
  'BusLcInfoInqireService', // 버스 위치 정보
  'BusSttnInfoInqireService', // 버스 정류소 정보
  'BusRouteInfoInqireService', // 버스 노선 정보 (첫차, 막차)
]);

/** 데이터가 자주 바뀌지 않는 서비스는 캐시해 호출 횟수를 아낀다 (초). */
const CACHE_SECONDS = {
  SubwayInfoService: 6 * 60 * 60,
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
      return json({ error: '없는 주소입니다.' }, 404);
    } catch (e) {
      // 오류 메시지에 인증키가 섞이지 않도록 내용은 돌려주지 않는다.
      return json({ error: '교통 정보를 가져오지 못했습니다.' }, 502);
    }
  },
};

/**
 * 공공데이터포털 TAGO API를 불러 응답을 그대로 돌려준다.
 * 예: /tago/SubwayInfoService/getKwrdFndSubwaySttnList?subwayStationName=서울역
 */
async function tago(service, operation, params, env) {
  if (!TAGO_SERVICES.has(service) || !/^get[A-Za-z]+$/.test(operation)) {
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

async function forward(upstream, cacheSeconds) {
  const init = cacheSeconds > 0
    ? { cf: { cacheTtl: cacheSeconds, cacheEverything: true } }
    : {};
  const res = await fetch(upstream.toString(), init);
  const body = await res.text();
  if (!res.ok) {
    return json({ error: '교통 정보 서버가 응답하지 않습니다.', status: res.status }, 502);
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
