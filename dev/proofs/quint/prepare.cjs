// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
const path=require('node:path');
const {fork}=require('node:child_process');
const {quintCommands,quintExecutable,checkVersion}=require('./runtime.cjs');

if(process.argv.includes('--worker')) {
  const commands=quintCommands();
  const {fetchApalache}=require(path.join(path.dirname(commands),'apalache.js'));
  fetchApalache('0.62.1',3).then(result=>{
    if(result.isLeft())throw Error(String(result.value));
    console.log(`QUINT-BACKEND-PREPARED ${result.value}`);
  }).catch(error=>{console.error(error);process.exitCode=1;});
} else {
  checkVersion(quintExecutable());
  console.log('QUINT-PREPARE backend=0.62.1 (not a proof receipt)');
  const child=fork(__filename,['--worker'],{detached:true,stdio:'inherit'});
  const timer=setTimeout(()=>{
    console.error('Quint backend preparation exceeded 60s');
    try {process.kill(-child.pid,'SIGKILL');} catch(error){if(error.code!=='ESRCH')throw error;}
  },60000);
  child.once('exit',(code,signal)=>{
    clearTimeout(timer);
    if(signal||code!==0)process.exitCode=1;
    else console.log('QUINT-PREPARE-OK (not a proof receipt)');
  });
}
