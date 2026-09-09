import pytest

from kmvpy.common.kmv import Kosmos, kosmos


def test_domain_attribute_is_not_available() -> None:
    removed_name = "domain"

    with pytest.raises(AttributeError):
        getattr(kosmos, removed_name)
    with pytest.raises(AttributeError):
        setattr(kosmos, removed_name, object())


def test_config_and_socketio_remain_dynamic_attributes() -> None:
    runtime = Kosmos()
    config = object()
    socketio = object()

    assert getattr(runtime, "config", None) is None
    assert getattr(runtime, "socketio", None) is None

    runtime.config = config
    runtime.socketio = socketio
    assert runtime.config is config
    assert runtime.socketio is socketio
    assert vars(runtime) == {"config": config, "socketio": socketio}

    delattr(runtime, "config")
    assert getattr(runtime, "config", None) is None
