#!/usr/bin/env bash
set -euo pipefail

CFG="${1:-dr/dr-config.yaml}"
yq() { command -v yq >/dev/null 2>&1 && yq "$@" || python - <<'PY' "$@"
import sys, yaml, json
doc = yaml.safe_load(open(sys.argv[1]))
print(eval(sys.argv[2],{}, {'cfg':doc}))
PY
}

PGW_URL=$(yq "$CFG" 'cfg["pushgateway"]["url"]')
PGW_USER=$(yq "$CFG" 'cfg["pushgateway"]["basic_auth"]["username"]')
PGW_PASS=$(yq "$CFG" 'cfg["pushgateway"]["basic_auth"]["password"]')

P_HEALTH=$(yq "$CFG" 'cfg["primary"]["health_url"]')
S_HEALTH=$(yq "$CFG" 'cfg["secondary"]["health_url"]')

TIMEOUT=$(yq "$CFG" 'cfg["timeout_seconds"]')
INTERVAL=$(yq "$CFG" 'cfg["probe_interval_seconds"]')

start_epoch=$(date +%s)

# 1 장애 유도 또는 simulate (여기서는 Primary Health 불응 가정)
echo "simulate primary outage (external trigger or manual)"
sleep 2

# 2 Failover 시작
failover_start=$(date +%s)

# 3 Secondary 가용 확인 loof
echo "waiting secondary ready: ${S_HEALTH}"
end=0
for ((i=0;i<${TIMEOUT};i+=${INTERVAL})); do
  if curl -sk --max-time 2 "${S_HEALTH}" >/dev/null; then
    end=$(date +%s)
    break
  fi
  sleep "${INTERVAL}"
done

if [ "$end" -eq 0 ]; then
  echo "timeout waiting secondary"
  end=$(date +%s)
fi

rto=$(( end - failover_start ))

# 4 RPO 측정(simplify  DB/CDC Lag 등 외부 메트릭을 Prometheus에서 조회 가능하면 여기에 추가)
rpo=0

job="dr_test"
metrics=$(cat <<EOF
# TYPE rpo_rto_seconds gauge
rpo_rto_seconds ${rto}
# TYPE rpo_seconds gauge
rpo_seconds ${rpo}
EOF
)

echo "RTO=${rto}s RPO=${rpo}s"
curl -sf --user "${PGW_USER}:${PGW_PASS}" --data-binary "${metrics}" "${PGW_URL}/metrics/job/${job}"

echo "끝'ㅜㅜㅜ"
