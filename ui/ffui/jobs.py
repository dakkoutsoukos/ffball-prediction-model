"""Background execution of the R adapter (ui/r/ui_adapter.R) with deterministic caching.

* Results live in data/archive/ui_cache/<op>/<key>/ (written by R via temp dir + rename, so never partial).
* One adapter job at a time (global lock file); identical requests share one job and one cached result.
* Jobs survive Streamlit reruns: state is on disk (status.json), the process is tracked by PID.
* Arguments are passed as a list (no shell); user input only ever reaches R inside request.json.
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
import sys
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

from .paths import Repo, find_rscript, is_inside

OPS = {
    # op: (timeout seconds, typical seconds measured on this machine at the default sims)
    "noop": (60, 2), "health": (120, 2), "context": (180, 4), "lineup": (180, 3), "odds": (420, 15),
    "trade_eval": (420, 10), "trade_search": (900, 45), "fa_board": (900, 30), "values3": (900, 50),
    "research_target": (180, 5),
}
ERROR_CODES = {2: "bad request", 3: "missing, stale or changed context", 4: "computation failed", 5: "safety trip-wire fired"}
LOCK_STALE_SECONDS = 1800


def _now() -> float:
    return time.time()


def pid_alive(pid: int | None) -> bool:
    if not pid:
        return False
    if sys.platform == "win32":
        import ctypes
        from ctypes import wintypes
        k32 = ctypes.WinDLL("kernel32", use_last_error=True)
        k32.OpenProcess.restype = wintypes.HANDLE
        h = k32.OpenProcess(0x1000, False, int(pid))  # PROCESS_QUERY_LIMITED_INFORMATION
        if not h:
            return False
        try:
            code = wintypes.DWORD()
            ok = k32.GetExitCodeProcess(h, ctypes.byref(code))
            return bool(ok) and code.value == 259  # STILL_ACTIVE
        finally:
            k32.CloseHandle(h)
    try:
        os.kill(int(pid), 0)
        return True
    except OSError:
        return False


def kill_tree(pid: int) -> None:
    if sys.platform == "win32":
        subprocess.run(["taskkill", "/PID", str(int(pid)), "/T", "/F"], capture_output=True,
                       creationflags=subprocess.CREATE_NO_WINDOW)
    else:  # pragma: no cover - the app targets Windows; kept for portability
        import signal
        try:
            os.killpg(os.getpgid(int(pid)), signal.SIGTERM)
        except OSError:
            pass


def _canon(x) -> str:
    return json.dumps(x, sort_keys=True, separators=(",", ":"), default=str)


def file_sha(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest() if p.exists() else "missing"


def git_head(repo: Repo) -> str:
    try:
        ref = (repo.root / ".git" / "HEAD").read_text().strip()
        if ref.startswith("ref: "):
            p = repo.root / ".git" / ref[5:]
            if p.exists():
                return p.read_text().strip()
            packed = repo.root / ".git" / "packed-refs"
            if packed.exists():
                for ln in packed.read_text().splitlines():
                    if ln.endswith(ref[5:]):
                        return ln.split()[0]
        return ref
    except OSError:
        return "unknown"


def cache_key(op: str, params: dict, context: dict, code_version: str) -> str:
    """Deterministic: op, normalized params, the data context (league snapshot hash, valuation run) and the
    code version (git HEAD + adapter file hash). Seeds are fixed inside the core R functions."""
    body = _canon({"op": op, "params": params, "context": context, "code": code_version})
    return hashlib.sha256(body.encode()).hexdigest()[:24]


@dataclass
class Job:
    op: str
    key: str
    state: str  # cached | running | done | failed | timeout | cancelled | interrupted | busy
    result: dict | None = None
    meta: dict | None = None
    message: str = ""
    elapsed: float = 0.0
    expected: float = 0.0
    code: int | None = None


class JobRunner:
    def __init__(self, repo: Repo, rscript: str | None = None):
        self.repo = repo
        self.rscript = rscript or find_rscript()
        self.cache = repo.ui_cache
        self.jobs_dir = self.cache / "jobs"
        self.lock = self.cache / ".lock"

    # ------------------------------------------------------------- paths
    def code_version(self) -> str:
        return git_head(self.repo)[:12] + ":" + file_sha(self.repo.adapter)[:12]

    def out_dir(self, op: str, key: str) -> Path:
        return self.cache / op / key

    def _status_path(self, key: str) -> Path:
        return self.jobs_dir / key / "status.json"

    def _read_status(self, key: str) -> dict | None:
        p = self._status_path(key)
        try:
            return json.loads(p.read_text(encoding="utf-8")) if p.exists() else None
        except (OSError, json.JSONDecodeError):
            return None

    def _write_status(self, key: str, st: dict) -> None:
        p = self._status_path(key)
        p.parent.mkdir(parents=True, exist_ok=True)
        tmp = p.with_suffix(".tmp")
        tmp.write_text(json.dumps(st, indent=1), encoding="utf-8")
        os.replace(tmp, p)

    # ------------------------------------------------------------- lock (one adapter job at a time)
    def lock_holder(self) -> dict | None:
        try:
            info = json.loads(self.lock.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            return None
        if not pid_alive(info.get("pid")) or _now() - info.get("t", 0) > LOCK_STALE_SECONDS:
            self.release_lock()
            return None
        return info

    def _acquire(self, key: str, pid: int) -> None:
        self.cache.mkdir(parents=True, exist_ok=True)
        self.lock.write_text(json.dumps({"key": key, "pid": pid, "t": _now()}), encoding="utf-8")

    def release_lock(self, key: str | None = None) -> None:
        try:
            if key is not None:
                info = json.loads(self.lock.read_text(encoding="utf-8"))
                if info.get("key") != key:
                    return
            self.lock.unlink()
        except (OSError, json.JSONDecodeError):
            pass

    # ------------------------------------------------------------- results
    def cached(self, op: str, key: str) -> Job | None:
        d = self.out_dir(op, key)
        if (d / "result.json").exists() and (d / "meta.json").exists():
            meta = json.loads((d / "meta.json").read_text(encoding="utf-8"))
            res = json.loads((d / "result.json").read_text(encoding="utf-8"))
            return Job(op, key, "cached", res, meta, elapsed=meta.get("elapsed_seconds", 0.0), expected=OPS[op][1])
        return None

    def key_for(self, op: str, params: dict, context: dict) -> str:
        return cache_key(op, params, context, self.code_version())

    # ------------------------------------------------------------- start / poll / cancel
    def start(self, op: str, params: dict, context: dict) -> Job:
        if op not in OPS:
            raise ValueError(f"unknown op {op}")
        key = self.key_for(op, params, context)
        hit = self.cached(op, key)
        if hit:
            return hit
        st = self._read_status(key)
        if st and st.get("state") == "running" and pid_alive(st.get("pid")):
            return self.poll(op, key)
        holder = self.lock_holder()
        if holder and holder.get("key") != key:
            return Job(op, key, "busy", message="Another calculation is running; wait for it or cancel it on the Operations page.")
        if not self.rscript:
            return Job(op, key, "failed", message="Rscript was not found (set FFUI_RSCRIPT to its path).")
        jd = self.jobs_dir / key
        jd.mkdir(parents=True, exist_ok=True)
        req = jd / "request.json"
        req.write_text(json.dumps({"op": op, "params": params, "context": context}, default=str), encoding="utf-8")
        out = self.out_dir(op, key)
        assert is_inside(out, self.cache)
        out.parent.mkdir(parents=True, exist_ok=True)
        flags = (subprocess.CREATE_NO_WINDOW | subprocess.CREATE_NEW_PROCESS_GROUP) if sys.platform == "win32" else 0
        with open(jd / "stdout.log", "wb") as so, open(jd / "stderr.log", "wb") as se:
            proc = subprocess.Popen([self.rscript, str(self.repo.adapter), op, "--request", str(req), "--out", str(out)],
                                    cwd=str(self.repo.root), stdout=so, stderr=se, stdin=subprocess.DEVNULL,
                                    creationflags=flags, start_new_session=(sys.platform != "win32"))
        self._acquire(key, proc.pid)
        self._write_status(key, {"op": op, "key": key, "pid": proc.pid, "state": "running", "started": _now(),
                                 "timeout": OPS[op][0], "params": params})
        return Job(op, key, "running", expected=OPS[op][1])

    def poll(self, op: str, key: str) -> Job:
        hit = self.cached(op, key)
        st = self._read_status(key) or {}
        if hit:
            if st.get("state") == "running":
                st["state"] = "done"
                self._write_status(key, st)
                self.release_lock(key)
            hit.state = "done" if st else "cached"
            return hit
        if not st:
            return Job(op, key, "failed", message="No such job.")
        elapsed = _now() - st.get("started", _now())
        if st.get("state") != "running":
            return Job(op, key, st.get("state", "failed"), message=st.get("message", ""), elapsed=elapsed,
                       code=st.get("code"), expected=OPS[op][1])
        if pid_alive(st.get("pid")):
            if elapsed > st.get("timeout", OPS[op][0]):
                kill_tree(st["pid"])
                return self._finish(key, st, "timeout", f"Stopped after {int(elapsed)} s (time limit {st.get('timeout')} s).")
            return Job(op, key, "running", elapsed=elapsed, expected=OPS[op][1])
        # the process ended without a result: read the adapter's own error line (never the raw trace)
        time.sleep(0.2)
        hit = self.cached(op, key)
        if hit:
            return self.poll(op, key)
        code, msg = self.adapter_error(key)
        return self._finish(key, st, "failed", msg, code)

    def _finish(self, key: str, st: dict, state: str, message: str, code: int | None = None) -> Job:
        st.update(state=state, message=message, code=code, finished=_now())
        self._write_status(key, st)
        self.release_lock(key)
        return Job(st["op"], key, state, message=message, code=code, elapsed=st["finished"] - st.get("started", st["finished"]))

    def adapter_error(self, key: str) -> tuple[int | None, str]:
        p = self.jobs_dir / key / "stderr.log"
        text = p.read_text(encoding="utf-8", errors="replace") if p.exists() else ""
        m = re.search(r"UI_ADAPTER_ERROR (\d+): (.*)", text)
        if m:
            code = int(m.group(1))
            return code, f"{ERROR_CODES.get(code, 'error')}: {m.group(2).strip()}"
        m = re.search(r"UI_ADAPTER_TRIPWIRE (\S+)", text)
        if m:
            return 5, f"safety trip-wire fired ({m.group(1)}); nothing was written. See the Operations page."
        return None, "The R process ended without a result. Details are in the job log on the Operations page."

    def cancel(self, op: str, key: str) -> Job:
        st = self._read_status(key)
        if not st or st.get("state") != "running":
            return self.poll(op, key)
        if pid_alive(st.get("pid")):
            kill_tree(st["pid"])
        return self._finish(key, st, "cancelled", "Cancelled.")

    def wait(self, op: str, params: dict, context: dict, poll_s: float = 0.25) -> Job:
        """Blocking run for fast ops (seconds); still cached and lock-protected."""
        job = self.start(op, params, context)
        while job.state == "running":
            time.sleep(poll_s)
            job = self.poll(op, job.key)
        return job

    # ------------------------------------------------------------- recovery and housekeeping
    def recover(self) -> int:
        """Mark jobs whose process died (app restart, crash) as interrupted; remove orphan temp dirs."""
        n = 0
        for sp in self.jobs_dir.glob("*/status.json") if self.jobs_dir.exists() else []:
            try:
                st = json.loads(sp.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError):
                continue
            if st.get("state") == "running" and not pid_alive(st.get("pid")) and not self.cached(st["op"], st["key"]):
                st.update(state="interrupted", message="The process stopped before finishing (app restart or crash).")
                self._write_status(st["key"], st)
                n += 1
        for t in self.cache.glob("*/*.tmp*") if self.cache.exists() else []:
            if t.is_dir() and _now() - t.stat().st_mtime > 3600:
                import shutil
                shutil.rmtree(t, ignore_errors=True)
        self.lock_holder()  # clears a stale lock
        return n

    def history(self, n: int = 50) -> list[dict]:
        out = []
        for sp in self.jobs_dir.glob("*/status.json") if self.jobs_dir.exists() else []:
            try:
                out.append(json.loads(sp.read_text(encoding="utf-8")))
            except (OSError, json.JSONDecodeError):
                continue
        return sorted(out, key=lambda s: s.get("started", 0), reverse=True)[:n]

    def cache_size(self) -> tuple[int, int]:
        files = [p for p in self.cache.rglob("*") if p.is_file()] if self.cache.exists() else []
        return len(files), sum(p.stat().st_size for p in files)

    def clear_cache(self) -> None:
        import shutil
        if self.lock_holder():
            raise RuntimeError("a calculation is running")
        if self.cache.exists() and is_inside(self.cache, self.repo.data_archive):
            shutil.rmtree(self.cache)


def fmt_time(ts: float | None) -> str:
    if not ts:
        return "-"
    return datetime.fromtimestamp(ts, timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
