const { spawnSync } = require('node:child_process');
const path = require('node:path');
const cases = [
  { name: 'missing API_URL', defines: ['SITE_URL=https://staging.kmstry.net'], expected: '_releaseApiUrlMustBeProvided' },
  { name: 'missing SITE_URL', defines: ['API_URL=https://api.kmstry.net'], expected: '_releaseSiteUrlMustBeProvided' },
  { name: 'explicit release origins', defines: ['API_URL=https://api.kmstry.net', 'SITE_URL=https://staging.kmstry.net'] },
];
for (const check of cases) {
  // Exercise the actual AppConfig constant evaluation, not a duplicate validator.
  // Tests do not initialize networking or contact these hosts.
  const result = spawnSync('flutter', ['test', 'test/core/config/app_config_test.dart', '--no-pub', '--reporter', 'expanded',
    '--dart-define=dart.vm.product=true', ...check.defines.map(x => `--dart-define=${x}`)],
  { cwd: path.resolve(__dirname, '..'), encoding: 'utf8', timeout: 120000, maxBuffer: 8 * 1024 * 1024 });
  const output = (result.stdout || '') + (result.stderr || '');
  const passed = !result.error && !result.signal && (check.expected
    ? result.status === 1 && output.includes('Constant evaluation error') && output.includes(check.expected)
    : result.status === 0 && output.includes('All tests passed'));
  if (!passed) { console.error(`Release configuration regression failed: ${check.name}`); process.exit(1); }
  console.log(`Release configuration verified: ${check.name}`);
}
