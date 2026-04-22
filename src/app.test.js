// Unit test — Node.js built-in only, no test framework needed
const http = require('http');

process.env.PORT = '18080';
process.env.APP_VERSION = 'test-1.0.0';
process.env.APP_ENV = 'test';

const app = require('./app');
const server = http.createServer(app);

let passed = 0;
let failed = 0;

function assert(condition, message) {
    if (condition) {
        console.log(`  ✅ PASS: ${message}`);
        passed++;
    } else {
        console.error(`  ❌ FAIL: ${message}`);
        failed++;
    }
}

function request(path) {
    return new Promise((resolve, reject) => {
        http.get(`http://localhost:18080${path}`, (res) => {
            let data = '';
            res.on('data', chunk => data += chunk);
            res.on('end', () => {
                try {
                    resolve({ status: res.statusCode, body: JSON.parse(data) });
                } catch (e) {
                    reject(new Error(`Invalid JSON from ${path}: ${data}`));
                }
            });
        }).on('error', reject);
    });
}

async function runTests() {
    console.log('\n=== Unit Tests ===\n');

    await new Promise((resolve, reject) =>
        server.listen(18080, (err) => err ? reject(err) : resolve())
    );

    try {
        // Test: GET /
        const home = await request('/');
        assert(home.status === 200, 'GET / returns 200');
        assert(home.body.service === 'my-service', 'GET / returns correct service name');
        assert(home.body.version === 'test-1.0.0', 'GET / returns correct version');
        assert(home.body.env === 'test', 'GET / returns correct env');

        // Test: GET /actuator/health
        const health = await request('/actuator/health');
        assert(health.status === 200, 'GET /actuator/health returns 200');
        assert(health.body.status === 'UP', 'Health status is UP');
        assert(health.body.version === 'test-1.0.0', 'Health returns correct version');
        assert(typeof health.body.uptime === 'number', 'Health returns numeric uptime');

        // Test: GET /api/v1/status
        const status = await request('/api/v1/status');
        assert(status.status === 200, 'GET /api/v1/status returns 200');
        assert(status.body.status === 'OK', 'API status is OK');
        assert(status.body.service === 'my-service', 'API status returns correct service');
        assert(status.body.version === 'test-1.0.0', 'API status returns correct version');

        // Test: GET /api/v1/config
        const config = await request('/api/v1/config');
        assert(config.status === 200, 'GET /api/v1/config returns 200');
        assert(config.body.env === 'test', 'Config returns correct env');
        assert(typeof config.body.features === 'object', 'Config returns features object');
        assert(config.body.features.newUI === false, 'Feature flag newUI defaults to false');

    } finally {
        server.close();
    }

    console.log(`\n=== Results: ${passed} passed, ${failed} failed ===`);
    if (failed > 0) {
        console.error('Tests FAILED');
        process.exit(1);
    } else {
        console.log('All tests PASSED');
        process.exit(0);
    }
}

runTests().catch(err => {
    console.error('Test runner error:', err);
    process.exit(1);
});