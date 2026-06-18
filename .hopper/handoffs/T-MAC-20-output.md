---
task_id: T-MAC-20
adapter: mimo
model: xiaomi/mimo-v2.5-pro
status: failed
pid: 56352
start_time: "2026-06-18T04:53:18.750Z"
end_time: "2026-06-18T04:59:31.951Z"
exit_code: 0
duration_ms: 373154
mode: background
phase: failed
last_progress_at: "2026-06-18T04:59:31.952Z"
last_progress: Task failed.
progress_seq: 2
progress_log: ./T-MAC-20-progress.log
raw_log: ./T-MAC-20-output.log
vendor_session_id: null
terminal_event_emitted: true
host_native: null
session_id: null
log: ./T-MAC-20-output.log
started_by_pid: 56350
signal: null
timed_out: null
adapter_status: permission-fail
---

# T-MAC-20 — mimo (background, in-progress)

Output streaming to `T-MAC-20-output.log`. Status updates here.

## Vendor output (parsed)

_(vendor produced no parsed text; see `T-MAC-20-output.log` for the raw output stream.)_

## Status (background completion)
- queue_status: failed
- adapter_status: permission-fail
- exit_code: 0
- duration_ms: 373154
- end_time: 2026-06-18T04:59:31.951Z

### Adapter error
```
mimo binary not found in PATH. Install: curl -fsSL https://mimo.xiaomi.com/install | bash OR npm install -g @mimo-ai/cli.
```
- log: see `T-MAC-20-output.log` for raw output
