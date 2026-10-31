// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
package YuanxuIncrementalRoles {
    private import ScalarValues::*;
    part def RoleInput {
        attribute ownerIdentity : String;
        attribute roleIdentity : String;
        attribute sourceRevision : String;
        attribute receiverIdentity : String;
        attribute phaseIdentity : String;
    }
    part def RetainedRole {
        ref part input : RoleInput;
        doc /* Native POO owns receiver-local values; std/make owns artifacts.
               Neither retained data nor a warm artifact is a cached approval. */
    }
    part def IncrementalOwner {
        part input : RoleInput;
        part retained : RetainedRole;
        doc /* Compile imports, semantic reads, module requirements and runtime
               order are distinct relations. Rebuild/evaluate only the demanded
               affected closure. Re-authenticate before publication. */
    }
    part def ReadEdgeProjection {
        doc /* Actual issued read->dependency records project consumer/provider
               receiver identities into depend-on-object!. Same-owner edges
               need no registration. Native invalidation clears whole receiver
               caches, so minimal individual-slot invalidation is not claimed.
               Serialized enrollment/mutation and complete support are premises. */
    }
    part def BoundedWorker {
        ref part owner : IncrementalOwner;
        doc /* Future scheduling allocation only. Do not copy the graph, inherit
               mutable observation frames unsafely or claim concurrent mutation.
               Aggregate memory remains bounded; no Actor implementation here. */
    }
    requirement def PreserveUnchangedWork {
        attribute affected : Boolean;
        attribute reconstructed : Boolean;
        require constraint { reconstructed implies affected }
        doc /* Eligibility depends on complete issued support and current source
               association; an author purity label cannot establish it. */
    }
    requirement def FreshAdmission {
        attribute approved : Boolean;
        attribute sourcesCurrent : Boolean;
        attribute bothRequirements : Boolean;
        require constraint { approved implies (sourcesCurrent and bothRequirements) }
    }
}
