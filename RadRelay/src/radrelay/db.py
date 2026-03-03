import sqlite3
import time
import os

def _conn(db_path: str):
    os.makedirs(os.path.dirname(db_path), exist_ok=True)
    return sqlite3.connect(db_path)

def init_db(cfg):
    db = cfg["paths"]["state_db"]
    with _conn(db) as c:
        c.execute("""
        CREATE TABLE IF NOT EXISTS jobs (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          workflow TEXT,
          path TEXT,
          status TEXT,
          error TEXT,
          created_at REAL,
          finished_at REAL
        )
        """)
        c.commit()

def record_job(cfg, workflow: str, path: str) -> int:
    db = cfg["paths"]["state_db"]
    with _conn(db) as c:
        cur = c.execute(
            "INSERT INTO jobs(workflow,path,status,created_at) VALUES(?,?,?,?)",
            (workflow, path, "running", time.time())
        )
        c.commit()
        return cur.lastrowid

def mark_job_done(cfg, job_id: int):
    db = cfg["paths"]["state_db"]
    with _conn(db) as c:
        c.execute("UPDATE jobs SET status=?, finished_at=? WHERE id=?", ("done", time.time(), job_id))
        c.commit()

def mark_job_failed(cfg, job_id: int, err: str):
    db = cfg["paths"]["state_db"]
    with _conn(db) as c:
        c.execute("UPDATE jobs SET status=?, error=?, finished_at=? WHERE id=?", ("failed", err[:2000], time.time(), job_id))
        c.commit()

def get_recent_jobs(cfg, limit: int = 50):
    db = cfg["paths"]["state_db"]
    with _conn(db) as c:
        c.row_factory = sqlite3.Row
        rows = c.execute("SELECT * FROM jobs ORDER BY id DESC LIMIT ?", (limit,)).fetchall()
        return [dict(r) for r in rows]