import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  scenarios: {
    steady: {
      executor: 'constant-vus',
      vus: 50,
      duration: '5m',
    },
    spike: {
      executor: 'ramping-arrival-rate',
      startRate: 200,
      timeUnit: '1s',
      preAllocatedVUs: 200,
      maxVUs: 400,
      stages: [
        { target: 500, duration: '2m' },
        { target: 1000, duration: '2m' },
        { target: 200, duration: '1m' },
      ],
      startTime: '5m',
    },
  },
  thresholds: {
    'http_req_duration{endpoint:/api/trade}': ['p(95)<50', 'p(99)<120'],
    'http_req_failed{endpoint:/api/trade}': ['rate<0.01'],
  },
};

const BASE = __ENV.TRADING_API_BASE || 'http://trading-api.trading.svc.cluster.local';

export default function () {
  const payload = JSON.stringify({
    user_id: Math.floor(Math.random() * 1000000),
    symbol: 'BTCUSDT',
    side: Math.random() > 0.5 ? 'BUY' : 'SELL',
    qty: Math.random() * 0.01,
    price: 60000 + Math.random() * 1000,
  });
  const res = http.post(`${BASE}/api/trade`, payload, {
    headers: { 'Content-Type': 'application/json' },
    tags: { endpoint: '/api/trade' },
  });
  check(res, { 'status 200/202': (r) => r.status === 200 || r.status === 202 });
  sleep(0.05);
}
