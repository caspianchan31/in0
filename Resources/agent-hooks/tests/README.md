# Agent hook tests

Two layers, ordered by setup cost:

## smoke.sh — no deps

End-to-end shell test. Spawns a Python AF_UNIX socket server, drives the
full prompt → pretool → posttool → stop sequence through `agent-hook.py`,
asserts socket payloads and session-file state.

```bash
./Resources/agent-hooks/tests/smoke.sh
# → SMOKE OK   (or a clear FAIL line on regression)
```

## test_agent_hook.py — pytest

Unit coverage of the pure-function surface: `describe_tool`,
`short_path`, `read_transcript_summary`, `gc_stale`, `dispatch`,
`resume_command_for`. Includes the shell-injection regression list so a
malicious session id can never round-trip into an auto-typed shell line.

```bash
pip install pytest    # one-time
python3 -m pytest Resources/agent-hooks/tests/ -v
```

Run both before publishing hook changes.
