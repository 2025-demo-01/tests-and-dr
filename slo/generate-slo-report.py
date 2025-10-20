#!/usr/bin/env python3
import os, json, time
import requests

PROM_URL = os.getenv("PROM_URL", "http://exchange-prom.observability.svc.cluster.local:9090")
PROM_TOKEN = os.getenv("PROM_TOKEN", "sophielog")

def q(expr):
    r = requests.get(f"{PROM_URL}/api/v1/query", params={"query": expr}, headers={"Authorization": f"Bearer {PROM_TOKEN}"}, timeout=10)
    r.raise_for_status()
    data = r.json()["data"]["result"]
    return float(data[0]["value"][1]) if data else 0.0

rows = []
rows.append(("p95_latency_ms", q('histogram_quantile(0.95, sum by (le) (rate(exchange_trading_api_latency_ms_bucket[5m])))')))
rows.append(("p99_latency_ms", q('histogram_quantile(0.99, sum by (le) (rate(exchange_trading_api_latency_ms_bucket[5m])))')))
rows.append(("wallet_queue_p95_s", q('histogram_quantile(0.95, sum by (le) (rate(wallet_withdraw_queue_time_seconds_bucket[10m])))')))
rows.append(("error_budget_burn_5m", q('(sum(rate(http_requests_total{status!~"2.."}[5m])) / sum(rate(http_requests_total[5m]))) / (1-0.9995)')))

stamp = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
report = {"timestamp": stamp, "metrics": {k: v for k, v in rows}}
print(json.dumps(report, indent=2))
with open("slo-report.json", "w") as f:
    json.dump(report, f, indent=2)
