import yaml
from pathlib import Path

def load_config(path: str) -> dict:
    p = Path(path)
    with p.open("r") as f:
        return yaml.safe_load(f)

def save_config(path: str, cfg: dict) -> None:
    p = Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    with p.open("w") as f:
        yaml.safe_dump(cfg, f, sort_keys=False)