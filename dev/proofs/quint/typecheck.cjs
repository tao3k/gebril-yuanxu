// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
// Reuse the pinned CLI implementation, never its source or typecheck results.
const readline = require('node:readline');
const { load, parse, typecheck } = require(process.argv[2]);

async function check(input) {
  // load creates a fresh source map; parse creates a fresh resolver/id generator.
  let result = await load({ input });
  if (result.isRight()) result = await parse(result.value);
  if (result.isRight()) result = await typecheck(result.value);
  if (result.isRight()) return { input, ok: true };
  return { input, ok: false, message: result.value.msg,
    errors: result.value.stage.errors };
}

(async () => {
  for await (const line of readline.createInterface({ input: process.stdin })) {
    const result = await check(JSON.parse(line));
    process.stdout.write(JSON.stringify(result,
      (_, value) => typeof value === 'bigint' ? value.toString() : value) + '\n');
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
