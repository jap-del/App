// Cloudflare가 실행하는 진입점. 테스트는 Node에서 돌아서 cloudflare:workers가 없는 index.js를 직접 쓴다.
import { WorkerEntrypoint } from 'cloudflare:workers';
import worker, { planKindPaths } from './index.js';

export default worker;

/**
 * 막차 계산을 종류(지하철, 버스, 지하철+버스)별로 나눠 맡는 내부 진입점.
 * 무료 요금제는 요청 하나에서 바깥 API를 50번까지만 부를 수 있어서, 종류마다 따로 불러 한도를 따로 받는다.
 * 인터넷에서는 부를 수 없고 wrangler.toml의 PLANNER 연결로 같은 서버만 부른다.
 */
export class Planner extends WorkerEntrypoint {
  plan(input) {
    return planKindPaths(input, this.env);
  }
}
