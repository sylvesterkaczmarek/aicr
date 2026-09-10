#!/usr/bin/env bash
# Copyright (c) 2026, NVIDIA CORPORATION & AFFILIATES.  All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLEANUP="${SCRIPT_DIR}/cleanup"
STUB_DIR="$(mktemp -d)"
KLOG="$(mktemp)"
trap 'rm -rf "${STUB_DIR}" "${KLOG}"' EXIT

cat >"${STUB_DIR}/kubectl" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${KLOG}"

if [[ "$1" == "config" && "$2" == "current-context" ]]; then
    echo "stub-ctx"
    exit 0
fi

if [[ "$1" == "get" && "$2" == "crd" ]]; then
    printf '%s\n' \
        "customresourcedefinition.apiextensions.k8s.io/jobsets.jobset.x-k8s.io" \
        "customresourcedefinition.apiextensions.k8s.io/widgets.example.com"
    exit 0
fi

if [[ "$1" == "get" && ( "$2" == "ns" || "$2" == "namespace" ) ]]; then
    for arg in "$@"; do
        [[ "$arg" == "name" ]] && exit 0
    done
    exit 1
fi

if [[ "$1" == "get" && "$2" == "daemonset" ]]; then
    exit 0
fi

if [[ "$1" == "api-resources" ]]; then
    exit 0
fi

exit 0
STUB

cat >"${STUB_DIR}/helm" <<'STUB'
#!/usr/bin/env bash
if [[ "$1" == "ls" ]]; then
    printf 'NAME\tNAMESPACE\tREVISION\n'
fi
exit 0
STUB

cat >"${STUB_DIR}/sleep" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB

chmod +x "${STUB_DIR}/kubectl" "${STUB_DIR}/helm" "${STUB_DIR}/sleep"

PATH="${STUB_DIR}:${PATH}" KLOG="${KLOG}" "${CLEANUP}" --yes >/dev/null 2>&1

log="$(cat "${KLOG}")"
jobset="delete customresourcedefinition.apiextensions.k8s.io/jobsets.jobset.x-k8s.io --ignore-not-found --wait=false --request-timeout=30s"
unrelated="delete customresourcedefinition.apiextensions.k8s.io/widgets.example.com"

if [[ "$log" != *"$jobset"* ]]; then
    echo "FAIL: JobSet CRD was not selected for cleanup"
    exit 1
fi

if [[ "$log" == *"$unrelated"* ]]; then
    echo "FAIL: unrelated CRD was selected for cleanup"
    exit 1
fi

echo "PASS: JobSet CRD is selected without broadening cleanup scope"
