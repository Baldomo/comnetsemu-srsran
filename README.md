# comnetsemu + srsRAN
This project aims to integrate a source build of [srsRAN](https://github.com/srsran/srsRAN) in [comnetsemu](https://git.comnets.net/public-repo/comnetsemu/-/tree/master).
Radio packets are exchanged through ZeroMQ instead of a physical radio device (see [srsRAN documentation](https://docs.srsran.com/en/latest/app_notes/source/zeromq/source/index.html) for more information).

### Development
This project uses a custom build script written in Bash (`make.sh`). The script serves as a replacement for Makefiles (it provides useful command line help and other functionalities) and is self-documenting.
For more information see:
```
$ ./make.sh --help
```

#### Notes on local development (on the host)
> Note: running topology code on the host is kinda useless, so don't do it

To enable code completion in editors and general testing, a Python `virtualenv` is recommended. It can be automatically setup using `./make.sh virtualenv`.

### Project structure
The root directory contains the following files (generally):

| Filename           | Description                                                       |
| ------------------ | ----------------------------------------------------------------- |
| `comnetsemu/`      | Git submodule linked to the comnetsemu repository                 |
| `comnetsemu-docs/` | HTML documentation compiled from comnetsemu                       |
| `config/`          | srsRAN configuration files. Used as a Docker volume inside the VM |
| `utils/`           | Contains extra utility files and bash functions for `make.sh`     |
| `*.py`             | Python scripts with network implementations or srsRAN             |
| `Dockerfile`       | srsRAN builder as Docker image                                    |
| `README.md`        | This file                                                         |
| `make.sh`          | Build script for this project                                     |
| `Vagrantfile`      | comnetsemu-compatible VM, extend from the original Vagrantfile    |

All other directories/files are either temporary or self-explanatory, e.g.:
- `build/`: contains build artifacts (archives, binaries, whatever's needed at runtime)
- `env/`: Python virtualenv (see section above)