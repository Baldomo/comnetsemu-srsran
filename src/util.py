from itertools import chain
from _collections_abc import MutableMapping


def dict_union(*args) -> dict:
    return dict(chain.from_iterable(d.items() for d in args))
