"""Offline parity tests for vim9-plug and the pinned vim-plug reference."""

import argparse
import difflib
import os
from pathlib import Path
import shlex
import shutil
import subprocess
from tempfile import TemporaryDirectory


ROOT = Path(__file__).resolve().parents[1]
UPSTREAM = ROOT / "reference/vim-plug/plug.vim"
PORT = ROOT / "autoload/plug.vim"


def git(directory, *args):
    return subprocess.check_output(
        ["git", "-C", str(directory), *args],
        stderr=subprocess.STDOUT, text=True
    ).strip()


def make_fixture(directory):
    local = directory / "local eager plugin"
    (local / "plugin").mkdir(parents=True)
    (local / "after/plugin").mkdir(parents=True)
    (local / "doc").mkdir()
    (local / "plugin/eager.vim").write_text(
        "call add(g:load_order, 'eager')\n", encoding="utf-8")
    (local / "after/plugin/eager.vim").write_text(
        "call add(g:load_order, 'after eager')\n", encoding="utf-8")
    (local / "doc/fixture.txt").write_text(
        "Local fixture *plug-test-fixture*\n", encoding="utf-8")

    lazy = directory / "lazy plugin"
    (lazy / "plugin").mkdir(parents=True)
    (lazy / "plugin/lazy.vim").write_text(
        "command! -nargs=* -bang -range FixtureLazy "
        "let g:lazy_call = [<bang>0, <line1>, <line2>, <q-args>]\n"
        "nnoremap <Plug>(fixture-lazy) :let g:lazy_mapping = 1<CR>\n"
        "call add(g:load_order, 'lazy')\n", encoding="utf-8")

    leaf = directory / "submodule"
    leaf.mkdir()
    git(leaf, "init", "-b", "main")
    git(leaf, "-c", "user.name=Fixture Author", "-c",
        "user.email=fixture@example.test", "commit", "--allow-empty", "-m", "Submodule")

    remote = directory / "upstream remote"
    (remote / "plugin").mkdir(parents=True)
    git(remote, "init", "-b", "main")
    git(remote, "config", "user.name", "Fixture Author")
    git(remote, "config", "user.email", "fixture@example.test")
    git(remote, "config", "core.autocrlf", "false")
    (remote / "plugin/managed.vim").write_text(
        "let g:managed_plugin = 1\n", encoding="utf-8")
    git(remote, "-c", "protocol.file.allow=always", "submodule", "add",
        leaf.as_uri(), "vendor/submodule")
    git(remote, "add", ".")
    git(remote, "commit", "-m", "Initial plugin")
    git(remote, "tag", "v1")
    git(remote, "checkout", "-b", "next")
    (remote / "plugin/managed.vim").write_text(
        "let g:managed_plugin = 2\n", encoding="utf-8")
    git(remote, "commit", "-am", "Second version")
    git(remote, "update-ref", "refs/fixtures/next", "HEAD")
    git(remote, "checkout", "main")
    git(remote, "branch", "-D", "next")
    return local, lazy, remote


def make_upgrade_fixture(directory, text):
    script = directory / "autoload/plug.vim"
    script.parent.mkdir(parents=True)
    script.write_text(text, encoding="utf-8", newline="\n")
    git(directory, "init", "-b", "main")
    git(directory, "config", "user.name", "Fixture Author")
    git(directory, "config", "user.email", "fixture@example.test")
    git(directory, "config", "core.autocrlf", "false")
    git(directory, "add", ".")
    git(directory, "commit", "-m", "Upgrade fixture")


def run(vim, source, directory, scenario="workflow", cmd_shell=False):
    autoload = directory / "autoload"
    autoload.mkdir(parents=True)
    plug = autoload / "plug.vim"
    shutil.copyfile(source, plug)
    if source == PORT:
        with plug.open("a", encoding="utf-8", newline="\n") as staged:
            staged.write("\ndefcompile\n")

    local, lazy, remote = make_fixture(directory)
    env = os.environ.copy()
    env.update({
        "GIT_ALLOW_PROTOCOL": "file",
        "VIM9_PLUG_TEST_ROOT": directory.as_posix(),
        "VIM9_PLUG_TEST_LOCAL": local.as_posix(),
        "VIM9_PLUG_TEST_LAZY": lazy.as_posix(),
        "VIM9_PLUG_TEST_REMOTE": remote.as_uri(),
        "VIM9_PLUG_TEST_GIT_REPO": remote.as_posix(),
        "VIM9_PLUG_TEST_FIRST_SHA": git(remote, "rev-parse", "v1"),
        "VIM9_PLUG_TEST_SECOND_SHA": git(remote, "rev-parse", "refs/fixtures/next"),
        "VIM9_PLUG_TEST_OUTPUT": (directory / "observed.txt").as_posix(),
    })
    if scenario == "upgrade":
        good = directory / "valid-upgrade"
        bad = directory / "invalid-upgrade"
        make_upgrade_fixture(good, PORT.read_text(encoding="utf-8")
                             + "\ng:upgrade_fixture = 1\n")
        make_upgrade_fixture(bad, "vim9script noclear\nthrow 'fixture upgrade error'\n")
        env.update({
            "GIT_CONFIG_COUNT": "1",
            "GIT_CONFIG_VALUE_0": "https://github.com/itsuki-hayashi/vim9-plug.git",
            "VIM9_PLUG_TEST_GOOD_URL": good.as_uri(),
            "VIM9_PLUG_TEST_BAD_URL": bad.as_uri(),
        })
    elif scenario == "jobs" and os.name != "nt":
        # A controlled clone that creates its destination and waits to be stopped.
        git_shim = directory / "bin/git"
        git_shim.parent.mkdir()
        git_shim.write_text(
            '#!/bin/sh\n'
            'if [ "$1" = clone ]; then\n'
            '  for destination do :; done\n'
            '  case "$destination" in\n'
            '    */slow) mkdir -p -- "$destination"; exec sleep 30 ;;\n'
            '  esac\n'
            'fi\n'
            f'exec {shlex.quote(shutil.which("git"))} "$@"\n',
            encoding="utf-8")
        git_shim.chmod(0o755)
        env["PATH"] = str(git_shim.parent) + os.pathsep + env["PATH"]
        env["VIM9_PLUG_TEST_SLOW"] = "1"
    script = directory / f"{scenario}.vim"
    shutil.copyfile(ROOT / "test" / script.name, script)
    argv = [vim, "-Nu", "NONE", "-U", "NONE", "-i", "NONE", "-n", "-es",
            "-V1", "-S", str(script)]
    if cmd_shell:
        argv[1:1] = ["--cmd", r"set shell=cmd.exe shellcmdflag=/c shellquote= shellxquote=( shellredir=>%s\ 2>&1"]
    if scenario != "jobs":
        argv.extend(["-c", "cquit 99"])
    try:
        process = subprocess.run(
            argv, stdin=subprocess.DEVNULL, capture_output=True, env=env, timeout=120)
    except subprocess.TimeoutExpired as exc:
        raise SystemExit(f"{scenario} timed out\n{(exc.stderr or b'').decode(errors='replace')}")
    if process.returncode:
        details = (process.stdout + process.stderr).decode(errors="replace")
        raise SystemExit(f"{source.name} ({source.parent}) failed\n{details}")
    return (directory / "observed.txt").read_text(encoding="utf-8")


def compare_workflows(expected, actual, name):
    if expected == actual:
        return
    diff = "".join(difflib.unified_diff(
        expected.splitlines(keepends=True),
        actual.splitlines(keepends=True),
        fromfile="upstream", tofile=name))
    raise SystemExit(diff)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--vim", default="vim", help="Vim executable to test")
    args = parser.parse_args()
    with TemporaryDirectory(prefix="vim9-plug-test-") as temporary:
        directory = Path(temporary)
        # Upstream's PowerShell filter fails when previewing Git output.
        windows = os.name == "nt"
        expected = run(args.vim, UPSTREAM, directory / "legacy", cmd_shell=windows)
        actual = run(args.vim, PORT, directory / "port", cmd_shell=windows)
        compare_workflows(expected, actual, "port")
        if windows:
            actual = run(args.vim, PORT, directory / "default shell")
            compare_workflows(expected, actual, "port with the default Windows shell")
        run(args.vim, PORT, directory / "vim9 caller", "vim9")
        run(args.vim, PORT, directory / "self upgrade", "upgrade")
        jobs = run(args.vim, PORT, directory / "async jobs", "jobs")
    print("Vim9 compile, workflow parity, Vim9 caller, and self-upgrade passed.")
    print(jobs.strip())


if __name__ == "__main__":
    main()
