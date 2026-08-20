// k6 load-test scaffold for the FinPay gateway (FP-28).
// Run:  k6 run --vus 50 --duration 2m loadtest/gateway.js
// Assumes the gateway is reachable (e.g. via port-forward on :8080).
import http from 'k6/http';
import { check, sleep } from 'k6';

const BASE = __ENV.GATEWAY_URL || 'http://localhost:8080';

export const options = {
  scenarios: {
    baseline: { executor: 'constant-vus', vus: 50, duration: '2m' },
    spike: { executor: 'ramping-vus', startVUs: 0, stages: [
      { duration: '30s', target: 200 },
      { duration: '1m', target: 200 },
      { duration: '30s', target: 0 },
    ] },
  },
  thresholds: {
    http_req_failed: ['rate<0.05'],
    http_req_duration: ['p(95)<300'],
  },
};

export default function () {
  // Unauthenticated health is expected 200; protected routes expected 401.
  const health = http.get(`${BASE}/actuator/health`);
  check(health, { 'health 2xx/3xx': (r) => r.status < 400 });

  const protectedCall = http.get(`${BASE}/v1/accounts`);
  check(protectedCall, { 'protected rejected': (r) => r.status === 401 });

  sleep(1);
}
