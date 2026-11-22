from __future__ import annotations

from enum import Enum


class StrValueEnum(str, Enum):
    """字符串枚举基类，便于统一做值校验。"""

    @classmethod
    def values(cls) -> tuple[str, ...]:
        return tuple(item.value for item in cls)

    @classmethod
    def has_value(cls, value: str | None) -> bool:
        return value in cls._value2member_map_