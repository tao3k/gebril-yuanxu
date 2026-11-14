// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
const fs=require('node:fs');
const path=require('node:path');
const crypto=require('node:crypto');
const {execFileSync}=require('node:child_process');
const catalog=require('./catalog.json');
const core=path.resolve(__dirname,'../../..');
const hash=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
function files(directory,extension,recursive=false) {
  return fs.readdirSync(directory,{withFileTypes:true}).flatMap(entry=>
    entry.isDirectory()&&recursive ? files(path.join(directory,entry.name),extension,true) :
    entry.isFile()&&entry.name.endsWith(extension) ? [path.join(directory,entry.name)] : []).sort();
}
function owners(producer=[]) {
  const paths=new Set(catalog.owners.map(name=>path.join(core,name)));
  for(const [directory,extension,recursive] of [['graph','.ss',false],
    ['module-system/schema/support','.ss',false],['modules/funflow/control-plane','.ss',false],
    ['dev/proofs/lean/YuanxuProof','.lean',true],['dev/proofs/quint','.qnt',false],
    ['dev/proofs/quint','.cjs',false]])
    for(const name of files(path.join(core,directory),extension,recursive))paths.add(name);
  for(const name of ['catalog.json','package.json','package-lock.json'])paths.add(path.join(__dirname,name));
  for(const name of producer)paths.add(name);
  return [...paths].sort();
}
function digests(producer=[]) {
  return Object.fromEntries(owners(producer).map(name=>[path.relative(core,name),hash(fs.readFileSync(name))]));
}
function producerInputs(directory,prefix) {
  if(!directory)return [];
  if(!prefix||!['SelectionReplay','IncrementalRoles','ThunkConstruction','GraphSnapshot'].some(name=>prefix.startsWith(name)))
    throw Error('Producer binding requires an explicit supported correspondence prefix');
  const names=prefix.startsWith('GraphSnapshot')?catalog.producerOwners.graph:catalog.producerOwners.reads;
  return names.map(name=>path.resolve(directory,name));
}
function checkProducer(directory,inputs) {
  if(!directory)return;
  const declared=fs.readFileSync(path.join(core,'gerbil.pkg'),'utf8').match(/github\.com\/tao3k\/gerbil-poo@([^"\s]+)/);
  if(!declared)throw Error('Core has no declared producer revision');
  const git=args=>execFileSync('git',['--no-replace-objects','-C',directory,...args],{timeout:5000});
  const expected=git(['rev-parse','--verify',declared[1]+'^{commit}']).toString().trim();
  if(git(['rev-parse','--verify','HEAD^{commit}']).toString().trim()!==expected)
    throw Error('Producer checkout differs from declared package reference');
  for(const filename of inputs) {
    const relative=path.relative(directory,filename);
    if(hash(fs.readFileSync(filename))!==hash(git(['cat-file','blob',`${expected}:${relative}`])))
      throw Error(`Producer source differs from pinned checkout: ${relative}`);
  }
}
module.exports={catalog,core,hash,files,digests,producerInputs,checkProducer};
