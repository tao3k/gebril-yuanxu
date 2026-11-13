;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Public functional API for Jobs and Agent control-plane projections.
(import (only-in "job.ss" job-graph job-flow run-job)
        (only-in "control-plane/runtime-command-descriptor.ss"
                 runtime-command-fields->manifest make-stdout-runtime-command-descriptor)
        (only-in "control-plane/agent-harness.ss"
                 make-yuanxu-agent-operation make-yuanxu-dispatch-receipt make-yuanxu-workflow-run
                 yuanxu-agent-operation->alist yuanxu-dispatch-receipt->alist yuanxu-workflow-run->alist
                 make-yuanxu-agent-session yuanxu-agent-session->alist
                 make-yuanxu-agent-harness make-yuanxu-agent-profile
                 yuanxu-agent-harness->alist yuanxu-agent-profile->alist))
(export job-graph job-flow run-job
        runtime-command-fields->manifest make-stdout-runtime-command-descriptor
        make-yuanxu-agent-operation make-yuanxu-dispatch-receipt make-yuanxu-workflow-run
        yuanxu-agent-operation->alist yuanxu-dispatch-receipt->alist yuanxu-workflow-run->alist
        make-yuanxu-agent-session yuanxu-agent-session->alist
        make-yuanxu-agent-harness make-yuanxu-agent-profile
        yuanxu-agent-harness->alist yuanxu-agent-profile->alist)
