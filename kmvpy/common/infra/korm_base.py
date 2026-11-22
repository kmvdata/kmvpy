import json
from datetime import date, datetime
from decimal import Decimal

from sqlalchemy import MetaData
from sqlalchemy.orm import as_declarative
from sqlalchemy.sql.sqltypes import BigInteger as SABigInteger

from kmvpy.common.infra.ksnowflake import KSnowflake

metadata = MetaData()

_MISSING = object()


@as_declarative(metadata=metadata)
class KOrmBase(object):
    """
    SQLAlchemy ORM 基类。

    说明：
    - 数据库会话/事务控制归属 infra/storage 层（见 `kmvpy.common.infra.korm_storage.KOrmStorage`）。
      该基类仅保留：db_name 标识、序列化/反序列化、kid 生成等与 Session 无关的能力。
    """

    __tablename__ = None

    # “内部使用但允许子类覆写”：使用单下划线（protected 约定）
    _snowflake = KSnowflake()

    def __init__(self, **kwargs):
        # 兼容 SQLAlchemy declarative 默认构造方式：允许 kwargs 直接赋值字段
        for k, v in kwargs.items():
            setattr(self, k, v)

    @classmethod
    def _is_bigint_type(cls, col_type) -> bool:
        # 兼容不同 dialect 的 BIGINT（mysql.BIGINT 等）
        if isinstance(col_type, SABigInteger):
            return True
        visit_name = getattr(col_type, "__visit_name__", "") or ""
        return visit_name.lower() == "bigint"

    @classmethod
    def _is_kid_like_name(cls, name: str) -> bool:
        # 仅对 kid / *_kid 做字符串化（id 按契约不会返回前端，无需处理）
        return name == "kid" or name.endswith("_kid")

    @classmethod
    def _should_stringify_kid_bigint(cls, column, value) -> bool:
        # bool 是 int 的子类，不能误判为需要字符串化
        if isinstance(value, bool) or not isinstance(value, int):
            return False
        col_type = getattr(column, "type", None)
        if col_type is None:
            return False
        col_name = getattr(column, "name", "")
        return cls._is_kid_like_name(col_name) and cls._is_bigint_type(col_type)

    @classmethod
    def _wrap_special_value(cls, value):
        if isinstance(value, datetime):
            return {"__type__": "datetime", "value": value.strftime("%Y-%m-%d %H:%M:%S")}
        if isinstance(value, date):
            return {"__type__": "date", "value": "{0.year:4d}-{0.month:02d}-{0.day:02d}".format(value)}
        if isinstance(value, Decimal):
            return {"__type__": "Decimal", "value": str(value)}
        return _MISSING

    @classmethod
    def _serialize_value(cls, value):
        wrapped = cls._wrap_special_value(value)
        if wrapped is not _MISSING:
            return wrapped
        if isinstance(value, dict):
            return {k: cls._serialize_value(v) for k, v in value.items()}
        if isinstance(value, list):
            return [cls._serialize_value(v) for v in value]
        if isinstance(value, tuple):
            return [cls._serialize_value(v) for v in value]
        return value

    @classmethod
    def _is_special_wrapper(cls, value) -> bool:
        return (
            isinstance(value, dict)
            and set(value.keys()) == {"__type__", "value"}
            and value.get("__type__") in {"datetime", "date", "Decimal"}
        )

    @classmethod
    def _deserialize_value(cls, value):
        if cls._is_special_wrapper(value):
            value_type = value["__type__"]
            if value_type == "datetime":
                return datetime.strptime(value["value"], "%Y-%m-%d %H:%M:%S")
            if value_type == "date":
                return datetime.strptime(value["value"], "%Y-%m-%d").date()
            if value_type == "Decimal":
                return Decimal(value["value"])
        if isinstance(value, dict):
            return {k: cls._deserialize_value(v) for k, v in value.items()}
        if isinstance(value, list):
            return [cls._deserialize_value(v) for v in value]
        return value

    def _build_serializable_dict(self, *, stringify_kid_bigint: bool = True):
        _rst_dict = {}
        for column in self.__table__.columns:
            key = column.name
            value = getattr(self, key)
            if stringify_kid_bigint and self._should_stringify_kid_bigint(column, value):
                _rst_dict[key] = str(value)
            else:
                _rst_dict[key] = self._serialize_value(value)
        return _rst_dict

    def to_serializable_dict(self):
        return self._build_serializable_dict()

    @classmethod
    def unserializable_from_dict(cls, obj_dict):
        col_by_name = {c.name: c for c in getattr(cls, "__table__", {}).columns} if hasattr(cls, "__table__") else {}
        _args = {}
        for key, value in obj_dict.items():
            decoded_value = cls._deserialize_value(value)
            col = col_by_name.get(key)
            if col is not None and isinstance(decoded_value, str) and cls._is_kid_like_name(key) and cls._is_bigint_type(col.type):
                try:
                    _args[key] = int(decoded_value)
                except Exception:
                    _args[key] = decoded_value
            else:
                _args[key] = decoded_value

        return cls(**_args)

    @classmethod
    def from_json(cls, json_str: str):
        if isinstance(json_str, (bytes, bytearray)):
            json_str = json_str.decode("utf-8")
        if not isinstance(json_str, str):
            raise TypeError(f"json_str must be str/bytes, got {type(json_str).__name__}")

        obj_dict = json.loads(json_str)
        if not isinstance(obj_dict, dict):
            raise TypeError(f"{cls.__name__}.from_json expects a JSON object payload")
        return cls.unserializable_from_dict(obj_dict)

    def to_json(self):
        return json.dumps(
            self._build_serializable_dict(stringify_kid_bigint=False),
            ensure_ascii=False,
            separators=(",", ":"),
        )

    @classmethod
    def gen_kid(cls) -> int:
        """
        定义方式：
        kid = Column(BigInteger, nullable=False, unique=True, comment='表全局唯一kid（雪花算法64位整数）')
        """
        return cls._snowflake.gen_kid()

    def del_kid_if_none(self):
        """
        兼容“没有 kid 字段/列”的 model。

        背景：某些场景（例如反序列化、kwargs 注入）可能会给实例挂上 `kid=None`，
        即使该 model 并未声明/映射 `kid` 列。为避免后续 merge/add 等流程携带无意义字段，
        这里在 **不触发属性懒加载** 的前提下，安全移除该实例属性。
        """
        # 优先走 __dict__：既快，也能避免 SQLAlchemy InstrumentedAttribute 的惰性加载/Detached 加载异常。
        d = getattr(self, "__dict__", None)
        if isinstance(d, dict):
            if d.get("kid", _MISSING) is None:
                d.pop("kid", None)
            return

        # 极端情况下对象没有 __dict__（例如使用了 __slots__），降级为 getattr/delattr 的安全尝试。
        try:
            kid = getattr(self, "kid", _MISSING)
        except Exception:
            return
        if kid is None:
            try:
                delattr(self, "kid")
            except Exception:
                # 不让兼容逻辑影响主流程
                pass

