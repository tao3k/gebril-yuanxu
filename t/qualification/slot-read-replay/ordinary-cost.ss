;;; Matched public-read control; use the same file before and after MOP recording.
;;; Measurement excludes imports and emits raw samples, never timing assertions.
(import :std/test :std/iter
        :clan/poo/object :clan/poo/slot-layout
        (only-in :clan/poo/t/closure-measure measure))
(export slot-read-cost-test)

(def (sample-read phase action repetitions)
  (for (round (in-range 3))
    (defvalues (value costs) (measure action repetitions))
    (check-equal? value 5432)
    (write (list 'READ-COST (getenv "YUANXU_READ_COST_LABEL" "unlabelled")
                 phase round repetitions costs))
    (newline)))

(def slot-read-cost-test
  (test-suite "Unobserved public slot costs"
    (test-case "same scalar result through cold and warm public reads"
      (def calls 0)
      (def shared (.o port: (begin (set! calls (+ calls 1)) 5432)))
      (def site (make-slot-cache 'port))
      (check-equal? (.ref/inline shared site) 5432)
      (sample-read 'empty (lambda () 5432) 100000)
      (sample-read 'warm-ref (cut .ref shared 'port) 100000)
      (sample-read 'warm-cached (cut .ref/cached shared 'port) 100000)
      (sample-read 'warm-inline (cut .ref/inline shared site) 100000)
      (sample-read 'cold-scalar (lambda () (.get (.o port: 5432) port)) 1000)
      (sample-read 'cold-derived
        (lambda () (.get (.o port: (.get shared port)) port)) 1000)
      (check-equal? calls 1))))
