// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
package YuanxuCaching {
    private import ScalarValues::*;

    doc /* Development architecture model, not a new runtime cache protocol.
           Correspondence and limits: 10.01-efficient-caching.org. */

    part def Receiver {
        attribute identity : String;
        attribute revision : Integer;
        attribute selectedDemand : String;
    }

    part def ReadDependency {
        ref part receiver : Receiver;
        attribute slot : String;
        attribute issuedRevision : Integer;
        attribute producerIssued : Boolean;
        attribute transientMiss : Boolean;
        ref part dependencies : ReadDependency[0..*];
    }

    part def SelectionCostSample {
        attribute replayCalls : Integer;
        attribute visitedIssuedRecords : Integer;
        attribute physicalSourceReads : Integer;
        attribute sourceReadWindows : Integer;
        attribute wallSeconds : Real;
        attribute cpuSeconds : Real;
        attribute collectionCpuSeconds : Real;
        attribute collections : Integer;
        attribute rawAllocationDelta : Real;
        attribute allocationQualified : Boolean;
        attribute correctedVmAccount : Real;
        attribute gcWallSeconds : Real;
        attribute wallCpuResidual : Real;
        attribute minorFaults : Integer;
        attribute majorFaults : Integer;
        doc /* Costs are inclusive, not additive across nested spans. Replay
               counts do not imply latency; GC placement is independent. The
               installed VM's allocation stream is unqualified, even when a
               particular delta is positive. Never force GC in the probe. */
        doc /* exec-stats owns sample/frame corrections. A corrected VM
               account remains distinct from constructor payload. Preserve
               signed residual = wall - CPU; it is not proof of IO wait or
               scheduler delay. GC CPU is included in CPU, never added twice. */
    }

    part def Computation {
        ref part receiver : Receiver;
        ref part dependencies : ReadDependency[0..*];
        attribute completed : Boolean;
        attribute dependencyReplayCurrent : Boolean;
        doc /* Identity deduplication may share nodes, never erase edges or
               change observer order. A miss need not be retained as a value. */
    }

    part def AdmissionRetentionSample {
        attribute producerRevision : String;
        attribute kernelRevision : String;
        attribute survivingOriginalReads : Integer;
        attribute sharedEvidenceSchemaReads : Integer;
        attribute identityUnionBodyBytes : Integer;
        attribute receiverShellBodyBytes : Integer;
        attribute opaqueFrontiers : Integer;
        attribute processLiveBefore : Integer;
        attribute processLiveHeld : Integer;
        doc /* Compare the same producer, input and native workload. Classify
               descriptor preparation separately from candidate-owned receipts.
               Schema ownership is an overlapping partition of original reads,
               not an extra additive cost or a per-module multiplier. Compare
               whole source/library cohorts, never substituted ABI fragments.
               Native lengths with the installed ABI supply body bytes; identity union
               charges shared payload once. Code, type descriptors, opaque POO
               referents and GC-table policy remain explicit frontiers. Only
               environments belonging to the actual native issuer code family
               are traversed; arbitrary callback environments remain opaque.
               Malformed inspection edges fail the census, rather than being
               counted as successfully inspected payload. Header
               bytes, padding and exclusive/dominator size are not inferred.
               Process-wide post-GC deltas are a separate observation, never
               assigned to individual records. Neither census authorizes
               pruning a read edge, skipping a callback or reusing a verdict. */
    }

    requirement def ContextOnlyAdmission {
        attribute hasValueType : Boolean;
        attribute preparesValueAction : Boolean;
        require constraint { hasValueType or not preparesValueAction }
        doc /* The actual value-contract slot, not a purity tag, selects the
               value stage. Without a Type, pass the same child to contextual
               classification and obligations. Source entry/replay/return
               certification and both contribution requirements still run.
               Empty diagnostic decoration returns this call's fresh receipt;
               it is never a recovered approval from a previous admission. */
    }

    part def ReplayStructure {
        ref part orderedRoots : ReadDependency[0..*];
        ref part preorder : ReadDependency[0..*];
        ref part protectedReceivers : Receiver[0..*];
        attribute nativeOwner : Boolean;
        attribute exactSignedPayloads : Boolean;
        attribute weakOwnerPresent : Boolean;
        attribute orderedRootsMatch : Boolean;
        attribute constructorIdentitiesMatch : Boolean;
        doc /* Native issuer owns one private ordinary POO cache receiver.
               A weak key/value index only locates it; GC eviction rebuilds.
               Roots are copied after successful original DFS authentication.
               Hit: compare the ordered root snapshot, authenticate every saved
               record in original preorder, install the read-only receiver set.
               Changed receiver revisions do not turn shape into validity:
               fresh per-record and final checks must refuse stale records.
               Selected-closure congruence requires no unselected reads.
               A miss with changed native CLOS initializers uses the original
               uncached DFS; authentication never invokes that new callback. */
        doc /* Native derived value, NOT implemented in Core.
               Reuse requires the identical ordered root records and unchanged
               authenticated dependency sequences. Revision alone is insufficient.
               Never share mutable DFS seen state or a passing admission verdict.
               Keep current issuance/route checks, callback order, fresh dynamic
               protection frames and post-callback currentness on every replay. */
    }

    requirement def CompletedPublicationReplay {
        attribute sourceObserverPresent : Boolean;
        attribute preparationReplays : Integer;
        attribute admissionReplays : Integer;
        require constraint {
            admissionReplays == 1 and
            ((sourceObserverPresent and preparationReplays == 2) or
             (not sourceObserverPresent and preparationReplays == 1))
        }
        doc /* Non-void admission support only. Native issuer/checker ownership
               and revision-only policy are derived from private call sites,
               never supplied as user purity declarations. Keep preflight
               order; do not merge the two native authentication traversals. */
    }

    requirement def SourceQueryLookup {
        attribute sourceObserverPresent : Boolean;
        attribute hits : Integer;
        attribute misses : Integer;
        attribute nativeLookups : Integer;
        require constraint {
            (sourceObserverPresent and nativeLookups == 2 * hits + misses) or
            (not sourceObserverPresent and nativeLookups == hits + misses)
        }
        doc /* The existing pure source window is the only owner. A private
               absence identity distinguishes false from a miss. Open observers
               keep lookup/callback/lookup order. Never retain the window or a
               passing currentness verdict across effects or admissions. */
    }

    action def CheckCompletedPublication {
        first start;
        then checkLocation;
        action checkLocation;
        then checkPolicyBefore;
        action checkPolicyBefore;
        then replayPreparation;
        action replayPreparation;
        then replayAdmission;
        action replayAdmission;
        then checkPolicyAfter;
        action checkPolicyAfter;
        then keepObserverTailWhenPresent;
        action keepObserverTailWhenPresent;
        then done;
    }

    part def BuildPublication {
        attribute expectedHead : String;
        attribute selectedSourceIdentity : String;
        attribute compilerIdentity : String;
        attribute approvalReference : String;
        attribute sourceCurrent : Boolean;
        attribute approvalCurrent : Boolean;
        attribute productDigestsMatch : Boolean;
        attribute restored : Boolean;
        doc /* stage/submit! owns installation. The package approval is an
               external trust premise, not a candidate-controlled self-signature. */
    }

    part def TestDemand {
        ref part receiver : Receiver;
        ref part publication : BuildPublication;
        ref part makeLayout : MakeLayout;
        attribute unselectedDemands : Integer;
        attribute compileActions : Integer;
        attribute harnessRuns : Integer;
        attribute selectedInputsUnchanged : Boolean;
        attribute validApprovedProductsPresent : Boolean;
        attribute noNewCompilerDependency : Boolean;
        attribute nativeTimestampsStable : Boolean;
        attribute warmReuseAccepted : Boolean;
    }

    part def MakeLayout {
        attribute sourceRoot : String;
        attribute packagePrefix : String;
        attribute libraryRoot : String;
        attribute relativeTarget : String;
        attribute targetIsRelative : Boolean;
        attribute selectedSourceMatches : Boolean;
        attribute expectedProductMatchesProducer : Boolean;
        doc /* Derived from admitted identities and physical sources, never
               supplied as a user purity/freshness assertion. */
    }

    action def LookupReceiverCompletion {
        doc /* Actual Core path: receiver -> issuance owner -> publication.current
               -> graph-cache-ref completion -> group-closed -> closed-raw.
               A retained POO completion is not an external-source verdict.
               Measure this path separately from recovery and currentness. */
        first start;
        then getReceiverPublicationHead;
        action getReceiverPublicationHead;
        then readClosedGraphCompletion;
        action readClosedGraphCompletion;
        then checkEffectiveSourcesAndProducts;
        action checkEffectiveSourcesAndProducts;
        then done;
    }

    action def RecoverSelectedTests {
        doc /* The selection accessor performs its own complete admission.
               Private codec output is shared, never a successful verdict.
               End observation windows before Make, callbacks and Harness. */
        first start;
        then admitSelection;
        action admitSelection;
        then admitRequestedFiles;
        action admitRequestedFiles;
        then decodeApprovedInputOnce;
        action decodeApprovedInputOnce;
        then checkApprovalBytes;
        action checkApprovalBytes;
        then matchSelectedProjection;
        action matchSelectedProjection;
        then admitRestoredProducts;
        action admitRestoredProducts;
        then checkBeforeHandoff;
        action checkBeforeHandoff;
        then done;
    }

    requirement def MakeOutputCorrespondence {
        subject layout : MakeLayout;
        require constraint {
            layout.targetIsRelative and layout.selectedSourceMatches and
            layout.expectedProductMatchesProducer
        }
    }

    requirement def RecoveryIsNotAdmission {
        subject publication : BuildPublication;
        attribute accepted : Boolean;
        require constraint {
            not accepted or (publication.sourceCurrent and
                publication.approvalCurrent and publication.productDigestsMatch)
        }
    }

    requirement def ReceiverIsolation {
        attribute requestIdentity : String;
        attribute cachedIdentity : String;
        attribute reusedWithoutReprojection : Boolean;
        require constraint {
            not reusedWithoutReprojection or requestIdentity == cachedIdentity
        }
    }

    requirement def DemandOnly {
        subject demand : TestDemand;
        require constraint { demand.unselectedDemands == 0 }
    }

    requirement def WarmCompilation {
        subject demand : TestDemand;
        require constraint {
            not (demand.warmReuseAccepted and demand.selectedInputsUnchanged and
                 demand.validApprovedProductsPresent and demand.noNewCompilerDependency and
                 demand.nativeTimestampsStable)
            or demand.compileActions == 0
        }
    }

    requirement def VerdictIsNeverRestored {
        subject demand : TestDemand;
        attribute successfulExplicitRun : Boolean;
        require constraint {
            not successfulExplicitRun or demand.harnessRuns == 1
        }
    }

    state def PublicationStates {
        state unbound;
        state selected;
        state recovered;
        state building;
        state admitted;
        state running;
        state rejected;
        doc /* Transitions and effect fences are specified in the companion Org.
               'recovered' is never an authorization to execute or publish. */
    }

    action def WarmTest {
        first start;
        then bindDemand;
        action bindDemand;
        then projectMakeLayout;
        action projectMakeLayout;
        then recoverPublication;
        action recoverPublication;
        then checkBeforeMake;
        action checkBeforeMake;
        then nativeMake;
        action nativeMake;
        then checkAfterMake;
        action checkAfterMake;
        then runHarness;
        action runHarness;
        then checkBeforeReturn;
        action checkBeforeReturn;
        then done;
    }

    requirement def PublicationWindowOwnership {
        doc /* SourceWindows/ReturnWindows Lean own sound byte reuse, exact
               requirement composition and first-diagnostic preservation via
               ReplayBoundary. RootChild retains exact candidate/receiver and
               both requirements. QNT owns callback writes, fresh post-callback
               checks, independent admissions and matched stale-parent controls.
               Runtime phase/window events establish actual source correspondence;
               a phase name or observer label is never a purity certificate.
               Qualification tooling observes actual output from its owned
               backend as well as the CLI; progress never renews wall time.
               No successful admission or token-current verdict is reused. */
    }

    requirement def ReplayPhaseAccounting {
        doc /* Native call-with-issued-reads owns lookup, identity DFS and the
               immutable projection. SelectionReplay Lean proves exact selected
               preorder and native cache lookup refinement; QNT owns callbacks,
               eviction/mutation, frames and independent final certification.
               Acquisition includes fresh issuance, even on projection hits.
               Cold DFS interleaves issuance with traversal: measure that joint
               interval without regrouping checks or changing the first failure.
               Issuance and route/live-state microprobes run only on ORIGINAL
               issued records inside their native protected frame. Their batch
               costs are diagnostic, not additive slices of ordinary replay.
               Reuse shape and private receiver sets, NEVER a currentness or
               admission verdict. Install/unwind a fresh frame on every call.
               Runtime owns VM accounts, post-GC live deltas and weak identity
               survival; none independently gives exclusive SDK/procedure bytes.
               Diagnostic native builds are separate source cuts, not releases.
               Candidate: require-current! already issued the record; use the
               existing private route/live-state primitives immediately instead
               of calling a public predicate which issues it again. Lean owns
               first-error equivalence for the SAME closed native operation.
               No callback, observer or second record may intervene. Public
               standalone predicates retain their own issuance check; acquisition,
               before-visitor and final phases each remain freshly authenticated.
               The source-call graph, not a producer purity flag, supplies this
               native closed-operation premise. QNT still owns effect schedules. */
    }

    requirement def ReplayCostAttribution {
        doc /* Runtime owns repeated fixed-source ordinary 16/32 and service
               cohorts, plus separate diagnostic stage probes. Alternate source
               cuts across fresh processes; do not mix preparation with demand.
               Match emitted code and actual issuance multiplicity to each cut;
               copied-output mtimes alone do not establish producer identity.
               Report CPU including GC, GC CPU/wall, process switches, faults,
               block I/O and residual wall separately. A context-switch count
               is NOT elapsed scheduling time; GC and CPU are not additive.
               Measure the SAME original issuance payload with the diagnostic
               hook enabled and disabled inside its actual protected frame.
               A probe may allocate: do not attribute probe cost to the payload.
               Invalid VM allocation deltas stay invalid, not clamped. Weak
               identity survival and process-wide live bytes are not exclusive
               retained bytes. Retain original rejection controls and budgets.
               Lean owns ordered-query refinement and structural cache laws;
               existing QNT models own callback, eviction and frame schedules.
               Neither proves a host timing result. No new cache or verdict
               reuse is licensed by measurement or observer quieting. */
    }

    action def PublishWithSourceAdmission {
        first start;
        then checkEntry;
        action checkEntry;
        then analyzeRoot;
        action analyzeRoot {
            doc /* Retains source entry/exit, every child obligation and
                   contribution callback's independent before/after checks,
                   including the replaceable Context currentness callback.
                   Analysis is not an indivisible pure interval. */
        }
        then replayObservedSources;
        action replayObservedSources;
        then checkCollectedSources;
        action checkCollectedSources;
        then bindExactEvidence;
        action bindExactEvidence;
        then invokeBoundContract;
        action invokeBoundContract {
            doc /* Includes its output, dependent meaning and exact evidence
                   identity. Open meaning may write AFTER checking sources. */
        }
        then completeOuterInvocation;
        action completeOuterInvocation {
            doc /* Native metadata.publish still checks output and dependent
                   meaning after the bound invocation returns. Do not merge
                   these checks based on the meaning procedure's name. */
        }
        then done;
    }

    action def ColdTest {
        first start;
        then bindDemand;
        action bindDemand;
        then projectMakeLayout;
        action projectMakeLayout;
        then nativeMakeInOwnedStaging;
        action nativeMakeInOwnedStaging;
        then verifyProducts;
        action verifyProducts;
        then submitPublication;
        action submitPublication;
        then runHarness;
        action runHarness;
        then checkBeforeReturn;
        action checkBeforeReturn;
        then done;
    }
}
