// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
package YuanxuModuleLoading {
    private import ScalarValues::*;
    part def SourceCatalogue {
        attribute entryCount : Integer;
        doc /* Directory/package identity and inert SourceRefs. Discovery must
               not expand roles, run user macros or admit domain objects.
               A wide-branch membership index projects the same ordered
               directory snapshot. A hit still checks the live path type.
               Full currentness still observes the directory listing.
               A large selection source compares exact decoded text through
               EOF with a bounded buffer inside one observation window. */
    }
    part def SelectedDeclarations {
        attribute selectedCount : Integer;
        attribute sourceRevision : String;
        doc /* Runtime interface metadata: identity, requirements, feature
               decisions, role locations and source association. Dependency
               closure is not a list of linked business scopes. */
    }
    part def PublicationPreflight {
        ref part declaration : SelectedDeclarations;
        attribute descriptorsValid : Boolean;
        doc /* Real publication admission demands Type descriptors for
               scope and dependency contracts. Config, Objects, Func and the
               export body stay cold. This is not domain admission. */
    }
    part def DemandedScope {
        attribute receiverIdentity : String;
        attribute sourceRevision : String;
        attribute featureDecision : String;
        attribute demandedCount : Integer;
        doc /* POO slots own role construction on actual access. Reuse
               requires exact receiver/source/feature/phase context. A parent
               cached scope is not a child's normalized configuration. */
    }
    part def ManagedDependencyPolicy {
        ref part declaration : SelectedDeclarations;
        doc /* Proposed gate between complete metadata selection and business
               activation. Bind actual native import owners and lexical aliases
               to admitted SourceRefs, requirement Contracts and current phases.
               Alias installation must not initialize every provider scope.
               Downstream applications supply no loader factory or purity flag. */
    }
    part def RuntimeReadSupport {
        attribute originalRecordCount : Integer;
        attribute orderedEdgeCount : Integer;
        doc /* Once issued, every original dependency remains. No observer
               event, miss, second requirement or stale record is pruned. */
    }
    part def PrivateLeafProjectionCandidate {
        ref part support : RuntimeReadSupport;
        doc /* The original local check authenticates the complete capture.
               A later representation may omit a direct root only after the
               producer proves that it is dependency-free, cannot escape, and
               cannot supply a later refusal. Keep the other original
               identities and their first-refusal order. Runtime projection
               requires evidence of non-escape for the actual producer. */
    }
    part def DirectoryReaderEntry {
        ref part support : RuntimeReadSupport;
        doc /* The directory factory owns the location check. POO authenticates
               the actual preparation roots before and after that closed check.
               The trailing policy and source checks still run. Custom
               callbacks, observers and all later effect boundaries retain
               independent authentication. */
    }
    part def InterfaceDatumProjection {
        ref part declaration : SelectedDeclarations;
        doc /* The private stock Interface datum read supplies both the
               binding check and deferred-role classification. Keep owner
               and native compiler identity independent. Custom readtables
               and source observers preserve separate reads. Release the
               datums before retaining the prepared declaration. */
    }
    part def DeferredWrapperImports {
        ref part declaration : SelectedDeclarations;
        doc /* One existing native module exports the fixed declaration
               and deferred-wrapper bindings. Keep them strong and retain
               their phase and identity. Each owner keeps its original
               context, payload expansion, and compiler role imports. */
    }
    part def CandidateReturn {
        ref part support : RuntimeReadSupport;
        doc /* A fixed directory and source check may run inside the
               native protection of preparation and admission roots.
               A refused preflight restores the original preparation,
               source, admission order. Open callbacks keep their own
               checkpoints. Every successful return rechecks live roots. */
    }
    part def StockAuthoringRun {
        ref part support : RuntimeReadSupport;
        doc /* Share authentication only within an established closed run
               with unchanged stock-method support. Keep the ordered read
               delivery of each rule invocation. An author callback owns
               independent entry and return guards. The next run reads
               the post-effect state. */
    }
    part def StockAuthoringReadDelivery {
        ref part support : RuntimeReadSupport;
        doc /* Capture the exact ordered native read delivery in a local
               scope. Preserve all native checks. Forward original records
               together only when the maintained observer has no effects
               on their receivers. Otherwise use original delivery. */
    }
    part def SourceAuthoringDecision {
        ref part authoring : StockAuthoringRun;
        doc /* Validate every actual datum. Source consumes a decision and
               optional diagnostic. An empty maintained result may omit its
               temporary receipt after native constructor, Type, prototype
               and warm owner fields are authenticated. Retain their actual
               reads. Changed Type and observer paths validate the ordinary
               receipt. */
    }
    part def ReadOnlyPublicationCheckpoint {
        ref part support : RuntimeReadSupport;
        doc /* Use native POO authentication for a validation-only traversal.
               Preserve the complete issued preorder and the independent
               return check. Actual observers keep their original effect
               boundaries and deliveries. A diagnostic count describes a
               completed preflight. */
    }
    part def DeferredRoleSlot {
        doc /* Native slot construction shares one implementation.
               The role captures its own owner resolver.
               Each alias reads the current POO receiver and role value.
               The Gerbil wrapper and effect guards remain owner-specific. */
    }
    part def DeferredRoleLexicalSupport {
        ref part slot : DeferredRoleSlot;
        doc /* Closed payload syntax may use a conservative inventory of its
               lexical identifiers to limit the wrapper's role aliases.
               Unknown expansion retains every visible alias. An existing
               nonempty alias group observes its receiver once even if the
               restricted inventory is empty. Source syntax,
               receiver, owner resolver, demand and native return checks
               remain attached to the individual publication. */
    }
    part def DeferredInterfaceFrame {
        ref part lexicalSupport : DeferredRoleLexicalSupport;
        doc /* Gerbil emits delayed field bodies in the owning Context.
               A closed frame can use the common native POO slot constructor.
               The binder, ordered dependency reads and lazy receiver survive
               that lowering. Unknown syntax, local shadowing and other
               object options retain normal declaration expansion.
               Source and issued-read guards still enclose expansion and
               author effects. The hygienic wrapper captures the current
               owner's reader resolver through its existing parameter. */
    }
    part def LoadingWork {
        attribute expandedIdentities : Integer;
        attribute processedEdgeOccurrences : Integer;
        attribute exhaustedFrames : Integer;
        attribute demandedReceivers : Integer;
        attribute affectedReceivers : Integer;
        doc /* Derived observations of the production algorithm, not policy
               flags or a second cache. Lean SourceClosureWork.Frames owns the
               recursive-frame/worklist representation proof and frame bound.
               IncrementalRoles owns affected-owner correspondence. Costs of
               actual index primitives, Type callbacks, per-boundary source
               authentication and unique strongly held payloads remain separate.
               A linear DFS alone does not prove linear publication work,
               a 2 GiB heap bound, or a wall-time deadline. Quint checks effect
               and mutation traces, not another copy of frame arithmetic.
               Physical source reads are attributed by actual init-source owner
               and authentication phase, without retaining another read graph.
               Lean SourceWindows owns stable-window requirement equivalence;
               it does not certify open observer callbacks as read-only or make
               equal-sized snapshots equivalent. Runtime controls own callback
               error identity, nested enrollment and fresh return observations.
               Context selected-membership uses one per-validation symbol
               identity index only after native cache/precedence/protocol and
               observer-state checks. Unknown observers and cold/hooked state
               retain original per-element reads. Lean SelectionIndex owns
               lookup and first-missing equivalence, not hash worst-case time. */
    }
    part def RuntimeCapacityWork {
        attribute selectedModules : Integer;
        attribute sourceObserverInstalled : Boolean;
        attribute firstGraphSeconds : Real;
        attribute firstValueSeconds : Real;
        attribute hotValueSeconds : Real;
        attribute changedValueSeconds : Real;
        doc /* The observed qualification workload retains all original events
               and assertions. Normal-runtime capacity is a SEPARATE std/test
               Case, using the same native init, role wrappers and module tree.
               Both workloads run as assertion functions in the current native
               std/test Case. No capacity Case may invoke another .run, CLI
               test command, compiler/signing pass or nested Harness. Tests of
               the explicit execution API remain separate end-to-end controls.
               Atomic entry invokes the installed test tool directly, without
               init selection or Script/Process construction. Independent build
               owns support issuance; module APIs and Cases own domain checks.
               The benchmark must not explicitly force complete graph admission
               before a value. Plain directory scope resolution starts at the
               requested owner. Signed Feature decisions, custom Contexts
               and realized package bindings retain their existing graph route.
               A cold export slot does not prove no internal graph was built.
               Use owner-qualified counters to assert every reached scope and
               every declaration admitted by the plain demand.
               It asserts no source observer is installed; it must not silently
               clear a caller's observer. Measure Graph demand separately from
               scope activation, value-cache access, independent admission,
               source preparation, compilation and Harness startup.
               A claimed Case stop must refuse the next genuine progress
               report on its owner before the relay changes. A local catch
               cannot replace the original rejection or extend the work.
               Change a real module's Config receiver, retain/replay original
               issued reads, and demand the getter again through native
               with-slot-dependencies. Assert exact computation counts and an
               unrelated hot identity. This explicit module getter is not
               automatic Loader enrollment or a cached admission verdict.
               Lean IncrementalRoles owns registration/affected correspondence;
               SourceWindows owns byte-sharing/independent-check equivalence.
               Quint owns stale source, omitted requirements, parent receiver
               and effect traces, not elapsed-time or GC arithmetic.
               Native runtime timings and retained-memory observations qualify
               capacity; a model theorem alone cannot establish the budget. */
    }
    part def Admission {
        ref part scope : DemandedScope;
        ref part support : RuntimeReadSupport;
        doc /* Domain obligations, source association and plan identity must
               hold for the final receiver. No successful decision is cached
               across callbacks/effects; return-currentness remains fresh. */
    }
    part def CallbackFrame {
        ref part support : RuntimeReadSupport;
        doc /* One known effect boundary during demanded scope linking:
               requirement admission, factory, or scope admission. Authenticate
               entry and successful exit with independent source reads. Preserve
               callback failure rather than replacing it with a later stale
               diagnostic. An observer's start/end delivery is also an effect
               boundary; it cannot carry approval into the callback body.
               End delivery during failure unwinding must retain both original
               causes if it fails too. Lean Boundary.finishObserved owns this
               outcome algebra; Scheme checks actual exception identity and
               dynamic-wind delivery counts, including false-valued exceptions.
               Quint retains its effect/support/cleanup trace responsibility.
               Lean ManagedBinding.execute owns the integrated ordered reference
               flow. This does not prove arbitrary effects inside one callback
               read-only or make external file snapshots atomic. */
    }
    part def Loading {
        part catalogue : SourceCatalogue;
        part declarations : SelectedDeclarations;
        part preflight : PublicationPreflight;
        part policy : ManagedDependencyPolicy;
        part scope : DemandedScope;
        part callback : CallbackFrame;
        part admission : Admission;
        dependency sourceSelection from catalogue to declarations;
        dependency descriptorAdmission from declarations to preflight;
        dependency dependencyAdmission from preflight to policy;
        dependency actualDemand from policy to scope;
        dependency explicitAdmission from scope to admission;
    }
    requirement def NoEarlyRoleConstruction {
        attribute declarationOnly : Boolean;
        attribute roleConstructions : Integer;
        require constraint { not declarationOnly or roleConstructions == 0 }
        doc /* Proposed fast path only. A source/MOP-owned closed projection
               must establish this; an author's Boolean cannot authorize it.
               Unknown code/hooks take the existing full guarded path. */
    }
    requirement def SeparateCapacityWorkloads {
        attribute catalogueCount : Integer;
        attribute selectedCount : Integer;
        attribute demandedCount : Integer;
        require constraint { demandedCount <= selectedCount }
        require constraint { selectedCount <= catalogueCount }
        doc /* Keep the existing 10000-selected declaration gate at 2 GiB.
               Separately measure large catalogue/small selection and full
               business-scope activation. Never substitute one for another. */
    }
    requirement def CompleteSelectionBeforeExposure {
        attribute viewExposed : Boolean;
        attribute declaredDependenciesAdmitted : Boolean;
        attribute sourceOwnersBound : Boolean;
        require constraint { not viewExposed or
            (declaredDependenciesAdmitted and sourceOwnersBound) }
        doc /* Runtime-projected facts, not user policy switches. Lazy business
               access cannot hide disabled, undeclared or cyclic requirements.
               For a plain directory scope, the admitted dependencies are
               those reached from the requested owner. Explicit complete
               Graph requests and selections with Feature decisions retain
               the full selection. */
    }
    requirement def NoPrematureBusinessActivation {
        attribute businessRoleInitialized : Boolean;
        attribute providerSelectedAndEnabled : Boolean;
        attribute phasePermitsBusinessActivation : Boolean;
        require constraint { not businessRoleInitialized or
            (providerSelectedAndEnabled and phasePermitsBusinessActivation) }
        doc /* Core bootstrap/type-descriptor initialization is classified
               separately. This does not establish purity of arbitrary macros,
               unsafe reflection or direct foreign calls. */
    }
    requirement def BeforePublication {
        attribute published : Boolean;
        attribute descriptorsValid : Boolean;
        attribute finalReceiverAdmitted : Boolean;
        attribute sourcesCurrent : Boolean;
        attribute requiredModulesEnabled : Boolean;
        require constraint { not published or
          (descriptorsValid and finalReceiverAdmitted and sourcesCurrent and requiredModulesEnabled) }
    }
}
