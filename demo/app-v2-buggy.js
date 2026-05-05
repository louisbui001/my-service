// ── VERSION 1.0.2 — Có bug giả lập (dùng để demo Canary chặn) ────────────────
// Endpoint /api/v1/data có 40% chance trả về 500 error
// → Kayenta / monitor sẽ phát hiện error rate tăng đột biến → rollback
const express = require('express');
const app = express();
const PORT = process.env.PORT || 8080;
const APP_VERSION = process.env.APP_VERSION || 'v1.0.2-canary';
const APP_ENV = process.env.APP_ENV || 'production';

app.use(express.json());

app.get('/', (req, res) => {
    res.json({
        service: 'my-service',
        version: APP_VERSION,
        env: APP_ENV,
        message: '🐦 CANARY build — đang được monitor',
        timestamp: new Date().toISOString()
    });
});

app.get('/actuator/health', (req, res) => {
    res.json({ status: 'UP', version: APP_VERSION, env: APP_ENV, uptime: process.uptime() });
});

app.get('/api/v1/status', (req, res) => {
    res.json({ status: 'OK', service: 'my-service', version: APP_VERSION, env: APP_ENV });
});

// ── Endpoint có bug: 40% chance trả 500 ──────────────────────────────────────
app.get('/api/v1/data', (req, res) => {
    const isBuggy = Math.random() < 0.4; // 40% error rate
    if (isBuggy) {
        return res.status(500).json({
            error: 'Internal Server Error',
            version: APP_VERSION,
            message: '💥 BUG: database connection timeout'
        });
    }
    res.json({
        data: { items: [1, 2, 3], total: 3 },
        version: APP_VERSION,
        timestamp: new Date().toISOString()
    });
});

app.get('/api/v1/config', (req, res) => {
    res.json({ env: APP_ENV, version: APP_VERSION, features: { newUI: true } });
});

if (require.main === module) {
    app.listen(PORT, () => {
        console.log(`my-service ${APP_VERSION} [${APP_ENV}] running on :${PORT}`);
    });
}
module.exports = app;
