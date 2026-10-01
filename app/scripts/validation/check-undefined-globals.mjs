import fs from 'node:fs';
import { Linter } from 'eslint';
import globals from 'globals';
import { readOrderedAppScripts, resolveAppScript } from '../lib/app-family-sandbox.mjs';
// Classic scripts share one lexical scope in the browser. Check the complete
// ordered family together so references between files are resolved correctly.
const scripts = readOrderedAppScripts({ filter: src => !src.includes('/') && fs.existsSync(resolveAppScript(src)) });
const source = scripts.map(name => fs.readFileSync(resolveAppScript(name), 'utf8')).join('\n;\n');
// IIFE/UMD modules publish browser globals as properties rather than lexical
// declarations. Only assignments in the loaded scripts define these names.
const exports = Object.fromEntries([...source.matchAll(/\b(?:window|global|globalThis|root)\.([A-Za-z_$][\w$]*)\s*=(?!=)/g)]
  .map(match => [match[1], 'readonly']));
const messages = new Linter().verify(source, [{
  languageOptions: { ecmaVersion: 'latest', sourceType: 'script', globals: { ...globals.browser, ...globals.es2021, ...exports, maplibregl: 'readonly', module: 'readonly' } },
  rules: { 'no-undef': 'error' },
}]);
for (const message of messages) console.error(`${message.line}:${message.column}: ${message.message}`);
if (messages.length) process.exitCode = 1;
else console.log(`Undefined-global check passed: ${scripts.length} classic scripts.`);
