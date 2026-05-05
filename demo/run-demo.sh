#!/bin/bash
# ═══════════════════════════════════════════════════════════
#  CANARY DEMO SCRIPT
#  Chạy: bash demo/run-demo.sh [STEP]
#
#  STEPS:
#    setup       — build images + apply manifests
#    watch       — live watch traffic split (đẹp để present)
#    stress      — gửi nhiều requests, tính error rate
#    promote     — promote canary thành stable (0 downtime)
#    rollback    — xóa canary, giữ stable
#    cleanup     — dọn dẹp toàn bộ
# ═══════════════════════════════════════════════════════════

set -euo pipefail

NS="canary-demo"
SVC_PORT="30080"
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || echo "localhost")
BASE_URL="http://${NODE_IP}:${SVC_PORT}"

# ─── Colors ───────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
BLUE='\033[0;34m'; MAGENTA='\033[0;35m'

banner() {
  echo ""
  echo -e "${CYAN}╔══════════════════════════════════════════════════════╗${RESET}"
  echo -e "${CYAN}║${BOLD}  🚀 Canary Deploy Demo — my-service                  ${CYAN}║${RESET}"
  echo -e "${CYAN}╚══════════════════════════════════════════════════════╝${RESET}"
  echo ""
}

step() { echo -e "\n${BOLD}${BLUE}▶ $1${RESET}"; }
ok()   { echo -e "  ${GREEN}✅ $1${RESET}"; }
warn() { echo -e "  ${YELLOW}⚠️  $1${RESET}"; }
err()  { echo -e "  ${RED}❌ $1${RESET}"; }
info() { echo -e "  ${CYAN}ℹ  $1${RESET}"; }

# ════════════════════════════════════════════════════════════
# STEP: setup
# ════════════════════════════════════════════════════════════
cmd_setup() {
  banner
  step "1. Build Docker image — Stable v1.0.1"
  docker build -f Dockerfile \
    --build-arg APP_VERSION=v1.0.1-stable \
    -t louisbui/dev:v1.0.1-stable .
  ok "Built louisbui/dev:v1.0.1-stable"

  step "2. Build Docker image — Canary v1.0.2 (có bug 40% error rate)"
  docker build -f demo/Dockerfile.v2-buggy \
    -t louisbui/dev:v1.0.2-canary .
  ok "Built louisbui/dev:v1.0.2-canary"

  step "3. Apply Kubernetes manifests"
  kubectl apply -f demo/k8s-canary-demo.yaml
  ok "Applied k8s-canary-demo.yaml"

  step "4. Patch image tags cho đúng"
  kubectl set image deployment/my-service-stable \
    my-service=louisbui/dev:v1.0.1-stable \
    -n ${NS}
  kubectl set image deployment/my-service-canary \
    my-service=louisbui/dev:v1.0.2-canary \
    -n ${NS}

  step "5. Chờ pods ready..."
  kubectl rollout status deployment/my-service-stable -n ${NS} --timeout=120s
  kubectl rollout status deployment/my-service-canary -n ${NS} --timeout=120s

  echo ""
  echo -e "${GREEN}${BOLD}════════════════════════════════════════════${RESET}"
  echo -e "${GREEN}${BOLD}  ✅ SETUP HOÀN TẤT — Trạng thái hiện tại:${RESET}"
  echo -e "${GREEN}${BOLD}════════════════════════════════════════════${RESET}"
  kubectl get pods -n ${NS} -o wide --show-labels 2>/dev/null | grep -E "NAME|my-service"
  echo ""
  echo -e "  ${BOLD}Service URL:${RESET} ${CYAN}${BASE_URL}${RESET}"
  echo -e "  ${BOLD}Traffic split:${RESET} ${GREEN}~75% → stable (v1.0.1)${RESET}  |  ${YELLOW}~25% → canary (v1.0.2)${RESET}"
}

# ════════════════════════════════════════════════════════════
# STEP: watch — Live traffic visualization (dùng khi present)
# ════════════════════════════════════════════════════════════
cmd_watch() {
  banner
  echo -e "${BOLD}Live traffic split — Ctrl+C để dừng${RESET}"
  echo -e "${GREEN}● stable${RESET}  = v1.0.1 (production)    ${YELLOW}● canary${RESET} = v1.0.2 (25% traffic)"
  echo ""
  echo -e "  Request  │ Version    │ Track   │ Status │ Response"
  echo -e "  ─────────┼────────────┼─────────┼────────┼──────────────────────"

  count=0; stable=0; canary=0; errors=0

  while true; do
    count=$((count+1))
    RESP=$(curl -s -o /tmp/_resp -w "%{http_code}" "${BASE_URL}/api/v1/data" 2>/dev/null || echo "000")
    BODY=$(cat /tmp/_resp 2>/dev/null || echo "{}")
    VERSION=$(echo "$BODY" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('version','?'))" 2>/dev/null || echo "?")
    TRACK=$(echo "$VERSION" | grep -q "canary" && echo "canary" || echo "stable")

    if [ "$TRACK" = "canary" ]; then
      canary=$((canary+1))
      TRACK_COLOR="${YELLOW}"
    else
      stable=$((stable+1))
      TRACK_COLOR="${GREEN}"
    fi

    if [ "$RESP" = "200" ]; then
      STATUS="${GREEN}200 OK${RESET}"
    else
      STATUS="${RED}${RESP} ERR${RESET}"
      errors=$((errors+1))
    fi

    printf "  %-8s │ %-10s │ ${TRACK_COLOR}%-7s${RESET} │ ${STATUS} │ "
    echo "$BODY" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    if 'error' in d:
        print(f'\033[31m{d[\"error\"]}\033[0m')
    else:
        items = d.get('data', {}).get('items', [])
        print(f'data: {items}')
except:
    print('parse error')
" 2>/dev/null || echo ""

    # Summary mỗi 10 requests
    if [ $((count % 10)) -eq 0 ]; then
      echo ""
      echo -e "  ${BOLD}── Summary (${count} requests) ─────────────────────────────────────${RESET}"
      echo -e "  ${GREEN}Stable hits:${RESET} ${stable}  ${YELLOW}Canary hits:${RESET} ${canary}  ${RED}Errors:${RESET} ${errors}"
      CANARY_PCT=0
      [ $count -gt 0 ] && CANARY_PCT=$(echo "scale=1; ${canary}*100/${count}" | bc 2>/dev/null || echo "?")
      ERROR_PCT=0
      [ $count -gt 0 ] && ERROR_PCT=$(echo "scale=1; ${errors}*100/${count}" | bc 2>/dev/null || echo "?")
      echo -e "  Canary traffic: ${YELLOW}~${CANARY_PCT}%${RESET}  Error rate: ${RED}~${ERROR_PCT}%${RESET}"
      echo ""
    fi

    sleep 0.5
  done
}

# ════════════════════════════════════════════════════════════
# STEP: stress — Gửi nhiều requests, tính error rate
# ════════════════════════════════════════════════════════════
cmd_stress() {
  banner
  TOTAL=${1:-100}
  step "Gửi ${TOTAL} requests đến /api/v1/data..."
  echo ""

  ok_count=0; err_count=0; canary_count=0; stable_count=0

  for i in $(seq 1 $TOTAL); do
    RESP=$(curl -s -o /tmp/_resp -w "%{http_code}" "${BASE_URL}/api/v1/data" 2>/dev/null || echo "000")
    BODY=$(cat /tmp/_resp 2>/dev/null || echo "{}")
    VERSION=$(echo "$BODY" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('version','?'))" 2>/dev/null || echo "?")

    if echo "$VERSION" | grep -q "canary"; then
      canary_count=$((canary_count+1))
    else
      stable_count=$((stable_count+1))
    fi

    if [ "$RESP" = "200" ]; then
      ok_count=$((ok_count+1))
      printf "${GREEN}.${RESET}"
    else
      err_count=$((err_count+1))
      printf "${RED}E${RESET}"
    fi

    [ $((i % 50)) -eq 0 ] && echo ""
  done

  echo -e "\n\n${BOLD}══════════════════════════════════════════${RESET}"
  echo -e "${BOLD}  📊 KẾT QUẢ — ${TOTAL} REQUESTS${RESET}"
  echo -e "${BOLD}══════════════════════════════════════════${RESET}"
  echo -e "  ${GREEN}✅ Success (200):${RESET}  ${ok_count}"
  echo -e "  ${RED}❌ Error (5xx):${RESET}    ${err_count}"
  echo -e "  ${GREEN}● Stable hits:${RESET}    ${stable_count} (~$(echo "scale=0;${stable_count}*100/${TOTAL}" | bc)%)"
  echo -e "  ${YELLOW}● Canary hits:${RESET}    ${canary_count} (~$(echo "scale=0;${canary_count}*100/${TOTAL}" | bc)%)"
  echo ""
  ERR_PCT=$(echo "scale=1; ${err_count}*100/${TOTAL}" | bc 2>/dev/null || echo "?")
  if (( $(echo "$ERR_PCT > 5.0" | bc -l 2>/dev/null || echo 0) )); then
    err ""
    echo -e "  ${RED}${BOLD}⚠️  ERROR RATE: ${ERR_PCT}% — VƯỢT NGƯỠNG 5% !${RESET}"
    echo -e "  ${RED}  → Kayenta sẽ tự động ROLLBACK canary !${RESET}"
  else
    ok "Error rate: ${ERR_PCT}% — trong ngưỡng cho phép"
  fi
}

# ════════════════════════════════════════════════════════════
# STEP: promote — Canary thành stable (zero downtime)
# ════════════════════════════════════════════════════════════
cmd_promote() {
  banner
  step "Promote canary v1.0.2 → stable"
  info "Scale stable lên image canary (blue-green full deploy)"

  kubectl set image deployment/my-service-stable \
    my-service=louisbui/dev:v1.0.2-canary \
    -n ${NS}

  kubectl rollout status deployment/my-service-stable -n ${NS} --timeout=120s

  step "Xóa canary deployment"
  kubectl delete deployment my-service-canary -n ${NS} 2>/dev/null || true

  ok "Promote hoàn tất — 100% traffic → v1.0.2"
  kubectl get pods -n ${NS} -o wide 2>/dev/null
}

# ════════════════════════════════════════════════════════════
# STEP: rollback — Xóa canary, giữ stable
# ════════════════════════════════════════════════════════════
cmd_rollback() {
  banner
  step "🔴 ROLLBACK — Xóa canary, giữ stable v1.0.1"
  warn "Scenario: Kayenta phát hiện error rate > 5% → tự động rollback"
  echo ""

  kubectl delete deployment my-service-canary -n ${NS} 2>/dev/null && \
    ok "Deleted my-service-canary" || \
    warn "my-service-canary không tồn tại hoặc đã xóa"

  echo ""
  echo -e "${GREEN}${BOLD}════════════════════════════════════════════${RESET}"
  echo -e "${GREEN}${BOLD}  ✅ ROLLBACK HOÀN TẤT${RESET}"
  echo -e "${GREEN}${BOLD}════════════════════════════════════════════${RESET}"
  echo -e "  ${GREEN}● 100% traffic → stable v1.0.1${RESET}"
  echo -e "  ${GREEN}● Canary v1.0.2 (buggy) đã bị xóa${RESET}"
  echo -e "  ${GREEN}● Zero downtime — stable pods không bị ảnh hưởng${RESET}"
  echo ""
  kubectl get pods -n ${NS} -o wide 2>/dev/null
}

# ════════════════════════════════════════════════════════════
# STEP: status — Check trạng thái hiện tại
# ════════════════════════════════════════════════════════════
cmd_status() {
  banner
  step "Pods trong namespace ${NS}"
  kubectl get pods -n ${NS} -o wide 2>/dev/null

  echo ""
  step "Deployments"
  kubectl get deployments -n ${NS} -o wide 2>/dev/null

  echo ""
  step "Services"
  kubectl get services -n ${NS} 2>/dev/null

  echo ""
  step "Test health check"
  curl -s "${BASE_URL}/actuator/health" 2>/dev/null | python3 -m json.tool 2>/dev/null || echo "(không kết nối được)"

  echo ""
  info "Base URL: ${BASE_URL}"
}

# ════════════════════════════════════════════════════════════
# STEP: cleanup
# ════════════════════════════════════════════════════════════
cmd_cleanup() {
  banner
  step "Cleanup toàn bộ demo resources"
  kubectl delete namespace ${NS} --ignore-not-found=true
  ok "Deleted namespace ${NS}"
}

# ─── Main ─────────────────────────────────────────────────
case "${1:-help}" in
  setup)    cmd_setup ;;
  watch)    cmd_watch ;;
  stress)   cmd_stress "${2:-100}" ;;
  promote)  cmd_promote ;;
  rollback) cmd_rollback ;;
  status)   cmd_status ;;
  cleanup)  cmd_cleanup ;;
  *)
    banner
    echo -e "${BOLD}Usage:${RESET} bash demo/run-demo.sh [COMMAND]"
    echo ""
    echo -e "  ${CYAN}setup${RESET}        Build images + deploy stable & canary vào K8s"
    echo -e "  ${CYAN}watch${RESET}        👁  Live watch traffic split (đẹp để present)"
    echo -e "  ${CYAN}stress [N]${RESET}   Gửi N requests, tính error rate (default: 100)"
    echo -e "  ${CYAN}promote${RESET}      Promote canary thành stable (zero downtime)"
    echo -e "  ${CYAN}rollback${RESET}     🔴 Xóa canary, giữ stable (simulate auto-rollback)"
    echo -e "  ${CYAN}status${RESET}       Check trạng thái hiện tại"
    echo -e "  ${CYAN}cleanup${RESET}      Dọn dẹp toàn bộ resources"
    echo ""
    echo -e "${BOLD}Demo flow khi present:${RESET}"
    echo -e "  1. ${CYAN}setup${RESET}    → Deploy stable + canary"
    echo -e "  2. ${CYAN}watch${RESET}    → Show live traffic 75%/25%"
    echo -e "  3. ${CYAN}stress${RESET}   → Show error rate cao từ canary"
    echo -e "  4. ${CYAN}rollback${RESET} → Show auto-rollback trong giây lát"
    echo -e "  5. ${CYAN}cleanup${RESET}  → Dọn dẹp"
    ;;
esac
