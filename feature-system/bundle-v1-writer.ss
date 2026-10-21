;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Explicit file output for a validated, frozen Bundle v1 image.
(import (only-in :clan/poo/object .ref)
        :yuanxu/feature-system/bundle-v1-foreign-arena)
(export write-feature-bundle-v1-image!)

;; : (-> String U8Vector Unit)
(def (write-u8vector-file! path bytes)
  (let (port (open-output-file (list path: path)))
    (unwind-protect
      (let (written
            (write-subu8vector bytes 0 (u8vector-length bytes) port))
        (unless (= written (u8vector-length bytes))
          (error "Incomplete Bundle v1 composition write"
                 path written (u8vector-length bytes))))
      (close-output-port port))))

(def (write-feature-bundle-v1-image! image descriptor-path arena-path)
  (require-feature-bundle-v1-foreign-arena-image image)
  (write-u8vector-file! descriptor-path (.ref image 'descriptor-image))
  (write-u8vector-file! arena-path (.ref image 'arena-image)))
