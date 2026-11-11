// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
// Owned execution of the existing pinned Quint CLI stages.
const fs = require('node:fs');
const path = require('node:path');
const { spawn, execFileSync } = require('node:child_process');
const { performance } = require('node:perf_hooks');

/** @typedef {{input:string, main?:string, invariant?:string, backend?:string,
 * apalacheVersion?:string, invariants?:string[], init?:string, step?:string,
 * maxSteps?:number, randomTransitions?:boolean, tlcConfig?:string,
 * verbosity?:number, serverEndpoint?:string}} QuintRequest */
/** @typedef {{status:0|1, output:Buffer}} QuintResult */

function quintExecutable() {
  return process.env.QUINT_BIN || path.join(__dirname, 'node_modules/.bin/quint');
}
function quintCommands(executable = quintExecutable()) {
  const filename = path.join(path.dirname(fs.realpathSync(executable)), 'cliCommands.js');
  if (!fs.statSync(filename).isFile()) throw Error('Pinned Quint CLI stages are missing');
  return filename;
}
function checkVersion(executable = quintExecutable()) {
  const version = execFileSync(executable, ['--version'], {encoding:'utf8', timeout:5000}).trim();
  if (version !== '0.33.0') throw Error(`Expected Quint 0.33.0, got ${version}`);
  return version;
}

class QuintRuntime {
  constructor(mode, options = {}) {
    if (!['typecheck','verify'].includes(mode)) throw Error('Unknown Quint stage');
    this.mode=mode;
    this.cancelled=false;
    this.pending=null;
    this.control='';
    this.sequence=0;
    this.child=spawn(process.execPath, ['--max-old-space-size=1024',
      path.join(__dirname,'quint-cli.cjs'), quintCommands(options.executable), mode, '3'],
      {cwd:options.cwd, detached:true, stdio:['pipe','pipe','pipe','pipe']});
    this.closed=new Promise(resolve=>this.child.once('close',resolve));
    const output=chunk=>{
      if (!this.pending) return;
      this.pending.chunks.push(Buffer.from(chunk));
      this.pending.lastOutput=performance.now();
      if (this.pending.emit) process.stdout.write(chunk);
    };
    this.child.stdout.on('data',output);
    this.child.stderr.on('data',output);
    this.child.stdin.on('error',error=>this.fail(error));
    this.child.on('error',error=>this.fail(error));
    this.child.once('exit',(code,signal)=>this.fail(Error(`Quint worker exited: ${code}/${signal}`)));
    this.child.stdio[3].on('data',chunk=>{
      this.control+=chunk.toString();
      const end=this.control.indexOf('\n');
      if(end<0) return;
      const frame=this.control.slice(0,end);
      this.control=this.control.slice(end+1);
      setImmediate(()=>{
        const pending=this.pending;
        if(!pending) return;
        try {
          const result=JSON.parse(frame);
          if(result.requestId!==pending.id) throw Error('Quint result belongs to another request epoch');
          for(const key of ['input','main','invariant'])
            if((pending.args[key]??null)!==result[key]) throw Error('Quint result belongs to another request');
          if(![0,1].includes(result.status)) throw Error('Quint result has no runtime status');
          clearInterval(pending.timer);
          this.pending=null;
          pending.resolve({status:result.status,output:Buffer.concat(pending.chunks)});
        } catch(error) { this.fail(error); }
      });
    });
  }
  /** @param {QuintRequest} args @returns {Promise<QuintResult>} */
  request(args, {wall=5,idle=5,emit=false,backendProgress=()=>0}={}) {
    if(this.cancelled) return Promise.reject(Error('Quint worker was cancelled; start a new worker'));
    if(this.pending) return Promise.reject(Error('Quint stage already has an active request'));
    return new Promise((resolve,reject)=>{
      const started=performance.now();
      const pending={id:++this.sequence,args,resolve,reject,started,lastOutput:started,chunks:[],emit,timer:null};
      this.pending=pending;
      const check=()=>{
        const now=performance.now();
        pending.lastOutput=Math.max(pending.lastOutput,backendProgress());
        if(now-started>=wall*1000 || now-pending.lastOutput>=idle*1000)
          this.fail(Error(`Quint ${this.mode} exceeded ${wall}s case or ${idle}s real-output deadline: ${args.input}`));
      };
      pending.timer=setInterval(check,10);
      check();
      if(this.pending===pending) this.child.stdin.write(JSON.stringify({...args,requestId:pending.id})+'\n');
    });
  }
  fail(error) {
    const pending=this.pending;
    if(!pending) return;
    clearInterval(pending.timer);
    this.pending=null;
    this.cancelled=true;
    try { process.kill(-this.child.pid,'SIGKILL'); } catch(cause) { if(cause.code!=='ESRCH') error=cause; }
    this.closed.then(()=>pending.reject(error));
  }
  async close() {
    if(this.pending) this.fail(Error('Quint runtime closed during a request'));
    this.child.stdin.end();
    await this.closed;
  }
}
async function typecheckEntries(entries, executable=quintExecutable()) {
  const runtime=new QuintRuntime('typecheck',{executable});
  try {
    for(const filename of entries) {
      const input=path.resolve(filename);
      const result=await runtime.request({input});
      if(result.status!==0) throw Error(`Quint typecheck failed: ${input}: ${result.output}`);
      console.log(`QUINT-TYPECHECK-ENTRY ${input}`);
    }
  } finally { await runtime.close(); }
}
module.exports={QuintRuntime,quintExecutable,quintCommands,checkVersion,typecheckEntries};
