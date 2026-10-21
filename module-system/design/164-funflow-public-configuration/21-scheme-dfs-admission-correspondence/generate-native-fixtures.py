#!/usr/bin/env python3
"""Numeric S-expression transcript to Lean checks; no eval or expected-result edits."""
from pathlib import Path
import hashlib,re,sys

def parse(line):
    tokens=re.findall(r'\(|\)|[^\s()]+',line)
    position=0
    def read():
        nonlocal position
        if position>=len(tokens):raise ValueError('truncated transcript')
        token=tokens[position];position+=1
        if token=='(':
            values=[]
            while position<len(tokens) and tokens[position]!=')':values.append(read())
            if position>=len(tokens):raise ValueError('missing close')
            position+=1;return values
        if token==')':raise ValueError('unexpected close')
        if token.isdecimal():return int(token)
        if re.fullmatch(r'[a-z]+',token):return token
        raise ValueError('unsupported token '+token)
    result=read()
    if position!=len(tokens):raise ValueError('trailing transcript')
    return result

def natural(n):
    if type(n) is not int or n<0:raise ValueError('not a natural')
    return str(n)

def numbers(xs):return '['+', '.join(natural(n) for n in xs)+']'
def boolean(n):
    if n not in (0,1):raise ValueError('not boolean')
    return 'true' if n else 'false'

def graph(name,rows):
    ids=[r[0] for r in rows]
    if len(set(ids))!=len(ids):raise ValueError('duplicate graph row')
    if any(x not in ids for _,ps in rows for x in ps):raise ValueError('incomplete reachable graph')
    return 'def '+name+' : Parents\n'+''.join('  | '+natural(n)+' => '+numbers(ps)+'\n' for n,ps in rows)+'  | _ => []\n'

def main(source,destination):
    raw=Path(source).read_text()
    rows=[parse(line) for line in raw.splitlines() if line.strip()]
    if rows[-1][0]!='pass':raise ValueError('native run did not pass')
    out=['-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors',
         '-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later',
         'import YuanxuProof.ModuleSystem.Schema.Association.Correspondence',
         '-- Generated only from the actual native transcript. Do not hand-edit observations.',
         '-- Transcript SHA-256: '+hashlib.sha256(raw.encode()).hexdigest(),
         'namespace YuanxuProof.ModuleSystem.Schema.Association.NativeFixtures',
         'open Projection',
         'def insertID (value : Nat) : List Nat → List Nat\n  | [] => [value]\n  | head :: tail => if value ≤ head then value :: head :: tail else head :: insertID value tail',
         'def canonical : List Nat → List Nat\n  | [] => []\n  | head :: tail => insertID head (canonical tail)']
    evidence=[];responsibilities=[];boundaries=[];case_count=0;gate_count=0;cycle_count=0
    def intern(row):
        if row in evidence:return evidence.index(row)
        evidence.append(row);return len(evidence)-1
    for row in rows:
        tag=row[0]
        if tag=='case':
            _,n,root,edges,anchors,found,actual,expected,receipt=row
            name='graph'+natural(n)
            out.append(graph(name,edges))
            anchor_text='['+', '.join('⟨'+natural(a)+', '+natural(c)+', 1, 1⟩' for a,c in anchors)+']'
            out.append('def roots'+natural(n)+' : List Anchor := '+anchor_text)
            out.append('#guard (match Traversal.visit '+name+' '+natural(len(edges)+2)+' '+natural(root)+' [] [] with\n'
                '  | .error _ => false\n'
                '  | .ok done => canonical ((Traversal.dfsAssociations done roots'+natural(n)+').map Anchor.contract) == canonical '+numbers(found)+')')
            out.append('#guard finalValueGate (fun _ => '+numbers(expected)+') '
                '⟨'+natural(root)+', 0, 1, 1, 1⟩ '+numbers(actual)+' == '+boolean(receipt[10]))
            intern(receipt);case_count+=1
        elif tag=='receipt':intern(row[1])
        elif tag=='responsibility':
            _,parent,children,own=row
            first=intern(parent);child_ids=[intern(child) for child in children]
            responsibilities.append((first,child_ids,own))
        elif tag=='identity':
            triples=row[1]
            text='['+', '.join('('+natural(a)+', '+natural(b)+', '+boolean(same)+')' for a,b,same in triples)+']'
            out.append('def identityObservations : List (Nat × Nat × Bool) := '+text)
            out.append('#guard identityObservations.all (fun pair => (pair.1 == pair.2.1) == pair.2.2)')
        elif tag=='boundary':
            _,root,context,edges,anchors,rhs,retained,receipts,accepted=row
            mapping=[(receipt[0],intern(receipt)) for receipt in receipts]
            if len({key for key,_ in mapping})!=len(mapping):raise ValueError('ambiguous call identity')
            boundaries.append((root,context,edges,anchors,rhs,retained,mapping,accepted))
        elif tag=='gate':
            _,mandatory,retained,checks,accepted=row
            name='requirementResult'+str(gate_count)
            out.append('def '+name+' : Nat → Bool\n'+''.join('  | '+natural(i)+' => '+boolean(v)+'\n' for i,v in checks)+'  | _ => false')
            out.append('#guard (match compositionGate '+numbers(mandatory)+' '+numbers(retained)+' '+name+' with\n'
                '  | .ok _ => true | .error _ => false) == '+boolean(accepted))
            gate_count+=1
        elif tag=='cycle':
            _,root,edges=row;name='cycleGraph'+str(cycle_count)
            out.append(graph(name,edges))
            out.append('#guard (match Traversal.visit '+name+' '+natural(len(edges)+2)+' '+natural(root)+' [] [] with\n'
                '  | .error (.cycle node) => node == '+natural(root)+' | _ => false)')
            cycle_count+=1
        elif tag!='pass':raise ValueError('unknown record '+str(tag))
    for i,row in enumerate(evidence):
        if len(row)!=14:raise ValueError('invalid receipt arity')
        expected_contract,expected_candidate,expected_context,typed,contract,candidate,context,classification,classified,obligations,accepted,class_candidate,class_context,gate=row
        name='evidence'+str(i)
        out.append('def '+name+' : Receipt :=\n  { typed := '+boolean(typed)+', contract := '+natural(contract)+', candidate := '+natural(candidate)+', context := '+natural(context)+',\n'
            '    classificationType := '+natural(classification)+', classificationCandidate := '+natural(class_candidate)+', classificationContext := '+natural(class_context)+',\n'
            '    classified := '+boolean(classified)+', obligations := '+numbers(obligations)+', accepted := '+boolean(accepted)+' }')
        out.append('#guard decide (CoreRule '+name+')')
        out.append('#guard receiptGate '+natural(expected_contract)+' '+natural(expected_candidate)+' '+natural(expected_context)+' '+name+' == '+boolean(gate))
    for parent,children,own in responsibilities:
        child_text='['+', '.join('evidence'+str(i) for i in children)+']'
        out.append('#guard decide (ResponsibilityRule evidence'+str(parent)+' '+child_text+' '+numbers(own)+')')
    for i,(root,context,edges,anchors,rhs,retained,mapping,accepted) in enumerate(boundaries):
        name='boundaryGraph'+str(i);out.append(graph(name,edges))
        anchor_text='['+', '.join('⟨'+natural(a)+', '+natural(c)+', 1, 1⟩' for a,c in anchors)+']'
        out.append('def boundaryRoots'+str(i)+' : List Anchor := '+anchor_text)
        lookup='boundaryReceipts'+str(i)
        out.append('def '+lookup+' : Nat → Receipt\n'+''.join('  | '+natural(key)+' => evidence'+str(row)+'\n' for key,row in mapping)+
            '  | _ => { typed := false, contract := 0, candidate := 0, context := 0, classificationType := 0, classificationCandidate := 0, classificationContext := 0, classified := false, obligations := [], accepted := false }')
        out.append('#guard (match Traversal.visit '+name+' '+natural(len(edges)+2)+' '+natural(root)+' [] [] with\n'
            '  | .error _ => false\n'
            '  | .ok done => match Correspondence.checkedBoundary done boundaryRoots'+str(i)+' '+numbers(rhs)+' '+numbers(retained)+' '+natural(root)+' '+natural(context)+' '+lookup+' with\n'
            '    | .ok _ => true | .error _ => false) == '+boolean(accepted))
    checked=[]
    for item in out:
        checked.append(item)
        if item.startswith('#guard '):
            expression=item[len('#guard '):]
            checked.append('example : ('+expression+') = true := by decide')
    out=checked
    out.append('end YuanxuProof.ModuleSystem.Schema.Association.NativeFixtures')
    Path(destination).write_text('\n\n'.join(out)+'\n')
    print('Generated',case_count,'native graph cases,',len(evidence),'real Core receipts,',gate_count,'RHS gates,',cycle_count,'cycle control;',sum(x.count('#guard') for x in out),'Lean guards.')

if __name__=='__main__':
    if len(sys.argv)!=3:raise SystemExit('usage: generate-native-fixtures.py TRANSCRIPT DESTINATION')
    main(sys.argv[1],sys.argv[2])
