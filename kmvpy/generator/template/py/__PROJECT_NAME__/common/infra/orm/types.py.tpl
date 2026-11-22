# coding: utf-8
from decimal import Decimal

from sqlalchemy import Numeric, String
from sqlalchemy.types import TypeDecorator


class PortableDecimal(TypeDecorator):
    """
    跨数据库的精确小数类型。

    - MySQL / PostgreSQL 使用 NUMERIC/DECIMAL
    - SQLite 使用字符串存储，避免其隐式走二进制浮点
    - ORM 读写统一暴露 Decimal
    """

    impl = Numeric
    cache_ok = True

    def __init__(self, precision: int = 18, scale: int = 6) -> None:
        super().__init__()
        self.precision = precision
        self.scale = scale
        self._numeric_impl = Numeric(precision, scale, asdecimal=True)
        self._sqlite_impl = String(max(precision + 2, scale + 8))
        self._quantizer = Decimal("1").scaleb(-scale)

    def load_dialect_impl(self, dialect):
        if dialect.name == "sqlite":
            return dialect.type_descriptor(self._sqlite_impl)
        return dialect.type_descriptor(self._numeric_impl)

    def process_bind_param(self, value, dialect):
        if value is None:
            return None

        decimal_value = self._coerce_decimal(value).quantize(self._quantizer)
        if dialect.name == "sqlite":
            return format(decimal_value, "f")
        return decimal_value

    def process_result_value(self, value, dialect):
        if value is None:
            return None
        if isinstance(value, Decimal):
            return value.quantize(self._quantizer)
        return self._coerce_decimal(value).quantize(self._quantizer)

    @staticmethod
    def _coerce_decimal(value) -> Decimal:
        if isinstance(value, Decimal):
            return value
        return Decimal(str(value))
