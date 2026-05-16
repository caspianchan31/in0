#!/usr/bin/env python3
"""agent-hook.py — agent lifecycle dispatch for Claude Code / Codex hooks.

Invoked by agent-hook.sh. Reads context out of env vars (the bash entry
moves stdin into `_IN0_PAYLOAD` so this stays an exec'd script with a
single stdin read upstream). Maintains a per-session state file under
`~/Library/Caches/in0/agent-sessions.json` so a single turn that spans
prompt → pretool* → posttool* → stop can carry state without re-parsing
the transcript on every step.

Subcommands:
    prompt    UserPromptSubmit — reset turn flags, emit `running`
    pretool   PreToolUse — store current tool, emit `running` + toolDetail
    posttool  PostToolUse — sticky-set turnHadError if tool_response.is_error,
              re-emit `running` (the user may have just resolved a permission
              prompt, which would have set us to `needsInput`)
    stop      Stop — aggregate to exitCode + transcript summary, emit
              `finished`, garbage-collect session entry
"""

import fcntl
import json
import os
import pathlib
import re
import socket
import time

SESSION_TTL_SEC = 3600
SUMMARY_MAXLEN = 200

# Session ids from claude/codex are UUID-ish. Lock the resume-command
# composition to this charset so a malformed hook payload can't inject
# shell metacharacters into the persisted `initial_input`.
SESSION_ID_RE = re.compile(r"\A[A-Za-z0-9_-]+\Z")


def parse_payload() -> dict:
    raw = os.environ.get("_IN0_PAYLOAD", "")
    if not raw.strip():
        return {}
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return {}


def short_path(p: str) -> str:
    """Trim file paths to their last three segments for status display."""
    parts = [s for s in p.split("/") if s]
    if len(parts) <= 3:
        return "/".join(parts)
    return "/".join(parts[-3:])


def describe_tool(tool: str, tool_input) -> str:
    """One-line human label for `<Tool> <args>` — used as toolDetail."""
    if not isinstance(tool_input, dict):
        return tool or ""
    if tool in ("Edit", "Write", "Read"):
        p = short_path(tool_input.get("file_path", ""))
        return f"{tool} {p}" if p else tool
    if tool == "Bash":
        cmd = (tool_input.get("command") or "").split("\n")[0][:60]
        return f"Bash: {cmd}" if cmd else "Bash"
    if tool == "Grep":
        return f"Grep {tool_input.get('pattern', '')!r}"
    if tool == "Glob":
        return f"Glob {tool_input.get('pattern', '')}"
    if tool == "Task":
        return f"Subagent: {tool_input.get('subagent_type', 'general-purpose')}"
    return tool or ""


def read_transcript_summary(path: str) -> str:
    """Pull the last assistant message out of Claude's transcript JSONL,
    strip <thinking>…</thinking> blocks, truncate to SUMMARY_MAXLEN. Any
    error returns empty string so we never block emit on transcript I/O."""
    if not path:
        return ""
    try:
        with open(path) as f:
            lines = f.readlines()
    except OSError:
        return ""
    for line in reversed(lines):
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            continue
        if not isinstance(msg, dict) or msg.get("role") != "assistant":
            continue
        content = msg.get("content", "")
        if isinstance(content, list):
            text = ""
            for block in content:
                if isinstance(block, dict) and block.get("type") == "text":
                    text = block.get("text", "")
                    break
            content = text
        if not isinstance(content, str):
            continue
        content = re.sub(r"<thinking>.*?</thinking>", "", content, flags=re.S)
        content = " ".join(content.split())
        if content:
            return content[:SUMMARY_MAXLEN]
    return ""


def load_sessions(path: pathlib.Path) -> dict:
    if not path.exists():
        return {"version": 1, "sessions": {}}
    try:
        with open(path) as f:
            fcntl.flock(f, fcntl.LOCK_SH)
            try:
                return json.load(f)
            finally:
                fcntl.flock(f, fcntl.LOCK_UN)
    except (OSError, json.JSONDecodeError):
        return {"version": 1, "sessions": {}}


def write_sessions(path: pathlib.Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w") as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        try:
            json.dump(data, f)
        finally:
            fcntl.flock(f, fcntl.LOCK_UN)


def gc_stale(doc: dict, now: float) -> dict:
    """Drop session entries whose `lastTouched` is older than the TTL."""
    cutoff = now - SESSION_TTL_SEC
    kept = {
        sid: s for sid, s in doc.get("sessions", {}).items()
        if s.get("lastTouched", 0) > cutoff
    }
    return {"version": 1, "sessions": kept}


def emit_to_socket(sock_path: str, msg: dict) -> None:
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(0.5)
        s.connect(sock_path)
        s.sendall((json.dumps(msg) + "\n").encode())
        s.close()
    except OSError:
        pass


def _default_entry(agent: str, terminal_id: str) -> dict:
    return {
        "agent": agent,
        "terminalId": terminal_id,
        "turnStartedAt": 0,
        "turnHadError": False,
        "currentToolName": None,
        "currentToolDetail": None,
        "transcriptPath": None,
        "lastTouched": 0,
    }


def resume_command_for(agent: str, session_id: str) -> str:
    """Build the `<agent> --resume <id>` CLI form. Returns '' for unknown
    agents or non-conforming session ids."""
    if not session_id or not SESSION_ID_RE.match(session_id):
        return ""
    if agent == "claude":
        return f"claude --resume {session_id}"
    if agent == "codex":
        return f"codex resume {session_id}"
    if agent == "opencode":
        return f"opencode --session {session_id}"
    return ""


def dispatch(subcmd, agent, payload, terminal_id, session_file, now):
    doc = load_sessions(session_file)
    entries = doc.setdefault("sessions", {})
    session_id = (payload.get("session_id")
                  or payload.get("sessionId")
                  or terminal_id)

    entry = entries.setdefault(session_id, _default_entry(agent, terminal_id))
    entry["agent"] = agent
    entry["terminalId"] = terminal_id
    entry["lastTouched"] = now

    emit: dict = {}

    if subcmd == "prompt":
        entry["turnStartedAt"] = now
        entry["turnHadError"] = False
        entry["currentToolName"] = None
        entry["currentToolDetail"] = None
        tp = payload.get("transcript_path")
        if tp:
            entry["transcriptPath"] = tp
        emit = {"event": "running", "at": now}
        resume = resume_command_for(agent, str(session_id))
        if resume:
            emit["resumeCommand"] = resume

    elif subcmd == "pretool":
        tool = payload.get("tool_name", "") or ""
        tool_input = payload.get("tool_input", {})
        detail = describe_tool(tool, tool_input) if tool else None
        entry["currentToolName"] = tool or None
        entry["currentToolDetail"] = detail
        emit = {"event": "running", "at": now}
        if detail:
            emit["toolDetail"] = detail

    elif subcmd == "posttool":
        resp = payload.get("tool_response", {})
        if isinstance(resp, dict) and resp.get("is_error"):
            entry["turnHadError"] = True
        emit = {"event": "running", "at": now}

    elif subcmd == "stop":
        exit_code = 1 if entry.get("turnHadError") else 0
        summary = read_transcript_summary(entry.get("transcriptPath") or "")
        emit = {"event": "finished", "at": now, "exitCode": exit_code}
        if summary:
            emit["summary"] = summary
        entries.pop(session_id, None)

    doc = gc_stale(doc, now)
    write_sessions(session_file, doc)
    return emit


def main():
    subcmd = os.environ.get("_IN0_SUBCMD", "stop")
    agent = os.environ.get("_IN0_AGENT", "claude")
    session_file = pathlib.Path(os.environ["_IN0_SESSION_FILE"])
    terminal_id = os.environ["IN0_TERMINAL_ID"]
    sock_path = os.environ["IN0_HOOK_SOCK"]
    payload = parse_payload()
    now = time.time()

    emit = dispatch(subcmd, agent, payload, terminal_id, session_file, now)
    if emit:
        emit["terminalId"] = terminal_id
        emit["agent"] = agent
        emit_to_socket(sock_path, emit)


if __name__ == "__main__":
    main()
