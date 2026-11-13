// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
const fs=require('node:fs');
const os=require('node:os');
const path=require('node:path');
const {parseArgs}=require('node:util');
const {QuintRuntime,quintExecutable,checkVersion,typecheckEntries}=require('./runtime.cjs');
const {startBackend}=require('./backend.cjs');
const {catalog,core,hash,files,digests,producerInputs,checkProducer}=require('./catalog.cjs');

function scheme(value) {
  if(typeof value==='boolean')return value?'#t':'#f';
  if(typeof value==='string')return JSON.stringify(value);
  if(Array.isArray(value))return '('+value.map(scheme).join(' ')+')';
  if(value&&typeof value==='object')return '('+Object.entries(value).map(([key,item])=>{
    const symbol=/^[\w./?-]+$/.test(key)?key:'|'+key.replace(/[\\|]/g,'\\$&')+'|';
    return '('+symbol+' . '+scheme(item)+')';
  }).join(' ')+')';
  if(typeof value==='number'&&Number.isFinite(value))return String(value);
  throw Error('Unsupported proof receipt value');
}
function classify(result,negative) {
  const text=result.output.toString();
  const counts=text.match(/([\d,]+) states generated, ([\d,]+) distinct states.*?([\d,]+) states left on queue/s);
  const accepted=negative
    ? result.status===1 && text.includes('Error: Invariant q_inv is violated.') &&
      text.includes('[violation] Found an issue') && text.includes('error: found a counterexample')
    : result.status===0 && text.includes('[ok] No violation found') && counts?.[3].replaceAll(',','')==='0';
  if(!accepted||!counts)throw Error(`Unexpected verifier result: exit=${result.status}`);
  return {'generated-states':Number(counts[1].replaceAll(',','')),
    'distinct-states':Number(counts[2].replaceAll(',',''))};
}
async function qualify(options) {
  const receipt=path.resolve(options.receipt);
  const prefix=options['case-prefix'];
  const shardCount=Number(options['shard-count']||1),shardIndex=Number(options['shard-index']||0);
  if(!Number.isSafeInteger(shardCount)||shardCount<1||!Number.isSafeInteger(shardIndex)||shardIndex<0||shardIndex>=shardCount)
    throw Error('Shard index must be within a positive shard count');
  if(prefix&&shardCount!==1)throw Error('Case prefixes and catalog sharding are separate qualification modes');
  const typecheckScope=options['typecheck-scope']||'all';
  if(!['all','selected'].includes(typecheckScope)||typecheckScope==='selected'&&!prefix)
    throw Error('Selected typechecking requires an explicit case prefix');
  const selected=catalog.cases.filter(item=>!prefix||item.model.startsWith(prefix))
    .filter((_item,index)=>index%shardCount===shardIndex);
  if(!selected.length)throw Error('Case prefix selects no catalogued models');
  fs.mkdirSync(path.dirname(receipt),{recursive:true});
  fs.rmSync(receipt,{force:true});
  const executable=options.quint||quintExecutable();
  const version=checkVersion(executable);
  const producer=options['producer-source']&&path.resolve(options['producer-source']);
  const producerBound=producerInputs(producer,prefix);
  checkProducer(producer,producerBound);
  const sources=digests(producerBound);
  const sidecar=suffix=>receipt.replace(/\.[^/.]+$/,'')+suffix;
  fs.writeFileSync(sidecar('.inputs.json'),JSON.stringify({status:'unqualified-input-cut','sources-sha256':sources},null,2)+'\n');
  const typecheckSources=typecheckScope==='all'
    ? files(__dirname,'.qnt').filter((_name,index)=>index%shardCount===shardIndex)
    : selected.map(item=>path.join(__dirname,item.model+'.qnt'));
  await typecheckEntries(typecheckSources,executable);
  console.log('QUINT-TYPECHECK-OK');
  console.log(`QUINT-TYPECHECK-SCOPE ${typecheckScope} ${typecheckSources.length} entries (including runtime imports)`);
  const work=fs.mkdtempSync(path.join(os.tmpdir(),'yuanxu-quint-'));
  const results=[];
  let backend,verifier;
  const cancelled=()=>verifier?.fail(Error('Quint qualification cancelled'));
  process.once('SIGTERM',cancelled);process.once('SIGINT',cancelled);
  try {
    for(const filename of files(__dirname,'.qnt')) {
      const bytes=fs.readFileSync(filename);
      if(hash(bytes)!==sources[path.relative(core,filename)])throw Error('Quint source changed before snapshot');
      fs.writeFileSync(path.join(work,path.basename(filename)),bytes);
    }
    const config=path.join(work,'backend.json');
    const workers=Math.max(4,os.availableParallelism());
    fs.writeFileSync(config,JSON.stringify({workers:String(workers),maxHeap:'-Xmx1G'})+'\n');
    console.log(`QUINT-WORKERS ${workers}`);
    const external=options['server-endpoint']||process.env.QUINT_SERVER_ENDPOINT;
    if(!external)backend=await startBackend(executable);
    verifier=new QuintRuntime('verify',{executable,cwd:work});
    for(const item of selected) {
      console.log(`QUINT-CHECK ${item.model} ${item.invariant}`);
      const result=await verifier.request({input:path.join(work,item.model+'.qnt'),main:item.model,
        backend:'tlc',apalacheVersion:'0.62.1',invariant:item.invariant,invariants:[],init:'init',step:'step',
        maxSteps:10,randomTransitions:false,tlcConfig:config,verbosity:3,serverEndpoint:external||backend.endpoint},
        {wall:45,idle:5,emit:true,backendProgress:()=>backend?.progressAt()||0});
      let counts;
      try {counts=classify(result,item.negative);}
      catch(error) {fs.writeFileSync(sidecar('.failure.log'),result.output);throw Error(`${item.model}/${item.invariant}: ${error.message}`);}
      results.push({...item,exit:result.status,...counts,'output-sha256':hash(result.output)});
      console.log(`QUINT-OK ${item.model}`);
    }
  } finally {
    process.removeListener('SIGTERM',cancelled);process.removeListener('SIGINT',cancelled);
    try {if(verifier)await verifier.close();}
    finally {try {if(backend)await backend.close();} finally {fs.rmSync(work,{recursive:true,force:true});}}
  }
  const current=digests(producerBound);
  if(JSON.stringify(sources)!==JSON.stringify(current)) {
    const changed=Object.fromEntries(Object.entries(sources).filter(([name,digest])=>current[name]!==digest)
      .map(([name,before])=>[name,{before,after:current[name]??null}]));
    fs.writeFileSync(sidecar('.drift.json'),JSON.stringify({status:'rejected-source-cut',changed},null,2)+'\n');
    throw Error('Bound sources changed during qualification');
  }
  checkProducer(producer,producerBound);
  const value={schema:'yuanxu.quint-proof.v1','quint-version':version,backend:'tlc','apalache-version':'0.62.1',
    'sources-sha256':sources,'case-prefix':prefix||'all','catalogue-size':catalog.cases.length,
    'shard-index':shardIndex,'shard-count':shardCount,
    'qualification-scope':shardCount>1?'partition':prefix?'selected':'complete',
    'typecheck-scope':typecheckScope,'typecheck-entries':typecheckSources.map(name=>path.basename(name,'.qnt')),cases:results};
  const temporary=receipt+'.tmp';
  fs.writeFileSync(temporary,scheme(value)+'\n');fs.renameSync(temporary,receipt);
  console.log(`QUINT-QUALIFICATION-OK ${results.length} cases`);
  return value;
}
if(require.main===module) {
  const options={quint:{type:'string'},receipt:{type:'string',default:'.cache/proofs/quint/receipt.ss'},
    'server-endpoint':{type:'string'},'case-prefix':{type:'string'},'producer-source':{type:'string'},
    'shard-count':{type:'string'},'shard-index':{type:'string'},'typecheck-scope':{type:'string'}};
  qualify(parseArgs({options}).values).catch(error=>{console.error(error);process.exitCode=1;});
}
module.exports={qualify,classify,scheme};
