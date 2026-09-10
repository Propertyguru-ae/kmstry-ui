const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
function validate(env) {
  for (const name of ['API_URL', 'SITE_URL']) {
    let url;
    try { url = new URL(env[name]); } catch { throw new Error(`${name} must be an HTTPS origin.`); }
    const host = url.hostname.toLowerCase();
    if (url.protocol !== 'https:' || url.username || url.password || url.search || url.hash || url.pathname !== '/' ||
        !host.includes('.') || host.includes(':') || /^(localhost|0\.|10\.|127\.|169\.254\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.)/.test(host) ||
        /(?:^|\.)(local|example\.com|example\.net|example\.org|invalid|test)$/.test(host) || /placeholder|replace-me/.test(host)) {
      throw new Error(`${name} must be a public HTTPS origin without credentials, query, fragment or path.`);
    }
  }
  if (!/^\d+\.\d+\.\d+$/.test(env.BUILD_NAME || '')) throw new Error('BUILD_NAME must be x.y.z.');
  if (!/^[1-9]\d*$/.test(env.BUILD_NUMBER || '') || Number(env.BUILD_NUMBER) > 2100000000) throw new Error('BUILD_NUMBER must be a positive Android-compatible build number.');
  if (env.BUILD_IOS && !['true', 'false'].includes(env.BUILD_IOS)) throw new Error('BUILD_IOS must be true or false.');
}
module.exports = { validate };
if (require.main === module) {
  try {
    validate(process.env);
    const expected = fs.readFileSync(path.join(__dirname, '../.flutter-version'), 'utf8').trim();
    const actual = JSON.parse(execFileSync('flutter', ['--version', '--machine'], { encoding: 'utf8' }));
    if (actual.frameworkVersion !== expected) throw new Error(`Use Flutter ${expected} for release (see .flutter-version).`);
    console.log('Release configuration and Flutter version verified.');
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}
