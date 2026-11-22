"""
    所有模块全局变量
    全局变量必须是class，不能是简单类型
    重要!!业务系统引用kosmos时，必须确保全局唯一，所以如果业务系统依赖california，必须引用california的kosmos。
"""

from kmvpy.common.conf import BaseConfig


class Kosmos(object):
    sessions: dict = dict()
    config: BaseConfig

    def __init__(self):
        pass

    def __setattr__(self, name: str, value: object) -> None:
        if name == "domain":
            raise AttributeError(
                "Kosmos no longer accepts a domain attribute; keep storage references explicitly."
            )
        super().__setattr__(name, value)


global kosmos
# noinspection PyRedeclaration
kosmos = Kosmos()
