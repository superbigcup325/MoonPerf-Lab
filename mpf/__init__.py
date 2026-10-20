"""MoonPerf Lab harness.

The harness owns the specification (workload manifests, adapter metadata,
result artifacts), generates datasets, runs the experiment flow and renders the
report, so a performance claim can be checked from its artifact.
"""

__version__ = "0.2.0"

# Version of the workload/result documents this harness reads and writes.
SCHEMA_VERSION = 1
