const { test } = require('node:test');
const assert = require('node:assert/strict');
const { inspect } = require('./secret-scan.cjs');

test('secret assignments are detected', () => {
  assert.ok(inspect('settings.txt', 'JWT_SECRET=' + 'a'.repeat(64)).includes('secret-assignment'));
});
test('scanner checks staged secrets even when working copy was cleaned', () => {
  const fs = require('node:fs');
  const path = require('node:path');
  const { execFileSync } = require('node:child_process');
  const { scan } = require('./secret-scan.cjs');
  const root = fs.mkdtempSync(path.join(require('node:os').tmpdir(), 'kmstry-secret-test-'));
  const originalError = console.error;
  const originalLog = console.log;
  const messages = [];
  try {
    execFileSync('git', ['init', '-q', root]);
    const file = path.join(root, 'settings.txt');
    fs.writeFileSync(file, 'JWT_SECRET=' + 'b'.repeat(64));
    execFileSync('git', ['-C', root, 'add', 'settings.txt']);
    fs.writeFileSync(file, 'safe');
    console.error = message => messages.push(message);
    console.log = () => {};
    assert.equal(scan(root), 1);
    assert.ok(messages.some(message => message.includes('[index; secret-assignment]')));
    assert.ok(!messages.join('').includes('b'.repeat(64)));
    execFileSync('git', ['-C', root, 'add', 'settings.txt']);
    assert.equal(scan(root), 0);
  } finally {
    console.error = originalError;
    console.log = originalLog;
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test('secret filenames block, public Firebase config and examples remain allowed', () => {
  for (const name of ['.env', '.env.production', 'android/key.properties', 'key.p8', 'release.jks']) assert.ok(inspect(name, '').length);
  for (const name of ['.env.example', 'android/app/google-services.json', 'ios/GoogleService-Info.plist']) assert.deepEqual(inspect(name, ''), []);
});
test('private key and credential URLs are blocked without returning their values', () => {
  const key = '-----BEGIN ' + 'PRIVATE KEY-----\n' + 'A'.repeat(80);
  assert.ok(inspect('config.txt', key).includes('private-key'));
  const url = 'postgresql://' + 'user:real-secret-value@database.invalid/db';
  assert.ok(inspect('config.txt', url).includes('credential-url'));
  assert.ok(!JSON.stringify(inspect('config.txt', url)).includes('real-secret-value'));
});
test('service accounts and provider tokens are blocked', () => {
  assert.ok(inspect('config.json', JSON.stringify({ type: 'service_account', private_key: 'test' })).length);
  assert.ok(inspect('config.txt', 'gh' + 'p_' + 'x'.repeat(40)).length);
});

const { validate } = require('./release-preflight.cjs');
const good = { API_URL: 'https://api.kmstry.net', SITE_URL: 'https://staging.kmstry.net', BUILD_NAME: '1.0.1', BUILD_NUMBER: '43' };
test('release preflight accepts explicit public origins and build metadata', () => assert.doesNotThrow(() => validate(good)));
test('release preflight rejects missing, private or malformed origins', () => {
  for (const value of ['', 'http://api.kmstry.net', 'https://192.168.1.1', 'https://localhost', 'https://[::1]', 'https://api.kmstry.net/path', 'https://user:pass@api.kmstry.net', 'https://api.kmstry.net?q=1', 'https://example.com']) {
    for (const field of ['API_URL', 'SITE_URL']) assert.throws(() => validate({ ...good, [field]: value }));
  }
});
test('release preflight rejects invalid build metadata', () => {
  for (const number of ['', '0', '-1', '1.2', '2100000001']) assert.throws(() => validate({ ...good, BUILD_NUMBER: number }));
  assert.throws(() => validate({ ...good, BUILD_NAME: '' }));
});
