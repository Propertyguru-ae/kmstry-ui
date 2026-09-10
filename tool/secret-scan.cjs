#!/usr/bin/env node
const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

function inspect(name, content) {
  const findings = [];
  const base = path.basename(name);
  if ((/^\.env(?:\.|$)/.test(base) && !/\.(example|sample|template)$/.test(base)) ||
      /\.(p12|pfx|jks|keystore|p8)$/i.test(base) ||
      /^(key\.properties|id_rsa|id_ed25519)$/i.test(base) ||
      /(?:service[-_]?account|firebase-adminsdk).*\.json$/i.test(base)) findings.push('secret-file');
  const patterns = [
    ['secret-assignment', /\b(?:JWT_SECRET|ADMIN_JWT_SECRET|DO_SPACES_SECRET|AWS_SECRET_ACCESS_KEY|RESEND_API_KEY)\s*["']?\s*[:=]\s*["']?([A-Za-z0-9+/_=-]{24,})/],
    ['private-key', /-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----\s*[A-Za-z0-9+/=]{32}/],
    ['credential-url', /(?:postgres(?:ql)?|mysql|mongodb(?:\+srv)?):\/\/[^\s:@]+:([^\s@]+)@/g],
    ['provider-token', /\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,}|AKIA[A-Z0-9]{16})\b/],
  ];
  for (const [label, re] of patterns) {
    for (const match of content.matchAll(new RegExp(re.source, 'g'))) {
      if (label === 'secret-assignment' && /^(?:your_|replace_|change_me|example_|test_|placeholder)/i.test(match[1])) continue;
      if (label === 'credential-url' && /^(?:password|postgres|test|test-only|changeme|YOUR_PASSWORD|\$\{[^}]+\}|<[^>]+>)$/i.test(match[1])) continue;
      findings.push(label); break;
    }
  }
  if (/"type"\s*:\s*"service_account"/.test(content) && /"private_key"\s*:/.test(content)) findings.push('service-account');
  return findings;
}
function scan(root) {
  const git = (...args) => execFileSync('git', args, { cwd: root, maxBuffer: 64 * 1024 * 1024 });
  const files = [...new Set(git('ls-files', '--cached', '--others', '--exclude-standard', '-z').toString().split('\0').filter(Boolean))];
  const staged = new Set(git('ls-files', '-z').toString().split('\0').filter(Boolean));
  let failures = 0;
  for (const name of files) {
    const versions = [];
    if (staged.has(name)) versions.push(['index', git('show', ':' + name).toString()]);
    const file = path.join(root, name);
    if (fs.existsSync(file) && fs.lstatSync(file).isFile()) versions.push(['working-tree', fs.readFileSync(file, 'utf8')]);
    for (const [version, content] of versions) {
      for (const rule of inspect(name, content)) {
        console.error(`SECRET_SCAN_BLOCKED: ${name} [${version}; ${rule}]`);
        failures++;
      }
    }
  }
  if (failures) return 1;
  console.log('Secret scan passed (index and non-ignored working files; values never printed).');
  return 0;
}
module.exports = { inspect, scan };
if (require.main === module) {
  try { process.exitCode = scan(path.resolve(__dirname, '..')); }
  catch { console.error('SECRET_SCAN_BLOCKED: unable to inspect all repository files.'); process.exitCode = 1; }
}
