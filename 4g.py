import os
from itertools import chain

from mininet.link import TCLink
from mininet.node import Controller, OVSBridge
from mininet.topo import Topo

from comnetsemu.net import Containernet
from comnetsemu.node import DockerHost


def dict_union(*args):
    return dict(chain.from_iterable(d.items() for d in args))


def build_net():
    net = Containernet(controller=Controller, link=TCLink)
    net.addController("c0")

    switch = net.addSwitch("s0")

    default_args = {
        "volumes": [
            os.getcwd() + "/config:/etc/srsran:ro",
            "/etc/timezone:/etc/timezone:ro",
            "/etc/localtime:/etc/localtime:ro"
        ]
    }

    epc = net.addDockerHost(
        "srsepc",
        dimage="srsran",
        docker_args=dict_union(default_args, {
            "command": [
                "srsepc"
            ],
            "devices": [ "/dev/net/tun" ],
        })
    )
    # Note: bw = bandwidth
    net.addLink(switch, epc, bw=10, delay="10ms")

    # TODO: generate ZeroMQ rules for multiple UEs
    enb = net.addDockerHost(
        "srsenb",
        dimage="srsran",
        docker_args=dict_union(default_args, {
            "command": [
                "srsenb",
                "--rf.device_name=zmq",
                '--rf.device_args="id=enb,fail_on_disconnect=true,tx_port=tcp://*:2000,rx_port=tcp://localhost:2001,base_srate=23.04e6"'
            ],
        })
    )
    net.addLink(switch, enb, bw=10, delay="10ms")

    # TODO: keep a cache of UE IPs + UE IDs for multiple UEs
    ue = net.addDockerHost(
        "srsue",
        dimage="srsran",
        docker_args=dict_union(default_args, {
            "command": [
                "srsue",
                "--rf.device_name=zmq",
                '--rf.device_args="id=ue,fail_on_disconnect=true,tx_port=tcp://*:2001,rx_port=tcp://srsenb:2000,base_srate=23.04e6"'
            ],
            "devices": [ "/dev/net/tun" ],
        })
    )
    net.addLink(switch, ue, bw=10, delay="10ms")

    net.start()
    net.pingAll()
    net.stop()

if __name__ == "__main__":
    build_net()
