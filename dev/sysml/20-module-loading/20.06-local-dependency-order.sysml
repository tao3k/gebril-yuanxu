// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
package YuanxuLocalDependencyOrder {
    private import ScalarValues::*;

    part def CapturedSchedule {
        attribute sourceIdentity : String;
        doc /* POO GeneralizedGraph owns exact support, captured adjacency,
               reverse buckets and a bijective owner/rank order. A candidate
               copies private state; no reader can observe partial relabelling.
               This is schedule data, not a second loader or approval cache. */
    }
    requirement def AdmittedOwnerRows {
        doc /* A native schedule consumes the same ordered, qualified Module
               rows as source admission, followed by the selected Feature
               rows in declaration order. The handoff requires row authority
               in the state after any intervening effect. Unknown authority
               keeps the original projection and observations. */
    }
    part def SparseRepair {
        ref part prior : CapturedSchedule;
        doc /* Consumer -> provider. Remove all batch deletions first. Admit
               each addition against the current candidate. Already lower
               providers retain ranks. Otherwise search dependency/reverse
               buckets bounded by the endpoint ranks; overlapping frontiers
               refuse a cycle. Stable-sort forward/backward owners, then pair
               them with the sorted union of their previous rank labels. */
    }
    requirement def CompleteStablePermutation {
        attribute exactFrontiers : Boolean;
        attribute oldOrderInjective : Boolean;
        attribute oldOrderValid : Boolean;
        attribute noCycle : Boolean;
        attribute constructionAccepted : Boolean;
        attribute allEdgesOrdered : Boolean;
        attribute labelsPermuted : Boolean;
        attribute outsideRanksUnchanged : Boolean;
        require constraint {
            (exactFrontiers and oldOrderInjective and oldOrderValid and noCycle)
            implies (constructionAccepted and allEdgesOrdered and labelsPermuted and outsideRanksUnchanged)
        }
        doc /* LeanPoo StableOrderRepair.sparse_repair_complete proves construction,
               not merely sufficiency of a postulated per-edge certificate.
               HashRankLabels proves actual HashMap assignment and the full
               roster permutation. Finite exact frontiers and immutable input
               are explicit premises, not evidence acquired by the theorem. */
    }
    requirement def IndependentValueInvalidation {
        doc /* The changed-rank set is not the changed-source consumer closure.
               A consumer outside the repair interval must still invalidate
               through the existing POO dependency/materialization path. Keep
               publication tickets, author callbacks, Gerbil expansion and
               currentness checks at their independent effect boundaries. */
    }
    requirement def SourceRevisionHandoff {
        doc /* Module selection supplies ordered admitted rows. POO owns
               schedule revisions, affected-owner discovery and publication.
               A local source revision requires the exact predecessor and
               complete registrations for the issued read receivers, including
               shared policy and type inputs. A caller must account for every
               changed freshness fact before transporting a certificate.
               The successor reverse index inherits untouched consumer rows.
               Rewritten consumer rows remove old-only and add new-only
               registrations. DependencyPublication proves this membership
               equals a cold reconstruction given the exact predecessor
               and the forward frame.
               The reused certificate retains its original root spine and
               signed dependency edges. PublicationReads proves equality of
               demanded support before transferring freshness.
               Unknown filesystem edits require live source checks. The
               separate artifact publication cannot authorize a source edit. */
    }
    part def WorkAccounting {
        doc /* Count footprint preparation, bounded search buckets and every
               inspected edge including pruned edges, rank writes and incident
               checks separately. The current immutable native snapshot copy
               and public order-list materialization remain linear in support;
               they are not included in a false O(delta) whole-update claim.
               The 10000-owner structural fixture is distinct from the real
               Interface EVAL gate (180 seconds, 4 GiB, negative controls). */
    }
    part def ComponentPartition {
        ref part prior : CapturedSchedule;
        doc /* POO strong-components owns iterative Tarjan frames, exact finite
               supported-key validation and source-order normalization. Private
               component IDs never replace public owner identities. The same
               partition owns representative-to-members lookup for condensation.
               LeanPoo ComponentWitness proves the SCC path/quotient certificate law;
               native differential and typed properties qualify the actual DFS. */
    }
    requirement def AtomicGraphHead {
        attribute headGeneration : Integer;
        attribute adjacencyGeneration : Integer;
        attribute rankGeneration : Integer;
        attribute indexGeneration : Integer;
        require constraint {
            headGeneration == adjacencyGeneration and
            headGeneration == rankGeneration and
            headGeneration == indexGeneration
        }
        doc /* GraphSnapshot.qnt abstracts existing immutable graph-cache and
               component-publication request/head identity. An effect result
               must bind its original snapshot when staging, including a
               rival commit before staging. Six matched faults
               expose mixed tables, stale staged tickets, premature retirement,
               failed head replacement, retired requests and interval-only value
               invalidation. Reuse CandidatePublication/IncrementalRoles for
               independent source/author effects. No new runtime epoch API. */
    }
}
