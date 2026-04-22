// Unit test — chỉ cần Node.js built-in, không cần framework test
const http = require('http');

// Set env trước khi load app
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

async function request(path) {
    return new Promise((resolve) => {
        server.listen(18080, () => {
            http.get(`http://localhost:18080${path}`, (res) => {
                let data = '';
                res.on('data', chunk => data += chunk);
                res.on('end', () => {
                    resolve({ status: res.statusCode, body: JSON.parse(data) });
                });
            });
        });
    });
}

async function runTests() {
    console.log('\n=== Unit Tests ===\n');

    // Test 1: Health endpoint
    const health = await request('/actuator/health');
    assert(health.status === 200, 'GET /actuator/health returns 200');
    assert(health.body.status === 'UP', 'Health status is UP');
    assert(health.body.version === 'test-1.0.0', 'Health returns correct version');

    server.close();

    // Kết quả
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