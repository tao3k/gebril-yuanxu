;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Bind borrowed static Scheme to the interfaces in the native import graph.
(import (only-in :gerbil/expander expander-context-id module-context-path)
        (only-in :gerbil/compiler/base module-id->path-string)
        (only-in :std/ffi C-ffi-macrology C-include def-C-type/pointer def-C-lambda)
        (only-in :clan/poo/object .o .get object-revision)
        (only-in :yuanxu/module-system/source/admission
                 module-source-type module-source-read module-source-admit-current!))
(export module-native-static-inputs)

;; Resolve the final alias through POSIX, without a process or fixed-size
;; pathname buffer. The standard FFI owns the allocation and releases it on
;; every Scheme exit; its finalizer also protects interrupted acquisition.
(C-ffi-macrology)
(C-include "<stdlib.h>")
(def-C-type/pointer NativePath "char" release: "ffi_free")
(def-C-lambda native-path-acquire (nonnull-char-string) NativePath*
  "___result = realpath(___arg1, NULL);")
(def-C-lambda native-path-text (NativePath*) nonnull-char-string
  "___result = ___arg1;")
(def (native-input-path path)
  (def pointer (native-path-acquire path))
  (unless pointer (error "native static compiler input cannot be resolved" path))
  (dynamic-wind void
    (lambda () (native-path-text pointer))
    (lambda () (foreign-release! pointer))))

;; Native namespace encoding determines the producer's static product role.
;; The imported interface supplies its actual library root, not a disk catalog.
(def (native-static-input identity path)
  (def relative (module-id->path-string identity))
  (def suffix (string-append relative ".ssi"))
  (unless (string-suffix? suffix path)
    (error "native interface does not match its compiler identity" identity path))
  (def library (substring path 0 (- (string-length path) (string-length suffix))))
  (def leaf (string-append (string-join (string-split relative #\/) "__") ".scm"))
  (def source (path-expand leaf (path-expand "static" library)))
  ;; Bazel projects Tree Artifact leaves as symlinks. This compiler-owned
  ;; path is not a Module source role; retain its alias and followed origin.
  (def kind (module-source-type source))
  (unless (memq kind '(regular symbolic-link))
    (error "native static compiler input is missing or non-regular" identity source))
  (def info (file-info source #t))
  (unless (eq? (file-info-type info) 'regular)
    (error "native static compiler input must resolve to a regular file" identity source))
  (def canonical (native-input-path source))
  ;; Expected bytes stay private. Public compiler projections must not alias
  ;; the text against which original evidence is admitted.
  (def text (string-copy (module-source-read canonical)))
  (def observation (list (cons canonical text)))
  (def witness
    (.o compiler-identity: identity path: (string-copy canonical)
        name: (string-copy leaf) contents: (string-copy text)
        admit-current: current!))
  (def revision (object-revision witness))
  (def (current!)
    (unless (and (= revision (object-revision witness))
                 (string=? (.get witness contents) text)
                 (string=? (.get witness path) canonical)
                 (string=? (.get witness name) leaf))
      (error "native static compiler projection changed" identity source))
    (unless (and (eq? (module-source-type source) kind)
                 (equal? (native-input-path source) canonical)
                 (let (actual (file-info source #t))
                   (and (eq? (file-info-type actual) 'regular)
                        (equal? (file-info-device actual) (file-info-device info))
                        (equal? (file-info-inode actual) (file-info-inode info)))))
      (error "native static compiler input changed origin" identity source))
    (module-source-admit-current! observation "native static compiler input changed"))
  witness)

(def (module-native-static-inputs contexts owned-identities)
  (def owned (make-hash-table-eq))
  (for-each (lambda (identity) (hash-put! owned identity #t)) owned-identities)
  (def selected (make-hash-table))
  (def result '())
  (for-each
    (lambda (context)
      (def identity (expander-context-id context))
      (def path (module-context-path context))
      (def name (and (symbol? identity) (symbol->string identity)))
      (when (and name (string? path) (string=? (path-extension path) ".ssi")
                 (not (hash-get owned identity))
                 ;; Gerbil links its own runtime from prebuilt C/objects.
                 ;; Imported user libraries need private writable inputs.
                 (not (string-prefix? "gerbil/" name))
                 (not (string-prefix? "std/" name)))
        (let* ((input (native-static-input identity path))
               (leaf (.get input name))
               (source (.get input path))
               (previous (hash-get selected leaf)))
          (if previous
            (unless (equal? previous source)
              (error "native static inputs have competing origins" identity previous source))
            (begin
              (hash-put! selected leaf source)
              (set! result (cons input result)))))))
    contexts)
  (reverse result))
