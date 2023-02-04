#!/usr/bin/python3

import argparse
import importlib.machinery
import logging
import logging
import pathlib
import sys

import yaml

log = logging.getLogger()

try:
    sibling = pathlib.Path(__file__).parent / "samba-from-source.py"
    _sfs = importlib.machinery.SourceFileLoader(
        "sfs", str(sibling)
    ).load_module()
except ImportError:
    raise RuntimeError("can not load samba-from-source.py file")


run = _sfs.run


def host_build_image(cli, engine):
    cmd = [engine, "build"]
    dnf_args = dnf_cache(cli)
    if cli.base_image:
        cmd.append(f"--build-arg=BASE_IMAGE={cli.base_image}")
    if dnf_args:
        cmd.append(f"--build-arg=CLEAN_DNF=no")
    tag = "dev"
    if cli.job:
        tag = f"dev-{cli.job}"
    cmd.append("-t")
    cmd.append(f"samba-from-source:{tag}")
    cmd.extend(dnf_args)
    cmd.append("-f")
    # TODO: auto-fix path
    cmd.append("images/fromsource/Containerfile")
    run(cmd)


def host_build_samba(cli, engine):
    tag = "dev"
    if cli.job:
        tag = f"dev-{cli.job}"
    img = f"samba-from-source:{tag}"
    cmd = [engine, "run", "--rm", "-it"]
    cmd.extend(dnf_cache(cli))
    if cli.source_dir:
        cmd.append("--volume")
        cmd.append(f"{cli.source_dir}:{cli.samba_source}")
    if cli.artifacts_dir:
        cmd.append("--volume")
        cmd.append(f"{cli.artifacts_dir}:{cli.workdir}")
    cmd.append("--userns=keep-id")
    if cli.shell:
        cmd.extend(["--entrypoint", "bash"])
    cmd.append(img)
    if not cli.shell:
        cmd.extend(Wrapper(cli).to_args())
    run(cmd)


def get_engine(cli):
    if cli.container_engine:
        return cli.container_engine
    # TODO: auto detect podman or docker
    return "podman"


def dnf_cache(cli):
    if not cli.dnf_cache:
        return []
    libdir = pathlib.Path(cli.dnf_cache) / "lib"
    cdir = pathlib.Path(cli.dnf_cache) / "cache"
    libdir.mkdir(parents=True, exist_ok=True)
    cdir.mkdir(parents=True, exist_ok=True)
    return [
        "--volume",
        f"{libdir}:/var/lib/dnf",
        "--volume",
        f"{cdir}:/var/cache/dnf",
    ]


def parse_cli():
    parser = argparse.ArgumentParser()
    _sfs.set_arguments(parser)
    parser.add_argument(
        "--container-engine",
        help="Specify container engine to use (typically docker, or podman)",
    )
    parser.add_argument(
        "--source-dir", "-s", help="Path to samba git checkout"
    )
    parser.add_argument(
        "--artifacts-dir",
        "-a",
        help="Where stuff gets written",
    )
    parser.add_argument(
        "--base-image",
        help="Base image (example: quay.io/centos/centos:stream9)",
    )
    parser.add_argument(
        "--task",
        "-t",
        action="append",
        choices=("image", "packages", "configure", "make"),
        help="What to build",
    )
    parser.add_argument(
        "--dnf-cache",
        help="Path to a directory for caching dnf state",
    )
    parser.add_argument(
        "--shell", action="store_true", help="Get a shell in the container"
    )
    parser.add_argument("--config", "-c", help="Provide a configuration file")
    cli = parser.parse_args()
    return cli


def _do_task(cli, task_name, is_default=True):
    if not cli.task and is_default:
        log.debug("default tasks enabled; running task %s", task_name)
        return True
    ok = task_name in list(cli.task)
    log.debug("%srunning task %s", "" if ok else "not ", task_name)
    return ok


class Configurator:
    def __init__(self, file=None, cli=None):
        self._cli = cli
        self._conf = None
        if file:
            with open(file) as fh:
                self._conf = yaml.safe_load(fh)
                log.debug("read config=%r", self._conf)

    def _get(self, name, altname=None):
        if self._cli:
            val = getattr(self._cli, name, None)
            if val:
                return val
        if self._conf:
            val = self._conf.get(name)
            if val is not None:
                return val
            if altname:
                val = self._conf.get(altname)
                if val is not None:
                    return val
        return None

    @property
    def base_image(self):
        return self._get("base_image")

    @property
    def container_engine(self):
        return self._get("container_engine")

    @property
    def source_dir(self):
        return self._get("source_dir")

    @property
    def artifacts_dir(self):
        return self._get("artifacts_dir")

    @property
    def dnf_cache(self):
        return self._get("dnf_cache")

    @property
    def task(self):
        return self._get("task", altname="tasks")

    @property
    def job(self):
        return self._get("job")

    @property
    def samba_source(self):
        return self._get("samba_source")

    @property
    def workdir(self):
        return self._get("workdir")

    tasks = task

    @property
    def shell(self):
        return self._cli and self._cli.shell

    def real_cli(self):
        return self._cli


class Wrapper:
    def __init__(self, cli):
        self._cli = cli
        self._rcli = None
        rcli = getattr(cli, "real_cli", None)
        if rcli:
            self._rcli = rcli()
        self._out = []

    def fetch(self, name):
        val = getattr(self._cli, name, Wrapper)
        if val is not Wrapper:
            return val
        if self._rcli:
            val = getattr(self._rcli, name, Wrapper)
            if val is not Wrapper:
                return val
        return None

    def add_argument(self, opt, *args, action=None, **kwargs):
        name = opt[2:].replace("-", "_")
        if action == "store_true":
            if self.fetch(name):
                self._out.append(opt)
            return
        val = self.fetch(name)
        if val:
            self._out.append(opt)
            self._out.append(val)

    def to_args(self):
        if not self._out:
            _sfs.set_arguments(self)
        return self._out


def main():
    cli = parse_cli()
    logging.basicConfig(
        level=logging.DEBUG,
        format="build.py: %(asctime)s: %(levelname)s: %(message)s",
    )
    cli = Configurator(cli.config, cli=cli)

    engine = get_engine(cli)
    if _do_task(cli, "image"):
        host_build_image(cli, engine)
    if _do_task(cli, "packages"):
        host_build_samba(cli, engine)
    sys.exit(0)


if __name__ == "__main__":
    main()
