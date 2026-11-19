import assert from 'node:assert/strict';
import { afterEach, describe, it } from 'node:test';
import worker, { xmlReason } from '../src/index.js';

const realFetch = globalThis.fetch;

/** 업스트림 호출을 가짜로 바꾸고, 불린 주소를 기록한다. */
function stubFetch(impl) {
  const calls = [];
  globalThis.fetch = async (url, init) => {
    calls.push(String(url));
    return impl(url, init);
  };
  return calls;
}

const env = { DATA_GO_KR_KEY: 'test+key/==', SEOUL_SUBWAY_KEY: 'seoulkey' };

function call(path, e = env) {
  return worker.fetch(new Request(`https://api.example.com${path}`), e);
}

function mockUpstream(body, status = 200) {
  return stubFetch(async () => new Response(body, { status }));
}

afterEach(() => {
  globalThis.fetch = realFetch;
});

describe('TAGO 프록시', () => {
  it('인증키와 JSON 형식을 붙여 공공데이터포털을 부른다', async () => {
    const upstream = mockUpstream('{"response":{"body":{}}}');
    const res = await call('/tago/SubwayInfo/GetKwrdFndSubwaySttnList?subwayStationName=서울역');

    assert.equal(res.status, 200);
    const called = new URL(upstream[0]);
    assert.equal(called.origin + called.pathname, 'https://apis.data.go.kr/1613000/SubwayInfo/GetKwrdFndSubwaySttnList');
    assert.equal(called.searchParams.get('serviceKey'), 'test+key/==');
    assert.equal(called.searchParams.get('_type'), 'json');
    assert.equal(called.searchParams.get('subwayStationName'), '서울역');
  });

  it('앱이 보낸 serviceKey는 무시하고 서버의 키를 쓴다', async () => {
    const upstream = mockUpstream('{}');
    await call('/tago/SubwayInfo/GetKwrdFndSubwaySttnList?serviceKey=hacked');
    const called = new URL(upstream[0]);
    assert.deepEqual(called.searchParams.getAll('serviceKey'), ['test+key/==']);
  });

  it('목록에 없는 서비스는 막는다', async () => {
    const upstream = mockUpstream('{}');
    const res = await call('/tago/SomeOtherService/getList');
    assert.equal(res.status, 404);
    assert.equal(upstream.length, 0);
  });

  it('키 오류 XML은 원인과 함께 502로 바꾼다', async () => {
    mockUpstream(
      '<OpenAPI_ServiceResponse><cmmMsgHeader><returnAuthMsg>SERVICE_KEY_IS_NOT_REGISTERED_ERROR</returnAuthMsg></cmmMsgHeader></OpenAPI_ServiceResponse>',
    );
    const res = await call('/tago/SubwayInfo/GetKwrdFndSubwaySttnList');
    assert.equal(res.status, 502);
    assert.equal((await res.json()).detail, 'SERVICE_KEY_IS_NOT_REGISTERED_ERROR');
  });

  it('키가 설정되지 않았으면 알려준다', async () => {
    mockUpstream('{}');
    const res = await call('/tago/SubwayInfo/GetKwrdFndSubwaySttnList', {});
    assert.equal(res.status, 500);
  });
});

describe('서울 실시간 지하철 프록시', () => {
  it('역 이름으로 실시간 도착정보를 부른다', async () => {
    const upstream = mockUpstream('{"realtimeArrivalList":[]}');
    const res = await call('/seoul/arrivals?station=강남');
    assert.equal(res.status, 200);
    assert.equal(upstream[0], 'http://swopenapi.seoul.go.kr/api/subway/seoulkey/json/realtimeStationArrival/0/100/%EA%B0%95%EB%82%A8');
  });

  it('노선 이름으로 열차 위치를 부른다', async () => {
    const upstream = mockUpstream('{"realtimePositionList":[]}');
    await call('/seoul/positions?line=2호선');
    assert.ok(upstream[0].includes('/json/realtimePosition/0/100/2%ED%98%B8%EC%84%A0'));
  });

  it('역 이름이 없으면 400', async () => {
    mockUpstream('{}');
    assert.equal((await call('/seoul/arrivals')).status, 400);
  });
});

describe('기타', () => {
  it('상태 확인 주소가 있다', async () => {
    assert.deepEqual(await (await call('/health')).json(), { ok: true });
  });

  it('업스트림 오류 내용에 키를 노출하지 않는다', async () => {
    stubFetch(async (u) => {
      throw new Error(`failed ${u}`);
    });
    const res = await call('/seoul/arrivals?station=강남');
    assert.equal(res.status, 502);
    assert.ok(!(await res.text()).includes('seoulkey'));
  });

  it('XML 오류 문구를 꺼낸다', () => {
    assert.equal(xmlReason('<x><resultMsg>LIMITED NUMBER OF SERVICE REQUESTS</resultMsg></x>'), 'LIMITED NUMBER OF SERVICE REQUESTS');
  });
});
