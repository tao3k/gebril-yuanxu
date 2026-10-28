;;; Only the package prelude supplies Gerbil and POO.
(.def Value port: 5440)
(unless (= (.get Value port) 5440) (error "missing POO prelude bindings"))
(when (ormap (lambda (entry) (string-prefix? "yuanxu/module-system/" (car entry)))
             (list-modules))
  (error "ordinary prelude imported Module System"))
(displayln "PRELUDE-INERT-OK")
