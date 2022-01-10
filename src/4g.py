import atexit
import os
import shlex
import signal
import subprocess
import time
from typing import Dict, List

from comnetsemu.net import Containernet
from comnetsemu.node import DockerHost
from mininet import log
from mininet.cli import CLI
from mininet.link import TCIntf, TCLink
from mininet.node import Controller, OVSBridge
from mininet.topo import Topo

from util import dict_union, get_root_dir

IPS: Dict[str, str] = {
    "epc": "10.80.95.10",
    "enb": "10.80.95.11",
    "ue": "10.80.97.12",
}

net: Containernet = Containernet(
    controller=Controller, ipBase="10.0.0.0/8", link=TCLink, waitConnected=True
)
cmds: Dict[DockerHost, str] = {}
hardcoded_ips: List[Dict[str, str]] = []


def run() -> None:
    net.addController("c0")

    switch = net.addSwitch("s1")

    default_args = {
        "volumes": [
            get_root_dir() + "/config:/etc/srsran:ro",
            get_root_dir() + "/logs:/tmp/srsran_logs",
            "/etc/timezone:/etc/timezone:ro",
            "/etc/localtime:/etc/localtime:ro",
        ]
    }

    _epc_cmd = [
        "srsepc",
        f"--mme.mme_bind_addr={IPS['epc']}",
        f"--spgw.gtpu_bind_addr={IPS['epc']}",
        "--log.all_level=info",
        "--log.filename=/tmp/srsran_logs/epc.log",
        ">",
        "/proc/1/fd/1",
        "2>&1",
        "&",
    ]
    epc = net.addDockerHost(
        "srsepc",
        ip=IPS["epc"],
        dimage="srsran",
        docker_args=dict_union(
            default_args,
            {"devices": ["/dev/net/tun"], "cap_add": ["SYS_NICE", "NET_ADMIN"]},
        ),
    )
    # Command lines are stored for later, to be run after self.net.start()
    cmds[epc] = " ".join(_epc_cmd)
    net.addLink(
        switch,
        epc,
        # Note: bw = bandwidth
        bw=1000,
        delay="1ms",
    )

    _enb_cmd = [
        "srsenb",
        f"--enb.mme_addr={IPS['epc']}",
        f"--enb.gtp_bind_addr={IPS['enb']}",
        f"--enb.s1c_bind_addr={IPS['enb']}",
        "--rf.device_name=zmq",
        f"--rf.device_args='id=enb,fail_on_disconnect=true,tx_port=tcp://*:2000,rx_port=tcp://{IPS['ue']}:2001,base_srate=23.04e6'",
        "--enb_files.sib_config=/etc/srsran/sib.conf",
        "--log.all_level=info",
        "--log.filename=/tmp/srsran_logs/enb.log",
        ">",
        "/proc/1/fd/1",
        "2>&1",
        "&",
    ]
    enb = net.addDockerHost(
        "srsenb",
        ip=IPS["enb"],
        dimage="srsran",
        docker_args=dict_union(
            default_args,
            {"cap_add": ["SYS_NICE"]},
        ),
    )
    cmds[enb] = " ".join(_enb_cmd)
    net.addLink(switch, enb, bw=1000, delay="1ms")

    # TODO: GNU radio companion broker for multiple UEs
    # TODO: configure authentication/user from user_db.csv
    _ue_cmd = [
        "srsue",
        "--rf.device_name=zmq",
        f"--rf.device_args='id=ue,fail_on_disconnect=true,tx_port=tcp://*:2001,rx_port=tcp://{IPS['enb']}:2000,base_srate=23.04e6'",
        "--log.all_level=info",
        "--log.filename=/tmp/srsran_logs/ue.log",
        ">",
        "/proc/1/fd/1",
        "2>&1",
        "&",
    ]
    ue = net.addDockerHost(
        "srsue",
        ip=IPS["ue"],
        dimage="srsran",
        docker_args=dict_union(
            default_args,
            {"devices": ["/dev/net/tun"], "cap_add": ["SYS_NICE", "NET_ADMIN"]},
        ),
    )
    cmds[ue] = " ".join(_ue_cmd)
    net.addLink(switch, ue, bw=1000, delay="1ms")

    log.output("::: Starting 4G network stack\n")
    net.start()
    for host in cmds:
        log.debug(f"::: Running cmd in container ({host.name}): {cmds[host]}\n")
        host.cmd(cmds[host])
        time.sleep(1)

    log.output("::: Waiting for containers\n")
    time.sleep(3)
    for host in net.hosts:
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

    net.pingAll()
    CLI(net)


if __name__ == "__main__":
    # log.setLogLevel("debug")
    run()
    atexit.register(net.stop)
