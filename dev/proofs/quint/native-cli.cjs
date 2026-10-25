// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
// Native CLI stages and reporting. Only the Node runtime survives a request.
const fs = require('node:fs');
const path = require('node:path');
const readline = require('node:readline');
const commands = require(process.argv[2]);
const root = path.dirname(process.argv[2]);
const { parseServerEndpoint } = require(path.join(root, 'apalache.js'));
const { createFinders, formatError } = require(path.join(root, 'errorReporter.js'));
const mode = process.argv[3];
if (!['typecheck', 'verify'].includes(mode)) throw new Error('unknown native CLI stage');

(async () => {
  for await (const line of readline.createInterface({ input: process.stdin })) {
    const args = JSON.parse(line);
    if (mode === 'verify') {
      const endpoint = parseServerEndpoint(args.serverEndpoint);
      if (endpoint.isLeft()) throw new Error(endpoint.value);
      args.serverEndpoint = endpoint.value;
    }
    // load/parse recreate the source map, resolver and id generator, including
    // transitive imports. compile/verify use the same stages as `quint verify`.
    let result = await commands.load(args);
    const stages = [commands.parse, commands.typecheck];
    if (mode === 'verify') stages.push(commands.compile, commands.verifySpec);
    for (const stage of stages) {
      if (result.isRight()) result = await stage(result.value);
    }
    const status = result.isRight() ? 0 : 1;
    if (result.isLeft()) {
      const { msg, stage } = result.value;
      const finders = createFinders(stage.sourceCode);
      for (const error of stage.errors) console.error(formatError(stage.sourceCode, finders, error));
      console.error(`error: ${msg}`);
    }
    await Promise.all([process.stdout, process.stderr].map(stream =>
      new Promise(resolve => stream.write('', resolve))));
    // A separate pipe keeps model diagnostics out of the result protocol.
    fs.writeSync(Number(process.argv[4]), JSON.stringify({ input: args.input,
      main: args.main ?? null, invariant: args.invariant ?? null, status }) + '\n');
  }
  // Match the CLI's ownership of its gRPC handles at process completion.
  process.exit(0);
})().catch(error => { console.error(error); process.exit(1); });
