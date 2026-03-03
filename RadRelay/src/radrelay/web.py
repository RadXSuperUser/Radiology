import os
from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.responses import HTMLResponse
from radrelay.config import load_config, save_config
from radrelay.db import get_recent_jobs

app = FastAPI(title="RadRelay")

CFG_PATH = os.environ.get("RADRELAY_CONFIG", "/etc/radrelay/config.yaml")

@app.get("/", response_class=HTMLResponse)
def home():
    cfg = load_config(CFG_PATH)
    jobs = get_recent_jobs(cfg, limit=50)
    rows = "\n".join([f"<tr><td>{j['id']}</td><td>{j['workflow']}</td><td>{j['path']}</td><td>{j['status']}</td><td>{j['created_at']}</td></tr>" for j in jobs])
    return f"""
    <html><body style="font-family: sans-serif;">
      <h1>RadRelay</h1>
      <p><b>Inbound:</b> {cfg['paths']['inbound']}</p>
      <h2>Recent Jobs</h2>
      <table border="1" cellpadding="6" cellspacing="0">
        <tr><th>ID</th><th>Workflow</th><th>Path</th><th>Status</th><th>Created</th></tr>
        {rows}
      </table>
      <h2>Config</h2>
      <p>Use API endpoints: GET/PUT /config</p>
    </body></html>
    """

@app.get("/config")
def get_config():
    return load_config(CFG_PATH)

@app.put("/config")
def put_config(new_cfg: dict):
    # minimal validation for v1; we’ll harden
    if "paths" not in new_cfg or "inbound" not in new_cfg["paths"]:
        raise HTTPException(400, "Invalid config")
    save_config(CFG_PATH, new_cfg)
    return {"ok": True}

@app.get("/jobs")
def jobs(limit: int = 100):
    cfg = load_config(CFG_PATH)
    return get_recent_jobs(cfg, limit=limit)