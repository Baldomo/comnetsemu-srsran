from itertools import chain
from subprocess import run

from _collections_abc import MutableMapping

_REPO_DIR = None


def get_root_dir() -> str:
    """Returns the root directory of the git repository"""
    global _REPO_DIR
    if not _REPO_DIR:
        _REPO_DIR = run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True,
            encoding="utf-8",
        ).stdout.strip()
    return _REPO_DIR


def dict_union(*args) -> dict:
    """Behaves like the | (binary or) operator in python 3.9+"""
    return dict(chain.from_iterable(d.items() for d in args))
