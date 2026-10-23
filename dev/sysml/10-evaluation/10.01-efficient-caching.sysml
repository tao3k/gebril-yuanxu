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
