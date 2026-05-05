# Canary Deploy Demo — Hướng dẫn chạy từng bước

## Kiến trúc demo

```
Service (NodePort :30080)
   │
   ├── 75% → my-service-stable  (3 pods, v1.0.1) ← PRODUCTION bình thường
   └── 25% → my-service-canary  (1 pod,  v1.0.2) ← CANARY có bug 40% error rate
```

---

## Bước 0 — Check prerequisites

```bash
# K8s cluster hoạt động
kubectl get nodes

# Docker daemon chạy
docker info | grep "Server Version"

# Lấy IP của node (dùng để test)
kubectl get nodes -o wide
# → ghi lại INTERNAL-IP của node01
```

---

## Bước 1 — Build images

```bash
cd /path/to/spinnaker-demo/my-service

# Build stable (v1.0.1) — dùng Dockerfile hiện tại
docker build -f Dockerfile \
  --build-arg APP_VERSION=v1.0.1-stable \
  -t louisbui/dev:v1.0.1-stable .

# Build canary (v1.0.2) — có bug 40% error rate
docker build -f demo/Dockerfile.v2-buggy \
  -t louisbui/dev:v1.0.2-canary .

# Verify
docker images | grep louisbui
```

> **Nếu images cần load lên K8s node** (cluster không pull từ DockerHub):
> ```bash
> docker save louisbui/dev:v1.0.1-stable | ssh user@node01 docker load
> docker save louisbui/dev:v1.0.2-canary | ssh user@node01 docker load
> ```
>
> Hoặc dùng local registry:
> ```bash
> # Trên node — chạy local registry
> docker run -d -p 5000:5000 --name registry registry:2
>
> # Tag và push
> docker tag louisbui/dev:v1.0.1-stable localhost:5000/my-service:v1.0.1-stable
> docker push localhost:5000/my-service:v1.0.1-stable
> ```

---

## Bước 2 — Deploy lên K8s

```bash
kubectl apply -f demo/k8s-canary-demo.yaml

# Chờ pods ready
kubectl rollout status deployment/my-service-stable -n canary-demo
kubectl rollout status deployment/my-service-canary -n canary-demo

# Verify — phải thấy 3 pods stable + 1 pod canary
kubectl get pods -n canary-demo -o wide --show-labels
```

**Kết quả mong đợi:**
```
NAME                                READY  STATUS   VERSION          TRACK
my-service-stable-xxx-xxx           1/1    Running  v1.0.1-stable    stable
my-service-stable-yyy-yyy           1/1    Running  v1.0.1-stable    stable
my-service-stable-zzz-zzz           1/1    Running  v1.0.1-stable    stable
my-service-canary-aaa-aaa           1/1    Running  v1.0.2-canary    canary
```

---

## Bước 3 — Verify traffic split

```bash
# Lấy NodeIP và port
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[1].status.addresses[?(@.type=="InternalIP")].address}')
BASE_URL="http://${NODE_IP}:30080"

# Test basic
curl ${BASE_URL}/

# Test health
curl ${BASE_URL}/actuator/health

# Gọi 10 lần, xem version nào trả về
for i in {1..10}; do
  curl -s ${BASE_URL}/ | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['version'])"
done
# Kỳ vọng: ~7-8 lần "v1.0.1-stable", ~2-3 lần "v1.0.2-canary"
```

---

## Bước 4 — Xem traffic live (đẹp để present)

```bash
bash demo/run-demo.sh watch
```

Output sẽ hiển thị từng request, version, status:
```
  Request  │ Version           │ Track   │ Status  │ Response
  ─────────┼───────────────────┼─────────┼─────────┼──────────────
  1        │ v1.0.1-stable     │ stable  │ 200 OK  │ data: [1, 2, 3]
  2        │ v1.0.1-stable     │ stable  │ 200 OK  │ data: [1, 2, 3]
  3        │ v1.0.2-canary     │ canary  │ 500 ERR │ BUG: db timeout  ← canary có lỗi!
  4        │ v1.0.1-stable     │ stable  │ 200 OK  │ data: [1, 2, 3]
  ...
```

---

## Bước 5 — Show error rate (dùng để present "Kayenta phát hiện")

```bash
# Gửi 100 requests, tính error rate
bash demo/run-demo.sh stress 100
```

Output:
```
  ✅ Success (200):  72
  ❌ Error (5xx):    28
  ● Stable hits:    76 (~76%)
  ● Canary hits:    24 (~24%)

  ⚠️  ERROR RATE: 28.0% — VƯỢT NGƯỠNG 5% !
  → Kayenta sẽ tự động ROLLBACK canary !
```

---

## Bước 6 — Demo ROLLBACK (dramatic moment!)

```bash
# Simulate: Kayenta tự động rollback sau khi phát hiện error rate cao
bash demo/run-demo.sh rollback
```

Sau đó verify 100% traffic về stable:
```bash
for i in {1..10}; do
  curl -s ${BASE_URL}/api/v1/data | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('version','?'))"
done
# → 10/10 đều là "v1.0.1-stable"
```

---

## Bước 7 — Hoặc PROMOTE (nếu canary OK)

```bash
bash demo/run-demo.sh promote
# → Scale stable lên image mới, xóa canary
# → 100% traffic vẫn chạy suốt (zero downtime)
```

---

## Cleanup

```bash
bash demo/run-demo.sh cleanup
```

---

## Script all-in-one — Chạy 1 lệnh

```bash
# Demo script tự động (dùng khi không có thời gian gõ tay)
bash demo/run-demo.sh setup && sleep 5 && bash demo/run-demo.sh stress 50
```

---

## Xử lý lỗi thường gặp

| Lỗi | Nguyên nhân | Fix |
|-----|-------------|-----|
| `ImagePullBackOff` | K8s không pull được image | Build local + `imagePullPolicy: Never` hoặc dùng local registry |
| `Connection refused :30080` | NodePort chưa bind | Check `kubectl get svc -n canary-demo`, thử `kubectl port-forward` |
| `curl: (6) Could not resolve host` | Sai NODE_IP | Chạy lại `kubectl get nodes -o wide` |
| Pod `Pending` | Node không đủ resource | Check `kubectl describe pod <name> -n canary-demo` |

### Port-forward thay cho NodePort

```bash
# Nếu NodePort không work
kubectl port-forward svc/my-service 8080:80 -n canary-demo &
BASE_URL="http://localhost:8080"
curl ${BASE_URL}/
```
