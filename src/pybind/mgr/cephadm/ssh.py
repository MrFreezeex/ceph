import logging
import os
import asyncio
from tempfile import NamedTemporaryFile
from threading import Thread
from contextlib import contextmanager
from io import StringIO
from shlex import quote
from typing import TYPE_CHECKING, Optional, List, Tuple, Dict, Any, Iterator
from orchestrator import OrchestratorError

try:
    import asyncssh
except ImportError:
    asyncssh = None

if TYPE_CHECKING:
    from cephadm.module import CephadmOrchestrator
    from asyncssh.connection import SSHClientConnection

logger = logging.getLogger(__name__)

asyncssh_logger = logging.getLogger('asyncssh')
asyncssh_logger.propagate = False

DEFAULT_SSH_CONFIG = """
Host *
  User root
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
  ConnectTimeout=30
"""


class EventLoopThread(Thread):

    def __init__(self) -> None:
        self._loop = asyncio.new_event_loop()
        asyncio.set_event_loop(self._loop)

        super().__init__(target=self._loop.run_forever)
        self.start()

    def get_result(self, coro) -> Any:  # type: ignore
        return asyncio.run_coroutine_threadsafe(coro, self._loop).result()


class SSHManager:

    def __init__(self, mgr: "CephadmOrchestrator"):
        self.mgr: "CephadmOrchestrator" = mgr
        self.cons: Dict[str, "SSHClientConnection"] = {}

    async def _remote_connection(self,
                                 host: str,
                                 addr: Optional[str] = None,
                                 ) -> "SSHClientConnection":
        if not self.cons.get(host):
            if not addr and host in self.mgr.inventory:
                addr = self.mgr.inventory.get_addr(host)

            if not addr:
                raise OrchestratorError("host address is empty")

            assert self.mgr.ssh_user
            n = self.mgr.ssh_user + '@' + addr
            logger.debug("Opening connection to {} with ssh options '{}'".format(
                n, self.mgr._ssh_options))

            asyncssh.set_log_level('DEBUG')
            asyncssh.set_debug_level(3)

            with self.redirect_log(host, addr):
                try:
                    conn = await asyncssh.connect(addr, username=self.mgr.ssh_user, client_keys=[self.mgr.tkey.name], known_hosts=None, config=[self.mgr.ssh_config_fname], preferred_auth=['publickey'])
                except OSError:
                    raise
                except asyncssh.Error:
                    raise
                except Exception:
                    raise
            self.cons[host] = conn

        self.mgr.offline_hosts_remove(host)
        conn = self.cons.get(host)
        return conn

    @contextmanager
    def redirect_log(self, host: str, addr: str) -> Iterator[None]:
        log_string = StringIO()
        ch = logging.StreamHandler(log_string)
        ch.setLevel(logging.DEBUG)
        asyncssh_logger.addHandler(ch)

        try:
            yield
        except OSError as e:
            self.mgr.offline_hosts.add(host)
            log_content = log_string.getvalue()
            msg = f"Can't communicate with remote host `{addr}`, possibly because python3 is not installed there. {str(e)}" + \
                '\n' + f'Log: {log_content}'
            logger.exception(msg)
            raise OrchestratorError(msg)
        except asyncssh.Error as e:
            self.mgr.offline_hosts.add(host)
            log_content = log_string.getvalue()
            msg = f'Failed to connect to {host} ({addr}). {str(e)}' + '\n' + f'Log: {log_content}'
            logger.debug(msg)
            raise OrchestratorError(msg)
        except Exception as e:
            self.mgr.offline_hosts.add(host)
            log_content = log_string.getvalue()
            logger.exception(str(e))
            raise OrchestratorError(
                f'Failed to connect to {host} ({addr}): {repr(e)}' + '\n' f'Log: {log_content}')
        finally:
            log_string.flush()
            asyncssh_logger.removeHandler(ch)

    def remote_connection(self,
                          host: str,
                          addr: Optional[str] = None,
                          ) -> "SSHClientConnection":
        return self.mgr.event_loop.get_result(self._remote_connection(host, addr))

    async def _execute_command(self,
                               host: str,
                               cmd: List[str],
                               stdin: Optional[str] = None,
                               addr: Optional[str] = None,
                               ) -> Tuple[str, str, int]:
        conn = await self._remote_connection(host, addr)
        cmd = "sudo " + " ".join(quote(x) for x in cmd)
        logger.debug(f'Running command: {cmd}')
        try:
            r = await conn.run(cmd, input=stdin)
        # handle these Exceptions otherwise you might get a weird error like TypeError: __init__() missing 1 required positional argument: 'reason' (due to the asyncssh error interacting with raise_if_exception)
        except (asyncssh.ChannelOpenError, Exception) as e:
            # SSH connection closed or broken, will create new connection next call
            logger.debug(f'Connection to {host} failed. {str(e)}')
            await self._reset_con(host)
            self.mgr.offline_hosts.add(host)
            raise OrchestratorError(f'Unable to reach remote host {host}. {str(e)}')
        out = r.stdout.rstrip('\n')
        err = r.stderr.rstrip('\n')
        return out, err, r.returncode

    def execute_command(self,
                        host: str,
                        cmd: List[str],
                        stdin: Optional[str] = None,
                        addr: Optional[str] = None,
                        ) -> Tuple[str, str, int]:
        return self.mgr.event_loop.get_result(self._execute_command(host, cmd, stdin, addr))

    async def _check_execute_command(self,
                                     host: str,
                                     cmd: List[str],
                                     stdin: Optional[str] = None,
                                     addr: Optional[str] = None,
                                     ) -> str:
        out, err, code = await self._execute_command(host, cmd, stdin, addr)
        if code != 0:
            msg = f'Command {cmd} failed. {err}'
            logger.debug(msg)
            raise OrchestratorError(msg)
        return out

    def check_execute_command(self,
                              host: str,
                              cmd: List[str],
                              stdin: Optional[str] = None,
                              addr: Optional[str] = None,
                              ) -> str:
        return self.mgr.event_loop.get_result(self._check_execute_command(host, cmd, stdin, addr))

    async def _write_remote_file(self,
                                 host: str,
                                 path: str,
                                 content: bytes,
                                 mode: Optional[int] = None,
                                 uid: Optional[int] = None,
                                 gid: Optional[int] = None,
                                 addr: Optional[str] = None,
                                 ) -> None:
        try:
            dirname = os.path.dirname(path)
            await self._check_execute_command(host, ['mkdir', '-p', dirname], addr=addr)
            tmp_path = path + '.new'
            await self._check_execute_command(host, ['touch', tmp_path], addr=addr)
            if uid is not None and gid is not None and mode is not None:
                # shlex quote takes str or byte object, not int
                await self._check_execute_command(host, ['chown', '-R', str(uid) + ':' + str(gid), tmp_path], addr=addr)
                await self._check_execute_command(host, ['chmod', oct(mode)[2:], tmp_path], addr=addr)
            with NamedTemporaryFile(prefix='cephadm-write-remote-file-') as f:
                os.fchmod(f.fileno(), 0o600)
                f.write(content)
                f.flush()
                conn = await self._remote_connection(host, addr)
                await asyncssh.scp(f.name, (conn, tmp_path))
            await self._check_execute_command(host, ['mv', tmp_path, path], addr=addr)
        except Exception as e:
            msg = f"Unable to write {host}:{path}: {e}"
            logger.exception(msg)
            raise OrchestratorError(msg)

    def write_remote_file(self,
                          host: str,
                          path: str,
                          content: bytes,
                          mode: Optional[int] = None,
                          uid: Optional[int] = None,
                          gid: Optional[int] = None,
                          addr: Optional[str] = None,
                          ) -> None:
        self.mgr.event_loop.get_result(self._write_remote_file(
            host, path, content, mode, uid, gid, addr))

    async def _reset_con(self, host: str) -> None:
        conn = self.cons.get(host)
        if conn:
            logger.debug(f'_reset_con close {host}')
            conn.close()
            del self.cons[host]

    def reset_con(self, host: str) -> None:
        self.mgr.event_loop.get_result(self._reset_con(host))

    def _reset_cons(self) -> None:
        for host, conn in self.cons.items():
            logger.debug(f'_reset_cons close {host}')
            conn.close()
        self.cons = {}

    def _reconfig_ssh(self) -> None:
        temp_files = []  # type: list
        ssh_options = []  # type: List[str]

        # ssh_config
        self.mgr.ssh_config_fname = self.mgr.ssh_config_file
        ssh_config = self.mgr.get_store("ssh_config")
        if ssh_config is not None or self.mgr.ssh_config_fname is None:
            if not ssh_config:
                ssh_config = DEFAULT_SSH_CONFIG
            f = NamedTemporaryFile(prefix='cephadm-conf-')
            os.fchmod(f.fileno(), 0o600)
            f.write(ssh_config.encode('utf-8'))
            f.flush()  # make visible to other processes
            temp_files += [f]
            self.mgr.ssh_config_fname = f.name
        if self.mgr.ssh_config_fname:
            self.mgr.validate_ssh_config_fname(self.mgr.ssh_config_fname)
            ssh_options += ['-F', self.mgr.ssh_config_fname]
        self.mgr.ssh_config = ssh_config

        # identity
        ssh_key = self.mgr.get_store("ssh_identity_key")
        ssh_pub = self.mgr.get_store("ssh_identity_pub")
        self.mgr.ssh_pub = ssh_pub
        self.mgr.ssh_key = ssh_key
        if ssh_key and ssh_pub:
            self.mgr.tkey = NamedTemporaryFile(prefix='cephadm-identity-')
            self.mgr.tkey.write(ssh_key.encode('utf-8'))
            os.fchmod(self.mgr.tkey.fileno(), 0o600)
            self.mgr.tkey.flush()  # make visible to other processes
            tpub = open(self.mgr.tkey.name + '.pub', 'w')
            os.fchmod(tpub.fileno(), 0o600)
            tpub.write(ssh_pub)
            tpub.flush()  # make visible to other processes
            temp_files += [self.mgr.tkey, tpub]
            ssh_options += ['-i', self.mgr.tkey.name]

        self.mgr._temp_files = temp_files
        if ssh_options:
            self.mgr._ssh_options = ' '.join(ssh_options)
        else:
            self.mgr._ssh_options = None

        if self.mgr.mode == 'root':
            self.mgr.ssh_user = self.mgr.get_store('ssh_user', default='root')
        elif self.mgr.mode == 'cephadm-package':
            self.mgr.ssh_user = 'cephadm'

        self._reset_cons()
