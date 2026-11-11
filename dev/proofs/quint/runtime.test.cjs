// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const os=require('node:os');
const path=require('node:path');
const {execFileSync}=require('node:child_process');
const {performance}=require('node:perf_hooks');
const {QuintRuntime,quintExecutable,typecheckEntries}=require('./runtime.cjs');

async function inDirectory(action) {
  const directory=fs.mkdtempSync(path.join(os.tmpdir(),'yuanxu-quint-control-'));
  try {await action(directory);} finally {fs.rmSync(directory,{recursive:true,force:true});}
}
test('wall and real-output deadlines cancel the owned worker permanently',async()=>{
  await inDirectory(async directory=>{
    const input=path.join(directory,'Sample.qnt');
    fs.writeFileSync(input,'module Sample { pure val answer: int = 1 }');
    for(const limits of [{wall:0,idle:5},{wall:5,idle:0},
      {wall:0,idle:5,backendProgress:()=>performance.now()},
      {wall:5,idle:0,backendProgress:()=>0}]) {
      const runtime=new QuintRuntime('typecheck');
      try {
        await assert.rejects(runtime.request({input},limits),/deadline/);
        assert.ok(runtime.child.exitCode!==null||runtime.child.signalCode!==null);
        await assert.rejects(runtime.request({input}),/worker was cancelled/);
      } finally {await runtime.close();}
    }
  });
});
test('runtime stages agree with the pinned CLI for acceptance, type, syntax and effects',async()=>{
  await inDirectory(async directory=>{
    const input=path.join(directory,'Sample.qnt');
    const cases=[['module Sample { pure val answer: int = 1 }',true],
      ['module Sample { pure val answer: int = true }',false],
      ['module Sample { pure val = }',false],
      ['module Sample { var n: int pure val answer = n }',false]];
    for(const [source,accepted] of cases) {
      fs.writeFileSync(input,source);
      let cliAccepted=true;
      try {execFileSync(quintExecutable(),['typecheck',input],{stdio:'pipe',timeout:5000});}
      catch(error){assert.equal(error.signal,null);cliAccepted=false;}
      assert.equal(cliAccepted,accepted);
      if(accepted)await typecheckEntries([input]);
      else await assert.rejects(typecheckEntries([input]),/typecheck failed/);
    }
  });
});
test('transitive import mutation between same-path requests is rejected',async()=>{
  await inDirectory(async directory=>{
    const support=path.join(directory,'Support.qnt'),input=path.join(directory,'Sample.qnt');
    fs.writeFileSync(input,'module Sample { import Support.* from "./Support"\npure val answer: int = value }');
    fs.writeFileSync(support,'module Support { pure val value: int = 1 }');
    function* entries(){yield input;fs.writeFileSync(support,'module Support { pure val value: int = true }');yield input;}
    await assert.rejects(typecheckEntries(entries()),/typecheck failed/);
  });
});

test('migration retains the complete ordered acceptance catalogue and digest bindings',()=>{
  const {catalog,hash,checkBindings}=require('./catalog.cjs');
  assert.equal(catalog.cases.length,540);
  assert.equal(catalog.bindings.length,53);
  assert.equal(hash(JSON.stringify(catalog.cases)),
    'cfb0b2d30617c7757944196511cfdfbf472116270a33d76f37993125da67f8f6');
  checkBindings();
});
