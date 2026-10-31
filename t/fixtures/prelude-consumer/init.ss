;;; No private imports and no module directories: importing init is inert.
(yuanxu!
  :load-modules "./missing-org" mode: explicit rename: Org (parser)
  :load-modules "./missing-native" mode: explicit rename: Native (c))
(unless (and (.slot? yuanxu-prelude-consumer.init.exports 'Org)
             (.slot? yuanxu-prelude-consumer.init.exports 'Native))
  (error "prelude lost native init export identity or mounts"))
(displayln "PRELUDE-INIT-OK")
