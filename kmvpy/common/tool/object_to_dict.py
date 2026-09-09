import contextlib
import datetime

from datetime import datetime, date
from decimal import Decimal
from enum import Enum
from typing import Union, Optional
from pydantic import BaseModel
from sqlalchemy.sql.sqltypes import BigInteger as SABigInteger

# try:
#     from cassandra.cqlengine.models import Model
#     from cassandra.util import Date
# except ModuleNotFoundError as e:
#     print(e)

with contextlib.suppress(Exception):
    pass

default_ignores: set[str] = {
    'id',
    'password',
    'salt',
    'deleted_at',
    'session_cookie_value',
    'session_secret',
    'private_key',
}


def _is_bigint_type(col_type) -> bool:
    # 兼容不同 dialect 的 BIGINT（如 mysql.BIGINT(unsigned=True)）
    if isinstance(col_type, SABigInteger):
        return True
    visit_name = getattr(col_type, "__visit_name__", "") or ""
    return visit_name.lower() == "bigint"


def object2dict(obj: any, ignores: Optional[set[str]] = None) -> Union[dict, list, any]:
    if ignores is None:
        ignores = default_ignores

    if obj is None:
        return None

    # 处理 list / tuple
    if isinstance(obj, (list, tuple)):
        return [object2dict(item, ignores) for item in obj]

    # 处理 dict
    if isinstance(obj, dict):
        return {k: object2dict(v, ignores) for k, v in obj.items() if k not in ignores}

    # 处理 Pydantic DTO；尊重 Field(exclude=True) 等模型级脱敏配置。
    if isinstance(obj, BaseModel):
        return object2dict(obj.model_dump(), ignores)

    # 处理 SQLAlchemy ORM 对象
    if hasattr(obj, '__table__'):
        result = {}
        for col in obj.__table__.columns:
            if col.key in ignores:
                continue

            value = getattr(obj, col.key)
            if (
                _is_bigint_type(getattr(col, "type", None))
                and isinstance(value, int)
                and not isinstance(value, bool)
            ):
                result[col.key] = str(value)
            else:
                result[col.key] = object2dict(value, ignores)

        return result

    # 处理普通类实例
    if hasattr(obj, '__dict__'):
        return {
            key: object2dict(value, ignores)
            for key, value in obj.__dict__.items()
            if not key.startswith('_') and key not in ignores
        }

    # 特殊类型处理
    if isinstance(obj, datetime):
        return obj.strftime("%Y-%m-%d %H:%M:%S")
    elif isinstance(obj, date):
        return obj.strftime("%Y-%m-%d")
    elif isinstance(obj, Decimal):
        return str(obj)
    elif isinstance(obj, Enum):
        return obj.value

    return obj
