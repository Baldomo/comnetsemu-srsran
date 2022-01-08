import atexit
import os
import shlex
import signal
import subprocess
import time

from comnetsemu.net import Containernet
from comnetsemu.node import DockerHost
from mininet import log
from mininet.cli import CLI
from mininet.link import TCIntf, TCLink
from mininet.node import Controller, OVSBridge
from mininet.topo import Topo

from util import dict_union

CORE_IPS: dict = {
    "epc": "10.80.95.10",
    "enb": "10.80.95.11",
}

# Fake network used for ZeroMQ data transfer
RF_IPS: dict = {"enb": "10.80.97.11", "ue": "10.80.97.12"}


class Simple4G:
    _net: Containernet = None
    _cmds: dict = {}

    def __init__(self) -> None:
        self._net = Containernet(
            controller=Controller, ipBase="10.0.0.0/8", link=TCLink, waitConnected=True
        )
        self._net.addController("c0")

        switch_core = self._net.addSwitch("s1")
        switch_rf = self._net.addSwitch("s2")

        default_args = {
            "volumes": [
                os.getcwd() + "/config:/etc/srsran:ro",
                os.getcwd() + "/logs:/tmp/srsran_logs",
                "/etc/timezone:/etc/timezone:ro",
                "/etc/localtime:/etc/localtime:ro",
            ]
        }

        _epc_cmd = [
            "srsepc",
            f"--mme.mme_bind_addr={CORE_IPS['epc']}",
            f"--spgw.gtpu_bind_addr={CORE_IPS['epc']}",
            "--log.all_level=info",
            "--log.filename=/tmp/srsran_logs/epc.log",
            ">",
            "/proc/1/fd/1",
            "2>&1",
            "&",
        ]
        epc = self._net.addDockerHost(
            "srsepc",
            dimage="srsran",
            docker_args=dict_union(
                default_args,
                {"devices": ["/dev/net/tun"], "cap_add": ["SYS_NICE", "NET_ADMIN"]},
            ),
        )
        self._cmds[epc] = " ".join(_epc_cmd)
        # Note: bw = bandwidth
        self._net.addLink(
            switch_core,
            epc,
            ip=CORE_IPS["epc"] + "/24",
            bw=1000,
            delay="1ms",
        )

        _enb_cmd = [
            "srsenb",
            f"--enb.mme_addr={CORE_IPS['epc']}",
            f"--enb.gtp_bind_addr={CORE_IPS['enb']}",
            f"--enb.s1c_bind_addr={CORE_IPS['enb']}",
            "--rf.device_name=zmq",
            f"--rf.device_args='id=enb,fail_on_disconnect=true,tx_port=tcp://*:2000,rx_port=tcp://{RF_IPS['ue']}:2001,base_srate=23.04e6'",
            "--enb_files.sib_config=/etc/srsran/sib.conf",
            "--log.all_level=info",
            "--log.filename=/tmp/srsran_logs/enb.log",
            ">",
            "/proc/1/fd/1",
            "2>&1",
            "&",
        ]
        enb = self._net.addDockerHost(
            "srsenb",
            dimage="srsran",
            docker_args=dict_union(
                default_args,
                {"cap_add": ["SYS_NICE"]},
            ),
        )
        self._cmds[enb] = " ".join(_enb_cmd)
        self._net.addLink(
            switch_core,
            enb,
            ip=CORE_IPS["enb"] + "/24",
            bw=1000,
            delay="1ms",
        )
        self._net.addLink(
            switch_rf, enb, ip=RF_IPS["enb"] + "/24", bw=1000, delay="1ms"
        )

        # TODO: GNU radio companion broker for multiple UEs
        # TODO: configure authentication/user from user_db.csv
        _ue_cmd = [
            "srsue",
            "--rf.device_name=zmq",
            f"--rf.device_args='id=ue,fail_on_disconnect=true,tx_port=tcp://*:2001,rx_port=tcp://{RF_IPS['enb']}:2000,base_srate=23.04e6'",
            "--log.all_level=info",
            "--log.filename=/tmp/srsran_logs/ue.log",
            ">",
            "/proc/1/fd/1",
            "2>&1",
            "&",
        ]
        ue = self._net.addDockerHost(
            "srsue",
            dimage="srsran",
            docker_args=dict_union(
                default_args,
                {"devices": ["/dev/net/tun"], "cap_add": ["SYS_NICE", "NET_ADMIN"]},
            ),
        )
        self._cmds[ue] = " ".join(_ue_cmd)
        self._net.addLink(
            switch_rf, ue, ip=RF_IPS["ue"] + "/24", bw=1000, delay="1ms"
        )

    def run(self) -> None:
        log.info("::: Starting 4G network stack")
        self._net.start()

        for host in self._cmds:
            log.debug(
                f"::: Running cmd in container ({host.name}): {self._cmds[host]}\n"
            )
            host.cmd(self._cmds[host])
            time.sleep(1)

        for host in self._net.hosts:
            proc = subprocess.Popen(
                [
                    "gnome-terminal",
                    f"--display={os.environ['DISPLAY']}",
                    "--disable-factory",
                    "--",
                    "docker",
                    "logs",
                    "-f",
                    host.name,
                ],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            log.debug(f"::: Spawning terminal with {proc.args}")

        log.info("::: Waiting for containers")
        time.sleep(4)
        self._net.pingAll()
        CLI(self._net)

    def cleanup(self) -> None:
        self._net.stop()


if __name__ == "__main__":
    # log.setLogLevel("debug")
    net = Simple4G()
    net.run()
    atexit.register(net.cleanup)
