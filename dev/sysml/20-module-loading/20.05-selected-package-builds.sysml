// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
package YuanxuSelectedPackageBuilds {
    private import ScalarValues::*;

    requirement def RootQualifiedOwnerIdentity {
        doc /* A leaf declaration name is relative to its Gerbil module
               namespace. Agentic AI Lab Governance and Weaver Governance
               have different complete native module identities. Mount aliases,
               checkout paths and downstream output paths are not identities.
               Resolve local requirements in the declaring owner's root; an
               explicit foreign requirement retains its complete module ID.
               Never repair a flat short-name index by renaming user Modules
               or falling back to a same-named leaf in another root.
               SelectedPackages.ScopedModuleId proves the bounded model laws.
               Scheme carries native keys through mounted source indexes,
               publication/prepared-input admission, Core/Feature edges and the
               shared build/test resolver. A declaration label is not an owner
               certificate; actual Gerbil source identity must match. Metadata
               inspection without a reader has no runtime admission authority.
               Native fixtures and Weaver's actual A/B consumer verify the
               bridge while retaining independent effect/currentness checks. */
    }

    part def SourceOwner {
        attribute publicationIdentity : String;
        attribute sourcePackage : String;
        attribute sourceRevision : String;
        doc /* Module/Feature owns compilation declarations, additional public
               roots, target options, assets and external contribution requests.
               Source bytes/package observations remain authoritative even for
               dirty or linked development sources. */
    }
    part def CompilerInput {
        ref part owner : SourceOwner;
        attribute compilerIdentity : String;
        attribute originalPath : String;
        attribute preparedForms : String;
        attribute phase : Integer;
        doc /* Actual Gerbil expansion supplies dependency edges. Semantic
               requires, compiler imports and runtime activation are separate.
               Generated frames preserve original locations and binding identity. */
    }
    part def DownstreamEnvironment {
        attribute outputRoot : String;
        attribute toolchain : String;
        doc /* Owns selected products, generated input view and cleanup. Distinct
               logical environments require physically disjoint canonical output
               roots. No upstream init or shared checkout mutation. */
    }
    part def BuildProjection {
        ref part environment : DownstreamEnvironment;
        part inputs : CompilerInput[0..*];
        doc /* One existing selected Graph. Every demanded input is classified
               as owned source, installed prerequisite or external contribution.
               Missing input and unfinished discovery refuse the plan. Package
               filters cannot discard selected foreign compiler entries. */
    }
    requirement def ExactSelectedClosure {
        doc /* Lean SelectedPackages.successful_closure_exact and
               successful_target_iff reuse Graph.TestAdmission discovery.
               Native input extraction, eligibility and finiteness are bridge
               obligations; this is not a thousand-module performance proof. */
    }
    requirement def LibraryBootstrapIndependence {
        doc /* A package library inventory must not initialize application
               source collections or selection policies merely to reconstruct
               a constant public library root. The real publisher and native
               dependency closure establish equivalence, not a filename filter.
               InterfaceRoots.literal_front_end_replaces_registry_query and
               front_end_refactor_preserves_demands preserve the ordinary root
               and the complete selected-source union. Existing CoreBuildHandoff
               owns callback/return freshness, independent requirements and
               parent isolation; this factoring adds no lifecycle or cache. */
    }
    requirement def InterfaceEntryAuthority {
        doc /* The Module System consumes Interface loading configuration.
               Applications consume init.exports through lazy POO .get demand,
               never direct Interface/private-role imports. One preparer supplies
               reader/compiler role association.
               InterfaceRoots proves selected-entry ancestry and separate extra
               root attribution. Native tests compare source projection, actual
               compiler events and fresh-process configured POO scope behavior.
               No handwritten internal role manifest is an acceptance oracle. */
    }
    requirement def SharedFunctionalDefinitions {
        doc /* Task/Flow Contracts and the Scenario Record family are shared
               Core library definitions, not activated Module scopes. Use the
               existing Gerbil Context catalogue and import closure; do not
               reconstruct them in publication-private namespaces. Catalogue
               eligibility never replaces actual-demand source enrollment or
               grants a Module role as an implicit compiler capability.
               Lean Building.Inputs proves catalogue-extension preservation,
               changed-source rejection and role refusal. Existing Quint
               SourceWindows owns callback/return freshness, competing
               requirements, receiver isolation and lazy demand; no second
               lifecycle model is introduced. Scheme qualification compares
               actual eq? bindings, return-time source reads and a cold
               unselected Module through an explicit init declaration.
               Performance qualification must separate removed duplicate
               initializations from skipped callbacks and must retain all
               remaining open-boundary checks. A native import cache hit alone
               does not prove a surrounding user guard is read-only. */
    }
    requirement def ContextCallbackWindow {
        doc /* Preparation extracts the actual owning context procedure.
               Native void performs no callback and may keep the current pure
               byte window. Any other procedure suspends and invalidates that
               existing window on entry and normal/exceptional resumption.
               This adds no acceptance cache or user purity annotation.
               Lean SourceWindows.ContextStep proves observation soundness,
               complete requirements and ordered first diagnostics. Quint
               SourceWindows checks effect/resume byte lifetime; it does not
               prove Scheme exception propagation or arbitrary guard purity.
               Native preparation regression owns callback error identity and
               the resumed outer window's fresh bytes. This qualification does
               not certify the whole linker/Reader guard as callback-free. */
    }
    requirement def DirectPOOExit {
        doc /* Interface remains loader configuration. Init uses the existing
               linker's default namespace: a demanded Module leaf is its actual
               admitted public POO object. No public scope facade, getModule
               alias or injected testing slots. Namespace enumeration stays cold;
               root tests.select remains separate. Existing ManagedBinding owns
               ordered requirement/currentness checks, DemandMaterialization owns
               receiver identity and native tests own this concrete bridge. */
    }
    requirement def OwnerDeclaration {
        doc /* Lean source_owner_declared and successful_projection require
               every compiled owner to be declared and compiler entries to be
               consistent. Native selection retains required-module decisions;
               source classification must not grant authority by prefix alone. */
    }
    requirement def OwnerPublicLibraryMigration {
        doc /* 13.34 uses the existing Build contribution: roots are additional
               owner-relative native targets/options; library-roots are public
               package-relative libraries. Retain role/currentness observations
               without compiling Build metadata as an ordinary target. Removing
               a retained root requires selected-owner projection coverage.
               InterfaceRoots contribution ancestry reuses existing discovery;
               native gates establish source, phase and compiler correspondence.
               A compiler include option alone does not cover C header bytes. */
    }
    requirement def DownstreamProductOwnership {
        doc /* Lean install_identity_preserved, install_other_environment,
               clean_other_environment and clean_unowned_product constrain store
               operations. Scheme/filesystem correspondence must establish path
               confinement, actual output identity, tools/options and isolation. */
    }
    requirement def PackageAndModuleSpecSeparation {
        doc /* yuanxu! remains the sole selected-module spec producer. Package
               library targets keep their original source paths/options; only
               selected role inputs pass through role lowering. The build entry
               consumes their native Make spec merge. Every admitted selected
               owner source remains a compiler target across package boundaries.
               Installed prerequisites are native Gerbil imports, not selected
               source entries inferred from a package-prefix mismatch.
               Cross-package source uses the existing downstream-owned source
               view and an absent Make prefix with full original compiler IDs.
               A present explicit prefix, including the truthy empty string,
               refuses before native compiler dispatch. The view has no
               gerbil.pkg that could reintroduce an inferred package prefix.
               Local-only retained libraries keep their original source paths.
               SelectedPackages.package_target_exact, package_partition_complete
               and package_partition_disjoint establish the ownership partition;
               they do not prove Scheme's package-prefix/path correspondence.
               BuildSpecContract checks shape and exact native-spec composition.
               The existing init consumer binds identity and source currentness;
               a caller-supplied origin tag cannot replace that association.
               No new temporal transitions or cache protocol are introduced. */
    }
    requirement def SelectedSourceDisposition {
        doc /* Graph entries carry admitted owner/source/input provenance. The
               complete source target set is SelectedPackages.targets, independent
               of the consumer package prefix or installed product availability.
               Source and installed prerequisite are disjoint dispositions;
               A native binding to an installed SSI outside the declared owner
               root must not suppress Gerbil's source lookup within that root.
               Retain an in-root bound source; otherwise use the existing native
               package lookup and validate the actual source header identity.
               A package window resolves the native pkg-root-dir public binding.
               Gerbil owns checkout layout and binding initialization. The
               lookup grants neither package installation nor compiler approval.
               Cold, hot and clean projections retain this same source set,
               including ordinary package libraries imported by selected roles.
               A nested gerbil.pkg compiler prefix is not the complete source
               authority: if its native lookup misses, try only the existing
               directory Context's admitted kernel root. Never search arbitrary
               ancestors or source checkouts for an installed prerequisite.
               a selected source is never silently demoted to an installed input.
               Package partitions are scheduling/naming groups, not permission
               to discard foreign entries. Reassembly must cover every source.
               Native projection retains input bytes, compiler identity, options,
               original locations and fresh currentness. Missing native imports
               refuse through Gerbil; they do not authorize compiling a checkout.
               Downstream output/clean affects only projected identities in its
               own canonical environment. Cross-owner artifact issuance remains
               separately refused until the existing issuer can cover all owners. */
    }
    requirement def CompletePublication {
        doc /* Lean publication_sources_current and missing_realization_refused
               retain complete input footprint and external realization demand.
               Publication remains the existing issuer's responsibility. Pure
               plan acceptance cannot certify native products or external effects. */
    }
    requirement def PreludeEntry {
        doc /* One reviewed yuanxu! binding through the existing optional Prelude
               and explicit-import path. PreludeEntry.admitted_binding_exact and
               eager_cycle_refused check concrete terminal binding/phase and
               strictly ranked eager dependency edges. Runtime compiler imports
               must establish those observations, including macro phases and
               custom Prelude behavior. No implicit selection or compile effect. */
    }
    requirement def NativeHandoff {
        doc /* The existing prepared-source adapter feeds one native std/make
               target graph for selected cross-package files. Stable wrappers
               are generated data, not a cached admission. Original observations
               and native timestamp correspondence need cold/hot controls.
               Existing budgeted Just harness owns all Scheme validation. */
    }
    requirement def StagedDeclarationImport {
        doc /* 13.31 allocates the demanded semantic implementation import to
               the consumer's native Context. Keep one canonical public macro
               reexported by Prelude. Lean PreludeEntry.stageImport preserves
               the dependency edge and rank; native syntax/phase extraction and
               terminal binding/hygiene controls must establish correspondence. */
    }
    requirement def PhysicalProductUniqueness {
        doc /* Compiler identities a/b__c and a__b/c have the same native static
               stem. SourceView checks pairwise output injectivity; existing
               products.ss owns the concrete artifact inventory. Refuse actual
               collisions before writes, including host path/extension aliases. */
    }
    requirement def InputAssociationBeforeReuse {
        doc /* SourceView preserves descriptor/product correspondence by
               invalidating owned std/make completion before replacing changed input
               data. Equal/backdated timestamps cannot establish byte identity.
               Raw marker reappearance during native failure is insufficient;
               existing complete product/source/issuer checks remain required.
               Local serialized preparation ordering is not a crash theorem for
               the filesystem or compiler and does not introduce a new cache. */
    }
    requirement def SelectedInputRetry {
        doc /* 13.33 reuses SourceView preparation idempotence: a callback
               exception after changed-input invalidation cannot recreate a
               completion marker. Equal-mtime byte changes must rebuild through
               native Make in a fresh process. Selection changes prune old
               generated source frames, never adopt unknown files. This is not
               runtime unloading or compiler/power-loss atomicity. Native
               tests retain another environment's products and input identity. */
    }
    requirement def NamespaceProjectionResearch {
        doc /* 13.35 proposal, not an implemented visibility API. Reuse native
               POO namespace slots, ManagedBinding admission and
               DemandMaterialization receiver identity. A future perspective
               view must preserve original leaf objects and source generation,
               agree on reflection and direct lookup, and never enlarge selected
               dependencies or compilation authority. Haumea's directory super
               is not POO's inheritance super. Quantitative efficiency and any
               new view refinement still require separate formal/native gates. */
    }
    requirement def NativePOONamespaceExpression {
        doc /* 13.35 refinement: branches are ordinary indexed POO objects,
               leaves are original admitted objects. Use native slot composition,
               Type/ObjectContract boundaries, prototype maps and existing table
               indexes where their snapshot semantics apply; add no Tree/Node
               wrapper family. Closed slot names govern reflection and lookup.
               Restrict target bindings before aliasing. Native .get remains the
               expression path and Interface remains loading configuration. */
    }
    requirement def NamespaceProjectionIdentity {
        doc /* NamespaceProjection delegates permitted demand to the original
               resolver with unchanged return/state and refuses absent bindings
               before resolver invocation. Warm native slots are generation
               snapshots, not live IO. Existing owner admission/currentness
               guards build/publication/execution; projection grants no effects.
               Opaque identity and cold native behavior require Scheme controls. */
    }
    requirement def BranchLocalIndexMeasurement {
        doc /* Native child buckets must preserve original path suffixes and
               enumeration semantics. Measure the previous global-filter source
               against branch-local grouping with identical paths and filesystem
               metadata workload, zero provider calls and unchanged budgets.
               Report metadata-only work separately from declaration admission,
               native compilation and thousand-Module end-to-end capacity. */
    }
    requirement def PhysicalCatalogDemandAndCompile {
        doc /* 13.35 separates physical catalog R, explicit declarations D,
               demanded scope closure S and native compiler closure C. R=1000
               does not imply D=1000 or C=1000. Complete declaration admission
               keeps all selected headers and contracts; ordinary native .get
               constructs only S. A separate downstream explicit selection
               determines compiler owners, including owner build declarations.
               Namespace visibility filtering never grants build authority.
               Keep original Case/heap/time limits. Failed full-catalog demand
               remains a failed gate even if a two-owner downstream passes. */
    }
    requirement def ThousandCatalogNativeOwnership {
        doc /* Use real role files, canonical Prelude, Interface configuration
               and native init.exports/.get. Count existing scope-factory events,
               compare cold native compiler events with projected targets,
               require hot zero compilation, fresh-process object use, native
               source identities, independent downstream output environments,
               clean isolation and unchanged producer/consumer sources. An
               independent D=3, S=2 control must retain the third admitted
               scope cold. Rejected selections own separate init/output roots
               and must leave the accepted environment usable and hot. No new loader,
               registry or cache. Lean closure laws do not establish native
               capacity, currentness or pointer identity. */
    }
    requirement def ClosedPublicationReadUnion {
        doc /* 13.35 attribution separates complete declaration admission,
               independent currentness and post-admission scope demand in the
               same 180-second Case. Reuse SourceClosureWork frame accounting
               and Quint pure-epoch/effect boundaries. Research only: a fixed reader may join
               its preparation/admission original read roots for ONE native POO
               replay, preserving ordered root membership and complete support.
               Keep location/policy checks and fresh pre/post-effect guards;
               source observers retain original delivery/order. A topology hit
               is never a currentness verdict or cross-boundary approval.
               The per-publication fusion experiment was removed from Scheme;
               these laws do not establish an installed optimization. */
    }
    requirement def NativeSessionMetadataTopology {
        doc /* Main metric: one cold business .get in a thousand-name namespace,
               including complete declaration admission, reached scopes and the
               returned business value. 180 seconds is an exception watchdog,
               not the reported EVAL latency or a performance target. Split
               cold/hot calls and explicit currentness in measurement receipts.
               Fixed reader publications retain original issued metadata roots
               and fixed entry/tail checks in the existing private record.
               An ordinary POO slot indexes their immutable append-only topology;
               table cardinality invalidates topology only, never source checks.
               In a no-observer, native-paired pure source guard, preserve all
               entry/tail checks and freshly replay the complete root union around
               source checkpoints with native
               POO. Read-only replay failure retries the original sequence and never
               approves a failed batch. Checkpoint failures retain their own cause. Unknown callbacks/contexts retain the original path.
               Every effect still has independent before/after authentication. */
    }
    requirement def ReaderGuardQueryWork {
        doc /* The existing pure source-read window keys a reader check by its
               private source-row producer and append-only guard/source counts.
               A query key must not recursively hash guard payloads, source bytes
               or POO graphs. Guards grow by cons and source rows only insert or
               confirm equal observations; same count preserves membership under
               those private premises. Every cache miss still checks all original
               guards in order. Independent calls and effects end the observation
               window; no accepted verdict survives it. Open observers retain
               the original query and callback order. Lean SourceClosureWork
               prepend_only_same_size_same_rows and existing Quint index replace,
               dropped-support and stale-approval controls bound this refinement. */
    }
    requirement def CandidateReplaySites {
        doc /* Attribute declaration-before, declaration-inputs, role-entry,
               role-return, declaration-after and candidate-admitted
               independently. Site labels must not change source phases or
               observer delivery. Native POO keys the traversal topology by
               the root spine. A topology hit still authenticates issuance,
               live route, receiver revision and slot value, including the
               native return check. Within one symbolic vector read, the
               slot query may consume the cells and indices authenticated
               by that same invocation. Issuance precedes route refusal,
               which precedes stale-state refusal. A missing offset or
               empty cell remains absent, and stored false is a value.
               An exact class guard may select a native field accessor
               that reads the same live slot as symbolic lookup. Wrapper,
               layout and shape guards precede their respective field
               accesses, and existing route refusal checks keep their order.
               Sharing a freshness pass requires equal
               live observations over the checked support throughout the
               interval. A filesystem observation, new enrolled input,
               Gerbil expansion, role execution or author Contract cannot
               inherit a successful verdict from a prior checkpoint. */
    }
    requirement def ProtectedMetadataCheckpoint {
        doc /* Source/policy checkpoints from the paired native producer are
               validation work, not user initialization. One native protected
               replay authenticates the original complete DAG before them and
               again on successful return, holding the same receiver protection
               through the checkpoint. No semantic observations are re-delivered.
               It executes every original checkpoint once; checkpoint failure
               propagates without retry. Preflight failure restores the original
               split diagnostic and cannot become approval. Observers, custom
               Contexts and effects retain the independent path. Per-candidate
               preparation/admission support is joined only inside one boundary,
               never across two initializers or Contract callbacks. */
    }
    requirement def WindowSourceOwnership {
        doc /* A yuanxu! window is a namespace admission boundary, not ownership
               of every file below its directory. Resolve selected owners through
               the existing directory index. Disabled declarations and an actual
               Interface boundary without an eligible owner refuse before source
               expansion. Only an ownerless library inside the same package kernel
               may use the existing shared-source projection across windows.
               Record negative Interface probes: creating a boundary invalidates
               the view. Preserve actual context identity, complete source guards,
               original compiler IDs and downstream output ownership. Package
               metadata never determines whether a directory is a Module.
               Ordinary libraries additionally retain their originally observed
               native public binding: source bytes, context instance, module ID,
               artifact path and registry association. A source-only binding
               cannot later retarget to an SSI. Only the existing dynamically
               scoped compiler-input association bridges temporary load-path
               removal; ending that consumer ends the bridge. An SSI spelling
               alone grants no source or execution authority. */
    }
    requirement def ToolExecutionAndBuildOwnership {
        doc /* Gerbil's actual context origin defines execution provenance.
               Captured context identity, module identity and artifact path must
               remain identical; reload requires a fresh reader. Source-bound
               tool contexts retain byte guards. Installed SSI contexts are
               runtime prerequisites, not mutable checkout source demands.
               Public checks and open callbacks authenticate again on return,
               including an observer which removes itself. Only the existing
               closed candidate fixed checkpoint has no intervening effect;
               its pure window requires no second native binding pass.
               The same existing dependency index retains the complete context
               closure. A separate owner-confined build projection may demand
               those libraries' sources, which retain original IDs and source
               guards as build inputs. Optional source aliases grant neither
               execution authority nor compiler ownership. Explicit owner source
               inputs may extend the SAME path index only after role confinement,
               fresh bytes and exact private preparation-to-captured-context
               association pass. Conflicting contexts/paths refuse. A relocated
               owner never initializes another copy of its installed tools.
               No loader/cache is
               added and no selected owner source check is omitted. */
    }
    requirement def BusinessEvalMeasurement {
        doc /* Measure one actual native .get of module-1 plan without warming
               the selected Graph. Its result requires admission of all 1000
               declarations and only the module-1/module-0 business scope closure.
               Enumerating namespace keys is outside this expression and must
               not admit declarations. Assert every unrelated leaf stays cold.
               Unrelated Objects/Config initializers must fail if entered, so cold
               public namespace leaves alone cannot hide eager internal scopes.
               A selected-provider initializer refusal must still be reached.
               Report wall, user/system CPU and included GC time for the entire
               expression; phase probes are separate runs, with nested totals
               explicitly identified. A hot value hit does not authenticate
               source currentness. Record incomplete runs as failures, never
               replace elapsed measurements with watchdog limits. */
    }
    requirement def SelectedPackageTimingEvidence {
        doc /* The fixed Lab integration gate owns a 120-second total fence.
               Each package action retains its own 180-second total and
               60-second genuine-progress idle checks. An observed successful
               native action exit advances the enclosing lifecycle, including
               spec, use and hot Make with no compiler events. Record timeout
               phase and termination status separately. Attribute time to the root
               business getter, native Make, metadata replay, and the interval
               from build main return to observed process completion.
               Nested spans overlap. Make includes import and currentness
               work, while the return interval includes output drain and wait.
               Admission and artifact ownership laws remain independent of
               elapsed time. Completion requires natural exit and all closure,
               currentness and cross-environment isolation assertions. */
    }
    requirement def ClosedAuthoringSupportForwarding {
        doc /* Research candidate, removed after native EVAL showed no gain.
               Default authoring Function policy and event delivery currently
               authenticate the same declaration support twice. One fresh native
               reobserve may capture the COMPLETE original ordered token trace.
               Reuse it only inside this invocation, with unchanged payloads,
               compatible actual observer identities and every support receiver
               warm and protocol-free. Then the maintained observers are no-ops;
               native bulk merge preserves the parent's occurrence/unique policy.
               Forward all events, not just roots or a deduplicated substitute.
               A changed/unknown observer, cold/protocol receiver, stale policy,
               failed capture or missing method retains the original path.
               No opaque effect crosses capture/forward; normal before/after
               source checks and result Type validation remain in force.
               No successful admission or currentness result survives the call. */
    }
    requirement def DirectRoleIdentifierLowering {
        doc /* Installed lowering: only an actual unshadowed bare role alias may lower
               from generated with-slots to the same nested native .get.
               Keep exact receiver/name, returned object identity, forcing point
               and native read provenance. Generated private role formulas use
               only explicit self and hygienic loader bindings: native
               bind-these: #f may omit implicit aliases there, preserving the
               computed-slot current receiver even on extension.
               Root/core/require shadowing retains
               its original meaning. Unknown identifiers and compound syntax
               keep the original path. No source/currentness/Contract boundary
               moves. Require native full EVAL evidence before claiming gain. */
    }

    requirement def IndependentPackageBoundary {
        doc /* Yuanxu is an independent Gerbil package. Its builds, tests and
               proof inputs must not require a downstream checkout, infer a
               downstream root from its parent, or carry product-specific source
               environment flags. Product integrations and fixtures belong to
               the product's test tree. Core uses self-contained producer and
               consumer packages and standard Gerbil runtime configuration.
               Module source ownership comes from declared POO source values;
               filesystem paths are consumed at source admission and artifact
               IO boundaries. Qualify from a standalone source root without an
               installed downstream product. */
    }

    requirement def ClosedNamespaceProjection {
        doc /* module-namespace-project consumes an admitted native POO source,
               a finite POO binding object (public slot -> source slot symbol),
               and permitted source slot symbols. Restriction applies to targets,
               including aliases. Construction checks names without reading source
               values. Reflection and lookup share one immutable prototype-map;
               excluded bindings have no getter. Permitted demand invokes the
               original source getter and returns its exact object. Nested paths
               compose ordinary projections, not wrappers or a second loader.
               Binding values are declaration metadata; evaluating author-supplied
               metadata is not assumed effect-free. Currentness and Contracts
               remain at the original admission owner. The Lab Nix consumer
               routes modules/nix to its admitted owner. Config and prototypes
               are slots on that scope. Its Interface requires no other Module
               scope. The scale fixture admits 1000 owners and demands only two
               scopes. Distinguish branch construction, declaration admission
               and reached scope work in native receipts. Sparse and dense
               projection benchmarks must separate metadata reads, index and
               slot construction, and cold and hot lookup. Bulk construction
               retains exactly the authorized rows after original validation.
               An invocation-local symbol hash checks permission during
               construction. Each admitted row produces a native lazy slot
               bound to its source target. The resulting POO object owns its
               slot index; the permit hash is discarded. */
    }

    requirement def ProfileTagSelection {
        doc /* A profiled Interface declares a nonempty literal set of distinct
               capability categories. Categories group owners independently of
               implementation names. A profile name matches that same tag within
               the declared source window. Runtime demand, production Make and
               test discovery share the selected Graph and declared dependencies.
               Testing consumes the selected file list against downstream products.
               Tag metadata cannot evaluate business scopes or widen source authority.
               Same-category roots are combined across declared windows; an
               auxiliary window without matches remains dependency-eligible.
               Empty tags and categories with no matches across their windows
               are refused. Relative cross-package window paths grant only the
               explicitly declared source authority. Public library roots belong
               to the selected owner: relative roots use its nearest native
               package, native library identities use its declared kernel.
               Installed contexts cannot infer new source targets from optional
               checkouts. Explicit library roots keep cold/hot/clean inventories
               equal; Profile test defaults follow the same dependency closure. */
    }

    requirement def CompilerInputContext {
        doc /* The init-owned build projection establishes its native Gerbil
               input context using the invocation's actual output directory.
               Preserve prerequisite order, keep outputs as native fallback,
               and restore the caller path on every exit.
               Declared package windows supply source checkouts ahead of
               ordinary prerequisites. An installed copy cannot hide an
               imported source from its declared package kernel. Actual
               imports enter the selected source closure with canonical
               identity and currentness guards.
               Reject a mutated
               context and refuse reuse of prepared evidence in that init build
               epoch. std/make owns output inventory and timestamp checks.
               Runtime and selected tests prefer downstream products. No new
               resolver, loader or approval cache is introduced.
               Qualification correlates caller/child wall timestamps and CPU
               separately, retains natural-exit admission, and keeps detailed
               per-file diagnostics out of ordinary scalar acceptance without
               skipping initializer work or any independent effect guard. */
    }

    requirement def PackageEditorIndexIsolation {
        doc /* Native dependency installation and its package-owned default build
               preserve source identities, tags and manifests. Editor indexing
               remains a required part of normal deps --install acceptance.
               Its completed source work must stream through the native process
               boundary rather than be captured and discarded. Real completed
               TAG events advance liveness; elapsed time or ordinary diagnostics
               do not. Index contents, including every expected public owner
               binding, are independently checked. Indexing must not bypass
               fetching, recursive dependencies, package defaults, errors or
               source currentness. Explicit retag remains available. Yuanxu neither
               intercepts gxtags nor provides another installer or loader.
               Qualification must distinguish the installed tool from a pinned
               native source candidate and retain all existing budgets. Native
               retag partitions the same ordered source walk into bounded serial
               invocations of the existing tags CLI, releasing each expander's
               syntax at process exit. Every source occurs exactly once. Native
               module IDs/exports and original file locations remain authoritative.
               Publish the staged combined index only after all invocations
               succeed. All batches share the one outer command deadline;
               partitioning does not multiply time or heap allowances. */
    }

    requirement def LeafReceiverAndInheritance {
        doc /* Haumea leaf self is the file-result fixed point; its super is the
               perspective-filtered containing directory, and root is a filtered,
               transformed tree. These spatial capabilities are distinct from
               native POO self, the final effective receiver, and super, the
               current slot's inherited computation. A per-slot name such as
               sup is a lexical binder, not another namespace or magic global.
               Reuse native direct replacement, => value transformation, =>.+
               object refinement and explicit lazy inherited-slot binders.
               Ancestor formulas keep the final receiver even after parent
               caches are warm. Nested names use native hygienic lexical slot
               binding; ordinary functions receive explicit arguments. Never
               inject ambient root/super namespaces into Module requirements.
               Namespace projection transports a scope unchanged; explicit
               derivation from its public prototypes creates a new business
               value and grants no source/build/admission authority.
               The filesystem declaration admits a branch and its owner keys.
               Public projections use native indexed slots to route names to
               those keys. Two public branches may point to the same admitted
               getter. Enumeration reads names only and never demands siblings.
               Native lazy slots and the original scope owner retain their
               results. A leaf formula receives its effective receiver, the
               inherited computation of its slot when requested, and only the
               explicit dependencies provided by its Interface. Moving a public
               binding does not change any of these three inputs. */
    }

    requirement def DeclaredWindowAuthority {
        doc /* A source window requires an actual yuanxu! declaration. Package
               metadata cannot invent membership, an automatic headless window
               or a broader kernel. Kernel source provenance comes from the
               declaring source or a matching upstream yuanxu! window, with
               declaration bytes observed by the existing currentness guard.
               Every selected SourceRef carries this per-window origin. A
               directory named modules or a neighboring gerbil.pkg is not a
               source authority. The reader cannot fall back to a compiler
               package root when the declared origin equals the collection
               root or is absent. Bare SourceRefs grant only Module-local
               source scope. Gerbil still owns native compiler package and
               prelude identity; those observations do not select Modules. */
    }

    requirement def NativePackageAdmissionBinding {
        doc /* Qualify native Gerbil package checkout identity, version
               and currentness as facts of the existing owned source declaration.
               Package code and package management own package structure and
               dependencies. Tests must not reconstruct a consumer file list or
               add bootstrap source files to make this path appear complete.
               Compiler engine/owner projection evidence and actual native
               package workflow acceptance are separate. No new loader, registry
               or cache is authorized by this acceptance scope. Native deps
               --install executes the producer's OWN default build; it is not
               intrinsically fetch-only. A source catalog package may declare
               zero default owner roots. Fetching 1000 owners must then compile
               none of them. Consumer-owned directory declarations select their
               source closure in the installed native package layout. Validate
               native tag/HEAD/manifest provenance, default and selected compile
               event sets, source/installed-prerequisite separation, unchanged
               producer checkout, cold/hot builds and A/B clean isolation.
               Use existing native package entrypoints before inferring any
               additional Core implementation or resolver. */
    }

}
