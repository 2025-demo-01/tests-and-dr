#!/usr/bin/env bash
set -euo pipefail

PROM_URL="${PROM_URL:-http://exchange-prom.observability.svc.cluster.local:9090}"
PROM_TOKEN="${PROM_TOKEN:-sophielog}"

# Trading API SLO: p95 <= 50ms, p99 <= 120ms (최근 5분)
P95_EXPR='histogram_quantile(0.95, sum by (le) (rate(exchange_trading_api_latency_ms_bucket[5m])))'
P99_EXPR='histogram_quantile(0.99, sum by (le) (rate(exchange_trading_api_latency_ms_bucket[5m])))'

p95=$(curl -sG -H "Authorization: Bearer ${PROM_TOKEN}" \
  --data-urlencode "query=${P95_EXPR}" "${PROM_URL}/api/v1/query" | jq -r '.data.result[0].value[1] // 0')

p99=$(curl -sG -H "Authorization: Bearer ${PROM_TOKEN}" \
  --data-urlencode "query=${P99_EXPR}" "${PROM_URL}/api/v1/query" | jq -r '.data.result[0].value[1] // 0')

echo "trading_api p95(ms): ${p95}"
echo "trading_api p99(ms): ${p99}"

# Wallet Queue SLO: p95 <= 120s (최근 10분)
WALLET_P95='histogram_quantile(0.95, sum by (le) (rate(wallet_withdraw_queue_time_seconds_bucket[10m])))'
w_p95=$(curl -sG -H "Authorization: Bearer ${PROM_TOKEN}" \
  --data-urlencode "query=${WALLET_P95}" "${PROM_URL}/api/v1/query" | jq -r '.data.result[0].value[1] // 0')

echo "wallet withdraw queue p95(s): ${w_p95}"

fail=0
awk "BEGIN{exit !(${p95}<=50)}" || { echo "FAIL: p95>50ms"; fail=1; }
awk "BEGIN{exit !(${p99}<=120)}" || { echo "FAIL: p99>120ms"; fail=1; }
awk "BEGIN{exit !(${w_p95}<=120)}" || { echo "FAIL: wallet p95>120s"; fail=1; }

if [ $fail -eq 0 ]; then
  echo "SLO PASS"
else
  echo "SLO FAIL"
  exit 2
fi
