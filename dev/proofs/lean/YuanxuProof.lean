-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import YuanxuProof.ProfileComposition.Composition
import YuanxuProof.Modules.Funflow.Policy
import YuanxuProof.Admission.Publication
import YuanxuProof.PooClos.MethodCombination
import YuanxuProof.ModuleSystem.Source.Ownership
import YuanxuProof.ModuleSystem.Source.Collections
import YuanxuProof.ModuleSystem.Building.Inputs
import YuanxuProof.ModuleSystem.Workflow
import YuanxuProof.ModuleSystem.Graph.ImportCorrespondence
import YuanxuProof.ModuleSystem.Graph.TestAdmission
import YuanxuProof.ModuleSystem.Graph.SourceClosureWork
import YuanxuProof.ModuleSystem.Graph.SemanticReads
import YuanxuProof.ModuleSystem.Graph.OwnedReads
import YuanxuProof.ModuleSystem.Graph.PublicationReads
import YuanxuProof.Composition.Overlay
import YuanxuProof.Composition.Identity
import YuanxuProof.PooClos.Outcomes
import YuanxuProof.Modules.Funflow.Continuation
import YuanxuProof.Modules.Funflow.FunctionBoundary
import YuanxuProof.Contribution.Qualification
import YuanxuProof.Admission.Federation
import YuanxuProof.Admission.Source
import YuanxuProof.Admission.SourceWindows
import YuanxuProof.Admission.RootChild
import YuanxuProof.Admission.ReturnWindows
import YuanxuProof.Admission.BoundaryComposition
import YuanxuProof.Admission.ReplayBoundary
import YuanxuProof.Admission.IdentityDFS
import YuanxuProof.Admission.DFSFrames
import YuanxuProof.Admission.ReadOnlyEntry
import YuanxuProof.Admission.SnapshotEntry
import YuanxuProof.Admission.SnapshotLifetime
import YuanxuProof.Admission.SerialUse
import YuanxuProof.Admission.IssuedRootForwarding
import YuanxuProof.Admission.ReadRetention
import YuanxuProof.Admission.RootCollection
import YuanxuProof.Admission.CallPhases
import YuanxuProof.Admission.AdmissionBody
import YuanxuProof.Admission.ReturnTail
import YuanxuProof.Admission.ClosedTail
import YuanxuProof.Admission.CheckerOrigin
import YuanxuProof.Admission.MetadataRoute
import YuanxuProof.Admission.IssuedRead
import YuanxuProof.Admission.IssuerProjection
import YuanxuProof.Admission.RouteMutation
import YuanxuProof.Admission.ReplayOwnership
import YuanxuProof.Admission.MetadataOwnership
import YuanxuProof.Admission.MetadataAllocation
import YuanxuProof.Admission.StoreLowering
import YuanxuProof.Admission.ArtifactClosure
import YuanxuProof.Admission.IssuedLoading
import YuanxuProof.Admission.SourceLoader
import YuanxuProof.Admission.CoreStoreRecovery
import YuanxuProof.Admission.CoreApprovedRecovery
import YuanxuProof.Admission.TestMakeLayout
import YuanxuProof.Admission.TestPublicationReuse
import YuanxuProof.Admission.SelectionReplay
import YuanxuProof.Admission.CoreBuildHandoff
import YuanxuProof.Admission.CoreBuildPublication
import YuanxuProof.FeatureSystem.DomainCase.Resolution
import YuanxuProof.Modules.Funflow.Context
import YuanxuProof.Modules.Funflow.CausalCut
import YuanxuProof.ModuleSystem.Selection.Requirements
import YuanxuProof.PooClos.NextMethod
import YuanxuProof.PooClos.InstanceStorage
import YuanxuProof.PooClos.Dispatch
import YuanxuProof.PooClos.CarrierCapture
import YuanxuProof.Admission.Decision
import YuanxuProof.Graph.Payload
import YuanxuProof.Ops.ProcessScript
import YuanxuProof.ModuleSystem.Authoring.Queries
import YuanxuProof.Graph.Operations
import YuanxuProof.ModuleSystem.Graph.Cache
import YuanxuProof.Modules.Funflow.ConclusionRevision
import YuanxuProof.ModuleSystem.Imports
import YuanxuProof.ModuleSystem.Schema.Query
import YuanxuProof.ModuleSystem.Schema.Resolution
import YuanxuProof.Modules.Funflow.Control
import YuanxuProof.ProfileComposition.BundleIdentity
import YuanxuProof.ProfileComposition.Prototype
import YuanxuProof.ProfileComposition.Revision
import YuanxuProof.Admission.Contributions
import YuanxuProof.Admission.Realization
import YuanxuProof.ModuleSystem.Schema.Contracts
import YuanxuProof.ModuleSystem.Graph.Aggregation
import YuanxuProof.ModuleSystem.Schema.Demand
import YuanxuProof.ProfileComposition.Syntax
import YuanxuProof.ModuleSystem.Schema.Association.Semantics
import YuanxuProof.ModuleSystem.Schema.Association.Traversal
import YuanxuProof.ModuleSystem.Schema.Association.Projection
import YuanxuProof.ModuleSystem.Schema.Association.Correspondence
import YuanxuProof.ModuleSystem.Schema.Association.Requirements
import YuanxuProof.ModuleSystem.Schema.Association.Construction
import YuanxuProof.ModuleSystem.Schema.Association.Selection
import YuanxuProof.ModuleSystem.Schema.Association.NativeFixtures
import YuanxuProof.ModuleSystem.Schema.Association.Controls
import YuanxuProof.ModuleSystem.Loading.MetadataProjection
import YuanxuProof.ModuleSystem.Loading.IncrementalRoles
import Lean.Util.CollectAxioms
import Lean.Elab.Command

/-! Build every Core owner and audit the complete imported Core closure together.
This checks trust dependencies, not whether domain premises describe the runtime. -/
open Lean Elab Command
run_cmd do
  let environment ← getEnv
  let allowed := #[`propext, `Classical.choice, `Quot.sound]
  let owners := #[`YuanxuProof]
  for required in #[
      `YuanxuProof.ModuleSystem.Loading.MetadataProjection.dependenciesUnchanged,
      `YuanxuProof.ModuleSystem.Loading.MetadataProjection.parentCannotHitChild,
      `YuanxuProof.ModuleSystem.Loading.MetadataProjection.constructAtFinalContext,
      `YuanxuProof.ModuleSystem.Loading.MetadataProjection.publishRequiresBothAndCurrent,
      `YuanxuProof.Admission.IssuedRootForwarding.preserves_issuance,
      `YuanxuProof.Admission.ReadRetention.closure_coverage,
      `YuanxuProof.Admission.RootCollection.callbacks_unchanged,
      `YuanxuProof.Admission.RootCollection.first_diagnostic_unchanged,
      `YuanxuProof.Admission.ReadRetention.omitted_dependency_refused,
      `YuanxuProof.Admission.ReadRetention.child_context_keeps_joint_claim,
      `YuanxuProof.Admission.ReadRetention.changed_child_context_misses,
      `YuanxuProof.Admission.IssuedRootForwarding.cannot_hide_unissued,
      `YuanxuProof.Admission.IssuedRootForwarding.forward_keeps_dependency_closure,
      `YuanxuProof.FeatureSystem.DomainCase.Resolution.constructed_winners_unique,
      `YuanxuProof.PooClos.InstanceStorage.migration_reads_own_class,
      `YuanxuProof.PooClos.InstanceStorage.subclass_metadata_retains_class_storage,
      `YuanxuProof.Modules.Funflow.Context.demand_certificate_exact,
      `YuanxuProof.ModuleSystem.Source.Ownership.located_owner_is_declared,
      `YuanxuProof.ModuleSystem.Building.Inputs.contradictory_snapshot_rejected,
      `YuanxuProof.ModuleSystem.Building.Inputs.tool_source_accepted_iff,
      `YuanxuProof.ModuleSystem.Building.Inputs.publication_role_not_a_tool,
      `YuanxuProof.Admission.RootChild.Routing.callback_reentry_is_independent,
      `YuanxuProof.Admission.RootChild.Routing.owned_responsibility_uses_child_analysis,
      `YuanxuProof.PooClos.Dispatch.selected_methods_reference,
      `YuanxuProof.PooClos.Dispatch.cache_refines_reference,
      `YuanxuProof.PooClos.NextMethod.changed_before_rejected,
      `YuanxuProof.PooClos.InstanceStorage.surviving_cell_retained,
      `YuanxuProof.Admission.Realization.validator_package_drift_preserves_previous,
      `YuanxuProof.Admission.Contributions.accepted_row_exact,
      `YuanxuProof.Composition.Overlay.indexed_overlay_matches_first_owner,
      `YuanxuProof.ModuleSystem.Authoring.Queries.raw_claimed_query_refused,
      `YuanxuProof.Graph.Payload.adjacent_appends_coalesce,
      `YuanxuProof.Ops.ProcessScript.arguments_preserved,
      `YuanxuProof.Modules.Funflow.Policy.validated_has_capability,
      `YuanxuProof.Modules.Funflow.Policy.plan_error_has_rejected_node,
      `YuanxuProof.Admission.Publication.check_certifies,
      `YuanxuProof.Admission.Publication.stale_return_keeps_previous,
      `YuanxuProof.ProfileComposition.Composition.composition_retains_existing,
      `YuanxuProof.Admission.Publication.changed_source_rejected,
      `YuanxuProof.ProfileComposition.Composition.conflicting_prefix_aborts,
      `YuanxuProof.PooClos.MethodCombination.accepted_group_valid,
      `YuanxuProof.PooClos.MethodCombination.applicable_reference,
      `YuanxuProof.Contribution.Qualification.missingFacetEvidenceBlocksUse,
      `YuanxuProof.Modules.Funflow.CausalCut.missingParentRejected,
      `YuanxuProof.ProfileComposition.BundleIdentity.conflictingRevisionRejected,
      `YuanxuProof.Admission.Source.changedSourceCannotBeCertified,
      `YuanxuProof.Admission.Source.returnCheck_certifies,
      `YuanxuProof.Admission.RootChild.child_sources,
      `YuanxuProof.Admission.RootChild.stale_return_keeps_previous,
      `YuanxuProof.Admission.RootChild.batching_equivalent,
      `YuanxuProof.Admission.ReturnWindows.check_append,
      `YuanxuProof.Admission.ReturnWindows.defer_covered_check,
      `YuanxuProof.Admission.ReturnWindows.covered_suffix_zero_reads,
      `YuanxuProof.Admission.ReturnWindows.joint_requirements_retained,
      `YuanxuProof.Admission.ReturnWindows.cached_parent_rejected,
      `YuanxuProof.Admission.ReturnWindows.fresh_after_callback_rejects_change,
      `YuanxuProof.Admission.ReturnWindows.pure_tail_fixture_cost,
      `YuanxuProof.Admission.BoundaryComposition.composition_equivalent,
      `YuanxuProof.Admission.BoundaryComposition.changed_after_action_rejected,
      `YuanxuProof.ModuleSystem.Graph.TestAdmission.discovery_visit_bound,
      `YuanxuProof.Admission.ReplayBoundary.ordered_diagnostic_exact,
      `YuanxuProof.Admission.ReplayBoundary.successful_coverage,
      `YuanxuProof.Admission.ReplayBoundary.both_branches_retained,
      `YuanxuProof.Admission.ReplayBoundary.enroll_complete,
      `YuanxuProof.Admission.ReplayBoundary.enroll_retains_earlier,
      `YuanxuProof.Admission.ReplayBoundary.failing_prefix_preserved,
      `YuanxuProof.Admission.ReplayBoundary.moving_check_changes_diagnostic,
      `YuanxuProof.Admission.ReplayBoundary.parent_token_rejected,
      `YuanxuProof.Admission.ReplayBoundary.conflicting_source_requirement_retained,
      `YuanxuProof.Admission.ReplayBoundary.changing_first_origin_changes_diagnostic,
      `YuanxuProof.Admission.IdentityDFS.measure_decreases,
      `YuanxuProof.Admission.IdentityDFS.walk_drains,
      `YuanxuProof.Admission.IdentityDFS.discover_drained,
      `YuanxuProof.Admission.IdentityDFS.discover_nodup,
      `YuanxuProof.Admission.IdentityDFS.discover_exact,
      `YuanxuProof.Admission.IdentityDFS.final_check_exact,
      `YuanxuProof.Admission.IdentityDFS.final_covers_reachable,
      `YuanxuProof.Admission.IdentityDFS.final_rejects_changed_record,
      `YuanxuProof.Admission.IdentityDFS.accepted_reachable_source,
      `YuanxuProof.Admission.IdentityDFS.graph_ordered_diagnostic,
      `YuanxuProof.Admission.IdentityDFS.diamond_cycle_discovery,
      `YuanxuProof.Admission.IdentityDFS.same_revision_does_not_imply_prepared,
      `YuanxuProof.Admission.DFSFrames.return_stutters,
      `YuanxuProof.Admission.DFSFrames.enter_refines,
      `YuanxuProof.Admission.DFSFrames.frame_decreases,
      `YuanxuProof.Admission.DFSFrames.frames_drain,
      `YuanxuProof.Admission.DFSFrames.replay_nodup,
      `YuanxuProof.Admission.DFSFrames.replay_exact,
      `YuanxuProof.Admission.DFSFrames.final_covers_frames,
      `YuanxuProof.Admission.ReadOnlyEntry.cold_order_has_no_protocol,
      `YuanxuProof.Admission.ReadOnlyEntry.warm_state_closes,
      `YuanxuProof.Admission.ReadOnlyEntry.cold_default_closes,
      `YuanxuProof.Admission.ReadOnlyEntry.self_protocol_not_default,
      `YuanxuProof.Admission.ReadOnlyEntry.successful_lowering_no_callbacks,
      `YuanxuProof.Admission.ReadOnlyEntry.lowering_independent,
      `YuanxuProof.Admission.ReadOnlyEntry.execute_preserves_protected,
      `YuanxuProof.Admission.ReadOnlyEntry.ordered_failure_exact,
      `YuanxuProof.Admission.ReadOnlyEntry.bootstrap_anchor_read,
      `YuanxuProof.Admission.ReadOnlyEntry.bootstrap_still_current_after_clear,
      `YuanxuProof.Admission.ReadOnlyEntry.ordinary_record_rejects_clear,
      `YuanxuProof.Admission.ReadOnlyEntry.bootstrap_validity_not_readiness,
      `YuanxuProof.Admission.ReadOnlyEntry.seal_does_not_change_inspection,
      `YuanxuProof.Admission.ReadOnlyEntry.cold_dispatch_remains_open,
      `YuanxuProof.Admission.SnapshotEntry.guard_accepts_exactly,
      `YuanxuProof.Admission.SnapshotEntry.guard_rejects_changed,
      `YuanxuProof.Admission.SnapshotEntry.guarded_projection,
      `YuanxuProof.Admission.SnapshotEntry.guarded_no_callbacks,
      `YuanxuProof.Admission.SnapshotEntry.ordered_first_failure,
      `YuanxuProof.Admission.SnapshotEntry.clear_rejected_without_revision_change,
      `YuanxuProof.Admission.SnapshotEntry.checker_change_rejected,
      `YuanxuProof.Admission.SnapshotEntry.cached_value_change_rejected,
      `YuanxuProof.Admission.SnapshotEntry.observer_change_rejected,
      `YuanxuProof.Admission.SnapshotEntry.ancestor_change_rejected,
      `YuanxuProof.Admission.SnapshotEntry.observer_aba_not_history,
      `YuanxuProof.Admission.SnapshotEntry.equal_cut_not_source_authority,
      `YuanxuProof.Admission.ClosedTail.opaque_refused_before_invocation,
      `YuanxuProof.Admission.ClosedTail.closed_tail_preserves_state,
      `YuanxuProof.Admission.ClosedTail.no_foreign_call,
      `YuanxuProof.Admission.ClosedTail.accepted_retains_requirements,
      `YuanxuProof.Admission.ClosedTail.accepted_replay_stays_current,
      `YuanxuProof.Admission.ClosedTail.external_writer_still_requires_snapshot,
      `YuanxuProof.Admission.ClosedTail.return_only_misses_cleanup,
      `YuanxuProof.Admission.ClosedTail.earlier_source_failure_keeps_order,
      `YuanxuProof.Admission.CheckerOrigin.accepted_record_has_native_identity_and_owner,
      `YuanxuProof.Admission.CheckerOrigin.closure_covers_every_dependency,
      `YuanxuProof.Admission.CheckerOrigin.copied_identity_does_not_copy_ownership,
      `YuanxuProof.Admission.CheckerOrigin.raw_table_write_defeats_issuance_claim,
      `YuanxuProof.Admission.CheckerOrigin.bootstrap_currentness_does_not_imply_ownership,
      `YuanxuProof.Admission.CheckerOrigin.cache_miss_currentness_does_not_imply_ownership,
      `YuanxuProof.Admission.CheckerOrigin.fixed_kernel_preserves_state,
      `YuanxuProof.Admission.CheckerOrigin.fixed_identity_does_not_close_metadata_dispatch,
      `YuanxuProof.Admission.CheckerOrigin.accepted_retains_two_requirements_and_child,
      `YuanxuProof.Admission.CheckerOrigin.source_failure_precedes_gate_and_checker,
      `YuanxuProof.Admission.MetadataRoute.full_gate_covers_nested_lookup,
      `YuanxuProof.Admission.MetadataRoute.outer_ref_does_not_close_hash,
      `YuanxuProof.Admission.MetadataRoute.reads_table_does_not_close_instance_table,
      `YuanxuProof.Admission.MetadataRoute.closed_direct_call_preserves_state,
      `YuanxuProof.Admission.MetadataRoute.entry_only_can_become_stale,
      `YuanxuProof.Admission.MetadataRoute.equal_endpoints_do_not_erase_history,
      `YuanxuProof.Admission.MetadataRoute.equal_miss_projection_gets_same_decision,
      `YuanxuProof.Admission.MetadataRoute.no_projection_only_issuer,
      `YuanxuProof.Admission.MetadataRoute.accepted_retains_requirements_and_child,
      `YuanxuProof.Admission.MetadataRoute.earlier_source_diagnosis_preserved,
      `YuanxuProof.Admission.IssuedRead.native_mint_authenticates,
      `YuanxuProof.Admission.IssuedRead.public_constructor_is_not_issuance,
      `YuanxuProof.Admission.IssuedRead.borrowed_birth_rejects_another_token,
      `YuanxuProof.Admission.IssuedRead.changed_payload_rejected,
      `YuanxuProof.Admission.IssuedRead.whole_closure_authenticates_every_selected_dependency,
      `YuanxuProof.Admission.IssuedRead.transient_mint_needs_no_registration,
      `YuanxuProof.Admission.IssuedRead.invalid_closure_observes_nothing,
      `YuanxuProof.Admission.IssuedRead.final_accept_retains_birth_route_requirements_and_child,
      `YuanxuProof.Admission.IssuedRead.raw_private_birth_rewrite_can_forge,
      `YuanxuProof.Admission.IssuedRead.source_diagnosis_keeps_priority,
      `YuanxuProof.Admission.IssuerProjection.projection_agrees_with_verifier,
      `YuanxuProof.Admission.IssuerProjection.single_closure_authentication,
      `YuanxuProof.Admission.IssuerProjection.inspection_cannot_authenticate,
      `YuanxuProof.Admission.IssuerProjection.inspection_preserves_ordered_payload,
      `YuanxuProof.Admission.RouteMutation.equal_projection_same_decision,
      `YuanxuProof.Admission.ReplayOwnership.selected_write_refused,
      `YuanxuProof.Admission.ReplayOwnership.nested_frame_keeps_outer,
      `YuanxuProof.Admission.ReplayOwnership.delivery_write_refused,
      `YuanxuProof.Admission.ReplayOwnership.rejected_edit_has_no_partial_clear,
      `YuanxuProof.Admission.ReplayOwnership.independent_edit_allowed,
      `YuanxuProof.Admission.ReplayOwnership.unaffected_parent_unchanged,
      `YuanxuProof.Admission.ReplayOwnership.exceptional_return_restores_outer,
      `YuanxuProof.Admission.ReplayOwnership.exceptional_return_preserves_error,
      `YuanxuProof.Admission.ReplayOwnership.raw_bypass_still_has_history,
      `YuanxuProof.Admission.MetadataOwnership.unknown_refused,
      `YuanxuProof.Admission.MetadataOwnership.associated_selected_refused,
      `YuanxuProof.Admission.MetadataOwnership.nested_keeps_outer,
      `YuanxuProof.Admission.MetadataOwnership.restored_raw_route_keeps_effect,
      `YuanxuProof.Admission.MetadataAllocation.allocation_keeps_existing,
      `YuanxuProof.Admission.MetadataAllocation.allocation_registers_receiver,
      `YuanxuProof.Admission.MetadataAllocation.restoration_keeps_parent_and_revision,
      `YuanxuProof.Admission.MetadataAllocation.restoration_retains_poisoned_cold_cache,
      `YuanxuProof.Admission.MetadataAllocation.restoration_is_not_invalidation,
      `YuanxuProof.Admission.StoreLowering.mediated_prewrite_refusal,
      `YuanxuProof.Admission.StoreLowering.mediated_no_cold_poison,
      `YuanxuProof.Admission.StoreLowering.unlowered_retains_counterexample,
      `YuanxuProof.Admission.StoreLowering.precompiled_callees_refuse,
      `YuanxuProof.Admission.StoreLowering.precompiled_callees_preserve_cold,
      `YuanxuProof.Admission.StoreLowering.fixture_owners_derived,
      `YuanxuProof.Admission.StoreLowering.direct_copies_are_required,
      `YuanxuProof.Admission.StoreLowering.missing_carrier_retains_counterexample,
      `YuanxuProof.Admission.ArtifactClosure.changed_closure_refuses,
      `YuanxuProof.Admission.ArtifactClosure.raw_store_refuses,
      `YuanxuProof.Admission.ArtifactClosure.stale_inputs_refuse,
      `YuanxuProof.Admission.ArtifactClosure.prior_loading_refuses,
      `YuanxuProof.Admission.ArtifactClosure.unchanged_mediated_admits,
      `YuanxuProof.Admission.ArtifactClosure.both_requirements_preserved,
      `YuanxuProof.Admission.IssuedLoading.changed_record_refuses,
      `YuanxuProof.Admission.IssuedLoading.changed_artifact_refuses,
      `YuanxuProof.Admission.IssuedLoading.changed_snapshot_refuses,
      `YuanxuProof.Admission.IssuedLoading.allowed_checks_match,
      `YuanxuProof.Admission.IssuedLoading.public_replace_preserves_consumed_bytes,
      `YuanxuProof.Admission.IssuedLoading.latest_path_not_implied,
      `YuanxuProof.Admission.IssuedLoading.private_writer_breaks_consumption,
      `YuanxuProof.Admission.SourceLoader.changed_cache_refused,
      `YuanxuProof.Admission.SourceLoader.stable_cache_allowed,
      `YuanxuProof.Admission.SourceLoader.saved_edge_independent_of_rebinding,
      `YuanxuProof.Admission.SourceLoader.both_requirements,
      `YuanxuProof.Admission.SourceLoader.old_edge_counterexample,
      `YuanxuProof.Admission.CoreStoreRecovery.valid_other_store_refused,
      `YuanxuProof.Admission.CoreStoreRecovery.stable_restart,
      `YuanxuProof.Admission.CoreStoreRecovery.joint_replacement_refused,
      `YuanxuProof.Admission.CoreStoreRecovery.changed_source_refused,
      `YuanxuProof.Admission.CoreStoreRecovery.nonregular_issuance_refused,
      `YuanxuProof.Admission.CoreStoreRecovery.recovery_requires_registered_contents,
      `YuanxuProof.Admission.CoreStoreRecovery.integrity_without_selection_counterexample,
      `YuanxuProof.Admission.CoreApprovedRecovery.changed_approval_refused,
      `YuanxuProof.Admission.CoreApprovedRecovery.noop_cannot_restore,
      `YuanxuProof.Admission.CoreApprovedRecovery.coverage_requires_each_selected,
      `YuanxuProof.Admission.CoreApprovedRecovery.omission_refused,
      `YuanxuProof.Admission.CoreApprovedRecovery.replacement_refused,
      `YuanxuProof.Admission.CoreApprovedRecovery.changed_source_refused,
      `YuanxuProof.Admission.CoreApprovedRecovery.joint_replacement_refused,
      `YuanxuProof.Admission.CoreApprovedRecovery.accepted_preserves_boundaries,
      `YuanxuProof.Admission.CoreApprovedRecovery.restart_has_accepting_path,
      `YuanxuProof.Admission.CoreApprovedRecovery.dropping_approval_is_unsound,
      `YuanxuProof.Admission.CoreBuildHandoff.accept_requires_exact_projection,
      `YuanxuProof.Admission.CoreBuildHandoff.joint_disk_replacement_refused,
      `YuanxuProof.Admission.CoreBuildHandoff.warm_handoff,
      `YuanxuProof.Admission.CoreBuildHandoff.final_and_both_requirements,
      `YuanxuProof.Admission.CoreBuildHandoff.parent_receiver_isolation,
      `YuanxuProof.Admission.CoreBuildPublication.joint_replacement_refused,
      `YuanxuProof.Admission.CoreBuildPublication.publication_requires_final_check,
      `YuanxuProof.Admission.CoreBuildPublication.both_requirements,
      `YuanxuProof.Admission.CoreBuildPublication.native_cache_grants_no_authority,
      `YuanxuProof.Admission.CoreBuildPublication.saved_entry_uses_same_check,
      `YuanxuProof.Admission.CoreBuildPublication.first_build_cannot_adopt_cache,
      `YuanxuProof.Admission.CoreBuildPublication.unchecked_adoption_counterexample,
      `YuanxuProof.Admission.RouteMutation.raw_restore_keeps_observation,
      `YuanxuProof.Admission.RouteMutation.raw_restore_keeps_generation,
      `YuanxuProof.Admission.RouteMutation.raw_restore_retains_history,
      `YuanxuProof.Admission.RouteMutation.restored_route_same_decision,
      `YuanxuProof.Admission.RouteMutation.tracked_write_rejected,
      `YuanxuProof.Admission.RouteMutation.restoring_route_cannot_restore_generation,
      `YuanxuProof.Admission.RouteMutation.untracked_write_defeats_generation,
      `YuanxuProof.Admission.RouteMutation.active_edit_refused_before_write,
      `YuanxuProof.Admission.RouteMutation.accepted_keeps_both,
      `YuanxuProof.Admission.IssuerProjection.empty_frontier,
      `YuanxuProof.Admission.IssuerProjection.mint_preserves_frontier,
      `YuanxuProof.Admission.IssuerProjection.raw_allocation_preserves_frontier,
      `YuanxuProof.Admission.IssuerProjection.raw_allocation_has_no_authority,
      `YuanxuProof.Admission.IssuerProjection.later_mint_does_not_sign_public_copy,
      `YuanxuProof.Admission.IssuerProjection.native_mint_constructs_association,
      `YuanxuProof.Admission.IssuerProjection.mint_projects_without_birth_premise,
      `YuanxuProof.Admission.IssuerProjection.transient_cache_unchanged,
      `YuanxuProof.Admission.IssuerProjection.raw_new_record_cannot_borrow_authority,
      `YuanxuProof.Admission.IssuerProjection.mint_keeps_parent_authentication,
      `YuanxuProof.Admission.IssuerProjection.replacement_rejected,
      `YuanxuProof.Admission.IssuerProjection.restore_has_same_endpoint,
      `YuanxuProof.Admission.IssuerProjection.restored_endpoint_can_have_effect,
      `YuanxuProof.Admission.IssuerProjection.final_admission_keeps_both_requirements_and_child,
      `YuanxuProof.Admission.IssuedRead.absent_private_association_rejects,
      `YuanxuProof.Admission.IssuedRead.displaced_closure_rejects,
      `YuanxuProof.Admission.IssuedRead.authentic_closure_still_checks_payload,
      `YuanxuProof.Admission.ReturnTail.object_tail_counterexample,
      `YuanxuProof.Admission.ReturnTail.retained_requirements,
      `YuanxuProof.Admission.ReturnTail.earlier_file_counterexample,
      `YuanxuProof.Admission.ReturnTail.closed_inspection_trace,
      `YuanxuProof.Admission.ReturnTail.quiet_tail_preserves_replay,
      `YuanxuProof.Admission.ReturnTail.late_source_failure_first,
      `YuanxuProof.Admission.AdmissionBody.nested_window_current,
      `YuanxuProof.Admission.AdmissionBody.member_current,
      `YuanxuProof.Admission.AdmissionBody.changed_nested_read_rejected,
      `YuanxuProof.Admission.AdmissionBody.accepted_preserves_all,
      `YuanxuProof.Admission.AdmissionBody.changed_child_prevents_root_return,
      `YuanxuProof.Admission.AdmissionBody.completed_body_source_first,
      `YuanxuProof.Admission.AdmissionBody.nested_adapter_failure_preserved,
      `YuanxuProof.Admission.AdmissionBody.diagnostic_schedule,
      `YuanxuProof.Admission.CallPhases.cold_lookup_pushes,
      `YuanxuProof.Admission.CallPhases.warm_lookup_adds_no_frame,
      `YuanxuProof.Admission.CallPhases.body_restores_ambient,
      `YuanxuProof.Admission.CallPhases.top_level_receiver_edit_allowed,
      `YuanxuProof.Admission.CallPhases.nested_receiver_edit_vetoed,
      `YuanxuProof.Admission.CallPhases.rejected_edit_not_certified,
      `YuanxuProof.Admission.CallPhases.unrelated_demand_edit_allowed,
      `YuanxuProof.Admission.CallPhases.lookup_only_misses_body_change,
      `YuanxuProof.Admission.CallPhases.both_requirements_and_identity,
      `YuanxuProof.Admission.CallPhases.diagnostic_schedule,
      `YuanxuProof.Admission.SerialUse.cold_step_preserves_root,
      `YuanxuProof.Admission.SerialUse.serial_cold_trace_preserves_root,
      `YuanxuProof.Admission.SerialUse.cold_does_not_freeze_demand,
      `YuanxuProof.Admission.SerialUse.cold_does_not_freeze_source,
      `YuanxuProof.Admission.SerialUse.checks_keep_requirements,
      `YuanxuProof.Admission.SerialUse.changed_version_refuses_commit,
      `YuanxuProof.Admission.SerialUse.version_aba_refuses_commit,
      `YuanxuProof.Admission.SerialUse.local_success_not_commit,
      `YuanxuProof.Admission.SerialUse.preserves_diagnostic_schedule,
      `YuanxuProof.Admission.SnapshotLifetime.selected_owner_once,
      `YuanxuProof.Admission.SnapshotLifetime.outside_closure_unchanged,
      `YuanxuProof.Admission.SnapshotLifetime.receiver_revision_not_dependency_certificate,
      `YuanxuProof.Admission.SnapshotLifetime.diamond_not_multiple,
      `YuanxuProof.Admission.SnapshotLifetime.supported_aba_leaves_revision,
      `YuanxuProof.Admission.SnapshotLifetime.active_closure_veto,
      `YuanxuProof.Admission.SnapshotLifetime.different_revision_rejected,
      `YuanxuProof.Admission.SnapshotLifetime.value_aba_rejected,
      `YuanxuProof.Admission.SnapshotLifetime.scope_aba_passes_endpoints,
      `YuanxuProof.Admission.SnapshotLifetime.initial_check_does_not_fence,
      `YuanxuProof.Admission.SnapshotLifetime.late_rejection_not_rollback,
      `YuanxuProof.Admission.SnapshotLifetime.ordered_diagnostics_retained,
      `YuanxuProof.Admission.Federation.attenuationCannotAmplify,
      `YuanxuProof.Admission.Decision.revokedCannotBeAdmitted,
      `YuanxuProof.ProfileComposition.Syntax.boundBodyPreserved,
      `YuanxuProof.ModuleSystem.Graph.Cache.cacheReadEstablishesCurrentGraphClosure,
      `YuanxuProof.Modules.Funflow.ConclusionRevision.revisionRetainsHistoricalEvidence,
      `YuanxuProof.ProfileComposition.Prototype.profileRefinementsKeepFinalSelf,
      `YuanxuProof.ProfileComposition.Revision.profileRevisionInvalidatesCachedResult,
      `YuanxuProof.ModuleSystem.Schema.Contracts.accumulatedResultPreservesValues,
      `YuanxuProof.ModuleSystem.Schema.Resolution.deniedAuthorizationCannotDisclose,
      `YuanxuProof.ModuleSystem.Selection.Requirements.resolvedCapabilitiesHaveDeclaredOrigin,
      `YuanxuProof.ModuleSystem.Workflow.cached_checks_remain_current,
      `YuanxuProof.ModuleSystem.Workflow.Revision.revision_requires_discharge,
      `YuanxuProof.ModuleSystem.Workflow.Revision.stale_cannot_be_certified,
      `YuanxuProof.ModuleSystem.Schema.Association.Projection.accepted_receipt_discharged] do
    unless environment.contains required do
      throwError "Required Core integration theorem was not loaded: {required}"
  let mut count : Nat := 0
  for (name, info) in environment.constants.toList do
    if owners.any (·.isPrefixOf name) then
      count := count + 1
      -- A proposition parameter is legitimate; a record that invents its own
      -- admission propositions as fields is not a model of checked data.
      if let .inductInfo inductiveInfo := info then
        if let some structureInfo := getStructureInfo? environment name then
          for field in structureInfo.fieldInfo do
            let some projection := environment.find? field.projFn
              | throwError "Missing structure projection {field.projFn}"
            let mut resultType := projection.type
            for _ in [:inductiveInfo.numParams + 1] do
              if let .forallE _ _ body _ := resultType then
                resultType := body
              else throwError "Malformed structure projection {field.projFn}"
            if resultType == .sort .zero then
              throwError "{field.projFn} stores an arbitrary Prop; define a predicate on concrete inputs instead"
      for axiomName in (← collectAxioms name) do
        unless allowed.contains axiomName do
          throwError "{name} depends on disallowed axiom {axiomName}"
  if count = 0 then throwError "No Core declarations were audited"
  logInfo "CORE-MODEL-SHAPE-AUDIT-OK: no arbitrary Prop-valued fields"
  logInfo m!"CORE-AXIOM-AUDIT-OK: {count} declarations; standard Lean axioms only"
