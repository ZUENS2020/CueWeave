import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';

const read = (path) => readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');
const version = read('Cargo.toml').match(/^version = "(\d+\.\d+\.\d+)"$/m)?.[1];
assert(version, 'Workspace version is missing');
const windows = read('apps/windows/CueWeave.Windows/CueWeave.Windows.csproj');
for (const field of ['Version', 'InformationalVersion']) {
  assert.equal(windows.match(new RegExp(`<${field}>([^<]+)</${field}>`))?.[1], version, `Windows ${field} mismatch`);
}
assert.equal(read('apps/macos/Info.plist').match(/<key>CFBundleShortVersionString<\/key>\s*<string>([^<]+)<\/string>/)?.[1], version, 'macOS version mismatch');
const lock = read('Cargo.lock');
for (const name of ['cueweave-cli', 'cueweave-core']) {
  assert.equal(lock.match(new RegExp(`name = "${name}"\\nversion = "([^"]+)"`))?.[1], version, `${name} lock version mismatch`);
}
if (process.env.CUEWEAVE_RELEASE_TAG) {
  assert.equal(process.env.CUEWEAVE_RELEASE_TAG, `v${version}`, 'Tag must match all app versions');
  assert(read(`docs/RELEASE_v${version}.md`).trim(), 'Bilingual release notes are missing');
}
console.log(`version=${version}`);
