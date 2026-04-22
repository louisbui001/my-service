// Demo Service — Express app
// Endpoints khớp với readinessProbe và smoke/regression test trong Spinnaker pipeline

const express = require('express');
const app = express();
const PORT = process.env.PORT || 8080;
const APP_VERSION = process.env.APP_VERSION || 'unknown';
const APP_ENV = process.env.APP_ENV || 'local';

app.use(express.json());

// ── Home ──────────────────────────────────────────────
app.get('/', (req, res) => {
    res.json({
        service: 'my-service',
        version: APP_VERSION,
        env: APP_ENV,
        message: 'Hello from Spinnaker CI/CD Demo!',
        timestamp: new Date().toISOString()
    });
});

// ── Health check (dùng cho readinessProbe & livenessProbe) ──
// Spinnaker pipeline dùng endpoint này để xác nhận pod healthy
app.get('/actuator/health', (req, res) => {
    res.json({
        status: 'UP',
        version: APP_VERSION,
        env: APP_ENV,
        uptime: process.uptime()
    });
});

// ── API Status (dùng cho smoke test & regression test) ──
app.get('/api/v1/status', (req, res) => {
    res.json({
        status: 'OK',
        service: 'my-service',
        version: APP_VERSION,
        env: APP_ENV,
        timestamp: new Date().toISOString()
    });
});

// ── API Config (dùng cho regression test) ──
app.get('/api/v1/config', (req, res) => {
    res.json({
        env: APP_ENV,
        version: APP_VERSION,
        features: {
            newUI: process.env.FEATURE_NEW_UI === 'true' || false
        }
    });
});

// ── Start server ──
app.listen(PORT, () => {
    console.log(`my-service v${APP_VERSION} [${APP_ENV}] running on port ${PORT}`);
});

module.exports = app;