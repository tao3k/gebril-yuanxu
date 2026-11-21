;;; No private imports and no module directories: importing init is inert.
(yuanxu!
  :load-modules "./missing-org" mode: explicit mount: Org (parser)
  :load-modules "./missing-standard" mode: explicit mount: Standard (c))
(unless (and (.slot? yuanxu-prelude-consumer.init.exports 'Org)
             (.slot? yuanxu-prelude-consumer.init.exports 'Standard))
  (error "prelude lost standard init export identity or mounts"))
(displayln "PRELUDE-INIT-OK")
