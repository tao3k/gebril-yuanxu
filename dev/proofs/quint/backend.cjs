// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
const fs=require('node:fs');
const os=require('node:os');
const path=require('node:path');
const net=require('node:net');
const {spawn}=require('node:child_process');
const {createRequire}=require('node:module');
const {performance}=require('node:perf_hooks');
const {quintCommands}=require('./runtime.cjs');
const delay=milliseconds=>new Promise(resolve=>setTimeout(resolve,milliseconds));

async function availablePort() {
  const reservation=net.createServer();
  await new Promise((resolve,reject)=>{
    reservation.once('error',reject);
    reservation.listen(0,'127.0.0.1',resolve);
  });
  const port=reservation.address().port;
  await new Promise(resolve=>reservation.close(resolve));
  return port;
}
async function closeProcess(child,closed) {
  const kill=signal=>{
    try {process.kill(-child.pid,signal);} catch(error) {if(error.code!=='ESRCH')throw error;}
  };
  if(child.exitCode===null && child.signalCode===null) {
    kill('SIGTERM');
    const ended=await Promise.race([closed.then(()=>true),delay(1000).then(()=>false)]);
    if(!ended)kill('SIGKILL');
  }
  await closed;
}
function reflectionReady(commands,port,milliseconds) {
  const load=createRequire(commands);
  const grpc=load('@grpc/grpc-js');
  const definition=load('@grpc/proto-loader').loadSync(load.resolve('./reflection.proto'),
    {keepCase:true,longs:String,enums:String,defaults:true,oneofs:true});
  const Service=grpc.loadPackageDefinition(definition).grpc.reflection.v1alpha.ServerReflection;
  const client=new Service(`127.0.0.1:${port}`,grpc.credentials.createInsecure());
  return new Promise(resolve=>{
    const deadline=new Date(Date.now()+milliseconds);
    let finished=false;
    const finish=value=>{if(finished)return;finished=true;client.close();resolve(value);};
    client.waitForReady(deadline,error=>{
      if(error)return finish(false);
      const call=client.ServerReflectionInfo({deadline});
      call.on('data',data=>{
        const files=data.file_descriptor_response?.file_descriptor_proto;
        call.end();finish(Boolean(files?.length));
      });
      call.on('error',()=>finish(false));
      call.on('end',()=>finish(false));
      call.write({file_containing_symbol:'shai.cmdExecutor.CmdExecutor'});
    });
  });
}
async function startBackend(executable) {
  const commands=quintCommands(executable);
  const program=path.join(process.env.QUINT_HOME||path.join(os.homedir(),'.quint'),
    'apalache-dist-0.62.1/apalache/bin/apalache-mc');
  if(!fs.existsSync(program))throw Error('Prepare pinned Apalache 0.62.1 first');
  const port=await availablePort();
  const started=performance.now();
  let lastOutput,output='';
  // HotSpot reports completed VM initialization stages before Apalache can log.
  const child=spawn(program,['server',`--port=${port}`],{detached:true,
    env:{...process.env,JVM_ARGS:'-Xmx1G -XX:TieredStopAtLevel=1 -Xlog:startuptime=info'},stdio:['ignore','pipe','pipe']});
  const closed=new Promise(resolve=>child.once('close',resolve));
  let spawnError;
  child.once('error',error=>{spawnError=error;});
  const consume=chunk=>{lastOutput=performance.now();output+=chunk.toString();process.stdout.write(chunk);};
  child.stdout.on('data',consume);child.stderr.on('data',consume);
  const remaining=()=> {
    const now=performance.now(),wall=45000-(now-started);
    // Before the first JVM output, only the startup wall deadline applies.
    return lastOutput===undefined?wall:Math.min(wall,5000-(now-lastOutput));
  };
  try {
    while(!output.includes('The Apalache server is running')) {
      if(spawnError)throw spawnError;
      if(child.exitCode!==null||child.signalCode!==null)throw Error('Apalache exited before readiness');
      if(remaining()<=0)throw Error('Apalache startup exceeded 45s or 5s real-output deadline');
      await delay(20);
    }
    if(!output.includes('APALACHE version: 0.62.1 |'))throw Error('Apalache did not attest version 0.62.1');
    while(true) {
      const budget=remaining();
      if(budget<=0)throw Error('Apalache gRPC readiness exceeded its original deadline');
      if(await reflectionReady(commands,port,budget))break;
      await delay(50);
    }
    if(child.exitCode!==null||child.signalCode!==null)throw Error('Apalache exited during readiness');
    console.log(`APALACHE-SESSION pid=${child.pid} endpoint=127.0.0.1:${port} version=0.62.1 heap=1G startup-ms=${Math.floor(performance.now()-started)} grpc=ready`);
    return {endpoint:`127.0.0.1:${port}`,progressAt:()=>lastOutput,close:()=>closeProcess(child,closed)};
  } catch(error) {await closeProcess(child,closed);throw error;}
}
module.exports={startBackend};
