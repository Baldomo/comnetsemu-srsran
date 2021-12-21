# comnetsemu + srsRAN
This project aims to integrate a custom build of [srsRAN/srsLTE](https://github.com/srsran/srsRAN) in [comnetsemu](https://git.comnets.net/public-repo/comnetsemu/-/tree/master).
The fork was chosen because it supports radio data exchange via shared memory and Docker's IPC network, but comnetsemu's network emulation is also supported and working.

This project is also loosely based on [pgorczak/srslte-docker-emulated](https://github.com/pgorczak/srslte-docker-emulated)

### Developing locally (on the host)
> Note: running topology code on the host is kinda useless, so don't do it

To enable code completion in editors and general testing, a Python `virtualenv` is recommended. It can be automatically setup using `make.sh virtualenv`.