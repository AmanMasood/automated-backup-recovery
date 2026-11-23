import os
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import backup_report  # noqa: E402


def make_set(root, name, content=b"data"):
    d = root / name
    d.mkdir(parents=True)
    f = d / "files_x.tar.gz"
    f.write_bytes(content)
    digest = subprocess.check_output(["sha256sum", str(f)]).split()[0].decode()
    (d / "SHA256SUMS").write_text(f"{digest}  files_x.tar.gz\n")
    return d


def test_no_backups(tmp_path):
    assert backup_report.main(["--root", str(tmp_path)]) == 1


def test_stale_backup(tmp_path):
    make_set(tmp_path, "2020-01-01_000000")
    assert backup_report.main(["--root", str(tmp_path), "--max-age-hours", "24"]) == 1


def test_checksum_failure(tmp_path):
    d = make_set(tmp_path, "2099-01-01_000000")
    (d / "files_x.tar.gz").write_bytes(b"tampered")
    assert backup_report.main(["--root", str(tmp_path), "--max-age-hours", "1e9"]) == 2


def test_ok(tmp_path, capsys):
    make_set(tmp_path, "2099-01-01_000000")
    assert backup_report.main(["--root", str(tmp_path), "--max-age-hours", "1e9", "--json"]) == 0
    assert '"status": "ok"' in capsys.readouterr().out
