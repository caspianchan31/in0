"""Unit tests for agent-hook.py.

Run: `python3 -m pytest Resources/agent-hooks/tests/ -v`

These exercise the pure-function surface of `agent-hook.py` (tool
labelling, transcript parsing, session GC, dispatch) without spinning
up the bash entry. The companion `smoke.sh` covers end-to-end.
"""

import importlib.util
import json
import os
import pathlib
import sys
import tempfile

import pytest  # noqa: F401  — pytest fixture import only

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

# `agent-hook.py` has a hyphen in the name (not a valid identifier),
# so load it via importlib.
SPEC = importlib.util.spec_from_file_location(
    "agent_hook", str(HERE.parent / "agent-hook.py"))
agent_hook = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(agent_hook)


# ---------- describe_tool ----------

def test_describe_tool_edit():
    assert agent_hook.describe_tool("Edit", {"file_path": "/a/b/c/foo.swift"}) == "Edit b/c/foo.swift"

def test_describe_tool_read():
    assert agent_hook.describe_tool("Read", {"file_path": "/foo.swift"}) == "Read foo.swift"

def test_describe_tool_write_no_path():
    assert agent_hook.describe_tool("Write", {"file_path": ""}) == "Write"

def test_describe_tool_bash_truncates():
    cmd = "x" * 200
    out = agent_hook.describe_tool("Bash", {"command": cmd})
    assert out.startswith("Bash: ")
    assert len(out) == len("Bash: ") + 60

def test_describe_tool_bash_first_line_only():
    assert agent_hook.describe_tool("Bash", {"command": "ls\necho hi"}) == "Bash: ls"

def test_describe_tool_grep():
    assert agent_hook.describe_tool("Grep", {"pattern": "foo"}) == "Grep 'foo'"

def test_describe_tool_glob():
    assert agent_hook.describe_tool("Glob", {"pattern": "**/*.swift"}) == "Glob **/*.swift"

def test_describe_tool_task():
    assert agent_hook.describe_tool("Task", {"subagent_type": "Plan"}) == "Subagent: Plan"

def test_describe_tool_unknown():
    assert agent_hook.describe_tool("MysteryTool", {"foo": "bar"}) == "MysteryTool"

def test_describe_tool_non_dict_input():
    assert agent_hook.describe_tool("Edit", "not a dict") == "Edit"


# ---------- short_path ----------

def test_short_path_three_segments_or_fewer_unchanged():
    assert agent_hook.short_path("a/b/c") == "a/b/c"
    assert agent_hook.short_path("a/b") == "a/b"

def test_short_path_strips_leading_slash():
    assert agent_hook.short_path("/a/b/c/d") == "b/c/d"


# ---------- read_transcript_summary ----------

def _write_transcript(path, messages):
    with open(path, "w") as f:
        for m in messages:
            f.write(json.dumps(m) + "\n")


def test_read_transcript_picks_last_assistant(tmp_path):
    p = tmp_path / "t.jsonl"
    _write_transcript(p, [
        {"role": "user", "content": "hi"},
        {"role": "assistant", "content": "Old response"},
        {"role": "user", "content": "another question"},
        {"role": "assistant", "content": "Latest response"},
    ])
    assert agent_hook.read_transcript_summary(str(p)) == "Latest response"


def test_read_transcript_strips_thinking(tmp_path):
    p = tmp_path / "t.jsonl"
    _write_transcript(p, [
        {"role": "assistant", "content": "<thinking>internal</thinking>Actual answer here"},
    ])
    assert agent_hook.read_transcript_summary(str(p)) == "Actual answer here"


def test_read_transcript_multi_block_content(tmp_path):
    p = tmp_path / "t.jsonl"
    _write_transcript(p, [
        {"role": "assistant",
         "content": [
             {"type": "text", "text": "Hello"},
             {"type": "tool_use", "name": "Edit"},
         ]},
    ])
    assert agent_hook.read_transcript_summary(str(p)) == "Hello"


def test_read_transcript_truncates_to_200():
    with tempfile.NamedTemporaryFile("w", suffix=".jsonl", delete=False) as f:
        txt = "x" * 500
        f.write(json.dumps({"role": "assistant", "content": txt}) + "\n")
        path = f.name
    try:
        result = agent_hook.read_transcript_summary(path)
        assert len(result) == 200
        assert result == "x" * 200
    finally:
        os.unlink(path)


def test_read_transcript_empty_file(tmp_path):
    p = tmp_path / "empty.jsonl"
    p.write_text("")
    assert agent_hook.read_transcript_summary(str(p)) == ""


def test_read_transcript_missing_file():
    assert agent_hook.read_transcript_summary("/nonexistent/path.jsonl") == ""


def test_read_transcript_skips_malformed(tmp_path):
    p = tmp_path / "t.jsonl"
    p.write_text('not json\n{"role":"assistant","content":"good"}\n')
    assert agent_hook.read_transcript_summary(str(p)) == "good"


def test_read_transcript_no_assistant(tmp_path):
    p = tmp_path / "t.jsonl"
    _write_transcript(p, [{"role": "user", "content": "only user"}])
    assert agent_hook.read_transcript_summary(str(p)) == ""


# ---------- gc_stale ----------

def test_gc_stale_drops_old_keeps_fresh():
    now = 10_000.0
    doc = {
        "version": 1,
        "sessions": {
            "s_old":   {"lastTouched": now - 7200},   # 2h ago: drop
            "s_fresh": {"lastTouched": now - 600},    # 10m ago: keep
            "s_no_ts": {},                            # missing field: drop
        },
    }
    out = agent_hook.gc_stale(doc, now)
    assert "s_fresh" in out["sessions"]
    assert "s_old" not in out["sessions"]
    assert "s_no_ts" not in out["sessions"]


# ---------- dispatch ----------

def test_dispatch_prompt_then_stop_clean_turn(tmp_path):
    sf = tmp_path / "sessions.json"
    transcript = tmp_path / "transcript.jsonl"
    _write_transcript(transcript, [{"role": "assistant", "content": "Done."}])

    now = 1_000_000.0
    emit1 = agent_hook.dispatch("prompt", "claude",
                                {"session_id": "s1", "transcript_path": str(transcript)},
                                "term1", sf, now)
    assert emit1 == {"event": "running", "at": now, "resumeCommand": "claude --resume s1"}

    emit2 = agent_hook.dispatch("stop", "claude", {"session_id": "s1"},
                                "term1", sf, now + 10)
    assert emit2["event"] == "finished"
    assert emit2["exitCode"] == 0
    assert emit2["summary"] == "Done."

    doc = agent_hook.load_sessions(sf)
    assert "s1" not in doc.get("sessions", {})


def test_dispatch_posttool_sticky_error(tmp_path):
    sf = tmp_path / "sessions.json"
    now = 2_000_000.0

    agent_hook.dispatch("prompt", "claude", {"session_id": "s2"}, "t2", sf, now)
    agent_hook.dispatch("pretool", "claude",
                        {"session_id": "s2", "tool_name": "Edit",
                         "tool_input": {"file_path": "/foo.swift"}},
                        "t2", sf, now + 1)
    agent_hook.dispatch("posttool", "claude",
                        {"session_id": "s2", "tool_response": {"is_error": True}},
                        "t2", sf, now + 2)
    # Subsequent clean posttool must NOT clear the sticky error.
    agent_hook.dispatch("posttool", "claude",
                        {"session_id": "s2", "tool_response": {"is_error": False}},
                        "t2", sf, now + 3)
    emit = agent_hook.dispatch("stop", "claude", {"session_id": "s2"}, "t2", sf, now + 4)
    assert emit["exitCode"] == 1


def test_dispatch_pretool_emits_tool_detail(tmp_path):
    sf = tmp_path / "sessions.json"
    now = 3_000_000.0
    agent_hook.dispatch("prompt", "claude", {"session_id": "s3"}, "t3", sf, now)
    emit = agent_hook.dispatch("pretool", "claude",
                               {"session_id": "s3", "tool_name": "Edit",
                                "tool_input": {"file_path": "/y/z/foo.swift"}},
                               "t3", sf, now + 1)
    assert emit["event"] == "running"
    assert emit["toolDetail"] == "Edit y/z/foo.swift"


def test_dispatch_stop_without_prompt_defaults_zero_exit(tmp_path):
    sf = tmp_path / "sessions.json"
    emit = agent_hook.dispatch("stop", "claude", {"session_id": "s4"},
                               "t4", sf, 4_000_000.0)
    assert emit["event"] == "finished"
    assert emit["exitCode"] == 0


def test_dispatch_falls_back_to_terminal_id(tmp_path):
    sf = tmp_path / "sessions.json"
    agent_hook.dispatch("prompt", "claude", {}, "t5", sf, 5_000_000.0)
    doc = agent_hook.load_sessions(sf)
    assert "t5" in doc["sessions"]


def test_dispatch_posttool_emits_running(tmp_path):
    sf = tmp_path / "sessions.json"
    now = 6_000_000.0
    agent_hook.dispatch("prompt", "claude", {"session_id": "s6"}, "t6", sf, now)
    agent_hook.dispatch("pretool", "claude",
                        {"session_id": "s6", "tool_name": "Edit",
                         "tool_input": {"file_path": "/foo.swift"}},
                        "t6", sf, now + 1)
    emit = agent_hook.dispatch("posttool", "claude",
                               {"session_id": "s6", "tool_response": {"is_error": False}},
                               "t6", sf, now + 2)
    assert emit == {"event": "running", "at": now + 2}


# ---------- resume_command_for ----------

def test_resume_command_claude():
    assert agent_hook.resume_command_for("claude", "abc") == "claude --resume abc"

def test_resume_command_codex():
    assert agent_hook.resume_command_for("codex", "xyz") == "codex resume xyz"

def test_resume_command_opencode():
    assert agent_hook.resume_command_for("opencode", "ses_abc") == "opencode --session ses_abc"

def test_resume_command_unknown_agent_returns_empty():
    assert agent_hook.resume_command_for("aider", "xyz") == ""

def test_resume_command_empty_session_returns_empty():
    assert agent_hook.resume_command_for("claude", "") == ""

def test_resume_command_rejects_shell_metacharacters():
    """Critical: session id is persisted into a string later auto-typed
    into a shell. Anything outside [A-Za-z0-9_-] must short-circuit so a
    malicious payload can't inject `; rm -rf …`."""
    bad = ["abc; touch /tmp/pwn", "abc def", "abc`whoami`", "abc$(id)",
           "abc&", "abc|cat", "abc\nrm", "../etc/passwd", "a/b"]
    for value in bad:
        assert agent_hook.resume_command_for("claude", value) == "", value
        assert agent_hook.resume_command_for("codex", value) == "", value

def test_resume_command_accepts_uuid_shapes():
    good = ["550e8400-e29b-41d4-a716-446655440000",
            "550e8400e29b41d4a716446655440000",
            "abc_DEF-123",
            "xyz"]
    for value in good:
        assert agent_hook.resume_command_for("claude", value) == f"claude --resume {value}"


def test_dispatch_pretool_does_not_emit_resume(tmp_path):
    """resumeCommand should appear ONLY on `prompt` to avoid spamming
    the socket with the same value on every tool call."""
    sf = tmp_path / "sessions.json"
    agent_hook.dispatch("prompt", "claude", {"session_id": "s9"}, "t9", sf, 6_000_000.0)
    emit = agent_hook.dispatch("pretool", "claude",
                               {"session_id": "s9", "tool_name": "Bash",
                                "tool_input": {"command": "ls"}},
                               "t9", sf, 6_000_001.0)
    assert "resumeCommand" not in emit
