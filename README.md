# comnetsemu + srsRAN
This project aims to integrate a source build of [srsRAN](https://github.com/srsran/srsRAN) in [comnetsemu](https://git.comnets.net/public-repo/comnetsemu/-/tree/master).
Radio packets are exchanged through ZeroMQ instead of a physical radio device (see [srsRAN documentation](https://docs.srsran.com/en/latest/app_notes/source/zeromq/source/index.html) for more information).

### Knowledge base
- `srsENB` supports only one UE per channel (each channel is a ZeroMQ rx/tx pair) as per [official documentation](https://docs.srsran.com/en/latest/app_notes/source/zeromq/source/index.html#known-issues). Since the rx/tx is implemented as a simple [REQ/REP pair](https://zguide.zeromq.org/docs/chapter1/#Ask-and-Ye-Shall-Receive), either:
  - a custom broker based on something like [zeromq/Malamute](https://github.com/zeromq/malamute) has to be used
  - the ZeroMQ implementation inside srsRAN must be refactored to support more complex patterns
- A single UE can use multiple channels for things like [5G NSA mode](https://docs.srsran.com/en/latest/app_notes/source/5g_nsa_zmq/source/index.html).
- Multiple cells can be emulated via [S1 handover](https://docs.srslte.com/en/latest/app_notes/source/handover/source/index.html).

### Development
This project uses a custom build script written in Bash (`make.sh`). The script serves as a replacement for Makefiles (it provides useful command line help and other functionalities) and is self-documenting.
For more information see:
```
$ ./make.sh --help
```

#### Updating `comnetsemu`
If a new version of `comnetsemu` is available, just run
```
$ ./make.sh git_submodules
```

or (basically the same):
```
$ git submodule update --recursive --remote
```

#### Notes on local development (on the host)
> Note: running topology code on the host is kinda useless, so don't do it

To enable code completion in editors and general testing, a Python `virtualenv` is recommended. It can be automatically setup using `./make.sh virtualenv`.

### Project structure
The root directory contains the following files (generally):

| Filename           | Description                                                             |
| ------------------ | ----------------------------------------------------------------------- |
| `comnetsemu/`      | Git submodule linked to the comnetsemu repository                       |
| `comnetsemu-docs/` | HTML documentation compiled from comnetsemu                             |
| `config/`          | srsRAN configuration files. Used as a Docker volume inside the VM       |
| `docker`           | `docker-compose` versions of the network stacks and srsRAN build file   |
| `logs/`            | Will be mounted as a volume inside the srsRAN containers and store logs |
| `slides/`          | Slides and assets                                                       |
| `src/`             | Python scripts with network implementations                             |
| `utils/`           | Contains extra utility files and bash functions for `make.sh`           |
| `README.md`        | This file                                                               |
| `make.sh`          | Build script for this project                                           |
| `Vagrantfile`      | comnetsemu-compatible VM, extend from the original Vagrantfile          |

All other directories/files are either temporary or self-explanatory, e.g.:
- `build/`: contains build artifacts (archives, binaries, whatever's needed at runtime)
- `env/`: Python virtualenv (see section above)