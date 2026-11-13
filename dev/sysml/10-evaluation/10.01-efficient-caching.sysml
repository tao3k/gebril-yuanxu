// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
package YuanxuCaching {
    private import ScalarValues::*;

    doc /* Development architecture model, not a new runtime cache protocol.
           Correspondence and limits: 10.01-efficient-caching.org.
           First-demand algorithm decision and producer obligations:
           10.08-first-demand-algorithm-review.org. Filesystem source policy,
           C4 ancestry, issued-read dependencies and Module dependencies
           retain distinct meanings even when they share POO indexes. */

    requirement def BoundedStageAccounting {
        attribute stagesEnabled : Boolean;
        attribute initializerFamilyCount : Integer;
        attribute initializerPathsRetained : Boolean;
        attribute exactOwnerScopeCounts : Boolean;
        attribute sameResultsAndErrors : Boolean;
        attribute sameAdmissionChecks : Boolean;
        require constraint {
            not stagesEnabled or
                (initializerFamilyCount >= 0 and initializerFamilyCount <= 2
                 and not initializerPathsRetained
                 and exactOwnerScopeCounts and sameResultsAndErrors
                 and sameAdmissionChecks)
        }
        doc /* Fixed initializer stage families accumulate the same actual
               measurements without retaining a metric family per path.
               Explicit detailed mode keeps source paths; owner-qualified
               scope counts remain distinct in every mode. This affects
               diagnostics only, never source admission or currentness.
               TestingCase.StageSummary proves the key projection and exact
               scope counts; see 10.09-bounded-stage-accounting.org. */
    }

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

    part def ComponentSourceCut {
        attribute sourceIdentity : String;
        attribute sourceRevision : Integer;
        attribute issuedConstructionIdentity : String;
        doc /* One native issuance binds the ordered owner roster and exact
               program, base and dependency rows. Equal revision numbers
               alone do not authenticate a construction. Detached topology
               contributes only owner and dependency rows. Its Graph cut
               is distinct from the upstream source admission. */
    }

    part def DirectSingletonMethod {
        ref part receiver : Receiver;
        attribute slot : String;
        attribute preparedRevision : Integer;
        doc /* One direct constant or self SlotSpec on an ancestor-free
               receiver without hooks, defaults or declarations can use one
               existing method cell. The thunk captures the constant payload
               or final receiver. Value storage, read issuance and
               invalidation remain receiver-owned. */
    }

    requirement def PackedPreparedMethods {
        attribute usesPackedDirectory : Boolean;
        attribute stockPreparationComplete : Boolean;
        attribute sameEffectiveThunks : Boolean;
        attribute sameReceiverValueStore : Boolean;
        attribute sameIssuedReads : Boolean;
        attribute exposesMethodTable : Boolean;
        attribute usesExposedTableAfterReturn : Boolean;
        require constraint {
            not usesPackedDirectory or
                (stockPreparationComplete and sameEffectiveThunks
                 and sameReceiverValueStore and sameIssuedReads
                 and (not exposesMethodTable or usesExposedTableAfterReturn))
        }
        doc /* A small completed method directory may retain keys and compiled
               thunks in a private array. The original method table is
               materialized upon exposure. Later reads use that table,
               including supported changes to uncomputed methods.
               Existing hook and refusal order precede storage selection. */
    }

    requirement def AdmissionKnowledgeBoundary {
        attribute acceptedUnknownAudit : Boolean;
        attribute independentRequiredFacts : Integer;
        attribute executedFactReads : Integer;
        attribute usesConstructorClassification : Boolean;
        attribute derivesFactsFromActualRecipes : Boolean;
        attribute coversActualWriterAndExposureRoutes : Boolean;
        attribute checksSharedRuntimeMetadata : Boolean;
        require constraint {
            independentRequiredFacts >= 0 and executedFactReads >= 0
            and (not acceptedUnknownAudit or
                 executedFactReads >= independentRequiredFacts)
            and (not usesConstructorClassification or
                 (derivesFactsFromActualRecipes
                  and coversActualWriterAndExposureRoutes
                  and checksSharedRuntimeMetadata))
        }
        doc /* AdmissionBoundary proves the adaptive unknown-input read bound
               and the strictly narrower generated-recipe classification law.
               These attributes are source correspondence obligations, never
               caller-controlled approval flags. Generated classification does
               not certify arbitrary raw sources, payload capture time, author
               hooks or mutable shared metadata. Charge source construction in
               the complete first request. See 10.13 for the existing
               object<-fun producer, required point-path representation and
               unchanged effect/reflection boundaries. */
    }

    requirement def IndexedPointDemand {
        attribute usedPointPreparation : Boolean;
        attribute stockPreparationCertified : Boolean;
        attribute sourceCurrent : Boolean;
        attribute exactOrderedKeySet : Boolean;
        attribute capturesAtAdmittedRevision : Boolean;
        attribute borrowedSourceIndexes : Boolean;
        attribute sameOrderedPayloadProjection : Boolean;
        attribute receiverLocalValues : Boolean;
        attribute unrelatedBindings : Integer;
        require constraint {
            not usedPointPreparation or
                (stockPreparationCertified and sourceCurrent and exactOrderedKeySet
                 and capturesAtAdmittedRevision and borrowedSourceIndexes
                 and sameOrderedPayloadProjection and receiverLocalValues
                 and unrelatedBindings == 0)
        }
        doc /* First demand binds only the reached effective methods and uses
               the ordinary receiver-owned value and read state. The source
               issuer must cover preparation failures in unrelated siblings.
               Reflection keeps the full key order. Gerbil expansion and author
               callbacks retain independent effect checks. Correspondence and
               open issuer proof are in 10.07-first-business-demand.org.
               LeanPoo.Object.IndexedPlan.prepareKey_sound and prepareKey_frame
               cover one unbound method for arbitrary final self. Concrete
               other-key slot/default edits preserve its ordered projection.
               This does not authorize reusing values or freezing mutable
               SlotSpec payloads before ordinary capture. The inherited-source
               native issuer obligation is recorded in 10.08 and the concrete
               compute-slot-funs! audit in 10.10. A sealed receiver alone does
               not certify every mutable SlotSpec or ancestor. The source
               issuer must bind payload capture and rejection order to the
               actual preparation cut, not accept a caller purity flag.
               Component schedule/SCC indexes do not by themselves implement
               this prototype preparation or slot-level invalidation. Whole
               source certification remains charged in the first-request
               total even when performed by import or init.
               CapturedBinding.newest_callable_exact and
               all_keys_refusal_exact permit hook-free callable preflight
               without eager receiver binding after actual payload capture.
               The hook-repair counterexample requires the ordinary hookful
               path. Pending and bound methods must remain states of the
               existing method store: preserve procedure identity/arity,
               reflection, retry and concurrent publication, and never cache
               business results in a parallel evaluator or store. These
               native representation obligations remain open. */
    }

    requirement def AdmittedNamespacePointWork {
        attribute usesPointWork : Boolean;
        attribute sourceViewAuthenticated : Boolean;
        attribute requiredWindowPolicyPreserved : Boolean;
        attribute ownerAndDependencyClosureExact : Boolean;
        attribute independentEffectChecksPreserved : Boolean;
        attribute unrelatedBranchIndexRebuilds : Integer;
        attribute unrelatedReceiverValueCells : Integer;
        require constraint {
            not usesPointWork or
                (sourceViewAuthenticated and requiredWindowPolicyPreserved
                 and ownerAndDependencyClosureExact and independentEffectChecksPreserved
                 and unrelatedBranchIndexRebuilds == 0
                 and unrelatedReceiverValueCells == 0)
        }
        doc /* Applies to an already admitted source view. A point lookup
               cannot establish a whole-window verdict over unobserved
               siblings of an unknown mutable directory. Preserve the
               original collision and symlink refusal order when that
               verdict is required. Charge source admission, indexing and
               any required complete listing separately in the first
               request. A complete SCC computation consumes captured Graph
               rows and cannot supply this source authority. See 10.13
               for the staged Core evidence and the unproved native
               correspondence. */
    }

    requirement def DirectoryListingReplay {
        attribute orderedInitialPolicy : Boolean;
        attribute admitsListing : Boolean;
        attribute exactObservedMultiplicity : Boolean;
        attribute independentEffectsChecked : Boolean;
        attribute sharesLexicalListing : Boolean;
        attribute rawKindChecked : Boolean;
        attribute sameClosedWindow : Boolean;
        attribute lexicalListingEquivalent : Boolean;
        require constraint {
            orderedInitialPolicy and independentEffectsChecked and
                (not admitsListing or exactObservedMultiplicity) and
                (not sharesLexicalListing or
                    (rawKindChecked and sameClosedWindow and lexicalListingEquivalent))
        }
        doc /* SourceWindows.sameDirectoryListing_eq_sorted allows an exact
               raw sequence hit to skip lexical sorting.
               SourceWindows.directoryAlias_value and directoryAlias_repeat
               distinguish raw kind checks from a shared listing key.
               Initial refusal order and independent source observations
               still apply. */
    }

    requirement def ReceiverValueLayoutExposure {
        attribute exposesDenseLayout : Boolean;
        attribute usesLivePopulatedCells : Boolean;
        attribute keepsPrimaryStoreIdentity : Boolean;
        attribute sameCanonicalOffsets : Boolean;
        attribute missingColdAndFalsePreserved : Boolean;
        attribute pointPayloadRetired : Boolean;
        require constraint {
            not exposesDenseLayout or
                (usesLivePopulatedCells and keepsPrimaryStoreIdentity
                 and sameCanonicalOffsets and missingColdAndFalsePreserved
                 and pointPayloadRetired)
        }
        doc /* PointLayout.Primary.exposeLive models the sole primary
               payload replacement. A value write can occur without a
               receiver revision change. An early copy with the same
               origin cannot justify exposure after that write. The local
               Scheme prototype retains the exact layout and HashTable
               identity through exposure and authenticates a point payload
               before read replay. See 10.13 for the native controls and
               the remaining first-request qualification. */
    }

    requirement def OrderedPointPreparation {
        attribute selectedPointPath : Boolean;
        attribute exactContributionMultiplicity : Boolean;
        attribute chronologicalSameKeyContributions : Boolean;
        attribute separateDefaultPass : Boolean;
        attribute originalPreparationRefusals : Boolean;
        attribute sourceCaptureAuthorized : Boolean;
        attribute preservesFinalSelfAndDelayedSup : Boolean;
        attribute reusesExistingNamePositionIndex : Boolean;
        attribute unrelatedReceiverMethodBindings : Integer;
        attribute unrelatedReceiverValueCells : Integer;
        require constraint {
            not selectedPointPath or
                (exactContributionMultiplicity and chronologicalSameKeyContributions
                 and separateDefaultPass and originalPreparationRefusals
                 and sourceCaptureAuthorized and preservesFinalSelfAndDelayedSup
                 and reusesExistingNamePositionIndex
                 and unrelatedReceiverMethodBindings == 0
                 and unrelatedReceiverValueCells == 0)
        }
        doc /* Refinement obligations on existing POO preparation, not caller
               purity switches. Source evidence must be issued by the actual
               preparation owner. Object.OrderedContributions proves the
               ordered-bucket fold (LeanPoo 3f8ca515, complete CI passed);
               POO c463add8 supplies the index primitive, not the source
               issuer or complete point preparation. These laws do not supply
               that native issuer. Existing Scheme names/ordinal indexes
               retain duplicate contributions; first-only/last-write-wins
               lookup cannot replace their sup chain. Sparse value storage
               must avoid make-slot-values over the whole key directory.
               Complete reflection remains explicitly charged. The local
               functional thunk cut removes the all-key method table and still
               uses the complete default vector layout. That experiment leaves
               full point preparation and value storage open. See 10.10 and 10.12. */
    }

    requirement def GeneratedPrototypeBulkIndexes {
        attribute usesBulkConstruction : Boolean;
        attribute sourceRowsOwned : Boolean;
        attribute ordinalOrderExact : Boolean;
        attribute symbolIdentityBucketsExact : Boolean;
        attribute scratchNotPublished : Boolean;
        attribute persistentUpdatesPreserved : Boolean;
        require constraint {
            not usesBulkConstruction or
                (sourceRowsOwned and ordinalOrderExact and symbolIdentityBucketsExact
                 and scratchNotPublished and persistentUpdatesPreserved)
        }
        doc /* Build the stock ordinal and name RBTree once from owned rows.
               Representation.BulkOrder proves position coverage and black
               height. OrderedContributions supplies the same-name ordinal
               laws. Neither proof waives source admission. See 10.13 for
               the matching Scheme fault and measured construction work. */
    }

    requirement def ConstructorOwnedSourceCapture {
        attribute borrowsGeneratedCut : Boolean;
        attribute actualConstructorFormsAdmitted : Boolean;
        attribute reusesSingleReadAuthority : Boolean;
        attribute sourceAndValueEvidenceRemainDistinct : Boolean;
        attribute nativeAllocationIdentity : Boolean;
        attribute allRawExposureRoutesCovered : Boolean;
        attribute standardRuntimeMopRoutesCovered : Boolean;
        attribute sharedRawStorageIdentityPreserved : Boolean;
        attribute aliasExposureRevokesNewIssuance : Boolean;
        attribute exactOrdinalCutBoundToView : Boolean;
        attribute ownerMultiplicityDerivedFromRows : Boolean;
        attribute sharedKernelMetadataCurrent : Boolean;
        attribute captureFencePreservesPreparedMethods : Boolean;
        attribute exposurePrecedesHandleReturn : Boolean;
        attribute rawWriteRequiresExposedHandle : Boolean;
        attribute newIssuanceRevokedAfterExposure : Boolean;
        attribute preparedReceiverSnapshotPreserved : Boolean;
        attribute retainedCaptureBorrowed : Boolean;
        attribute independentEffectChecksPreserved : Boolean;
        require constraint {
            not borrowsGeneratedCut or
                (actualConstructorFormsAdmitted and reusesSingleReadAuthority
                 and sourceAndValueEvidenceRemainDistinct and nativeAllocationIdentity
                 and allRawExposureRoutesCovered and standardRuntimeMopRoutesCovered
                 and sharedRawStorageIdentityPreserved and aliasExposureRevokesNewIssuance
                 and exactOrdinalCutBoundToView and ownerMultiplicityDerivedFromRows
                 and sharedKernelMetadataCurrent and captureFencePreservesPreparedMethods
                 and exposurePrecedesHandleReturn
                 and rawWriteRequiresExposedHandle and newIssuanceRevokedAfterExposure
                 and preparedReceiverSnapshotPreserved and retainedCaptureBorrowed
                 and independentEffectChecksPreserved)
        }
        doc /* SourcePreparation derives coverage from allocation/exposure/write
               transitions, not a caller-supplied private marker. Borrowing an
               old prepared receiver's recipes is not authority for a new
               capture after raw mutation. Source identity is native allocation,
               not package revision or another source digest. Native lowering,
               raw identity and complete escape coverage remain open. Standard
               Gerbil MOP is an available route, not an unsafe-FFI exemption:
               an unmarked runtime field write preserves allocation identity
               and an exposure flag while breaking captured-field equality.
               The local SourcePreparation runtime_bypass counterexamples
               rule out an exposure-bit-only issuer. Existing
               clone views can share untouched SlotSpec identities. Exposure
               through any alias must fence the shared storage owner, while
               preserving already prepared receiver snapshots. A view-local
               flag or namespace identity alone cannot do this. Existing
               SourceViews derives exact replacement/batch registration and
               the old Graph row frame. Duplicate keys can retain an owner;
               counts cannot authenticate distinct view ordinals. Source
               eligibility fences govern new capture, not an old receiver's
               immutable methods. See 10.12. Existing
               source preparation must reuse the one existing issuer and the
               lower structural index implementation, not allocate a source
               registry. Sharing authority must not admit source certificates
               as ordinary receiver value reads. The local dependency move
               supplies neither source grammar nor point execution by itself.
               Existing
               read-route authentication requires the actual cells vector;
               sparse storage cannot bypass that guard. See 10.10. */
    }

    requirement def BoundedStageAccounting {
        attribute stagesEnabled : Boolean;
        attribute initializerFamilyCount : Integer;
        attribute initializerPathsRetained : Boolean;
        attribute exactOwnerScopeCounts : Boolean;
        attribute sameResultsAndErrors : Boolean;
        attribute sameAdmissionChecks : Boolean;
        require constraint {
            not stagesEnabled or
                (initializerFamilyCount >= 0 and initializerFamilyCount <= 2
                 and not initializerPathsRetained
                 and exactOwnerScopeCounts and sameResultsAndErrors
                 and sameAdmissionChecks)
        }
        doc /* Fixed initializer stage families accumulate the same actual
               measurements without retaining a metric family per path.
               Explicit detailed mode keeps source paths; owner-qualified
               scope counts remain distinct in every mode. This affects
               diagnostics only, never source admission or currentness.
               TestingCase.StageSummary proves the key projection and exact
               scope counts; see 10.09-bounded-stage-accounting.org. */
    }

    requirement def ProtocolSelectionSharing {
        attribute usedSharedSelection : Boolean;
        attribute actualProtocolAbsent : Boolean;
        attribute nativeWriteFrameDerived : Boolean;
        attribute sameFinalEnumeration : Boolean;
        attribute sameAdmissionOrder : Boolean;
        attribute sameErrorsAndFinalState : Boolean;
        attribute emptySetAddsNoSelection : Boolean;
        attribute singleSetUsesOriginalSelection : Boolean;
        attribute declarationsAlreadyCompleted : Boolean;
        attribute payloadsAlreadyCaptured : Boolean;
        require constraint {
            not usedSharedSelection or
                (actualProtocolAbsent and nativeWriteFrameDerived
                 and sameFinalEnumeration and sameAdmissionOrder
                 and sameErrorsAndFinalState and emptySetAddsNoSelection
                 and singleSetUsesOriginalSelection
                 and declarationsAlreadyCompleted and payloadsAlreadyCaptured)
        }
        doc /* POO's final method installation can share one actual absent
               protocol selection instead of scanning C4 for every slot only
               when every intervening native operation preserves absence.
               Gerbil HashTable.set! and for-each are dispatch points, not
               automatically pure because a POO protocol is absent. Derive
               the frame from the selected runtime route or keep the original
               per-slot selection. No caller purity tag or stored successful
               verdict supplies this authority. SlotPreparation's
               EffectfulAdmission.without_hooks_exact proves the framed
               equivalence; initial_absence_is_insufficient rejects hoisting
               over a write that installs a protocol. The guarded adapter
               compares the selected symbolic primitive, wrapper/backend,
               hash/test and lock before sharing; changed routes retain
               dynamic selection. Producer controls and the independent
               Module qualification limits are recorded in 10.08. */
    }

    requirement def FactorySlotExposure {
        attribute rawSlotsExposed : Boolean;
        attribute preparedBeforeExposure : Boolean;
        attribute methodsCapturedBeforeReturn : Boolean;
        attribute sameRevision : Boolean;
        attribute sameValueStore : Boolean;
        attribute sameIssuedReadIndex : Boolean;
        require constraint {
            not rawSlotsExposed or
                (sameRevision and sameValueStore and sameIssuedReadIndex
                 and (preparedBeforeExposure == methodsCapturedBeforeReturn))
        }
        doc /* Cold exposure retains the mutable SlotSpecs for ordinary later
               preparation. After preparation, expose only after capturing
               all effective methods from the private source, including slots
               that have never been demanded. Exposed references stay in
               chronological order and are reused on subsequent inspection.
               A later supported edit owns invalidation and recapture. */
    }

    requirement def DirectoryPolicyReuse {
        attribute reusedPolicy : Boolean;
        attribute currentHead : Boolean;
        attribute exactAffectedOrder : Boolean;
        attribute untouchedFactsTransported : Boolean;
        attribute wholeRosterVisits : Integer;
        require constraint {
            not reusedPolicy or
                (currentHead and exactAffectedOrder and untouchedFactsTransported
                 and wholeRosterVisits == 0)
        }
        doc /* A checked source edit transports untouched policy evidence to
               the new cut and rechecks the indexed affected facts in the
               reference refusal order. Without this authority the guarded
               full policy pass supplies missing facts. The Lean
               NamespaceProjection proof states the transport premise
               independently of how the runtime retrieves affected facts. */
    }

    requirement def ReverseBucketDemand {
        attribute indexedWideBucket : Boolean;
        attribute sameLiveOrder : Boolean;
        attribute oldSnapshotUnchanged : Boolean;
        attribute liveBaseEntries : Integer;
        attribute skippedDeletedRuns : Integer;
        require constraint {
            not indexedWideBucket or
                (sameLiveOrder and oldSnapshotUnchanged
                 and skippedDeletedRuns <= liveBaseEntries + 1)
        }
        doc /* POO Graph's ordered inverse cursor over a wide bucket emits
               the same surviving readers. Revision-owned run endpoints
               join adjacent deletions. A cursor can cross one deleted run
               at a time, keeping its position when suspended. */
    }

    requirement def FactoryValueLayoutPublication {
        attribute layoutPublished : Boolean;
        attribute sameLayout : Boolean;
        attribute sameValueStore : Boolean;
        attribute sameRevision : Boolean;
        attribute preservedValues : Boolean;
        attribute completeOffsets : Boolean;
        require constraint {
            not layoutPublished or
                (sameLayout and sameValueStore and sameRevision
                 and preservedValues and completeOffsets)
        }
        doc /* Offset demand publishes the shape and cells in the receiver's
               existing layout. Preserve absent and false values and offsets
               for declared and previously written dynamic keys. Read replay
               authenticates the published representation without exposing or
               constructing the shape. */
    }

    requirement def DirectDirectoryOwnerKey {
        attribute reusedRootKey : Boolean;
        attribute closedRootObservation : Boolean;
        attribute implicitDirectOwner : Boolean;
        attribute exactChildSpelling : Boolean;
        attribute originalOwnerOrder : Boolean;
        attribute freshRootPathGuard : Boolean;
        attribute independentObservationWindow : Boolean;
        require constraint {
            not reusedRootKey or
                (closedRootObservation and implicitDirectOwner and exactChildSpelling
                 and originalOwnerOrder and freshRootPathGuard and independentObservationWindow)
        }
        doc /* A checked literal child can use the canonical root and its
               physical directory name. Other owner rows use native path
               normalization. Root and owner refusals preserve their original
               priority. Denied declarations still claim their directory.
               An enclosing source-read window retains native normalization.
               NamespaceProjection.owner_and_directory_refusals_exact relates
               this order to the shared child-kind snapshot. */
    }

    requirement def DirectoryKindObservationReuse {
        attribute reusesKind : Boolean;
        attribute closedSourceObservation : Boolean;
        attribute collisionRefusalFirst : Boolean;
        attribute firstLinkRefusalPreserved : Boolean;
        require constraint {
            not reusesKind or
                (closedSourceObservation and collisionRefusalFirst and firstLinkRefusalPreserved)
        }
        doc /* The two policies share a child-kind observation within one
               directory snapshot. NamespaceProjection.directory_link_refusal_exact
               relates the reduced probe sequence to source-order link refusal.
               Later location and publication checks have independent authority. */
    }

    requirement def SharedSourceInputObservation {
        attribute reusedObservation : Boolean;
        attribute exactExpectedInput : Boolean;
        attribute sameObservationAtEveryUse : Boolean;
        require constraint {
            not reusedObservation or (exactExpectedInput and sameObservationAtEveryUse)
        }
        doc /* PublicationReads.shared_source_input_exact equates per-owner
               validation with a single shared input check under this premise.
               Recheck at Gerbil expansion and author effect boundaries when
               the source can change. Source identity and read-index overlap
               alone do not establish the premise. Without authenticated
               revision authority the exact comparison covers the full input.
               PublicationReads.exact_source_probe_iff_complete characterizes
               this coverage for arbitrary same-size edits. */
    }

    requirement def SelectedComponentProjection {
        attribute usesSelectedRows : Boolean;
        attribute effectiveRootsIncluded : Boolean;
        attribute reachedRowsExact : Boolean;
        attribute providersClosed : Boolean;
        attribute rootPolicyChecked : Boolean;
        require constraint {
            not usesSelectedRows or
                (effectiveRootsIncluded and reachedRowsExact
                 and providersClosed and rootPolicyChecked)
        }
        doc /* TestAdmission.admitted_rows_component_exact preserves mutual
               reachability inside the selected forward-closed Graph. Root
               policy has independent authority. Updates retain the old
               Graph's registrations for consumers outside the demand. */
    }

    requirement def IssuedComponentCapture {
        attribute issuedRoute : Boolean;
        attribute accepted : Boolean;
        attribute sameCut : Boolean;
        attribute entryCurrent : Boolean;
        attribute returnCurrent : Boolean;
        attribute liveAtInstallation : Boolean;
        require constraint {
            not (issuedRoute and accepted) or
                (sameCut and entryCurrent and returnCurrent and liveAtInstallation)
        }
        doc /* The Graph can hand an existing issued source to SCC packing.
               Its first capture still observes unknown producers. SCC row
               normalization preserves last duplicate occurrence and the
               resulting order of provider refusals.
               Stale or failed capture retains the authoritative live head.
               Lean and Scheme boundaries are recorded in
               10.07-first-business-demand.org. */
    }

    requirement def CompactSourceRegistration {
        attribute usedSingletonFrame : Boolean;
        attribute accepted : Boolean;
        attribute wholeIssuanceChecked : Boolean;
        attribute oneExactReceiver : Boolean;
        attribute beforeCurrent : Boolean;
        attribute afterCurrent : Boolean;
        attribute sameExternalWeakEdge : Boolean;
        require constraint {
            not (usedSingletonFrame and accepted) or
                (wholeIssuanceChecked and oneExactReceiver and beforeCurrent
                 and afterCurrent and sameExternalWeakEdge)
        }
        doc /* A single issued root and optional leaf parent on the same
               receiver use that receiver as the protected frame. The weak
               source edge is registered only after admission. The return
               check is independent. Wider traversals keep the receiver set. */
    }

    requirement def SharedAuthoringProfileReplay {
        attribute accepted : Boolean;
        attribute reusesSharedTopology : Boolean;
        attribute originalProfileReceipt : Boolean;
        attribute sharedRecordsCheckedAtCurrentCut : Boolean;
        attribute ownerRecordsCheckedAtCurrentCut : Boolean;
        attribute preservesRefusalOrder : Boolean;
        require constraint {
            not (accepted and reusesSharedTopology) or
                (originalProfileReceipt and sharedRecordsCheckedAtCurrentCut
                 and ownerRecordsCheckedAtCurrentCut and preservesRefusalOrder)
        }
        doc /* The default authoring Profile contributes a shared signed
               subtree to separate owner-local preparations. An independent
               effect can alter a shared record while the local records
               remain current. Topology sharing does not carry an approval
               into the next check. The complete publication-root merge in
               source/link.ss and the unconnected owner-demand boundary are
               audited in 10.10-first-demand-implementation-obligations.org;
               no narrower replay is authorized by this requirement. */
    }

    requirement def ScopedPublicationEvidence {
        attribute usesScopedProjection : Boolean;
        attribute exactSelectedDependencyClosure : Boolean;
        attribute completeSharedPolicyFacts : Boolean;
        attribute samePublishedBundleAndTicket : Boolean;
        attribute originalIssuedRoots : Boolean;
        attribute independentEffectChecks : Boolean;
        attribute representsWholeGraphApproval : Boolean;
        require constraint {
            not usesScopedProjection or
                (exactSelectedDependencyClosure and completeSharedPolicyFacts
                 and samePublishedBundleAndTicket and originalIssuedRoots
                 and independentEffectChecks and not representsWholeGraphApproval)
        }
        doc /* ScopeProjection.projected_current_exact proves this scoped
               contract; its counterexample forbids claiming whole-graph
               approval. Runtime integration remains open in 10.11. */
    }

    requirement def TrackedOwnerCertificateTransport {
        attribute transportsCurrentness : Boolean;
        attribute actualReadReceiverRegistrationComplete : Boolean;
        attribute nativeWriterCoversAllChanges : Boolean;
        attribute oldReverseClosureComplete : Boolean;
        attribute sameImmutableRootCut : Boolean;
        attribute unknownEffectsKeepOrdinaryChecking : Boolean;
        require constraint {
            not transportsCurrentness or
                (actualReadReceiverRegistrationComplete and nativeWriterCoversAllChanges
                 and oldReverseClosureComplete and sameImmutableRootCut
                 and unknownEffectsKeepOrdinaryChecking)
        }
        doc /* These are producer-derived proof obligations, not runtime
               flags supplied by an owner. TrackedEdit proves transport and
               counterexamples for incomplete registration/untracked writes.
               Native witness stamps alone do not establish the frame. */
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
        doc /* Compare the same producer, input and runtime workload. Classify
               descriptor preparation separately from candidate-owned receipts.
               Schema ownership is an overlapping partition of original reads,
               not an extra additive cost or a per-module multiplier. Compare
               whole source/library cohorts, never substituted ABI fragments.
               Runtime lengths with the installed ABI supply body bytes; identity union
               charges shared payload once. Code, type descriptors, opaque POO
               referents and GC-table policy remain explicit frontiers. Only
               environments belonging to the actual runtime issuer code family
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
        attribute runtimeOwner : Boolean;
        attribute exactSignedPayloads : Boolean;
        attribute weakOwnerPresent : Boolean;
        attribute orderedRootsMatch : Boolean;
        attribute constructorIdentitiesMatch : Boolean;
        doc /* Runtime issuer owns one private ordinary POO cache receiver.
               A weak key/value index only locates it; GC eviction rebuilds.
               Roots are copied after successful original DFS authentication.
               Hit: compare the ordered root snapshot, authenticate every saved
               record in original preorder, install the read-only receiver set.
               Changed receiver revisions do not turn shape into validity:
               fresh per-record and final checks must refuse stale records.
               Selected-closure congruence requires no unselected reads.
               A miss with changed runtime CLOS initializers uses the original
               uncached DFS; authentication never invokes that new callback. */
        doc /* Runtime derived value, NOT implemented in Core.
               Reuse requires the identical ordered root records and unchanged
               authenticated dependency sequences. Revision alone is insufficient.
               Never share mutable DFS seen state or a passing admission verdict.
               Keep current issuance/route checks, callback order, fresh dynamic
               protection frames and post-callback currentness on every replay. */
    }

    requirement def IssuedReceiverRouteMarkers {
        attribute usesMarkers : Boolean;
        attribute completeIssuanceBeforeRoutes : Boolean;
        attribute preflightAndSweepShareCut : Boolean;
        attribute originalPreorder : Boolean;
        attribute firstNonBootstrapPerReceiver : Boolean;
        attribute everyKeyAndLiveStateChecked : Boolean;
        attribute freshRoutesAtEachBoundary : Boolean;
        require constraint {
            not usesMarkers or
                (completeIssuanceBeforeRoutes and preflightAndSweepShareCut
                 and originalPreorder and firstNonBootstrapPerReceiver
                 and everyKeyAndLiveStateChecked and freshRoutesAtEachBoundary)
        }
        doc /* LeanPoo.Object.ReadRouteRuns.marked_eq_serial proves one closed
               sweep's refusal equivalence. marked_checkpoint_eq_serial keeps
               the independent return sweep after an effect. Markers describe
               receiver occurrence, with fresh route authentication on each use.
               native_fixed_refusals_exact and native_preflight_skip_exact
               include the complete issuance preflight before any route check.
               A proposed warm native topology lookup could supply this
               preflight to the immediately following indexed sweep. The
               candidate remains local. Cold construction and nonidentity
               conversion retain their entry protocol.
               native_callback_return_exact keeps return issuance independent
               after an arbitrary effect. Callback delivery continues to
               authenticate each actual read. The issuer compares structural
               read keys against its own issuance snapshot. */
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
        doc /* Non-void admission support only. Runtime issuer/checker ownership
               and revision-only policy are derived from private call sites,
               never supplied as user purity declarations. Keep preflight
               order; do not merge the two runtime authentication traversals. */
    }

    requirement def SourceQueryLookup {
        attribute sourceObserverPresent : Boolean;
        attribute hits : Integer;
        attribute misses : Integer;
        attribute runtimeLookups : Integer;
        require constraint {
            (sourceObserverPresent and runtimeLookups == 2 * hits + misses) or
            (not sourceObserverPresent and runtimeLookups == hits + misses)
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
        attribute runtimeTimestampsStable : Boolean;
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
                 demand.runtimeTimestampsStable)
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
        then runtimeMake;
        action runtimeMake;
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
        doc /* Runtime call-with-issued-reads owns lookup, identity DFS and the
               immutable projection. SelectionReplay Lean proves exact selected
               preorder and runtime cache lookup refinement; QNT owns callbacks,
               eviction/mutation, frames and independent final certification.
               Acquisition includes fresh issuance, even on projection hits.
               Cold DFS interleaves issuance with traversal: measure that joint
               interval without regrouping checks or changing the first failure.
               Issuance and route/live-state microprobes run only on ORIGINAL
               issued records inside their runtime protected frame. Their batch
               costs are diagnostic, not additive slices of ordinary replay.
               Reuse shape and private receiver sets, NEVER a currentness or
               admission verdict. Install/unwind a fresh frame on every call.
               Runtime owns VM accounts, post-GC live deltas and weak identity
               survival; none independently gives exclusive SDK/procedure bytes.
               Diagnostic runtime builds are separate source cuts, not releases.
               Candidate: require-current! already issued the record; use the
               existing private route/live-state primitives immediately instead
               of calling a public predicate which issues it again. Lean owns
               first-error equivalence for the SAME closed runtime operation.
               No callback, observer or second record may intervene. Public
               standalone predicates retain their own issuance check; acquisition,
               before-visitor and final phases each remain freshly authenticated.
               The source-call graph, not a producer purity flag, supplies this
               runtime closed-operation premise. QNT still owns effect schedules. */
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
            doc /* Runtime metadata.publish still checks output and dependent
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
        then runtimeMakeInOwnedStaging;
        action runtimeMakeInOwnedStaging;
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
