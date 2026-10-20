"""MoonPerf Lab harness.

The harness is deliberately small at this stage: it owns the specification
(workload manifests, adapter metadata, result artifacts) and validates it in
CI, so the experiment protocol has teeth before the runner exists.
"""

__version__ = "0.1.0"

# Version of the workload/result documents this harness reads and writes.
SCHEMA_VERSION = 1
