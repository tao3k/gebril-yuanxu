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
        doc /* QNT owns transition ordering, interleavings, callback gaps,
               invalidation and recovery traces. Bounds must be explicit.
               Do not duplicate Lean value equalities as finite state cases. */
    }
    part def SemanticProof {
        attribute theoremPath : String;
        attribute premises : String;
        attribute implementationProjection : String;
        doc /* Lean/locked LeanPoo owns universal structural and semantic
               properties: identities, exact edges, lookup equivalence and
               sharing preconditions. Do not restate an existing transition
               model merely to provide a second tool's badge. */
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
        // Allocate by the question; a workstream need not create both models.
        part temporal : TemporalAnalysis [0..1];
        part semantic : SemanticProof [0..1];
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

    requirement def SingleProofOwner {
        doc /* Each claim has one primary formal owner. Structural sharing is
               owned by PayloadSharing.lean. Temporal callback/currentness and
               invalidation claims reference existing IssuedRootForwarding,
               ReadRetention and IncrementalRoles QNT models. Cross references
               do not require copying their state or tests into PayloadSharing.
               Runtime correspondence and measured memory remain separate
               obligations; neither formal tool certifies physical heap cost. */
    }

    requirement def EvidenceBoundary {
        attribute runtimeClaimed : Boolean;
        attribute currentRuntimeVerified : Boolean;
        attribute proofClaimed : Boolean;
        attribute theoremChecked : Boolean;
        require constraint { not runtimeClaimed or currentRuntimeVerified }
        require constraint { not proofClaimed or theoremChecked }
    }
}
