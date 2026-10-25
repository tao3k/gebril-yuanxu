// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
package YuanxuPayloadOwnership {
    requirement def VerificationAllocation {
        doc /* Lean PayloadSharing owns binding injection, exact records and
               ordered edges, identity-union accounting and receiver/capture
               preservation. No duplicate PayloadSharing QNT model is kept.
               Existing QNT IssuedRootForwarding/ReadRetention/IncrementalRoles
               own callback-to-admission, invalidation and parent/child event
               traces. Scheme tests own actual MOP correspondence; the bounded
               census owns measured reachability and GC-live observations.
               A new model requires a new question, not a second encoding. */
    }
    part def CanonicalContext {
        doc /* Existing native SDK context and source index. Actual source
               authentication remains fresh at each admitted use. */
    }
    part def RoleContext {
        ref part imports : CanonicalContext;
        doc /* Local private constructor alias only. Original source lexical
               bindings and the native import dependency stay authoritative. */
    }
    part def Call {
        doc /* Distinct effective/invocation receivers. Within this call the
               existing argument list may be shared; callbacks stay distinct. */
    }
    part def IssuedRead {
        doc /* Original native identity, receiver, birth and ordered edges.
               No synthetic token or successful approval substitutes for it.
               Its issuer-private parent snapshot may store a single non-vector
               identity directly; empty/many/vector-valued cases stay dense.
               Lean proves exact sequence restoration; existing ReadRetention
               QNT owns temporal controls. Runtime tests check public mutation,
               inspector-copy isolation and actual retained-vector counts. */
    }
    part def ReceiverInstance {
        doc /* Receiver identity, monotone revision and native instance identity
               guard currentness. Cached cells are receiver-local, not pooled. */
    }
    part def Shape {
        doc /* Existing producer-owned name/index structure may be shared.
               It carries neither cached values nor a currentness verdict. */
    }
    part def CallbackEnvironment {
        doc /* One call/receiver owns mutable captures. Equal printed values
               cannot authorize merging closures or their environments.
               Warm/cold table entries may reference the same function. Lean
               owns the identity partition, Scheme owns raw non-forcing key
               extraction; existing QNT owns value-demand/currentness traces.
               No model here proves compute-slot construction hooks may be
               reordered just because a value is absent from the cache. */
    }
    requirement def OwnerShellAccounting {
        doc /* Shell projections and indirect environments share one identity
               union. Ordered marginal counts are not exclusive bytes; VM GC
               live is not a root dominator account. Nested owners, weak tables
               and descriptors remain explicit frontiers. Lean owns identity
               accounting; existing QNT owns temporal invalidation. */
    }
    part def Loading {
        part context : CanonicalContext;
        part role : RoleContext;
        part call : Call;
        part read : IssuedRead;
        part instance : ReceiverInstance;
        ref part shape : Shape;
        part callback : CallbackEnvironment;
        dependency anchor from read to instance;
        dependency cachedCallback from instance to callback;
        dependency structuralIndex from instance to shape;
        dependency originalImport from role to context;
        dependency originalObservation from call to read;
    }
}
// Diagnostic union cardinality refinement: PayloadSharing.partitionLength,
// unionCountWithoutCopy, intersectionCountSymmetric and smallerIntersectionCorrect
// own the finite identity enumeration calculation. No QNT timing copy is added.
