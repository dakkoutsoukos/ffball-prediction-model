import json
import time

import pytest

from ffui import jobs as J

CTX = {"league_raw_sha256": "abc", "valuation_run_id": "r1"}


def wait(r, op, key, timeout=30):
    t = time.time()
    job = r.poll(op, key)
    while job.state == "running" and time.time() - t < timeout:
        time.sleep(0.1)
        job = r.poll(op, key)
    return job


def test_cache_key_deterministic_and_sensitive():
    k = J.cache_key("odds", {"sims": 1000, "add": []}, CTX, "v1")
    assert k == J.cache_key("odds", {"add": [], "sims": 1000}, dict(reversed(list(CTX.items()))), "v1")
    assert k != J.cache_key("odds", {"sims": 2000, "add": []}, CTX, "v1")
    assert k != J.cache_key("odds", {"sims": 1000, "add": []}, {**CTX, "league_raw_sha256": "new"}, "v1")
    assert k != J.cache_key("odds", {"sims": 1000, "add": []}, CTX, "v2")
    assert k != J.cache_key("lineup", {"sims": 1000, "add": []}, CTX, "v1")


def test_run_then_cached(fake_runner):
    r = fake_runner
    job = r.start("odds", {"sims": 1000}, CTX)
    assert job.state == "running"
    done = wait(r, "odds", job.key)
    assert done.state == "done" and done.result["echo"] == {"sims": 1000}
    again = r.start("odds", {"sims": 1000}, CTX)
    assert again.state == "cached" and again.key == job.key
    assert r.lock_holder() is None
    out = r.out_dir("odds", job.key)
    assert J.is_inside(out, r.repo.ui_cache) and not list(out.parent.glob("*.tmp*"))


def test_duplicate_request_shares_one_job_and_lock_blocks_others(fake_runner):
    r = fake_runner
    a = r.start("odds", {"sleep": 1.5}, CTX)
    b = r.start("odds", {"sleep": 1.5}, CTX)
    assert a.state == "running" and b.state == "running" and a.key == b.key
    c = r.start("lineup", {}, CTX)
    assert c.state == "busy"
    assert wait(r, "odds", a.key).state == "done"
    assert wait(r, "lineup", r.start("lineup", {}, CTX).key).state == "done"


def test_adapter_error_is_parsed_without_trace(fake_runner):
    r = fake_runner
    job = r.start("odds", {"fail": 3}, CTX)
    done = wait(r, "odds", job.key)
    assert done.state == "failed" and done.code == 3
    assert "test failure" in done.message and "noise line" not in done.message
    assert r.lock_holder() is None
    assert r.cached("odds", job.key) is None


def test_tripwire_reported(fake_runner):
    r = fake_runner
    job = r.start("odds", {"trip": 1}, CTX)
    done = wait(r, "odds", job.key)
    assert done.state == "failed" and done.code == 5 and "trip-wire" in done.message


def test_timeout_kills_process(fake_runner, monkeypatch):
    r = fake_runner
    monkeypatch.setitem(J.OPS, "odds", (1, 1))
    job = r.start("odds", {"sleep": 30}, CTX)
    pid = json.loads(r._status_path(job.key).read_text())["pid"]
    time.sleep(1.6)
    done = r.poll("odds", job.key)
    assert done.state == "timeout"
    time.sleep(0.5)
    assert not J.pid_alive(pid)
    assert r.cached("odds", job.key) is None and r.lock_holder() is None


def test_cancel(fake_runner):
    r = fake_runner
    job = r.start("odds", {"sleep": 30}, CTX)
    pid = json.loads(r._status_path(job.key).read_text())["pid"]
    assert r.cancel("odds", job.key).state == "cancelled"
    time.sleep(0.5)
    assert not J.pid_alive(pid) and r.lock_holder() is None


def test_recover_marks_interrupted(fake_runner):
    r = fake_runner
    key = r.key_for("odds", {"x": 1}, CTX)
    r._write_status(key, {"op": "odds", "key": key, "pid": 999999, "state": "running", "started": time.time()})
    assert r.recover() == 1
    assert r.poll("odds", key).state == "interrupted"


def test_stale_lock_cleared(fake_runner):
    r = fake_runner
    r._acquire("k", 999999)
    assert r.lock_holder() is None and not r.lock.exists()


def test_unknown_op_and_missing_rscript(repo):
    r = J.JobRunner(repo, rscript=None)
    r.rscript = None
    with pytest.raises(ValueError):
        r.start("rm_rf", {}, CTX)
    assert r.start("odds", {}, CTX).state == "failed"


def test_clear_cache_only_inside_data_archive(fake_runner):
    r = fake_runner
    wait(r, "odds", r.start("odds", {}, CTX).key)
    assert r.cache_size()[0] > 0
    r.clear_cache()
    assert not r.cache.exists()
