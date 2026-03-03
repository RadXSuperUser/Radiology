"""
Daemon entrypoints and lifecycle helpers for RadRelay.

Implement process supervision, startup/shutdown hooks, and signal
handling here as the service is developed.
"""

import os
import re
import time
import queue
import threading
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Dict, Optional

from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler

from radrelay.config import load_config
from radrelay.db import init_db, record_job, mark_job_done, mark_job_failed
from radrelay.logging import get_logger

log = get_logger("radrelay.daemon")

@dataclass
class Job:
    path: str
    workflow: str
    created_at: float

class InboundHandler(FileSystemEventHandler):
    def __init__(self, job_queue: queue.Queue, cfg):
        self.job_queue = job_queue
        self.cfg = cfg
        self.ignore = tuple(cfg["watch"]["ignore_patterns"])
        self.routes = [(re.compile(r["match"]), r["workflow"]) for r in cfg["routing"]]

    def _ignored(self, p: str) -> bool:
        name = os.path.basename(p)
        return any(name.endswith(x.replace("*", "")) for x in self.ignore) or name.startswith(".")

    def _route(self, p: str) -> str:
        name = os.path.basename(p)
        for rx, wf in self.routes:
            if rx.match(name):
                return wf
        return "hl7_pdf_dcm"

    def on_created(self, event):
        if event.is_directory:
            return
        self._handle(event.src_path)

    def on_moved(self, event):
        if event.is_directory:
            return
        self._handle(event.dest_path)

    def _handle(self, path: str):
        if self._ignored(path):
            return
        # Avoid immediate processing if still writing
        if not wait_for_stable_size(path, max_wait_s=30, stable_checks=2, interval_s=0.5):
            log.warning("File not stable but proceeding: %s", path)

        wf = self._route(path)
        self.job_queue.put(Job(path=path, workflow=wf, created_at=time.time()))
        log.info("Queued job workflow=%s path=%s", wf, path)

def wait_for_stable_size(path: str, max_wait_s: int, stable_checks: int, interval_s: float) -> bool:
    p = Path(path)
    if not p.exists():
        return False
    last = -1
    stable = 0
    deadline = time.time() + max_wait_s
    while time.time() < deadline:
        if not p.exists():
            return False
        try:
            size = p.stat().st_size
        except Exception:
            time.sleep(interval_s)
            continue
        if size == last and size >= 0:
            stable += 1
            if stable >= stable_checks:
                return True
        else:
            stable = 0
            last = size
        time.sleep(interval_s)
    return False

def worker_loop(job_queue: queue.Queue, cfg, workflows: Dict[str, Callable[[str, dict], None]]):
    while True:
        job: Job = job_queue.get()
        job_id = record_job(cfg, job.workflow, job.path)
        try:
            workflows[job.workflow](job.path, cfg)
            mark_job_done(cfg, job_id)
        except Exception as e:
            log.exception("Job failed id=%s workflow=%s path=%s", job_id, job.workflow, job.path)
            mark_job_failed(cfg, job_id, str(e))
        finally:
            job_queue.task_done()

def main():
    cfg = load_config(os.environ.get("RADRELAY_CONFIG", "/etc/radrelay/config.yaml"))
    init_db(cfg)

    # Ensure dirs exist
    for k in ["data_dir", "inbound", "fax_dir", "prelim_dir", "hl7_dir"]:
        os.makedirs(cfg["paths"][k], exist_ok=True)
    os.makedirs(os.path.dirname(cfg["paths"]["state_db"]), exist_ok=True)
    os.makedirs(cfg["paths"]["logs_dir"], exist_ok=True)

    from radrelay.workflows.hl7_pdf_dcm import run as run_hl7
    from radrelay.workflows.oru2pdf import run as run_oru
    from radrelay.workflows.prelim_sr import run as run_prelim

    workflows = {
        "hl7_pdf_dcm": run_hl7,
        "oru2pdf": run_oru,
        "prelim_sr": run_prelim,
    }

    job_queue: queue.Queue = queue.Queue(maxsize=5000)

    # Worker pool
    workers = []
    for _ in range(4):
        t = threading.Thread(target=worker_loop, args=(job_queue, cfg, workflows), daemon=True)
        t.start()
        workers.append(t)

    observer = Observer()
    handler = InboundHandler(job_queue, cfg)
    observer.schedule(handler, cfg["paths"]["inbound"], recursive=False)
    observer.start()

    log.info("RadRelay started. Watching: %s", cfg["paths"]["inbound"])
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        pass
    finally:
        observer.stop()
        observer.join()

if __name__ == "__main__":
    main()