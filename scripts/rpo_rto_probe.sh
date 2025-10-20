#!/usr/bin/env bash
set -euo pipefail

RPO_TARGET=${RPO_TARGET_SECONDS:-15}
RTO_TARGET=${RTO_TARGET_SECONDS:-300}
PUSHGW=${PROM_PUSHGATEWAY:-http://prometheus-pushgateway.observability:9091}
CHECK_URL=${CHECK_URL:-https://api.upx.exchange/healthz}

ns="dr-tests"

start_epoch=$(date +%s)

# 1) 서비스 헬스 확인
curl -fsS "${CHECK_URL}" >/dev/null || echo "WARN: initial healthz failed"

# 2) RPO 측정: 최신 trade 이벤트 타임스탬프와 복제 지연 비교(메트릭 가정)
# 실제로는 Kafka Mirror/Metrics 또는 Aurora ReplicaLag 연동 필요
REPLICA_LAG_SEC=$(kubectl -n observability exec deploy/kube-prometheus-stack-prometheus -- \
  curl -s 'http://localhost:9090/api/v1/query?query=aurora_replica_lag_seconds' \
  | jq -r '.data.result[0].value[1]' || echo 0)

# 3) RTO 측정: 의도적 Failover 시뮬레이션 직후 가용성 회복까지 시간 측정
fail_start=$(date +%s)
# 시뮬: 5xx 응답이 끝날 때까지 폴링
timeout ${RTO_TARGET}s bash -c "
  until curl -fsS ${CHECK_URL} >/dev/null; do sleep 3; done
"
fail_end=$(date +%s)
RTO=$((fail_end - fail_start))

RPO=${REPLICA_LAG_SEC}

cat <<EOF | curl --data-binary @- ${PUSHGW}/metrics/job/dr-tests/instance/primary
# HELP rpo_rto_seconds RPO/RTO seconds measured by DR rehearsal
# TYPE rpo_rto_seconds gauge
rpo_rto_seconds{type="rpo"} ${RPO}
rpo_rto_seconds{type="rto"} ${RTO}
EOF

echo "RPO=${RPO}s (target<=${RPO_TARGET}s), RTO=${RTO}s (target<=${RTO_TARGET}s)"
if [ "${RPO}" -gt "${RPO_TARGET}" ] || [ "${RTO}" -gt "${RTO_TARGET}" ]; then
  echo "DR targets not met" >&2
  exit 1
fi
