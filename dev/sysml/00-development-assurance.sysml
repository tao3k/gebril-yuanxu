// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
package YuanxuDevelopment {
    private import ScalarValues::*;

    part def Architecture {
        attribute scope : String;
        attribute requirements : String;
        doc /* SysML owns boundaries and allocation, never runtime approval. */
    }
    part def TemporalAnalysis {
        attribute modelPath : String;
        attribute positiveRun : String;
        attribute counterexample : String;
        doc /* Existing dev/proofs/quint owner. Bounds must be explicit. */
    }
    part def SemanticProof {
        attribute theoremPath : String;
        attribute premises : String;
        attribute implementationProjection : String;
        doc /* Existing dev/proofs/lean and locked LeanPoo owner. */
    }
    part def RuntimeCorrespondence {
        attribute sourceRevision : String;
        attribute testEntry : String;
        attribute failureControls : String;
        doc /* Existing Just gate and native Scheme mechanisms, not a model runner. */
    }
    part def Measurement {
        attribute workloadIdentity : String;
        attribute processCount : Integer;
        attribute compileCount : Integer;
        attribute seconds : Real;
        attribute hostContext : String;
        doc /* Local/CI receipts; never commit raw logs or infer correctness from speed. */
    }
    part def Workstream {
        part architecture : Architecture;
        part temporal : TemporalAnalysis;
        part semantic : SemanticProof;
        part runtime : RuntimeCorrespondence;
        part measurement : Measurement;
        dependency transitions from architecture to temporal;
        dependency invariants from architecture to semantic;
        dependency correspondence from semantic to runtime;
        dependency negativeControls from temporal to runtime;
        dependency qualifiedCosts from runtime to measurement;
    }

    part efficientCaching : Workstream;
    part demandDrivenModuleLoading : Workstream;

    requirement def EvidenceBoundary {
        attribute runtimeClaimed : Boolean;
        attribute currentRuntimeVerified : Boolean;
        attribute proofClaimed : Boolean;
        attribute theoremChecked : Boolean;
        require constraint { not runtimeClaimed or currentRuntimeVerified }
        require constraint { not proofClaimed or theoremChecked }
    }
}
