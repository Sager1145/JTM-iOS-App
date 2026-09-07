"""Coordinate package writers and readers across one multi-file release."""
import fcntl
import json
import os
from contextlib import contextmanager, ExitStack

_HELD = {}
_ENV = 'JTM_RAIL_RELEASE_LOCKS'


def inherited_lock_fds():
    return tuple(_HELD.values())


@contextmanager
def release_locks(directories, shared=False):
    """Fail promptly on a competing writer; child audits inherit our locks.

    Lock both the package and solver-data directories. Different candidate
    builds may share one data directory, so locking only the package is unsafe.
    Lock files stay in place: unlinking a held lock creates a second inode.
    """
    inherited = json.loads(os.environ.get(_ENV, '{}'))
    with ExitStack() as stack:
        previous = os.environ.get(_ENV)
        acquired = []
        try:
            for directory in sorted({os.path.realpath(p) for p in directories}):
                os.makedirs(directory, exist_ok=True)
                path = os.path.join(directory, '.na-rail.lock')
                if path in _HELD:
                    continue
                fd = inherited.get(path)
                if isinstance(fd, int):
                    try:
                        actual, expected = os.fstat(fd), os.stat(path)
                        if (actual.st_dev, actual.st_ino) == (expected.st_dev, expected.st_ino):
                            continue
                    except OSError:
                        pass
                handle = stack.enter_context(open(path, 'a+'))
                try:
                    fcntl.flock(handle, (fcntl.LOCK_SH if shared else fcntl.LOCK_EX)
                                | fcntl.LOCK_NB)
                except BlockingIOError:
                    raise RuntimeError('rail release is busy: ' + directory) from None
                _HELD[path] = handle.fileno()
                acquired.append(path)
            os.environ[_ENV] = json.dumps({**inherited, **_HELD})
            yield
        finally:
            for path in acquired:
                _HELD.pop(path, None)
            if previous is None:
                os.environ.pop(_ENV, None)
            else:
                os.environ[_ENV] = previous

