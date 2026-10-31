;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :std/ffi C-declare))
(C-declare "#ifndef YUANXU_NATIVE_OPTIONS_PROBE\n#error missing native compiler option\n#endif\n")
(export native-value)
(def native-value 7)
