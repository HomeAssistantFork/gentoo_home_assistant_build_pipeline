# AI Temp Test Scripts

Scripts in this directory are AI-generated test/diagnostic helpers for GentooHA.

## Scripts

| Script | Purpose |
|---|---|
| `common_test.sh` | Shared helpers (test_pass, test_fail, test_warn, vm_exec, ha_api) |
| `run_all_tests.sh` | Orchestrator — runs all test suites in order |
| `test_boot.sh` | Boot GentooHA VDI in VirtualBox headless, wait for HA port |
| `test_services.sh` | Verify Docker / os-agent / hassio-supervisor are active |
| `test_ha_api.sh` | HTTP API checks against running HA instance |
| `test_supervisor.sh` | Supervisor API, add-on store, Docker image checks |
| `test_ha_core.sh` | Run HA core pytest suite on host against cloned repo |

## Usage

```bash
# Full test run (VM must exist, VDI path auto-detected)
bash scripts/tests/ai/run_all_tests.sh

# Skip boot if VM already running
SKIP_BOOT=true bash scripts/tests/ai/run_all_tests.sh

# Enable HA API authenticated tests
HA_TOKEN=<long-lived-token> SKIP_BOOT=true bash scripts/tests/ai/run_all_tests.sh

# Run HA core pytest suite too
SKIP_HA_CORE=false bash scripts/tests/ai/run_all_tests.sh

# Individual scripts
bash scripts/tests/ai/test_services.sh
bash scripts/tests/ai/test_ha_api.sh http://localhost:8123
bash scripts/tests/ai/test_supervisor.sh <token>
```

## Note

This directory is for AI-generated test scripts. Do not store permanent production scripts here.
