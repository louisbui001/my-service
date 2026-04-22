# ─── Stage 1: Build ───────────────────────────────────────
FROM node:20-alpine AS builder

WORKDIR /app

# Copy package files trước để tận dụng Docker layer cache
# Khi chỉ thay đổi code (không thay đổi dependencies) → layer này không rebuild
COPY package*.json ./
RUN npm ci --only=production

# ─── Stage 2: Runtime ─────────────────────────────────────
# Dùng image nhỏ hơn cho production (không có npm, không có dev tools)
FROM node:20-alpine AS runtime

# Build-time metadata args
ARG APP_VERSION=unknown
ARG BUILD_DATE=unknown
ARG GIT_COMMIT=unknown
LABEL app.version="${APP_VERSION}" \
      build.date="${BUILD_DATE}" \
      git.commit="${GIT_COMMIT}"

# Tạo user non-root để chạy app (security best practice)
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

WORKDIR /app

# Copy dependencies từ builder stage
COPY --from=builder /app/node_modules ./node_modules

# Copy source code
COPY src/ ./src/
COPY package.json ./
COPY VERSION ./

# Chuyển ownership sang user non-root
RUN chown -R appuser:appgroup /app
USER appuser

# Expose port
EXPOSE 8080

# Health check trong Docker (backup nếu K8s probe chưa kịp chạy)
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD wget -qO- http://localhost:8080/actuator/health || exit 1

# Start app
CMD ["node", "src/app.js"]