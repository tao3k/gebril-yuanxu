# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Check Core-owned finite Quint models and matched counterexample controls."""
from pathlib import Path
from contextlib import nullcontext
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import tempfile

if __package__:
    from .native import QuintCLI
else:
    from native import QuintCLI

CASES = [
    ("IncrementalRoles", "safety", False),
    ("IncrementalRoles_edge", "Invalidation", True),
    ("IncrementalRoles_compile", "Compilation", True),
    ("IncrementalRoles_observer", "Observer", True),
    ("IncrementalRoles_approval", "Current", True),
    ("IncrementalRoles_parent", "Isolation", True),
    ("IncrementalRoles_dropB", "Both", True),
    ("IncrementalRoles", "NoAcceptance", True),
    ("ModuleDemand", "safety", False),
    ("ModuleDemand_preflight", "PreflightOnly", True),
    ("ModuleDemand_contract", "ValidPublication", True),
    ("ModuleDemand_classifier", "Classification", True),
    ("ModuleDemand_eager", "DeclarationOnly", True),
    ("ModuleDemand_premature", "AdmissionPhase", True),
    ("ModuleDemand_edge", "ActualTrace", True),
    ("ModuleDemand_observer", "ActualTrace", True),
    ("ModuleDemand_stale", "Fresh", True),
    ("ModuleDemand_disabled", "Enabled", True),
    ("ModuleDemand_dropB", "Both", True),
    ("ModuleDemand_parent", "ParentIsolation", True),
    ("ModuleDemand_opaque", "OpaqueCoverage", True),
    ("ModuleDemand", "NoPublication", True),
    ("SelectionReplay", "safety", False),
    ("SelectionReplay_skipObserver", "Current", True),
    ("SelectionReplay_reorder", "Diagnostic", True),
    ("SelectionReplay", "RejectAll", True),
    ("SelectionReplay", "FewerMeansFaster", True),
    ("SelectionReplay_falseMiss", "FalseHit", True),
    ("SelectionReplayTopology", "safety", False),
    ("SelectionReplayTopology_verdict", "Fresh", True),
    ("SelectionReplayTopology_roots", "Order", True),
    ("SelectionReplayTopology_seen", "Delivery", True),
    ("SelectionReplayTopology_constructor", "Construction", True),
    ("TestMakeLayout", "safety", False),
    ("TestMakeLayout_absolute", "NoWork", True),
    ("TestMakeLayout_skipSource", "Current", True),
    ("TestMakeLayout", "RejectAll", True),
    ("TestPublicationReuse", "safety", False),
    ("TestPublicationReuse_memoAdmission", "Fresh", True),
    ("TestPublicationReuse_packet", "Bound", True),
    ("TestPublicationReuse", "RejectAll", True),
    ("RootCollection", "safety", False),
    ("RootCollection_suppress", "ObserverOrder", True),
    ("RootCollection_observerOrder", "ObserverOrder", True),
    ("RootCollection_reverse", "FirstDiagnostic", True),
    ("RootCollection_receiver", "IdentityOrder", True),
    ("RootCollection_copy", "IdentityOrder", True),
    ("RootCollection_edges", "Edges", True),
    ("RootCollection", "NoWork", True),
    ("ReadRetention", "safety", False),
    ("ReadRetention_receiver", "Coverage", True),
    ("ReadRetention_miss", "Coverage", True),
    ("ReadRetention_approval", "Fresh", True),
    ("ReadRetention_dropB", "Both", True),
    ("ReadRetention_eager", "Lazy", True),
    ("ReadRetention", "RejectAll", True),
    ("ReplayOwnership_dropDelivery", "PreWriteRefusal", True),
    ("IssuedRootForwarding", "safety", False),
    ("IssuedRootForwarding_omit", "Coverage", True),
    ("IssuedRootForwarding_forge", "Authentic", True),
    ("IssuedRootForwarding_source", "Current", True),
    ("IssuedRootForwarding_dropB", "Both", True),
    ("IssuedRootForwarding_eager", "Lazy", True),
    ("IssuedRootForwarding", "RejectAll", True),
    ("CoreApprovedRecovery", "safety", False),
    ("CoreApprovedRecovery_install", "Installed", True),
    ("CoreApprovedRecovery_coverage", "Coverage", True),
    ("CoreApprovedRecovery_approval", "Approval", True),
    ("CoreApprovedRecovery_warm", "Approval", True),
    ("CoreApprovedRecovery_source", "Source", True),
    ("CoreApprovedRecovery_joint", "Files", True),
    ("CoreApprovedRecovery_dropB", "Both", True),
    ("CoreApprovedRecovery_parent", "Parent", True),
    ("CoreApprovedRecovery_eager", "Lazy", True),
    ("CoreApprovedRecovery_acceptance", "RejectAll", True),
    ("CoreStoreRecovery", "safety", False),
    ("CoreStoreRecovery_pin", "Origin", True),
    ("CoreStoreRecovery_registry", "Origin", True),
    ("CoreStoreRecovery_nar", "Origin", True),
    ("CoreStoreRecovery_asset", "Origin", True),
    ("CoreStoreRecovery_tail", "Final", True),
    ("CoreStoreRecovery_dropB", "Both", True),
    ("CoreStoreRecovery_parent", "Parent", True),
    ("CoreStoreRecovery_eager", "Lazy", True),
    ("CoreStoreRecovery_acceptance", "RejectAll", True),
    ("CoreBuildHandoff", "safety", False),
    ("CoreBuildHandoff_disk", "Origin", True),
    ("CoreBuildHandoff_selection", "Origin", True),
    ("CoreBuildHandoff_tail", "Final", True),
    ("CoreBuildHandoff_source", "Final", True),
    ("CoreBuildHandoff_parent", "Parent", True),
    ("CoreBuildHandoff_eager", "Lazy", True),
    ("CoreBuildHandoff_acceptance", "RejectAll", True),
    ('CoreBuildPublication', 'safety', False),
    ('CoreBuildPublication_adopt', 'Compiled', True),
    ('CoreBuildPublication_trustDisk', 'Issued', True),
    ('CoreBuildPublication_saved', 'Issued', True),
    ('CoreBuildPublication_skipReturn', 'Issued', True),
    ('CoreBuildPublication_dropB', 'BothRequirements', True),
    ('CoreBuildPublication_parent', 'ParentCache', True),
    ('CoreBuildPublication_eager', 'LazyBranch', True),
    ('CoreBuildPublication_acceptance', 'RejectAll', True),
    ('SourceLoader', 'safety', False),
    ('SourceLoader_oldEdge', 'EntryCoverage', True),
    ('SourceLoader_reload', 'EntryCoverage', True),
    ('SourceLoader_retry', 'EntryCoverage', True),
    ('SourceLoader_dropB', 'BothRequirements', True),
    ('SourceLoader_parent', 'ParentCache', True),
    ('SourceLoader_eager', 'LazyBranch', True),
    ('SourceLoader_acceptance', 'RejectAll', True),
    ('IssuedLoading', 'safety', False),
    ('IssuedLoading_trustSidecar', 'ByteSafety', True),
    ('IssuedLoading_skipHandoff', 'HandoffCurrent', True),
    ('IssuedLoading_publicPath', 'ByteSafety', True),
    ('IssuedLoading_skipCache', 'CacheAuthority', True),
    ('IssuedLoading_poolWriter', 'ByteSafety', True),
    ('IssuedLoading_latest', 'LatestPath', True),
    ('IssuedLoading_dropB', 'BothRequirements', True),
    ('IssuedLoading_parent', 'ParentCache', True),
    ('IssuedLoading_eager', 'LazyBranch', True),
    ('IssuedLoading_acceptance', 'RejectAll', True),
    ('ArtifactClosure', 'safety', False),
    ('ArtifactClosure_omitDependency', 'NoChangedAdmission', True),
    ('ArtifactClosure_ignoreResolution', 'NoChangedAdmission', True),
    ('ArtifactClosure_trustOldBody', 'NoPoison', True),
    ('ArtifactClosure_skipInput', 'NoChangedAdmission', True),
    ('ArtifactClosure_ignoreLoaded', 'NoChangedAdmission', True),
    ('ArtifactClosure_dropB', 'BothRequirements', True),
    ('ArtifactClosure_parent', 'ParentCache', True),
    ('ArtifactClosure_eager', 'LazyBranch', True),
    ('ArtifactClosure_acceptance', 'RejectAll', True),
    ('StoreLowering', 'safety', False),
    ('StoreLowering_unlowered', 'NoPoison', True),
    ('StoreLowering_missConstructor', 'OwnerCoverage', True),
    ('StoreLowering_missCarrier', 'DeclaredPreWrite', True),
    ('StoreLowering_missInline', 'DeclaredPreWrite', True),
    ('StoreLowering_missCallback', 'DeclaredPreWrite', True),
    ('StoreLowering_dropB', 'BothRequirements', True),
    ('StoreLowering_parent', 'ChildPlan', True),
    ('StoreLowering_eager', 'LazyBranch', True),
    ('StoreLowering_acceptance', 'RejectAll', True),
    ('MetadataAllocation', 'safety', False),
    ('MetadataAllocation_raw', 'RestoredImpliesCoherent', True),
    ('MetadataAllocation_exports', 'HiddenExportsStopReflection', True),
    ('MetadataAllocation_lastOwner', 'SupportedPreWrite', True),
    ('MetadataAllocation_dropB', 'BothRequirements', True),
    ('MetadataAllocation_parent', 'ChildPlan', True),
    ('MetadataAllocation_eager', 'LazyBranch', True),
    ('MetadataAllocation_acceptance', 'RejectAll', True),
    ('MetadataOwnership', 'safety', False),
    ('MetadataOwnership_noGuard', 'GatewayPreWrite', True),
    ('MetadataOwnership_allowUnknown', 'UnknownRefused', True),
    ('MetadataOwnership_omitBackend', 'Coverage', True),
    ('MetadataOwnership_dropB', 'BothRequirements', True),
    ('MetadataOwnership_parent', 'ChildPlan', True),
    ('MetadataOwnership_eager', 'LazyBranch', True),
    ('MetadataOwnership_raw', 'NoRawCallbacks', True),
    ('MetadataOwnership_acceptance', 'RejectAll', True),
    ('ReplayOwnership', 'safety', False),
    ('ReplayOwnership_noGuard', 'PreWriteRefusal', True),
    ('ReplayOwnership_dropOuter', 'PreWriteRefusal', True),
    ('ReplayOwnership_partialClear', 'NoPartialClear', True),
    ('ReplayOwnership_leak', 'Released', True),
    ('ReplayOwnership_dropB', 'BothRequirements', True),
    ('ReplayOwnership_parent', 'ChildPlan', True),
    ('ReplayOwnership_eager', 'LazyBranch', True),
    ('ReplayOwnership_raw', 'NoRawCallbacks', True),
    ('ReplayOwnership_acceptance', 'RejectAll', True),
    ('RouteMutation', 'safety', False),
    ('RouteMutation_endpoint', 'NoRouteWritesAtReturn', True),
    ('RouteMutation_untracked', 'NoRouteWritesAtReturn', True),
    ('RouteMutation_dropB', 'BothRequirements', True),
    ('RouteMutation_parent', 'ChildPlan', True),
    ('RouteMutation_eager', 'LazyBranch', True),
    ('RouteMutation_acceptance', 'RejectAll', True),
    ('IssuerSequence', 'safety', False),
    ('IssuerSequence_drop', 'OrderedSnapshot', True),
    ('IssuerSequence_order', 'OrderedSnapshot', True),
    ('IssuerSequence_alias', 'OrderedSnapshot', True),
    ('IssuerProjection', 'safety', False),
    ('IssuerProjection_noRegistry', 'AuthenticAtReturn', True),
    ('IssuerProjection_noPayload', 'AuthenticAtReturn', True),
    ('IssuerProjection_cacheMiss', 'MissNotCached', True),
    ('IssuerProjection_noRoute', 'NoForeignKernelCalls', True),
    ('IssuerProjection_skipFinal', 'EndpointCurrent', True),
    ('IssuerProjection_dropB', 'BothRequirements', True),
    ('IssuerProjection_parent', 'ChildPlan', True),
    ('IssuerProjection_eager', 'LazyBranch', True),
    ('IssuerProjection_history', 'NoCallbackEffects', True),
    ('IssuerProjection_acceptance', 'RejectAll', True),
    ('IssuedRead', 'safety', False),
    ('IssuedRead_noBirth', 'NoForgery', True),
    ('IssuedRead_rootOnly', 'WholeClosureBeforeObserve', True),
    ('IssuedRead_noRoute', 'NoForeignCheckerCalls', True),
    ('IssuedRead_skipFinal', 'FinalAuthenticity', True),
    ('IssuedRead_registerMiss', 'MissNotCached', True),
    ('IssuedRead_rawBirth', 'NoForgery', True),
    ('IssuedRead_dropB', 'TwoRequirements', True),
    ('IssuedRead_parent', 'FinalPlan', True),
    ('IssuedRead_acceptance', 'RejectAll', True),
    ('MetadataRoute', 'safety', False),
    ('MetadataRoute_refOnly', 'NoForeignCalls', True),
    ('MetadataRoute_readsOnly', 'NoForeignCalls', True),
    ('MetadataRoute_entryOnly', 'NoForeignCalls', True),
    ('MetadataRoute_endpoint', 'NoForeignCalls', True),
    ('MetadataRoute_issuance', 'Issuance', True),
    ('MetadataRoute_dropB', 'TwoRequirements', True),
    ('MetadataRoute_parent', 'FinalPlan', True),
    ('MetadataRoute_acceptance', 'RejectAll', True),
    ('CheckerOrigin', 'safety', False),
    ('CheckerOrigin_identityOnly', 'OwnedAtAdmission', True),
    ('CheckerOrigin_invokeAny', 'NoForeignCheckerCalls', True),
    ('CheckerOrigin_rootOnly', 'NoForeignCheckerCalls', True),
    ('CheckerOrigin_rawTable', 'AuthenticIssuance', True),
    ('CheckerOrigin_metadataHook', 'NoForeignCalls', True),
    ('CheckerOrigin_dropB', 'BothRequirements', True),
    ('CheckerOrigin_parent', 'FinalPlan', True),
    ('CheckerOrigin_acceptance', 'RejectAll', True),
    ("NativeSemanticQuery", "safety", False),
    ("GraphOperations_none", "safety", False),
    ("GraphOperations_reverseOrder", "OrderedPayload", True),
    ("GraphOperations_wrongTarget", "PathIdentity", True),
    ("GraphOperations_orphanDelete", "StructuralClosure", True),
    ("GraphOperations_replay", "OrderedPayload", True),
    ("GraphOperations_fixedPoint", "HonestReceipt", True),
    ("TestSourceAdmission", "safety", False),
    ("TestSourceAdmission_eager", "NoUnrelatedExpansion", True),
    ("TestSourceAdmission_stale", "CurrentEvidence", True),
    ("TestSourceAdmission_cleanup", "FailureCleanup", True),
    ("TestSourceAdmission_hardStop", "FailureCleanup", True),
    ("TestSourceAdmission_secondGraph", "SameGraphIdentity", True),
    ("TestSourceAdmission_repeat", "UniqueDiscovery", True),
    ("TestSourceAdmission_dropDeferred", "CompleteConfiguration", True),
    ("SourceClosureWork", "safety", False),
    ("SourceClosureWork_repeat", "UniqueExpansion", True),
    ("SourceClosureWork_eager", "DemandOnly", True),
    ("SourceClosureWork_drop", "Complete", True),
    ("SourceClosureWork_reuse", "Current", True),
    ("SourceClosureWork_rescan", "PureEpochOnce", True),
    ("SourceClosureWork_wideGuard", "GuardScope", True),
    ("SourceClosureWork_leak", "Cleanup", True),
    ("SourceClosureWork_acceptance", "RejectAll", True),
    ("SourcePrefix", "safety", False),
    ("SourcePrefix_open", "EntryCurrent", True),
    ("SourcePrefix_scope", "EntryCurrent", True),
    ("SourcePrefix_carry", "PublishedCurrent", True),
    ("SourcePrefix_coldMetadata", "PublishedCurrent", True),
    ("SourcePrefix_contextAfterCheck", "PublishedCurrent", True),
    ("SourcePrefix_rawSubject", "SameAdmittedSubject", True),
    ("SourcePrefix_drop", "PublishedCurrent", True),
    ("SourcePrefix_repeat", "ClosedPrefixOnce", True),
    ("SourcePrefix_cleanup", "Cleanup", True),
    ("SourcePrefix_acceptance", "RejectAll", True),
    ("DependencyContinuation", "safety", False),
    ("DependencyContinuation_openWalk", "OpenEntryCurrent", True),
    ("DependencyContinuation_unseenToken", "OpenEntryCurrent", True),
    ("DependencyContinuation_beforeRead", "OpenEntryCurrent", True),
    ("DependencyContinuation_beforeFeature", "OpenEntryCurrent", True),
    ("DependencyContinuation_drop", "PublishedCurrent", True),
    ("DependencyContinuation_earlyPublish", "AcceptedOnlyAtEnd", True),
    ("DependencyContinuation_cleanup", "Cleanup", True),
    ("DependencyContinuation_acceptance", "RejectAll", True),
    ("ReaderEffectSupport", "safety", False),
    ("ReaderEffectSupport_importsOnly", "EntrySupport", True),
    ("ReaderEffectSupport_returnImports", "ReturnSupport", True),
    ("ReaderEffectSupport_cleanup", "Cleanup", True),
    ("ReaderEffectSupport_acceptance", "RejectAll", True),
    ("CandidatePublication", "safety", False),
    ("CandidatePublication_dropImport", "LocalEntry", True),
    ("CandidatePublication_openBefore", "OpenEntry", True),
    ("CandidatePublication_openAfter", "OpenReturn", True),
    ("CandidatePublication_skipCommit", "FinalCurrent", True),
    ("CandidatePublication_dropSchema", "FinalCurrent", True),
    ("CandidatePublication_earlyVisible", "CommitOnly", True),
    ("CandidatePublication_replaceOnFailure", "KeepPrevious", True),
    ("CandidatePublication_cleanup", "Cleanup", True),
    ("CandidatePublication_acceptance", "RejectAll", True),
    ("CandidatePublication_retainScratch", "NoSpuriousRefusal", True),
    ("CandidateLocation", "safety", False),
    ("CandidateLocation_dropCachedPath", "LocalEntry", True),
    ("CandidateLocation_skipCommit", "FinalCurrent", True),
    ("CandidateLocation_acceptance", "RejectAll", True),
    ("CompilerEnrollment", "safety", False),
    ("CompilerEnrollment_reuseApproval", "FreshDemand", True),
    ("CompilerEnrollment_dropEnrollment", "Complete", True),
    ("CompilerEnrollment_acceptance", "RejectAll", True),
    ("AuthoringStage", "safety", False),
    ("AuthoringStage_skipAdmission", "BoundaryChecked", True),
    ("AuthoringStage_oldContract", "ValidAdmission", True),
    ("AuthoringStage_rawSubject", "CheckedSubject", True),
    ("AuthoringStage_skipCommit", "CurrentPublication", True),
    ("AuthoringStage_acceptance", "RejectAll", True),
    ("CarrierReturn", "ValidExecution", False),
    ("CarrierReturn_skipReturn", "ValidExecution", True),
    ("CarrierReturn_acceptance", "RejectAll", True),
    ("CarrierAdmission", "safety", False),
    ("CarrierAdmission_skipBefore", "CheckedHandoff", True),
    ("CarrierAdmission_skipAfter", "ValidExecution", True),
    ("CarrierAdmission_acceptance", "RejectAll", True),
    ("WitnessReplay", "safety", False),
    ("WitnessReplay_dropLive", "Complete", True),
    ("WitnessReplay_openWeak", "Complete", True),
    ("WitnessReplay_missing", "LiveToken", True),
    ("WitnessReplay_skipFinal", "Current", True),
    ("WitnessReplay_repeat", "BatchWork", True),
    ("WitnessReplay_noPin", "LiveRoots", True),
    ("WitnessReplay_retain", "Released", True),
    ("WitnessReplay_acceptance", "RejectAll", True),
    ("ContextWalk", "safety", False),
    ("ContextWalk_lateMark", "UniqueEntry", True),
    ("ContextWalk_preorder", "Prefix", True),
    ("ContextWalk_ignoreCut", "Prefix", True),
    ("ContextWalk_forgetShared", "UniqueEntry", True),
    ("ContextWalk_dropAfter", "Complete", True),
    ("ContextWalk_eager", "Lazy", True),
    ("ContextWalk_acceptance", "RejectAll", True),
    ("ReaderProjection", "safety", False),
    ("ReaderProjection_retain", "NoIdleProjection", True),
    ("ReaderProjection_cacheInputs", "ExactInputs", True),
    ("ReaderProjection_cutUnknown", "ExactInputs", True),
    ("ReaderProjection_dropSource", "ExactInputs", True),
    ("ReaderProjection_skipGuard", "Current", True),
    ("ReaderProjection_acceptance", "RejectAll", True),
    ("PublicationReads", "safety", False),
    ("PublicationReads_byKey", "Complete", True),
    ("PublicationReads_failure", "Complete", True),
    ("PublicationReads_observers", "AllEvents", True),
    ("PublicationReads_suffix", "Current", True),
    ("PublicationReads_skipGuard", "Current", True),
    ("PublicationReads_acceptance", "RejectAll", True),
    ("CarrierRoots", "safety", False),
    ("CarrierRoots_strongObserver", "WeakDiagnostic", True),
    ("CarrierRoots_dropArgument", "SamePayloads", True),
    ("CarrierRoots_forgetRead", "ReadRetention", True),
    ("CarrierRoots_clearSDK", "CanonicalPreserved", True),
    ("CarrierRoots_payload", "PayloadGoneAfterReturn", True),
    ("CarrierRoots_acceptance", "RejectAll", True),
    ("SemanticReads", "safety", False),
    ("SemanticReads_policy", "Current", True),
    ("SemanticReads_contract", "Current", True),
    ("SemanticReads_source", "Current", True),
    ("SemanticReads_generic", "Current", True),
    ("SemanticReads_escape", "Current", True),
    ("SemanticReads_return", "Current", True),
    ("SemanticReads_acceptance", "RejectAll", True),
    ("OwnedReads", "safety", False),
    ("OwnedReads_promotion", "Current", True),
    ("OwnedReads_policy", "Current", True),
    ("OwnedReads_dead", "Current", True),
    ("OwnedReads_missing", "MissingRefused", True),
    ("OwnedReads_open", "UnknownStrong", True),
    ("OwnedReads_acceptance", "RejectAll", True),
    ("OwnedReads_construction", "ConstructorOnly", True),
    ("OwnedReads_generation", "GenerationStable", True),
    ("OwnedReads_parentDuring", "GenerationStable", True),
    ("SourceWindows", "safety", False),
    ("SourceWindows_cross", "CurrentEvidence", True),
    ("SourceWindows_omit", "CompleteRequirements", True),
    ("SourceWindows_receiver", "FinalReceiver", True),
    ("SourceWindows_repeat", "OncePerWindow", True),
    ("SourceWindows_eager", "LazyBranch", True),
    ("SourceWindows_skipfinal", "CurrentEvidence", True),
    ("SourceWindows_acceptance", "RejectAll", True),
    ("RootChild", "safety", False),
    ("RootChild_analyticAuthority", "FinalSources", True),
    ("RootChild_crossEffect", "FinalSources", True),
    ("RootChild_omit", "TwoRequirements", True),
    ("RootChild_skipchild", "DomainChecks", True),
    ("RootChild_omitSource", "FinalSources", True),
    ("RootChild_parent", "ReceiverIsolation", True),
    ("RootChild_eager", "LazyBranch", True),
    ("RootChild_lateEffect", "FinalSources", True),
    ("RootChild_acceptance", "RejectAll", True),
    ("ReturnWindows", "safety", False),
    ("ReturnWindows_pure", "safety", False),
    ("ReturnWindows_skipBefore", "CallbackEntry", True),
    ("ReturnWindows_crossContribution", "PostContribution", True),
    ("ReturnWindows_trustReturn", "FinalSources", True),
    ("ReturnWindows_crossReplay", "FinalSources", True),
    ("ReturnWindows_omitLate", "CompleteProjection", True),
    ("ReturnWindows_dropParty", "TwoRequirements", True),
    ("ReturnWindows_repeat", "PureBudget", True),
    ("ReturnWindows_acceptance", "RejectAll", True),
    ("ReplayBoundary", "safety", False),
    ("ReplayBoundary_move", "OrderedDiagnostic", True),
    ("ReplayBoundary_reuse", "SourcesCurrent", True),
    ("ReplayBoundary_omit", "CompleteCoverage", True),
    ("ReplayBoundary_effects", "NoEffects", True),
    ("ReplayBoundary_acceptance", "RejectAll", True),
    ("IdentityDFS", "safety", False),
    ("IdentityDFS_lateMark", "TerminationBound", True),
    ("IdentityDFS_payload", "CompleteCoverage", True),
    ("IdentityDFS_noFinal", "RecheckedCurrent", True),
    ("IdentityDFS_dropFinal", "FinalCoverage", True),
    ("IdentityDFS_finalWrite", "RecheckedCurrent", True),
    ("IdentityDFS_sourceReuse", "SourcesCurrent", True),
    ("IdentityDFS_parent", "ReceiverIdentity", True),
    ("IdentityDFS_acceptance", "RejectAll", True),
    ('ReadOnlyEntry', 'safety', False),
    ('ReadOnlyEntry_sealed', 'NoOpaque', True),
    ('ReadOnlyEntry_revision', 'NoOpaque', True),
    ('ReadOnlyEntry_checker', 'NoOpaque', True),
    ('ReadOnlyEntry_observer', 'NoOpaque', True),
    ('ReadOnlyEntry_anchorExecute', 'NoOpaque', True),
    ('ReadOnlyEntry_scopeReuse', 'NoOpaque', True),
    ('ReadOnlyEntry_dropPrefix', 'OrderedDiagnostic', True),
    ('ReadOnlyEntry_parent', 'ReceiverIdentity', True),
    ('ReadOnlyEntry_sourceReuse', 'SourcesCurrent', True),
    ('ReadOnlyEntry_acceptance', 'RejectAll', True),
    ('SnapshotEntry', 'safety', False),
    ('SnapshotEntry_revision', 'ChangedRejected', True),
    ('SnapshotEntry_checker', 'ChangedRejected', True),
    ('SnapshotEntry_value', 'ChangedRejected', True),
    ('SnapshotEntry_observer', 'ChangedRejected', True),
    ('SnapshotEntry_ancestor', 'ChangedRejected', True),
    ('SnapshotEntry_source', 'SourcesCurrent', True),
    ('SnapshotEntry_prefix', 'OrderedDiagnostic', True),
    ('SnapshotEntry_parent', 'ReceiverIdentity', True),
    ('SnapshotEntry_aba', 'NoInterveningCallback', True),
    ('SnapshotEntry_acceptance', 'RejectAll', True),
    ('ClosedTail', 'safety', False),
    ('ClosedTail_foreign', 'NoForeignCalls', True),
    ('ClosedTail_returnOnly', 'ObjectsCurrent', True),
    ('ClosedTail_dropB', 'TwoRequirements', True),
    ('ClosedTail_parent', 'ChildIdentity', True),
    ('ClosedTail_prefix', 'OrderedDiagnostic', True),
    ('ClosedTail_external', 'SourcesCurrent', True),
    ('ClosedTail_acceptance', 'RejectAll', True),
    ('ReturnTail', 'recordedChecks', False),
    ('ReturnTail_skipReplay', 'ReplayWasCurrent', True),
    ('ReturnTail_skipFile', 'FilesMatchedWhenRead', True),
    ('ReturnTail_dropB', 'RequirementsWereChecked', True),
    ('ReturnTail_parent', 'ChildIdentity', True),
    ('ReturnTail_prefix', 'DiagnosticOrder', True),
    ('ReturnTail_objects', 'ObjectsCurrentAtReturn', True),
    ('ReturnTail_sources', 'SourcesCurrentAtReturn', True),
    ('ReturnTail_plan', 'PlanMatchesAtReturn', True),
    ('ReturnTail_acceptance', 'RejectAll', True),
    ('AdmissionBody', 'safety', False),
    ('AdmissionBody_acquisitionOnly', 'ObservedCurrent', True),
    ('AdmissionBody_skipReplay', 'ObservedCurrent', True),
    ('AdmissionBody_trustHot', 'HotBodies', True),
    ('AdmissionBody_skipChild', 'ChildOwnReject', True),
    ('AdmissionBody_dropB', 'TwoRequirements', True),
    ('AdmissionBody_parent', 'ChildIdentity', True),
    ('AdmissionBody_prefix', 'DiagnosticOrder', True),
    ('AdmissionBody_noWrites', 'NoWritesBeforeReject', True),
    ('AdmissionBody_acceptance', 'RejectAll', True),
    ('CallPhases', 'safety', False),
    ('CallPhases_acceptVeto', 'FailedBodyRejected', True),
    ('CallPhases_lookupOnly', 'CurrentPlan', True),
    ('CallPhases_leak', 'MethodUnwound', True),
    ('CallPhases_dropCaller', 'NestedProtected', True),
    ('CallPhases_dropB', 'TwoRequirements', True),
    ('CallPhases_parent', 'ReceiverIdentity', True),
    ('CallPhases_prefix', 'OrderedDiagnostic', True),
    ('CallPhases_protected', 'NoBodyMutation', True),
    ('CallPhases_acceptance', 'RejectAll', True),
    ('SerialUse', 'safety', False),
    ('SerialUse_noGuard', 'ActiveProtected', True),
    ('SerialUse_omitDemand', 'ReadCurrent', True),
    ('SerialUse_dropB', 'TwoRequirements', True),
    ('SerialUse_parent', 'ReceiverIdentity', True),
    ('SerialUse_prefix', 'OrderedDiagnostic', True),
    ('SerialUse_localOnly', 'ConditionalCommit', True),
    ('SerialUse_coldAll', 'ColdFreezesAll', True),
    ('SerialUse_acceptance', 'RejectAll', True),
    ('SnapshotLifetime', 'safety', False),
    ('SnapshotLifetime_valueOnly', 'CurrentPlan', True),
    ('SnapshotLifetime_receiverOnly', 'CurrentPlan', True),
    ('SnapshotLifetime_crossEffect', 'SourcesCurrent', True),
    ('SnapshotLifetime_skipClosure', 'ActiveBlocked', True),
    ('SnapshotLifetime_duplicate', 'OncePerOwner', True),
    ('SnapshotLifetime_parent', 'ReceiverIdentity', True),
    ('SnapshotLifetime_dropRequirement', 'TwoRequirements', True),
    ('SnapshotLifetime_prefix', 'OrderedDiagnostic', True),
    ('SnapshotLifetime_history', 'EndpointMeansNoEffect', True),
    ('SnapshotLifetime_fenced', 'NoStaleUse', True),
    ('SnapshotLifetime_acceptance', 'RejectAll', True),
]
COUNTS = re.compile(rb"([\d,]+) states generated, ([\d,]+) distinct states.*?([\d,]+) states left on queue")


def typecheck_entries(quint, sources):
    """Fresh native CLI stages per entry, sharing only the Node runtime."""
    with QuintCLI(quint, "typecheck") as runtime:
        for source in sources:
            source = str(source.resolve())
            status, output = runtime.request({"input": source})
            if status != 0:
                raise RuntimeError(f"Quint typecheck failed: {source}: {output.decode(errors='replace')}")
            print(f"QUINT-TYPECHECK-ENTRY {source}", flush=True)


def scheme(value):
    if isinstance(value, bool):
        return "#t" if value else "#f"
    if isinstance(value, str):
        return json.dumps(value)
    if isinstance(value, dict):
        return "(" + " ".join("(" + key + " . " + scheme(item) + ")" for key, item in value.items()) + ")"
    if isinstance(value, list):
        return "(" + " ".join(map(scheme, value)) + ")"
    return str(value)


def quint_executable():
    local = Path(__file__).resolve().parent / "node_modules/.bin/quint"
    return os.environ.get("QUINT_BIN", str(local) if local.exists() else shutil.which("quint"))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--quint", default=quint_executable())
    parser.add_argument("--server-endpoint", default=os.environ.get("QUINT_SERVER_ENDPOINT"))
    parser.add_argument("--receipt", type=Path, required=True)
    parser.add_argument("--case-prefix", help="Qualify an explicitly scoped subset; default is the complete catalog")
    parser.add_argument("--producer-source", type=Path,
                        help="Bind native gerbil-poo source owners for replay/incremental correspondence")
    parser.add_argument("--shard-count", type=int, default=1)
    parser.add_argument("--shard-index", type=int, default=0)
    parser.add_argument("--typecheck-scope", choices=("all", "selected"), default="all",
                        help="Keep all-source checking by default; selected checks each named case and its native imports")
    args = parser.parse_args()
    if args.shard_count < 1 or not 0 <= args.shard_index < args.shard_count:
        parser.error("shard index must be within the positive shard count")
    if args.case_prefix and args.shard_count != 1:
        parser.error("case-prefix and catalog sharding are separate qualification modes")
    selected_cases = [case for case in CASES if not args.case_prefix or case[0].startswith(args.case_prefix)]
    selected_cases = selected_cases[args.shard_index::args.shard_count]
    if not selected_cases:
        parser.error("case prefix selects no catalogued models")
    if args.typecheck_scope == "selected" and not args.case_prefix:
        parser.error("selected typechecking requires an explicit --case-prefix")
    producer_bound = []
    if args.producer_source:
        if not args.case_prefix or not args.case_prefix.startswith(("SelectionReplay", "IncrementalRoles")):
            parser.error("producer-source requires replay or incremental correspondence cases")
        args.producer_source = args.producer_source.resolve()
        producer_bound = [args.producer_source / name for name in
                          ("gerbil.pkg", "object.ss", "object-state.ss", "slot-observation.ss",
                           "read-route.ss", "slot-layout.ss", "prototype-map.ss",
                           "support/object-syntax.ss", "t/issued-read-test.ss")]
        if not all(p.is_file() for p in producer_bound):
            parser.error("producer-source must contain the complete selected native source owners")
    args.receipt.unlink(missing_ok=True)
    version = subprocess.check_output([args.quint, "--version"], text=True, timeout=5).strip()
    if version != "0.33.0":
        raise SystemExit(f"expected Quint 0.33.0, got {version}")
    models = Path(__file__).resolve().parent
    core = models.parents[2]
    bound = (sorted(models.glob("*.qnt")) + sorted((core / "graph").glob("*.ss"))
             + sorted((core / "module-system/schema/support").glob("*.ss"))
             + [core / "t/graph-operations-test.ss", core / "module-system/source/projection.ss",
                core / "module-system/source/collection.ss", core / "t/module-source-admission-test.ss",
                core / "dev/proofs/lean/YuanxuProof/ModuleSystem/Source/Collections.lean"])
    bound.extend(sorted((core / "modules/funflow/control-plane").glob("*.ss")))
    bound.extend([core / "modules/funflow/types.ss", core / "modules/funflow/objects.ss",
                  core / "modules/funflow/func.ss", core / "modules/funflow/store.ss",
                  core / "t/funflow-function-types-test.ss",
                  core / "dev/proofs/lean/YuanxuProof/Modules/Funflow/FunctionBoundary.lean"])
    def digests():
        current = set(bound) | set(models.glob("*.qnt"))
        if all(case[0].startswith(("TestMakeLayout", "TestPublicationReuse", "SelectionReplay")) for case in selected_cases):
            # A scoped test-publication receipt binds its actual consumers and the
            # complete local Lean source tree, not deleted tests of unrelated
            # model owners. The full-catalogue gate keeps its original bindings.
            current = (set(layout_bound) | set(models.glob("*.qnt")) |
                       set((core / "dev/proofs/lean/YuanxuProof").rglob("*.lean")))
            if all(case[0].startswith("SelectionReplay") for case in selected_cases):
                current |= set(selection_bound)
        result = {str(p.relative_to(core)): hashlib.sha256(p.read_bytes()).hexdigest()
                  for p in sorted(current)}
        result.update({os.path.relpath(p, core):
                       hashlib.sha256(p.read_bytes()).hexdigest() for p in producer_bound})
        return result
    incremental_lean = core / "dev/proofs/lean/YuanxuProof/ModuleSystem/Loading/IncrementalRoles.lean"
    incremental_digest = "sha256:" + hashlib.sha256((models / "IncrementalRoles.qnt").read_bytes()).hexdigest()
    if f'quintSourceDigest : String := "{incremental_digest}"' not in incremental_lean.read_text():
        raise AssertionError("Lean retains a stale IncrementalRoles Quint source binding")
    bound.extend([incremental_lean, core / "t/module-incremental-cache-test.ss",
                  core / "t/module-incremental-make-test.ss",
                  core / "dev/sysml/20-module-loading/20.03-incremental-role-ownership.sysml",
                  core / "t/module-retention-census-test.ss",
                  core / "module-system/building/test-observation.ss",
                  core / "t/qualification/module-scale/fixture.ss",
                  core / "t/qualification/module-scale/worker-test.ss",
                  core / "poo-clos/objects.ss", core / "poo-clos/dispatch.ss"])
    demand_lean = core / "dev/proofs/lean/YuanxuProof/ModuleSystem/Loading/MetadataProjection.lean"
    demand_digest = "sha256:" + hashlib.sha256((models / "ModuleDemand.qnt").read_bytes()).hexdigest()
    if f'quintSourceDigest : String := "{demand_digest}"' not in demand_lean.read_text():
        raise AssertionError("Lean retains a stale ModuleDemand Quint source binding")
    bound.extend([demand_lean, core / "t/module-demand-projection-test.ss",
                  core / "dev/sysml/20-module-loading/20.01-demanded-module-lifecycle.sysml",
                  core / "module-system/source/declaration.ss",
                  core / "module-system/source/role-forms.ss",
                  core / "module-system/source/preparation.ss",
                  core / "module-system/bootstrap/body-inclusion.ss"])
    bound.extend(sorted((core / "t/qualification/module-demand").rglob("*.ss")))
    issued_roots_lean = core / "dev/proofs/lean/YuanxuProof/Admission/IssuedRootForwarding.lean"
    layout_lean = core / "dev/proofs/lean/YuanxuProof/Admission/TestMakeLayout.lean"
    layout_digest = "sha256:" + hashlib.sha256((models / "TestMakeLayout.qnt").read_bytes()).hexdigest()
    if f'quintSourceDigest : String := "{layout_digest}"' not in layout_lean.read_text():
        raise AssertionError("Lean retains a stale TestMakeLayout Quint source binding")
    reuse_lean = core / "dev/proofs/lean/YuanxuProof/Admission/TestPublicationReuse.lean"
    reuse_digest = "sha256:" + hashlib.sha256((models / "TestPublicationReuse.qnt").read_bytes()).hexdigest()
    if f'quintSourceDigest : String := "{reuse_digest}"' not in reuse_lean.read_text():
        raise AssertionError("Lean retains a stale TestPublicationReuse Quint source binding")
    selection_lean = core / "dev/proofs/lean/YuanxuProof/Admission/SelectionReplay.lean"
    selection_digest = "sha256:" + hashlib.sha256((models / "SelectionReplay.qnt").read_bytes()).hexdigest()
    if f'quintSourceDigest : String := "{selection_digest}"' not in selection_lean.read_text():
        raise AssertionError("Lean retains a stale SelectionReplay Quint source binding")
    topology_digest = "sha256:" + hashlib.sha256((models / "SelectionReplayTopology.qnt").read_bytes()).hexdigest()
    if f'topologySourceDigest : String := "{topology_digest}"' not in selection_lean.read_text():
        raise AssertionError("Lean retains a stale replay topology Quint source binding")
    declared_poo = re.search(r'github\.com/tao3k/gerbil-poo@([0-9a-f]{40})',
                             (core / "gerbil.pkg").read_text())
    if not declared_poo or f'declaredPooRevision : String := "{declared_poo[1]}"' not in selection_lean.read_text():
        raise AssertionError("Replay proof correspondence retains a stale gerbil-poo revision")
    if producer_bound:
        producer_digest = "sha256:" + hashlib.sha256((args.producer_source / "object.ss").read_bytes()).hexdigest()
        if f'projectionObjectDigest : String := "{producer_digest}"' not in selection_lean.read_text():
            raise AssertionError("Replay projection proof retains a stale native object source binding")
    selection_bound = [selection_lean, core / "module-system/source/reader.ss",
                       core / "module-system/source/admission.ss", core / "module-system/source/link.ss",
                       core / "module-system/source/publication.ss", core / "t/module-publication-test.ss",
                       core / "t/reader-root-collection-test.ss", core / "t/slot-read-replay-test.ss",
                       core / "t/runtime-statistics-test.ss", core / "t/module-source-cost-test.ss"]
    selection_bound += [core / "t/mop-checker-origin-test.ss"]
    layout_bound = [layout_lean, core / "module-system/building/build-projection.ss",
                  core / "module-system/building/artifacts.ss",
                  core / "observability/testing-script.ss", core / "t/module-test-preparation-test.ss",
                  core / "module-system/building/interface.ss", core / "module-system/building/test-projection.ss",
                  core / "module-system/building/source-closure.ss", core / "t/qualification/testing/run.ss",
                  core / "t/gitea-postgresql-publication-test.ss", core / "admission/source.ss",
                  core / "scenarios/gitea-postgresql/types.ss",
                  core / "scenarios/gitea-postgresql/gitea/types.ss",
                  core / "scenarios/gitea-postgresql/postgresql/types.ss",
                  core / "dev/proofs/lean/lakefile.lean", core / "dev/proofs/lean/lake-manifest.json",
                  core / "dev/proofs/lean/YuanxuProof.lean", core / "gerbil.pkg",
                  Path(__file__).resolve(), models / "backend.py",
                  core / "dev/proofs/lean/lean-toolchain",
                  core / "dev/sysml/10-evaluation/10.01-efficient-caching.sysml"]
    bound.extend(layout_bound)
    retention_lean = core / "dev/proofs/lean/YuanxuProof/Admission/ReadRetention.lean"
    collection_lean = core / "dev/proofs/lean/YuanxuProof/Admission/RootCollection.lean"
    collection_digest = "sha256:" + hashlib.sha256((models / "RootCollection.qnt").read_bytes()).hexdigest()
    if f'quintSourceDigest : String :=\n  "{collection_digest}"' not in collection_lean.read_text():
        raise AssertionError("Lean retains a stale RootCollection Quint source binding")
    bound.extend([collection_lean, core / "module-system/source/reader.ss",
                  core / "object-family/read-projection.ss", core / "t/read-retention-cost-test.ss",
                  core / "t/module-publication-test.ss"])
    retention_digest = "sha256:" + hashlib.sha256((models / "ReadRetention.qnt").read_bytes()).hexdigest()
    if f'quintSourceDigest : String :=\n  "{retention_digest}"' not in retention_lean.read_text():
        raise AssertionError("Lean retains a stale ReadRetention Quint source binding")
    bound.extend([retention_lean, core / "t/read-retention-cost-test.ss",
                  core / "t/gitea-postgresql-publication-test.ss",
                  core / "object-family/read-projection.ss"])
    issued_roots_digest = "sha256:" + hashlib.sha256((models / "IssuedRootForwarding.qnt").read_bytes()).hexdigest()
    if f'quintSourceDigest : String :=\n  "{issued_roots_digest}"' not in issued_roots_lean.read_text():
        raise AssertionError("Lean retains a stale IssuedRootForwarding Quint source binding")
    bound.extend([issued_roots_lean, core / "t/issued-root-forwarding-test.ss",
                  core / "t/persistent-selected-head-test.ss",
                  core / "t/contract-diagnostics-test.ss",
                  core / "scenarios/gitea-postgresql/types.ss",
                  core / "scenarios/gitea-postgresql/gitea/types.ss",
                  core / "scenarios/gitea-postgresql/postgresql/types.ss"])
    window_lean = core / "dev/proofs/lean/YuanxuProof/Admission/SourceWindows.lean"
    window_digest = "sha256:" + hashlib.sha256((models / "SourceWindows.qnt").read_bytes()).hexdigest()
    if f'quintSourceDigest : String :=\n  "{window_digest}"' not in window_lean.read_text():
        raise AssertionError("Lean retains a stale SourceWindows Quint source binding")
    bound.extend([window_lean, core / "admission/source.ss",
                  core / "admission/contributions.ss", core / "module-system/source/admission.ss",
                  core / "dev/proofs/lean/YuanxuProof/Admission/Source.lean",
                  core / "dev/proofs/lean/lakefile.lean", core / "dev/proofs/lean/lake-manifest.json",
                  core / "dev/proofs/lean/lean-toolchain", core / "gerbil.pkg",
                  core / "t/source-admission-test.ss", core / "t/source-observation-test.ss",
                  core / "t/slot-read-cost-test.ss"])
    root_child_lean = core / "dev/proofs/lean/YuanxuProof/Admission/RootChild.lean"
    root_child_digest = "sha256:" + hashlib.sha256((models / "RootChild.qnt").read_bytes()).hexdigest()
    if f'quintSourceDigest : String :=\n  "{root_child_digest}"' not in root_child_lean.read_text():
        raise AssertionError("Lean retains a stale RootChild Quint source binding")
    bound.extend([root_child_lean, core / "object-types/contracts.ss", core / "object-types/ports.ss", core / "admission/publication.ss"])
    return_lean = core / "dev/proofs/lean/YuanxuProof/Admission/ReturnWindows.lean"
    return_digest = "sha256:" + hashlib.sha256((models / "ReturnWindows.qnt").read_bytes()).hexdigest()
    if f'quintSourceDigest : String :=\n  "{return_digest}"' not in return_lean.read_text():
        raise AssertionError("Lean retains a stale ReturnWindows Quint source binding")
    bound.extend([return_lean, core / "configuration/slot-origin.ss",
                  core / "t/root-child-admission-test.ss", core / "t/root-child-effect-test.ss"])
    replay_lean = core / "dev/proofs/lean/YuanxuProof/Admission/ReplayBoundary.lean"
    replay_digest = "sha256:" + hashlib.sha256((models / "ReplayBoundary.qnt").read_bytes()).hexdigest()
    if f'quintSourceDigest : String :=\n  "{replay_digest}"' not in replay_lean.read_text():
        raise AssertionError("Lean retains a stale ReplayBoundary Quint source binding")
    bound.append(replay_lean)
    identity_lean = core / "dev/proofs/lean/YuanxuProof/Admission/IdentityDFS.lean"
    identity_digest = "sha256:" + hashlib.sha256((models / "IdentityDFS.qnt").read_bytes()).hexdigest()
    if f'quintSourceDigest : String :=\n  "{identity_digest}"' not in identity_lean.read_text():
        raise AssertionError("Lean retains a stale IdentityDFS Quint source binding")
    bound.append(identity_lean)
    frames_lean = core / "dev/proofs/lean/YuanxuProof/Admission/DFSFrames.lean"
    if 'def quintSourceDigest : String := IdentityDFS.quintSourceDigest' not in frames_lean.read_text():
        raise AssertionError("DFSFrames must retain the IdentityDFS projection binding")
    bound.append(frames_lean)
    entry_lean = core / "dev/proofs/lean/YuanxuProof/Admission/ReadOnlyEntry.lean"
    entry_digest = "sha256:" + hashlib.sha256((models / "ReadOnlyEntry.qnt").read_bytes()).hexdigest()
    if f'quintSourceDigest : String :=\n  "{entry_digest}"' not in entry_lean.read_text():
        raise AssertionError("Lean retains a stale ReadOnlyEntry Quint source binding")
    bound.append(entry_lean)
    snapshot_lean = core / "dev/proofs/lean/YuanxuProof/Admission/SnapshotEntry.lean"
    snapshot_digest = "sha256:" + hashlib.sha256((models / "SnapshotEntry.qnt").read_bytes()).hexdigest()
    if f'quintSourceDigest : String :=\n  "{snapshot_digest}"' not in snapshot_lean.read_text():
        raise AssertionError("Lean retains a stale SnapshotEntry Quint source binding")
    bound.extend([snapshot_lean, core / "t/mop-state-snapshot-test.ss",
                  core / "t/qualification/mop-state/snapshot.ss"])
    closed_lean = core / "dev/proofs/lean/YuanxuProof/Admission/ClosedTail.lean"
    closed_digest = "sha256:" + hashlib.sha256((models / "ClosedTail.qnt").read_bytes()).hexdigest()
    if f'quintSourceDigest : String :=\n  "{closed_digest}"' not in closed_lean.read_text():
        raise AssertionError("Lean retains a stale ClosedTail Quint source binding")
    bound.extend([closed_lean, core / "t/source-admission-closed-tail-test.ss",
                  core / "t/source-admission-gateway-test.ss",
                  core / "t/qualification/mop-state/closed-tail.ss",
                  core / "t/qualification/mop-state/compile-tail-gateway.ss",
                  core / "t/qualification/mop-state/refine-tail-policy.ss"])
    checker_lean = core / "dev/proofs/lean/YuanxuProof/Admission/CheckerOrigin.lean"
    checker_digest = "sha256:" + hashlib.sha256((models / "CheckerOrigin.qnt").read_bytes()).hexdigest()
    if f'quintSourceDigest : String :=\n  "{checker_digest}"' not in checker_lean.read_text():
        raise AssertionError("Lean retains a stale CheckerOrigin Quint source binding")
    bound.extend([checker_lean, core / "t/mop-checker-origin-test.ss",
                  core / "t/qualification/mop-state/checker-origin.ss"])
    route_lean = core / "dev/proofs/lean/YuanxuProof/Admission/MetadataRoute.lean"
    route_digest = "sha256:" + hashlib.sha256((models / "MetadataRoute.qnt").read_bytes()).hexdigest()
    if f'quintSourceDigest : String :=\n  "{route_digest}"' not in route_lean.read_text():
        raise AssertionError("Lean retains a stale MetadataRoute Quint source binding")
    bound.extend([route_lean, core / "t/mop-metadata-route-test.ss",
                  core / "t/qualification/mop-state/metadata-route.ss"])
    projection_lean = core / "dev/proofs/lean/YuanxuProof/Admission/IssuerProjection.lean"
    mutation_lean = core / "dev/proofs/lean/YuanxuProof/Admission/RouteMutation.lean"
    ownership_lean = core / "dev/proofs/lean/YuanxuProof/Admission/ReplayOwnership.lean"
    metadata_lean = core / "dev/proofs/lean/YuanxuProof/Admission/MetadataOwnership.lean"
    allocation_lean = core / "dev/proofs/lean/YuanxuProof/Admission/MetadataAllocation.lean"
    store_lean = core / "dev/proofs/lean/YuanxuProof/Admission/StoreLowering.lean"
    artifact_lean = core / "dev/proofs/lean/YuanxuProof/Admission/ArtifactClosure.lean"
    core_build_lean = core / "dev/proofs/lean/YuanxuProof/Admission/CoreBuildPublication.lean"
    core_build_digest = "sha256:" + hashlib.sha256((models / "CoreBuildPublication.qnt").read_bytes()).hexdigest()
    if f'quintSourceDigest : String := "{core_build_digest}"' not in core_build_lean.read_text():
        raise AssertionError("Lean retains a stale CoreBuildPublication Quint source binding")
    bound.extend([core_build_lean, core / "dev/proofs/lean/CoreBuildPublicationCheck.lean",
                  core / "t/build-artifact-publication-test.ss",
                  core / "t/qualification/build-publication/compile.ss",
                  core / "module-system/building/artifacts.ss", core / "build.ss",
                  core / "module-system/building/interface.ss",
                  core / "module-system/building/build-projection.ss",
                  core / "module-system/selection/init-syntax.ss",
                  core / "t/module-build-process-test.ss", core / "core-spec.ss",
                  core / "t/qualification/module-bootstrap/objects.ss"])
    handoff_lean = core / "dev/proofs/lean/YuanxuProof/Admission/CoreBuildHandoff.lean"
    handoff_digest = "sha256:" + hashlib.sha256((models / "CoreBuildHandoff.qnt").read_bytes()).hexdigest()
    if f'quintSourceDigest : String := "{handoff_digest}"' not in handoff_lean.read_text():
        raise AssertionError("Lean retains a stale CoreBuildHandoff Quint source binding")
    bound.extend([handoff_lean, core / "dev/proofs/lean/CoreBuildHandoffCheck.lean",
                  core / "t/qualification/build-publication/projection.ss",
                  core / "t/qualification/build-publication/worker.ss", core / "Justfile"])
    recovery_lean = core / "dev/proofs/lean/YuanxuProof/Admission/CoreStoreRecovery.lean"
    approved_lean = core / "dev/proofs/lean/YuanxuProof/Admission/CoreApprovedRecovery.lean"
    approved_digest = "sha256:" + hashlib.sha256((models / "CoreApprovedRecovery.qnt").read_bytes()).hexdigest()
    if f'quintSourceDigest : String := "{approved_digest}"' not in approved_lean.read_text():
        raise AssertionError("Lean retains a stale CoreApprovedRecovery Quint source binding")
    bound.extend([approved_lean, core / "dev/proofs/lean/CoreApprovedRecoveryCheck.lean",
                  core / "t/build-recovery-boundary-test.ss",
                  core / "admission/source.ss", core / "ops/selected-packages.ss"])
    recovery_digest = "sha256:" + hashlib.sha256((models / "CoreStoreRecovery.qnt").read_bytes()).hexdigest()
    if f'quintSourceDigest : String := "{recovery_digest}"' not in recovery_lean.read_text():
        raise AssertionError("Lean retains a stale CoreStoreRecovery Quint source binding")
    bound.extend([recovery_lean, core / "dev/proofs/lean/CoreStoreRecoveryCheck.lean",
                  core / "t/qualification/build-publication/store.ss",
                  core / "t/qualification/build-publication/store-producer.ss",
                  core / "module-system/source/role-forms.ss",
                  core / "module-system/source/declaration.ss",
                  core / "module-system/source/module-prelude.ss",
                  core / "module-system/source/config-prelude.ss"])
    source_loader_lean = core / "dev/proofs/lean/YuanxuProof/Admission/SourceLoader.lean"
    source_loader_digest = "sha256:" + hashlib.sha256((models / "SourceLoader.qnt").read_bytes()).hexdigest()
    if f'quintSourceDigest : String := "{source_loader_digest}"' not in source_loader_lean.read_text():
        raise AssertionError("Lean retains a stale SourceLoader Quint source binding")
    bound.extend([source_loader_lean, core / "dev/proofs/lean/SourceLoaderCheck.lean",
                  core / "t/source-loader-authority-test.ss",
                  core / "t/qualification/mop-state/compile-store-boundary.ss"])
    issued_loading_lean = core / "dev/proofs/lean/YuanxuProof/Admission/IssuedLoading.lean"
    issued_loading_digest = "sha256:" + hashlib.sha256((models / "IssuedLoading.qnt").read_bytes()).hexdigest()
    if f'quintSourceDigest : String := "{issued_loading_digest}"' not in issued_loading_lean.read_text():
        raise AssertionError("Lean retains a stale IssuedLoading Quint source binding")
    bound.extend([issued_loading_lean, core / "dev/proofs/lean/IssuedLoadingCheck.lean",
                  core / "t/artifact-authority-test.ss",
                  core / "t/qualification/mop-state/artifact-authority.ss"])
    artifact_digest = "sha256:" + hashlib.sha256((models / "ArtifactClosure.qnt").read_bytes()).hexdigest()
    if f'quintSourceDigest : String := "{artifact_digest}"' not in artifact_lean.read_text():
        raise AssertionError("Lean retains a stale ArtifactClosure Quint source binding")
    bound.extend([artifact_lean, core / "dev/proofs/lean/ArtifactClosureCheck.lean",
                  core / "t/artifact-closure-test.ss",
                  core / "t/qualification/mop-state/seal-artifact-closure.ss",
                  core / "t/qualification/mop-state/artifact-closure.ss"])
    store_digest = "sha256:" + hashlib.sha256((models / "StoreLowering.qnt").read_bytes()).hexdigest()
    if f'quintSourceDigest : String := "{store_digest}"' not in store_lean.read_text():
        raise AssertionError("Lean retains a stale StoreLowering Quint source binding")
    bound.extend([store_lean, core / "dev/proofs/lean/StoreLoweringCheck.lean",
                  core / "t/mop-store-boundary-test.ss", core / "t/mop-store-boundary-driver-test.ss",
                  core / "t/qualification/mop-state/store-policy.ss",
                  core / "t/qualification/mop-state/compile-store-boundary.ss",
                  core / "t/qualification/mop-state/precompiled-stores.ss",
                  core / "t/qualification/mop-state/unlowered-store.ss"])
    allocation_digest = "sha256:" + hashlib.sha256((models / "MetadataAllocation.qnt").read_bytes()).hexdigest()
    if f'quintSourceDigest : String := "{allocation_digest}"' not in allocation_lean.read_text():
        raise AssertionError("Lean retains a stale MetadataAllocation Quint source binding")
    bound.extend([allocation_lean, core / "dev/proofs/lean/MetadataAllocationCheck.lean",
                  core / "t/mop-metadata-allocation-test.ss",
                  core / "t/qualification/mop-state/reflection-surface.ss"])
    metadata_digest = "sha256:" + hashlib.sha256((models / "MetadataOwnership.qnt").read_bytes()).hexdigest()
    if f'quintSourceDigest : String := "{metadata_digest}"' not in metadata_lean.read_text():
        raise AssertionError("Lean retains a stale MetadataOwnership Quint source binding")
    bound.extend([metadata_lean, core / "t/mop-metadata-ownership-test.ss",
                  core / "t/qualification/mop-state/metadata-ownership.ss"])
    ownership_digest = "sha256:" + hashlib.sha256((models / "ReplayOwnership.qnt").read_bytes()).hexdigest()
    if f'quintSourceDigest : String := "{ownership_digest}"' not in ownership_lean.read_text():
        raise AssertionError("Lean retains a stale ReplayOwnership Quint source binding")
    bound.extend([ownership_lean, core / "t/mop-replay-write-guard-test.ss"])
    mutation_digest = "sha256:" + hashlib.sha256((models / "RouteMutation.qnt").read_bytes()).hexdigest()
    if f'quintSourceDigest : String := "{mutation_digest}"' not in mutation_lean.read_text():
        raise AssertionError("Lean retains a stale RouteMutation Quint source binding")
    bound.extend([mutation_lean, core / "t/mop-route-mutation-test.ss"])
    projection_digest = "sha256:" + hashlib.sha256((models / "IssuerProjection.qnt").read_bytes()).hexdigest()
    if f'quintSourceDigest : String := "{projection_digest}"' not in projection_lean.read_text():
        raise AssertionError("Lean retains a stale IssuerProjection Quint source binding")
    sequence_digest = "sha256:" + hashlib.sha256((models / "IssuerSequence.qnt").read_bytes()).hexdigest()
    if f'sequenceSourceDigest : String := "{sequence_digest}"' not in projection_lean.read_text():
        raise AssertionError("Lean retains a stale issuer sequence source binding")
    bound.extend([projection_lean, core / "dev/proofs/lean/IssuerProjectionCheck.lean",
                  core / "t/issuer-projection-test.ss"])
    issued_lean = core / "dev/proofs/lean/YuanxuProof/Admission/IssuedRead.lean"
    issued_digest = "sha256:" + hashlib.sha256((models / "IssuedRead.qnt").read_bytes()).hexdigest()
    if f'quintSourceDigest : String :=\n  "{issued_digest}"' not in issued_lean.read_text():
        raise AssertionError("Lean retains a stale IssuedRead Quint source binding")
    bound.extend([issued_lean, core / "t/issued-read-admission-test.ss"])
    tail_lean = core / "dev/proofs/lean/YuanxuProof/Admission/ReturnTail.lean"
    tail_digest = "sha256:" + hashlib.sha256((models / "ReturnTail.qnt").read_bytes()).hexdigest()
    if f'quintSourceDigest : String :=\n  "{tail_digest}"' not in tail_lean.read_text():
        raise AssertionError("Lean retains a stale ReturnTail Quint source binding")
    bound.extend([tail_lean, core / "t/source-admission-tail-test.ss"])
    body_lean = core / "dev/proofs/lean/YuanxuProof/Admission/AdmissionBody.lean"
    body_digest = "sha256:" + hashlib.sha256((models / "AdmissionBody.qnt").read_bytes()).hexdigest()
    if f'quintSourceDigest : String :=\n  "{body_digest}"' not in body_lean.read_text():
        raise AssertionError("Lean retains a stale AdmissionBody Quint source binding")
    bound.extend([body_lean, core / "t/source-admission-body-test.ss"])
    call_lean = core / "dev/proofs/lean/YuanxuProof/Admission/CallPhases.lean"
    call_digest = "sha256:" + hashlib.sha256((models / "CallPhases.qnt").read_bytes()).hexdigest()
    if f'quintSourceDigest : String :=\n  "{call_digest}"' not in call_lean.read_text():
        raise AssertionError("Lean retains a stale CallPhases Quint source binding")
    bound.extend([call_lean, core / "t/mop-call-phases-test.ss"])
    serial_lean = core / "dev/proofs/lean/YuanxuProof/Admission/SerialUse.lean"
    serial_digest = "sha256:" + hashlib.sha256((models / "SerialUse.qnt").read_bytes()).hexdigest()
    if f'quintSourceDigest : String :=\n  "{serial_digest}"' not in serial_lean.read_text():
        raise AssertionError("Lean retains a stale SerialUse Quint source binding")
    bound.extend([serial_lean, core / "t/mop-serial-use-test.ss"])
    lifetime_lean = core / "dev/proofs/lean/YuanxuProof/Admission/SnapshotLifetime.lean"
    lifetime_digest = "sha256:" + hashlib.sha256((models / "SnapshotLifetime.qnt").read_bytes()).hexdigest()
    if f'quintSourceDigest : String :=\n  "{lifetime_digest}"' not in lifetime_lean.read_text():
        raise AssertionError("Lean retains a stale SnapshotLifetime Quint source binding")
    bound.extend([lifetime_lean, core / "t/mop-snapshot-lifetime-test.ss"])
    sources = digests()
    lean = core / "dev/proofs/lean/YuanxuProof/Graph/Operations.lean"
    digest = "sha256:" + hashlib.sha256((models / "GraphOperations.qnt").read_bytes()).hexdigest()
    if f'quintSourceDigest : String := "{digest}"' not in lean.read_text():
        raise AssertionError("Lean retains a stale GraphOperations Quint source binding")
    bound.append(lean)
    admission_lean = core / "dev/proofs/lean/YuanxuProof/ModuleSystem/Graph/TestAdmission.lean"
    admission_digest = "sha256:" + hashlib.sha256((models / "TestSourceAdmission.qnt").read_bytes()).hexdigest()
    if f'quintSourceDigest : String := "{admission_digest}"' not in " ".join(admission_lean.read_text().split()):
        raise AssertionError("Lean retains a stale TestSourceAdmission Quint source binding")
    work_lean = core / "dev/proofs/lean/YuanxuProof/ModuleSystem/Graph/SourceClosureWork.lean"
    work_digest = "sha256:" + hashlib.sha256((models / "SourceClosureWork.qnt").read_bytes()).hexdigest()
    if f'quintSourceDigest : String := "{work_digest}"' not in " ".join(work_lean.read_text().split()):
        raise AssertionError("Lean retains a stale SourceClosureWork Quint source binding")
    prefix_digest = "sha256:" + hashlib.sha256((models / "SourcePrefix.qnt").read_bytes()).hexdigest()
    if f'sourcePrefixQuintDigest : String := "{prefix_digest}"' not in " ".join(work_lean.read_text().split()):
        raise AssertionError("Lean retains a stale SourcePrefix Quint source binding")
    continuation_digest = "sha256:" + hashlib.sha256((models / "DependencyContinuation.qnt").read_bytes()).hexdigest()
    if f'dependencyContinuationQuintDigest : String := "{continuation_digest}"' not in " ".join(work_lean.read_text().split()):
        raise AssertionError("Lean retains a stale DependencyContinuation Quint source binding")
    reader_effect_digest = "sha256:" + hashlib.sha256((models / "ReaderEffectSupport.qnt").read_bytes()).hexdigest()
    if f'readerEffectSupportQuintDigest : String := "{reader_effect_digest}"' not in " ".join(work_lean.read_text().split()):
        raise AssertionError("Lean retains a stale ReaderEffectSupport Quint source binding")
    candidate_digest = "sha256:" + hashlib.sha256((models / "CandidatePublication.qnt").read_bytes()).hexdigest()
    if f'candidatePublicationQuintDigest : String := "{candidate_digest}"' not in " ".join(work_lean.read_text().split()):
        raise AssertionError("Lean retains a stale CandidatePublication Quint source binding")
    location_digest = "sha256:" + hashlib.sha256((models / "CandidateLocation.qnt").read_bytes()).hexdigest()
    if f'candidateLocationQuintDigest : String := "{location_digest}"' not in " ".join(work_lean.read_text().split()):
        raise AssertionError("Lean retains a stale CandidateLocation Quint source binding")
    enrollment_digest = "sha256:" + hashlib.sha256((models / "CompilerEnrollment.qnt").read_bytes()).hexdigest()
    if f'compilerEnrollmentQuintDigest : String := "{enrollment_digest}"' not in " ".join(work_lean.read_text().split()):
        raise AssertionError("Lean retains a stale CompilerEnrollment Quint source binding")
    authoring_digest = "sha256:" + hashlib.sha256((models / "AuthoringStage.qnt").read_bytes()).hexdigest()
    if f'authoringStageQuintDigest : String := "{authoring_digest}"' not in " ".join(work_lean.read_text().split()):
        raise AssertionError("Lean retains a stale AuthoringStage Quint source binding")
    carrier_return_digest = "sha256:" + hashlib.sha256((models / "CarrierReturn.qnt").read_bytes()).hexdigest()
    if f'carrierReturnQuintDigest : String := "{carrier_return_digest}"' not in " ".join(work_lean.read_text().split()):
        raise AssertionError("Lean retains a stale CarrierReturn Quint source binding")
    carrier_admission_digest = "sha256:" + hashlib.sha256((models / "CarrierAdmission.qnt").read_bytes()).hexdigest()
    if f'carrierAdmissionQuintDigest : String := "{carrier_admission_digest}"' not in " ".join(work_lean.read_text().split()):
        raise AssertionError("Lean retains a stale CarrierAdmission Quint source binding")
    bound.append(core / "t/module-authoring-dispatch-work-test.ss")
    witness_lean = core / "dev/proofs/lean/YuanxuProof/ModuleSystem/Graph/OwnedReads.lean"
    witness_digest = "sha256:" + hashlib.sha256((models / "WitnessReplay.qnt").read_bytes()).hexdigest()
    if f'witnessReplayQuintDigest : String := "{witness_digest}"' not in " ".join(witness_lean.read_text().split()):
        raise AssertionError("Lean retains a stale WitnessReplay Quint source binding")
    bound.extend([core / "poo-clos/classes.ss", core / "observability/memory.ss",
                  core / "t/testing-script-test.ss",
                  core / "t/qualification/module-scale/worker-test.ss"])
    bound.extend([core / "t/module-candidate-stage-test.ss",
                  core / "t/module-candidate-metadata-test.ss",
                  core / "object-family/read-projection.ss"])
    bound.append(core / "t/module-reader-effect-support-test.ss")
    bound.extend([work_lean, core / "module-system/graph/funs.ss", core / "t/module-closure-work-test.ss",
                  core / "t/module-context-walk-test.ss"])
    bound.extend([admission_lean, core / "module-system/building/test-projection.ss",
                  core / "t/module-init-import-test.ss",
                  core / "ops/progress.ss", core / "ops/func.ss",
                  core / "observability/testing-fixture.ss",
                  core / "t/execution-cancellation-test.ss",
                  core / "module-system/building/interface.ss",
                  core / "t/module-testing-source-admission-test.ss",
                  core / "t/module-loading-scale-test.ss",
                  core / "t/qualification/module-scale/fixture.ss",
                  core / "t/qualification/module-scale/worker-test.ss",
                  core / "t/module-declaration-calibration-test.ss",
                  core / "t/module-declaration-retention-test.ss",
                  core / "t/module-dependency-continuation-test.ss",
                  core / "t/evidence-read-ownership-test.ss",
                  core / "t/evidence-witness-replay-test.ss",
                  core / "t/module-declaration-1000-test.ss",
                  core / "t/module-declaration-10000-test.ss",
                  core / "module-system/building/test-observation.ss",
                  core / "t/module-test-observation-test.ss",
                  core / "module-system/source/directory.ss",
                  core / "module-system/source/objects.ss",
                  core / "module-system/source/selection.ss",
                  core / "module-system/graph/funs.ss",
                  core / "module-system/source/reader.ss",
                  core / "module-system/source/preparation.ss",
                  core / "module-system/source/link.ss",
                  core / "module-system/source/publication.ss",
                  core / "module-system/building/configuration-source.ss",
                  core / "module-system/authoring/admission.ss",
                  core / "module-system/authoring/roles.ss",
                  core / "module-system/config.ss",
                  core / "module-system/source/interface.ss",
                  core / "t/module-authoring-stage-test.ss",
                  core / "module-system/types.ss",
                  core / "t/semantic-module-test.ss",
                  core / "t/module-authoring-test.ss",
                  core / "poo-clos/objects.ss",
                  core / "poo-clos/types.ss",
                  core / "poo-clos/dispatch.ss",
                  core / "object-family/read-projection.ss",
                  core / "t/poo-clos-dispatch-test.ss",
                  core / "dev/proofs/lean/YuanxuProof/PooClos/CarrierCapture.lean",
                  core / "dev/proofs/lean/YuanxuProof/ModuleSystem/Graph/SemanticReads.lean",
                  core / "dev/proofs/lean/YuanxuProof/ModuleSystem/Graph/OwnedReads.lean",
                  core / "dev/proofs/lean/YuanxuProof/ModuleSystem/Graph/PublicationReads.lean",
                  core / "poo-clos/method-bundle-syntax.ss",
                  core / "poo-clos/syntax.ss",
                  core / "t/poo-clos-method-bundle-test.ss",
                  core / "t/module-scope-link-test.ss",
                  core / "module-system/building/configuration-source.ss",
                  core / "module-system/building/source-closure.ss",
                  core / "dev/proofs/lean/YuanxuProof/ModuleSystem/Graph/ImportCorrespondence.lean",
                  core / "ops/func.ss", core / "ops/types.ss", core / "ops/process-script.ss",
                  core / "modules/json-schema/types.ss",
                  core / "modules/json-schema/objects.ss",
                  core / "t/module-json-schema-publication-test.ss",
                  core / "module-system/schema/slot-contracts.ss",
                  core / "t/contract-function-composition-test.ss",
                  core / "ops/tests/atomic-test.ss", core / "t/module-publication-test.ss"])
    bound.extend([core / "t/qualification/module-publication/fixtures.ss",
                  core / "t/qualification/module-publication/controls.ss",
                  core / "ops/interface.ss", core / "core-spec.ss", core / "init.ss"])
    bound.extend([Path(__file__).resolve(), Path(__file__).with_name("backend.py").resolve(),
                  Path(__file__).with_name("native-cli.cjs").resolve(),
                  Path(__file__).with_name("native.py").resolve(),
                  Path(__file__).with_name("test_typecheck.py").resolve()])
    sources = digests()
    args.receipt.parent.mkdir(parents=True, exist_ok=True)
    # Input identities are not a passing qualification receipt. Retain them even
    # if a concurrently edited owner makes the final source-cut gate fail.
    args.receipt.with_suffix(".inputs.json").write_text(json.dumps({
        "status": "unqualified-input-cut", "sources-sha256": sources}, indent=2) + "\n")
    typecheck_sources = (sorted(models.glob("*.qnt")) if args.typecheck_scope == "all" else
                         [models / (model + ".qnt") for model, _, _ in selected_cases])
    if args.typecheck_scope == "all":
        typecheck_sources = typecheck_sources[args.shard_index::args.shard_count]
    # The same pinned CLI load/parse/typecheck stages resolve transitive imports
    # afresh per entry. Only Node startup is shared; each entry keeps its 5s limit.
    typecheck_entries(args.quint, typecheck_sources)
    print("QUINT-TYPECHECK-OK", flush=True)
    print(f"QUINT-TYPECHECK-SCOPE {args.typecheck_scope} {len(typecheck_sources)} entries (including native imports)", flush=True)
    results = []
    if __package__:
        from .backend import backend_session
    else:
        from backend import backend_session
    session = (nullcontext(args.server_endpoint) if args.server_endpoint else
               backend_session(lambda chunk: print(chunk.decode(errors="replace"), end="", flush=True), args.quint))
    with tempfile.TemporaryDirectory(prefix="core-quint-") as directory, session as endpoint, QuintCLI(args.quint, "verify", directory) as verifier:
        work = Path(directory)
        for source in models.glob("*.qnt"):
            shutil.copyfile(source, work / source.name)
        config = work / "backend.json"
        config.write_text('{"workers":"1","maxHeap":"-Xmx1G"}\n')
        for model, invariant, negative in selected_cases:
            print(f"QUINT-CHECK {model} {invariant}", flush=True)
            status, output = verifier.request({
                "input": str(work / (model + ".qnt")), "main": model,
                "backend": "tlc", "apalacheVersion": "0.62.1",
                "invariant": invariant, "invariants": [], "init": "init", "step": "step",
                "maxSteps": 10, "randomTransitions": False,
                "tlcConfig": str(config), "verbosity": 3, "serverEndpoint": endpoint,
            }, wall=45, idle=5, emit=True)
            counts = COUNTS.search(output)
            accepted = ((status == 1 and b"Error: Invariant q_inv is violated." in output
                         and b"[violation] Found an issue" in output
                         and b"error: found a counterexample" in output) if negative else
                        (status == 0 and b"[ok] No violation found" in output and counts is not None
                         and counts[3].replace(b",", b"") == b"0"))
            if not accepted or counts is None:
                raise AssertionError(f"unexpected verifier result: {model}/{invariant}, exit={status}")
            results.append({"model": model, "invariant": invariant, "negative": negative,
                "exit": status, "generated-states": int(counts[1].replace(b",", b"")),
                "distinct-states": int(counts[2].replace(b",", b"")),
                "output-sha256": hashlib.sha256(output).hexdigest()})
            print(f"QUINT-OK {model}", flush=True)
    current_sources = digests()
    if sources != current_sources:
        changed = {name: {"before": digest, "after": current_sources.get(name)}
                   for name, digest in sources.items() if current_sources.get(name) != digest}
        args.receipt.with_suffix(".drift.json").write_text(
            json.dumps({"status": "rejected-source-cut", "changed": changed}, indent=2) + "\n")
        raise AssertionError("bound sources changed during qualification: " + ", ".join(changed))
    args.receipt.parent.mkdir(parents=True, exist_ok=True)
    args.receipt.write_text(scheme({"schema": "yuanxu.quint-proof.v1", "quint-version": version,
        "backend": "tlc", "apalache-version": "0.62.1", "sources-sha256": sources,
        "case-prefix": args.case_prefix or "all", "catalogue-size": len(CASES),
        "shard-index": args.shard_index, "shard-count": args.shard_count,
        "qualification-scope": ("partition" if args.shard_count > 1 else
                                "selected" if args.case_prefix else "complete"),
        "typecheck-scope": args.typecheck_scope,
        "typecheck-entries": [source.stem for source in typecheck_sources],
        "cases": results}) + "\n")
    print(f"QUINT-QUALIFICATION-OK {len(results)} cases", flush=True)


if __name__ == "__main__":
    main()
