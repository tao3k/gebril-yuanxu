;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: deterministic lazy-slot admission over upstream POO objects.
;;; Invariant: debug paths retain symbols only; receivers and values stay out.

(import :gerbil/core
        (only-in :clan/poo/object
                 .o
                 .ref
                 .all-slots
                 .putslot!
                 object?
                 $computed-slot-spec)
        (only-in :clan/poo/mop validate)
        (only-in :clan/poo/support/debug traced-function)
        (only-in :clan/poo/debug DDT)
        (only-in :std/error deferror-class)
        (only-in :yuanxu/observability/types
                 YuanxuDebugSlotPolicyContract
                 YuanxuDebugSlotReceiptContract)
        (only-in :yuanxu/observability/funcs
                 yuanxu-debug-slot-policy
                 yuanxu-debug-slot-receipt
                 yuanxu-debug-slot-receipt-sexp))

(export YuanxuDebugSlotPolicyContract
        YuanxuDebugSlotReceiptContract
        yuanxu-debug-slot-policy
        yuanxu-debug-slot-receipt
        yuanxu-debug-slot-receipt-sexp
        yuanxu-debug-poo
        yuanxu-debug-poos
        YuanxuDebugSlotAnomaly?
        YuanxuDebugSlotAnomaly-receipt)

(deferror-class YuanxuDebugSlotAnomaly (receipt))

;;; Active slots are dynamically scoped per Scheme thread.  A path contains
;;; only receiver/slot symbol pairs and therefore cannot keep a receiver or
;;; computed value alive while a resolution is being diagnosed.
;; : (Parameter [(Pair Symbol Symbol)])
(def yuanxu-debug-active-slot-path (make-parameter '()))

;; : (-> YuanxuDebugSlotReceipt OutputPort Unit)
(def (yuanxu-debug-emit-slot-receipt receipt port)
  (parameterize ((current-error-port port))
    (DDT 'debug-slot yuanxu-debug-slot-receipt-sexp receipt)))

;; : (-> YuanxuDebugSlotReceipt Never)
(def (yuanxu-debug-raise-slot-anomaly receipt)
  (let (failure
        (YuanxuDebugSlotAnomaly
         "Yuanxu debug slot admission rejected lazy resolution"
         irritants: '()))
    (set! (YuanxuDebugSlotAnomaly-receipt failure) receipt)
    (raise failure)))

;;; Resolution tracing follows Clan's `traced-function`, but the upstream
;;; printer sees a zero-argument thunk and the closed symbol `resolved` only.
;;; The actual slot value and original exception remain lexical values here.
;; : (forall (a) (-> YuanxuDebugSlotPolicy Symbol Symbol (-> a) OutputPort Boolean a))
;; : (-> YuanxuDebugSlotPolicy Symbol Symbol (-> Object) OutputPort Boolean Object)
(def (yuanxu-debug-resolve-slot policy receiver slot superfun port emit?)
  (let* ((edge (cons receiver slot))
         (path (yuanxu-debug-active-slot-path))
         (depth (length path))
         (rejected-outcome
          (cond ((member edge path) 'rejected-cycle)
                ((>= depth (.ref policy 'maximum-depth)) 'rejected-depth)
                (else #f))))
    (when rejected-outcome
      (let (receipt
            (yuanxu-debug-slot-receipt
             policy receiver slot depth path rejected-outcome))
        (when emit? (yuanxu-debug-emit-slot-receipt receipt port))
        (yuanxu-debug-raise-slot-anomaly receipt)))
    (let (resolved-value #!void)
      ;; The non-emitting guard is an admission boundary, not a receipt path.
      ;; Avoid constructing and validating an observation that cannot escape.
      (when emit?
        (yuanxu-debug-emit-slot-receipt
         (yuanxu-debug-slot-receipt
          policy receiver slot depth path 'admitted)
         port))
      (parameterize ((yuanxu-debug-active-slot-path (cons edge path)))
        (let (resolve
              (lambda ()
                (set! resolved-value (superfun))
                'resolved))
          (with-exception-catcher
           (lambda (failure)
             (when emit?
               (yuanxu-debug-emit-slot-receipt
                (yuanxu-debug-slot-receipt
                 policy receiver slot depth path 'raised)
                port))
             (raise failure))
           (lambda ()
             (if emit?
               ((traced-function
                 (list 'yuanxu-debug-slot receiver slot)
                 resolve
                 port))
               (resolve))))))
      (when emit?
        (yuanxu-debug-emit-slot-receipt
         (yuanxu-debug-slot-receipt
          policy receiver slot depth path 'resolved)
         port))
      resolved-value)))

;; : (-> YuanxuDebugSlotPolicy Symbol Symbol OutputPort Boolean SlotSpec)
(def (yuanxu-debug-slot-spec policy receiver slot port emit?)
  ($computed-slot-spec
   (lambda (_self superfun)
     (yuanxu-debug-resolve-slot
      policy receiver slot superfun port emit?))))

;; : (-> YuanxuDebugSlotPolicy Symbol PooObject OutputPort Boolean PooObject)
(def (yuanxu-debug-install-slot-guards! policy receiver source port emit?)
  (let (guarded (.o (:: @ source)))
    (for-each
     (lambda (slot)
       (.putslot!
        guarded
        slot
        (yuanxu-debug-slot-spec policy receiver slot port emit?)))
     (.all-slots source))
    guarded))

;; : (-> YuanxuDebugSlotPolicy Symbol PooObject OutputPort Boolean PooObject)
(def (yuanxu-debug-poo/validated policy receiver source port emit?)
  (yuanxu-debug-install-slot-guards!
   policy receiver source port emit?))

;; : (-> YuanxuDebugSlotPolicy Symbol [PooObject] port: OutputPort emit?: Boolean [PooObject])
;; yuanxu-debug-poos
;;   : (-> YuanxuDebugSlotPolicy Symbol [PooObject] port: OutputPort emit?: Boolean [PooObject])
;;   | doc m%
;;       Install the same slot policy over a batch of native POO values. The
;;       shared policy is admitted once at the batch boundary; each returned
;;       receiver still owns independent :clan/poo lazy-slot caches.
;;     %
(def (yuanxu-debug-poos policy receiver sources
                          port: (port (current-error-port))
                          emit?: (emit? #t))
  (unless (and (symbol? receiver) (list? sources)
               (andmap object? sources)
               (output-port? port) (boolean? emit?))
    (error "invalid Yuanxu slot debug batch request" receiver))
  (unless (eq? (validate YuanxuDebugSlotPolicyContract policy) policy)
    (error "invalid Yuanxu debug slot policy"))
  (map (lambda (source)
         (yuanxu-debug-poo/validated
          policy receiver source port emit?))
       sources))

;; : (forall (a) (-> YuanxuDebugSlotPolicy Symbol a port: OutputPort emit?: Boolean a))
;; yuanxu-debug-poo
;;   : (-> YuanxuDebugSlotPolicy Symbol PooObject port: OutputPort emit?: Boolean PooObject)
;;   | doc m%
;;       Create a POO proxy whose inherited slots are admitted before lazy
;;       resolution. Crossing the guard's depth budget raises a typed anomaly;
;;       native POO cycle failures propagate unchanged when detected first.
;;       Successful values retain ordinary POO object-local caching.  Clan's
;;       tracer receives only a zero-argument resolver returning `resolved`.
;;
;;       The receiver name is explicit and symbolic: this boundary never reads
;;       a potentially recursive `sexp` or identity slot to label the object.
;;
;;       # Examples
;;
;;       ```scheme
;;       (def guarded
;;         (yuanxu-debug-poo policy 'configuration configuration))
;;       (.ref guarded 'project-id)
;;       ;; => cached value, or raises YuanxuDebugSlotAnomaly
;;       ```
;;     %
(def (yuanxu-debug-poo policy receiver source
                         port: (port (current-error-port))
                         emit?: (emit? #t))
  (unless (and (symbol? receiver) (object? source)
               (output-port? port) (boolean? emit?))
    (error "invalid Yuanxu slot debug request" receiver))
  (unless (eq? (validate YuanxuDebugSlotPolicyContract policy) policy)
    (error "invalid Yuanxu debug slot policy"))
  (yuanxu-debug-poo/validated policy receiver source port emit?))
