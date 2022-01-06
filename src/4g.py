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
    "epc": "10.80.95.10/24",
    "enb": "10.80.95.11/24",
}

# Fake network used for ZeroMQ data transfer
RF_IPS: dict = {
    "enb": "10.80.97.11/24",
    "ue": "10.80.97.12/24"
}


class Simple4G:
    _daemon: bool = False
    _net: Containernet = None
    _hosts: list = []

    def __init__(self, daemon=False) -> None:
        self._daemon = daemon

        self._net = Containernet(
            controller=Controller, ipBase="10.0.0.0/8", link=TCLink
        )
        self._net.addController("c0")

        switch_core = self._net.addSwitch("s1", ip="10.80.95.0/24")
        switch_rf = self._net.addSwitch("s2", ip="10.80.97.0/24")

        default_args = {
            "volumes": [
                os.getcwd() + "/config:/etc/srsran:ro",
                "/etc/timezone:/etc/timezone:ro",
                "/etc/localtime:/etc/localtime:ro",
            ]
        }

        # FIXME: read() blocking everything
        _epc_cmd = [
            "srsepc",
            f"--mme.mme_bind_addr={CORE_IPS['epc']}",
            f"--spgw.gtpu_bind_addr={CORE_IPS['epc']}",
        ]
        epc = self._net.addDockerHost(
            "srsepc",
            dcmd=shlex.join(_epc_cmd),
            dimage="srsran",
            docker_args=dict_union(
                default_args,
                {
                    "devices": ["/dev/net/tun"],
                    "cap_add": ["SYS_NICE", "NET_ADMIN"]
                },
            ),
        )
        self._hosts.append(epc)
        # Note: bw = bandwidth
        self._net.addLink(switch_core, epc, intf=TCIntf, ip=CORE_IPS["epc"], bw=1000, delay="1ms")

        _enb_cmd = [
            "srsenb",
            f"--enb.mme_addr={CORE_IPS['epc']}",
            f"--enb.gtp_bind_addr={CORE_IPS['enb']}",
            f"--enb.s1c_bind_addr={CORE_IPS['enb']}",
            "--rf.device_name=zmq",
            f"--rf.device_args='id=enb,fail_on_disconnect=true,tx_port=tcp://*:2000,rx_port=tcp://{RF_IPS['ue']}:2001,base_srate=23.04e6'",
            "--enb_files.sib_config=/etc/srsran/sib.conf",
        ]
        enb = self._net.addDockerHost(
            "srsenb",
            dcmd=shlex.join(_enb_cmd),
            dimage="srsran",
            docker_args=dict_union(
                default_args,
                {
                    "cap_add": ["SYS_NICE"]
                },
            ),
        )
        self._hosts.append(enb)
        self._net.addLink(switch_core, enb, intf=TCIntf, ip=CORE_IPS["enb"], bw=1000, delay="1ms")
        self._net.addLink(switch_rf, enb, intf=TCIntf, ip=RF_IPS["enb"], bw=1000, delay="1ms")

        # TODO: GNU radio companion broker for multiple UEs
        # TODO: configure authentication/user from user_db.csv
        _ue_cmd = [
            "srsue",
            "--rf.device_name=zmq",
            f"--rf.device_args='id=ue,fail_on_disconnect=true,tx_port=tcp://*:2001,rx_port=tcp://{RF_IPS['enb']}:2000,base_srate=23.04e6'",
        ]
        ue = self._net.addDockerHost(
            "srsue",
            dcmd=shlex.join(_ue_cmd),
            dimage="srsran",
            docker_args=dict_union(
                default_args,
                {
                    "devices": ["/dev/net/tun"],
                    "cap_add": ["SYS_NICE", "NET_ADMIN"]
                },
            ),
        )
        self._hosts.append(ue)
        self._net.addLink(switch_rf, ue, intf=TCIntf, ip=RF_IPS["ue"], bw=1000, delay="1ms")

    def run(self) -> None:
        log.info("::: Starting 4G network stack")
        self._net.start()
        for host in self._net.hosts:
            subprocess.Popen(
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
        log.info("::: Waiting for containers")
        time.sleep(4)
        self._net.pingAll()
        if not self._daemon:
            CLI(self._net)

    def cleanup(self) -> None:
        self._net.stop()


if __name__ == "__main__":
    log.setLogLevel("debug")
    net = Simple4G(daemon=False)
    net.run()
    atexit.register(net.cleanup)
    # signal.signal(signal.SIGINT, net.cleanup)
    # signal.signal(signal.SIGTERM, net.cleanup)
    # signal.signal(signal.SIGKILL, net.cleanup)
    # signal.pause()
