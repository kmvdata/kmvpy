import inspect
import json
import logging
import os
import sys
import time
from functools import wraps
from typing import Annotated, Any, Callable, Iterable, Mapping, Optional
import tarfile
from datetime import datetime
from logging.handlers import RotatingFileHandler
import threading
import queue
import re

# 设置core日志
logger = logging.getLogger(__package__)
# logger.setLevel(logging.INFO)

_KMVPY_LOGGER_DEBUG: bool = False

_ARCHIVE_WORKER_LOCK = threading.Lock()
_ARCHIVE_QUEUE: "queue.Queue[str | None] | None" = None
_ARCHIVE_THREAD: "threading.Thread | None" = None


def _stop_archive_worker() -> None:
    """
    停止上一轮 init_logger() 启动的归档线程（若存在）。
    只做资源回收/避免重复线程，不改变对外日志功能。
    """
    global _ARCHIVE_QUEUE, _ARCHIVE_THREAD
    with _ARCHIVE_WORKER_LOCK:
        if _ARCHIVE_QUEUE is not None:
            try:
                _ARCHIVE_QUEUE.put_nowait(None)
            except Exception:
                # 不影响主流程；最多是旧线程多存活一会儿
                pass
        _ARCHIVE_QUEUE = None
        _ARCHIVE_THREAD = None


def _get_main_caller_package_name():
    """
    获取主调用项目的包名
    通过遍历调用栈查找不在当前包内的第一个调用者，获取主调用项目的顶级包名
    """
    frame = inspect.currentframe().f_back
    while frame:
        module_name = frame.f_globals.get('__name__', '')
        # 检查是否属于 kmvpy 包内部
        if not module_name.startswith('kmvpy.'):
            # 找到非 kmvpy 包的调用者，提取其顶级包名
            parts = module_name.split('.')
            if parts and parts[0]:  # 确保有有效的包名
                return parts[0]
        frame = frame.f_back
    return None


def _parse_size(size_str):
    """
    解析大小字符串，如 "10M", "100MB", "1G" 等，返回对应的字节数
    """
    min_bytes = 1024 ** 2  # 1MB
    if isinstance(size_str, (int, float)):
        return max(int(size_str), min_bytes)
    
    size_str = size_str.strip().upper()
    
    # 使用正则表达式匹配数字和单位
    match = re.match(r'^(\d+\.?\d*)\s*(B|KB|MB|GB|TB)?$', size_str)
    if not match:
        raise ValueError(f"Invalid size format: {size_str}")
    
    number, unit = match.groups()
    number = float(number)
    
    # 定义单位转换
    units = {
        'B': 1,
        'KB': 1024,
        'MB': 1024 ** 2,
        'GB': 1024 ** 3,
        'TB': 1024 ** 4
    }
    
    multiplier = units.get(unit or 'B', 1)
    return max(int(number * multiplier), min_bytes)


def _seconds_since_midnight(now: datetime) -> int:
    """当日秒数：距离当天 00:00:00 的秒数（0~86399）。"""
    return now.hour * 3600 + now.minute * 60 + now.second


class TraceableSizeRotatingFileHandler(RotatingFileHandler):
    """
    自定义按大小轮转 Handler：
    - 不使用 RotatingFileHandler 默认的 .1/.2 链
    - 轮转时把 baseFilename 原子改名为 {base}_{YYYYMMDD}.{当日秒数}[.{k}].log
    """

    def __init__(
        self,
        filename: str,
        maxBytes: int,
        encoding: str,
        make_rotated_log_path,
        on_rotated,
        filename_lock: threading.Lock,
    ) -> None:
        # backupCount 置 0，避免父类逻辑依赖 .1/.2 链（我们完全重写 doRollover）
        super().__init__(filename, maxBytes=maxBytes, backupCount=0, encoding=encoding)
        self._make_rotated_log_path = make_rotated_log_path
        self._on_rotated = on_rotated
        self._filename_lock = filename_lock

    def doRollover(self) -> None:
        rotated_path: str | None = None

        try:
            if self.stream:
                self.stream.close()
                self.stream = None

            with self._filename_lock:
                rotated_path = self._make_rotated_log_path()
                # base 文件不存在时无需 rename（可能是首次写入或被外部清理）
                if os.path.exists(self.baseFilename):
                    os.replace(self.baseFilename, rotated_path)
        except Exception:
            logger.exception("Failed to rollover log file: %s", self.baseFilename)
        finally:
            # 重新打开活动日志文件，继续写入
            if not self.delay:
                try:
                    self.stream = self._open()
                except Exception:
                    logger.exception("Failed to reopen log file after rollover: %s", self.baseFilename)

        if rotated_path and os.path.exists(rotated_path):
            try:
                self._on_rotated(rotated_path)
            except Exception:
                logger.exception("Failed to enqueue rotated log for archiving: %s", rotated_path)


def init_logger(debug: Annotated[bool, 'debug模式'],
                level: Annotated[int, '日志级别'] = logging.INFO,
                logger_path: Annotated[str| None, '日志文件路径'] = None,
                _format: Annotated[str | None, '日志格式'] = None,
                max_bytes: Annotated[str | None, '最大文件大小'] = None,
                backup_count: Annotated[int | None, '保留备份文件数量'] = None) -> None:
    global _KMVPY_LOGGER_DEBUG
    _KMVPY_LOGGER_DEBUG = bool(debug)

    # 避免重复初始化导致的 handler/线程资源泄漏
    _stop_archive_worker()

    # 创建一个logger
    logger.setLevel(level)

    # @20201108增加打印进程ID和线程ID
    # formatter = logging.Formatter('%(asctime)s - %(levelname)s - 进程%(process)d:线程%(thread)d - %(filename)s:%(funcName)s:%(lineno)d: %(message)s')
    # 尝试不打印文件名
    # formatter = logging.Formatter('%(asctime)s - %(levelname)s - 进程%(process)d:线程%(thread)d - %(module)s:%(funcName)s:%(lineno)d: %(message)s')
    # 尝试隐藏更多信息
    # formatter = logging.Formatter('%(asctime)s - %(levelname)s - 进程%(process)d:线程%(thread)d - %(message)s')
    if _format is None:
        _format = '%(asctime)s - %(levelname)s - 进程%(process)d:线程%(thread)d - %(filename)s:%(funcName)s:%(lineno)d: %(message)s'
    if max_bytes is None:
        max_bytes = '100M'

    formatter = logging.Formatter(fmt=_format)

    # 清除之前的 handlers（并显式 close，避免文件句柄泄漏）
    for h in list(logger.handlers):
        try:
            logger.removeHandler(h)
        finally:
            try:
                h.close()
            except Exception:
                # 不影响主流程：close 失败不应阻塞日志初始化
                pass

    # Debug模式不输出日志文件
    if debug:
        console_handler = logging.StreamHandler(sys.stdout)
        console_handler.setFormatter(formatter)
        logger.addHandler(console_handler)
    else:
        # 获取主调用项目的包名作为app_name
        app_name = _get_main_caller_package_name()
        if not app_name:  # 如果无法获取主调用项目包名，则使用默认值
            app_name = "kmvpy_app"
        
        # 根据logger_path是否以.log结尾来决定如何处理路径
        if not logger_path or len(logger_path) == 0:
            # 如果logger_path为None或者为空字符串，使用当前目录
            logger_path = os.path.join(os.getcwd(), f"{app_name}.log")
        elif not logger_path.endswith('.log'):
            # 如果logger_path不是以.log结尾，将其视为目录路径
            logger_path = os.path.join(logger_path, f"{app_name}.log")
        # 否则直接使用logger_path作为最终路径9

        # 确保日志文件所在的目录存在
        os.makedirs(os.path.dirname(logger_path), exist_ok=True)

        # 解析max_bytes参数
        parsed_max_bytes = _parse_size(max_bytes)

        log_dir = os.path.dirname(logger_path)
        orig_basename = os.path.basename(logger_path)  # e.g. neptune.log
        filename_lock = threading.Lock()

        def _next_rotated_log_path() -> str:
            """
            生成不冲突的中间轮转文件路径（可追溯）：
            {原文件名}_{YYYYMMDD}.{当日秒数}[.{k}].log
            同时避免与已存在的 .tar.gz 冲突。
            """
            now = datetime.now()
            date_str = now.strftime("%Y%m%d")
            sod = _seconds_since_midnight(now)
            base_prefix = f"{orig_basename}_{date_str}.{sod:05d}"

            def ok(prefix: str) -> bool:
                return (
                    not os.path.exists(os.path.join(log_dir, prefix + ".log"))
                    and not os.path.exists(os.path.join(log_dir, prefix + ".tar.gz"))
                )

            if ok(base_prefix):
                return os.path.join(log_dir, base_prefix + ".log")
            k = 1
            while True:
                candidate_prefix = f"{base_prefix}.{k}"
                if ok(candidate_prefix):
                    return os.path.join(log_dir, candidate_prefix + ".log")
                k += 1

        def _cleanup_old_archives() -> None:
            """按 backup_count 仅保留最多 N 个归档，超出删最旧（按 mtime）。"""
            if not backup_count or backup_count <= 0:
                return
            # 注意：orig_basename 可能含 '.'，需要 escape
            # 允许带同秒冲突后缀：...{sod}.tar.gz 或 ...{sod}.{k}.tar.gz
            pattern = re.compile(rf"^{re.escape(orig_basename)}_\d{{8}}\.\d{{5}}(\.\d+)?\.tar\.gz$")
            items: list[tuple[float, str]] = []
            try:
                for name in os.listdir(log_dir):
                    if not pattern.match(name):
                        continue
                    path = os.path.join(log_dir, name)
                    try:
                        st = os.stat(path)
                        items.append((st.st_mtime, path))
                    except FileNotFoundError:
                        continue
            except Exception:
                logger.exception("Failed to list archive files in %s", log_dir)
                return
            
            # 从旧到新排序，超出删除最旧
            items.sort(key=lambda x: x[0])
            while len(items) > backup_count:
                _, path_to_remove = items.pop(0)
                try:
                    os.remove(path_to_remove)
                except FileNotFoundError:
                    continue
                except Exception:
                    logger.exception("Failed to remove old archive: %s", path_to_remove)
        
        def archive_worker():
            """归档工作线程：将轮转备份日志打包为 .tar.gz"""
            while True:
                try:
                    item = archive_queue.get(timeout=1)
                    if item is None:  # 结束信号
                        archive_queue.task_done()
                        break

                    rotated_log_path = item
                    if not os.path.exists(rotated_log_path):
                        archive_queue.task_done()
                        continue

                    try:
                        # 归档文件名：与中间文件同名前缀（.log -> .tar.gz）
                        if rotated_log_path.endswith(".log"):
                            archive_path = rotated_log_path[:-len(".log")] + ".tar.gz"
                        else:
                            archive_path = rotated_log_path + ".tar.gz"

                        # tar 内部成员文件名：与中间文件名一致
                        member_name = os.path.basename(rotated_log_path)

                        # 打包压缩为 tar.gz
                        with tarfile.open(archive_path, "w:gz") as tf:
                            tf.add(rotated_log_path, arcname=member_name)

                        # 归档成功后删除中间轮转文件，只保留活动日志 + 归档包
                        try:
                            os.remove(rotated_log_path)
                        except FileNotFoundError:
                            pass

                        # 执行归档保留策略
                        _cleanup_old_archives()
                    except Exception:
                        # 不影响主流程写日志；归档失败不删除中间文件，避免数据丢失
                        logger.exception("Failed to archive rotated log: %s", rotated_log_path)
                    finally:
                        archive_queue.task_done()
                except queue.Empty:
                    continue
        
        # 归档队列：仅入队“可追溯中间轮转文件”（*.log_YYYYMMDD.SSSSS[.k].log）
        archive_queue: "queue.Queue[str | None]" = queue.Queue()

        # 启动归档工作线程
        archive_thread = threading.Thread(target=archive_worker, daemon=True)
        archive_thread.start()
        # 记录当前工作线程，避免重复 init 导致多线程常驻
        global _ARCHIVE_QUEUE, _ARCHIVE_THREAD
        with _ARCHIVE_WORKER_LOCK:
            _ARCHIVE_QUEUE = archive_queue
            _ARCHIVE_THREAD = archive_thread

        def _enqueue_for_archiving(rotated_log_path: str) -> None:
            archive_queue.put(rotated_log_path)

        # 使用自定义轮转 Handler，避免 .1/.2 链
        file_handler = TraceableSizeRotatingFileHandler(
            logger_path,
            maxBytes=parsed_max_bytes,
            encoding="utf-8",
            make_rotated_log_path=_next_rotated_log_path,
            on_rotated=_enqueue_for_archiving,
            filename_lock=filename_lock,
        )
        file_handler.setFormatter(formatter)
        logger.addHandler(file_handler)

        def _enqueue_existing_traceable_logs_on_startup() -> None:
            """
            启动时将历史遗留的“可追溯中间文件”入队归档（例如上次归档失败/中断留下的 .log）。
            这不会产生 .log.1/.2 文件。
            """
            pattern = re.compile(rf"^{re.escape(orig_basename)}_\d{{8}}\.\d{{5}}(\.\d+)?\.log$")
            try:
                for name in os.listdir(log_dir):
                    if not pattern.match(name):
                        continue
                    archive_queue.put(os.path.join(log_dir, name))
            except Exception:
                logger.exception("Failed to scan traceable rotated logs in %s", log_dir)

        _enqueue_existing_traceable_logs_on_startup()


_DEFAULT_MASK_KEYS = frozenset(
    {
        "password",
        "passwd",
        "pwd",
        "secret",
        "secret_key",
        "private_key",
        "session_secret",
        "session_cookie_value",
        "token",
        "access_token",
        "refresh_token",
        "authorization",
        "api_key",
        "apikey",
        "sign",
        "signature",
        "cookie",
        "set-cookie",
    }
)

# 非 debug 模式下，对过大的容器不做递归展开，直接打印摘要，避免 O(n) 遍历
_NON_DEBUG_COLLECTION_MAX_ITEMS = 50


def _truncate_str(s: str, max_len: int) -> str:
    if max_len <= 0:
        return ""
    if len(s) <= max_len:
        return s
    return s[: max(0, max_len - 3)] + "..."


def _is_primitive(x: Any) -> bool:
    return x is None or isinstance(x, (bool, int, float, str))


def _mask_value(_: Any) -> str:
    return "***"


def _brief_type_and_size(obj: Any) -> str:
    """
    返回一个“轻量摘要”字符串：尽量只包含类型与大小信息，避免序列化大对象。

    设计目标：
    - O(1) 或近似 O(1) 的开销（不做深度遍历）
    - 不输出对象内容本身（避免日志暴涨/敏感信息泄露）
    """
    if obj is None:
        return "None"

    tname = type(obj).__name__

    # 常见可直接 len() 的结构
    if isinstance(obj, (str, bytes, bytearray, memoryview, list, tuple, set, frozenset, dict)):
        try:
            return f"{tname}(len={len(obj)})"  # type: ignore[arg-type]
        except Exception:
            return tname

    # numpy/pandas 等常见 shape
    try:
        shape = getattr(obj, "shape", None)
        if isinstance(shape, tuple):
            return f"{tname}(shape={shape})"
    except Exception:
        pass

    # 其他对象：尝试 len / getsizeof（均不做深度统计）
    try:
        return f"{tname}(len={len(obj)})"  # type: ignore[arg-type]
    except Exception:
        pass

    try:
        return f"{tname}(bytes={sys.getsizeof(obj)})"
    except Exception:
        return tname


def _compact_data_field_for_log(obj: Any) -> Any:
    """
    当返回值是 Mapping 且包含 data 字段时，将 data 替换为轻量摘要，
    以避免非 debug 模式打印大对象导致日志暴涨。
    """
    if not isinstance(obj, Mapping):
        return obj

    data_key: Any | None = None
    try:
        for k in obj.keys():
            if isinstance(k, str) and k.lower() == "data":
                data_key = k
                break
    except Exception:
        return obj

    if data_key is None:
        return obj

    try:
        data_val = obj[data_key]
    except Exception:
        return obj

    # 浅拷贝即可：避免深拷贝/深遍历
    try:
        out = dict(obj)
    except Exception:
        out = {}
        try:
            for k, v in obj.items():
                out[k] = v
        except Exception:
            return obj

    out[data_key] = _brief_type_and_size(data_val)
    return out


def _sanitize(
    obj: Any,
    *,
    max_depth: int,
    max_str_len: int,
    mask_keys_lc: frozenset[str],
    _depth: int = 0,
    debug: bool | None = None,
) -> Any:
    """
    将对象转成可安全打印的结构（尽量保持可读性）：
    - 支持 pydantic v2: model_dump()
    - 支持 dataclass / dict / list 等常见结构
    - 对敏感 key 脱敏
    - 对长字符串截断
    - 深度限制防止递归爆炸
    """
    if debug is None:
        debug = _KMVPY_LOGGER_DEBUG

    if _depth > max_depth:
        return "<max_depth>"

    if _is_primitive(obj):
        if isinstance(obj, str):
            return _truncate_str(obj, max_str_len)
        return obj

    # 非 debug：对超大容器直接摘要，避免递归展开带来的性能/日志体积问题
    if not debug:
        if isinstance(obj, Mapping):
            try:
                if len(obj) > _NON_DEBUG_COLLECTION_MAX_ITEMS:
                    return _brief_type_and_size(obj)
            except Exception:
                return _brief_type_and_size(obj)
        if isinstance(obj, (list, tuple, set, frozenset)):
            try:
                if len(obj) > _NON_DEBUG_COLLECTION_MAX_ITEMS:
                    return _brief_type_and_size(obj)
            except Exception:
                return _brief_type_and_size(obj)

    # kmvpy ApiResponse（及子类）
    try:
        from kmvpy.common.response import ApiResponse as KmvApiResponse  # type: ignore

        if isinstance(obj, KmvApiResponse):
            code = getattr(obj, "code", None)
            msg = getattr(obj, "msg", None)
            count = getattr(obj, "count", None)
            data = getattr(obj, "data", None)

            if not debug:
                # 非 debug：只打印 data 的“类型/大小摘要”，避免大对象序列化/解析开销
                return {
                    "code": code,
                    "msg": msg,
                    "count": count,
                    "data": _brief_type_and_size(data),
                }

            payload = {"code": code, "msg": msg, "count": count, "data": data}
            return _sanitize(
                payload,
                max_depth=max_depth,
                max_str_len=max_str_len,
                mask_keys_lc=mask_keys_lc,
                _depth=_depth + 1,
                debug=debug,
            )
    except Exception:
        # 不影响日志主流程
        pass

    # pydantic v2
    model_dump = getattr(obj, "model_dump", None)
    if callable(model_dump):
        if not debug:
            # 非 debug：避免 model_dump 触发深度序列化
            return _brief_type_and_size(obj)
        try:
            return _sanitize(
                model_dump(exclude_none=True),
                max_depth=max_depth,
                max_str_len=max_str_len,
                mask_keys_lc=mask_keys_lc,
                _depth=_depth + 1,
                debug=debug,
            )
        except Exception:
            return _truncate_str(repr(obj), max_str_len)

    # pydantic v1
    dict_fn = getattr(obj, "dict", None)
    if callable(dict_fn):
        if not debug:
            # 非 debug：避免 dict() 触发深度序列化
            return _brief_type_and_size(obj)
        try:
            return _sanitize(
                dict_fn(),
                max_depth=max_depth,
                max_str_len=max_str_len,
                mask_keys_lc=mask_keys_lc,
                _depth=_depth + 1,
                debug=debug,
            )
        except Exception:
            return _truncate_str(repr(obj), max_str_len)

    if isinstance(obj, Mapping):
        out: dict[str, Any] = {}
        for k, v in obj.items():
            ks = str(k)
            if ks.lower() in mask_keys_lc:
                out[ks] = _mask_value(v)
            else:
                out[ks] = _sanitize(
                    v,
                    max_depth=max_depth,
                    max_str_len=max_str_len,
                    mask_keys_lc=mask_keys_lc,
                    _depth=_depth + 1,
                    debug=debug,
                )
        return out

    if isinstance(obj, (list, tuple, set, frozenset)):
        return [
            _sanitize(
                x,
                max_depth=max_depth,
                max_str_len=max_str_len,
                mask_keys_lc=mask_keys_lc,
                _depth=_depth + 1,
                debug=debug,
            )
            for x in obj
        ]

    if isinstance(obj, (bytes, bytearray, memoryview)):
        try:
            ln = len(obj)  # type: ignore[arg-type]
        except Exception:
            ln = -1
        return f"<{type(obj).__name__} len={ln}>"

    if isinstance(obj, BaseException):
        return {"type": type(obj).__name__, "msg": _truncate_str(str(obj), max_str_len)}

    # Starlette/FastAPI Response：尽量打印 status + body（若已渲染）
    status_code = getattr(obj, "status_code", None)
    body = getattr(obj, "body", None)
    media_type = getattr(obj, "media_type", None)
    if status_code is not None and body is not None:
        try:
            if isinstance(body, (bytes, bytearray, memoryview)):
                body_text = bytes(body).decode("utf-8", errors="replace")
                body_text = _truncate_str(body_text, max_str_len)
                if isinstance(media_type, str) and "json" in media_type.lower():
                    try:
                        parsed = json.loads(body_text)
                        safe_body = _sanitize(
                            parsed,
                            max_depth=max_depth,
                            max_str_len=max_str_len,
                            mask_keys_lc=mask_keys_lc,
                            _depth=_depth + 1,
                            debug=debug,
                        )
                    except Exception:
                        safe_body = body_text
                else:
                    safe_body = body_text
            else:
                safe_body = _sanitize(
                    body,
                    max_depth=max_depth,
                    max_str_len=max_str_len,
                    mask_keys_lc=mask_keys_lc,
                    _depth=_depth + 1,
                    debug=debug,
                )
            return {"status_code": status_code, "media_type": media_type, "body": safe_body}
        except Exception:
            pass

    return _truncate_str(repr(obj), max_str_len)


def api_log(
    func: Callable[..., Any] | None = None,
    *,
    include_args: bool = True,
    include_kwargs: bool = True,
    include_result: bool = True,
    level: int = logging.INFO,
    debug: bool | None = None,
    mask_keys: Iterable[str] | None = None,
    max_depth: int = 6,
    max_str_len: int = 2000,
) -> Callable[..., Any]:
    """
    记录 API 函数的入参/出参日志（支持 `def` / `async def`）。

    用法：
    - `@api_log`：使用默认配置
    - `@api_log(level=logging.DEBUG, include_args=False, ...)`：自定义配置

    参数说明：
    - `include_args`：是否记录位置参数 `args`
    - `include_kwargs`：是否记录关键字参数 `kwargs`
    - `include_result`：是否记录返回值
    - `level`：日志级别（会先检查 `logger.isEnabledFor(level)`，避免无谓序列化开销）
    - `debug`：仅本次调用的 debug 覆盖开关（默认 `None`）
      - `None`：使用 `init_logger(debug=...)` 设置的全局 `_KMVPY_LOGGER_DEBUG`
      - `True/False`：本次调用强制使用该值（会覆盖全局设置；例如可用 `False` 临时关闭 `api_return` 返回值打印）
    - `mask_keys`：额外需要脱敏的字段名（大小写不敏感），与内置敏感 key 集合合并
    - `max_depth`：嵌套结构最大展开深度（防止递归爆炸）
    - `max_str_len`：字符串/文本最大长度，超出会截断

    打印策略（重点）：
    - `api_call`：入参始终尽量“完整打印”（仍会脱敏），不做非 debug 的大对象摘要/截断。
    - `api_return`：仅在 debug 模式下打印返回值（仍会脱敏）；非 debug 只打印 func 与耗时。
    """
    mask_keys_lc = frozenset({*(k.lower() for k in (mask_keys or ())), *_DEFAULT_MASK_KEYS})

    def decorator(f: Callable[..., Any]) -> Callable[..., Any]:
        func_name = getattr(f, "__qualname__", getattr(f, "__name__", "unknown"))

        if inspect.iscoroutinefunction(f):

            @wraps(f)
            async def async_wrapper(*args: Any, **kwargs: Any) -> Any:
                if logger.isEnabledFor(level):
                    # api_call：要求入参尽量完整打印（仍脱敏）。
                    # - 强制 debug=True：避免非 debug 的“超大容器摘要 / pydantic 摘要”等逻辑
                    # - 放大 max_depth/max_str_len：避免默认 4 层 / 2000 截断导致“不完整”
                    call_max_depth = max(max_depth, 50)
                    call_max_str_len = max(max_str_len, 2_147_483_647)
                    payload: dict[str, Any] = {"func": func_name}
                    if include_args:
                        payload["args"] = _sanitize(
                            args,
                            max_depth=call_max_depth,
                            max_str_len=call_max_str_len,
                            mask_keys_lc=mask_keys_lc,
                            debug=True,
                        )
                    if include_kwargs:
                        payload["kwargs"] = _sanitize(
                            kwargs,
                            max_depth=call_max_depth,
                            max_str_len=call_max_str_len,
                            mask_keys_lc=mask_keys_lc,
                            debug=True,
                        )
                    logger.log(level, "api_call %s", payload)

                start = time.perf_counter()
                try:
                    result = await f(*args, **kwargs)
                except Exception as e:
                    cost_ms = int((time.perf_counter() - start) * 1000)
                    # KmvException 属于可预期业务错误：不要打印 traceback（会极大污染日志）。
                    # 仍然保持抛出，让上层（如 FastAPI exception_handler）负责统一的业务响应。
                    try:
                        from kmvpy.common.exception.kmv_exception import KmvException  # type: ignore

                        if isinstance(e, KmvException):
                            logger.debug(
                                "api_business_error func=%s cost_ms=%s err=%s",
                                func_name,
                                cost_ms,
                                e,
                            )
                        else:
                            logger.exception(
                                "api_error func=%s cost_ms=%s err=%s", func_name, cost_ms, e
                            )
                    except Exception:
                        # 极端情况下（导入失败等）保持原行为，避免吞掉关键异常信息
                        logger.exception(
                            "api_error func=%s cost_ms=%s err=%s", func_name, cost_ms, e
                        )
                    raise

                if include_result and logger.isEnabledFor(level):
                    cost_ms = int((time.perf_counter() - start) * 1000)
                    effective_debug = _KMVPY_LOGGER_DEBUG if debug is None else debug
                    if effective_debug:
                        safe_result = _sanitize(
                            result,
                            max_depth=max_depth,
                            max_str_len=max_str_len,
                            mask_keys_lc=mask_keys_lc,
                            debug=True,
                        )
                        logger.log(
                            level, "api_return func=%s cost_ms=%s result=%s", func_name, cost_ms, safe_result
                        )
                    else:
                        logger.log(level, "api_return func=%s cost_ms=%s", func_name, cost_ms)

                return result

            return async_wrapper

        @wraps(f)
        def sync_wrapper(*args: Any, **kwargs: Any) -> Any:
            if logger.isEnabledFor(level):
                # api_call：要求入参尽量完整打印（仍脱敏）。
                # - 强制 debug=True：避免非 debug 的“超大容器摘要 / pydantic 摘要”等逻辑
                # - 放大 max_depth/max_str_len：避免默认 4 层 / 2000 截断导致“不完整”
                call_max_depth = max(max_depth, 50)
                call_max_str_len = max(max_str_len, 2_147_483_647)
                payload: dict[str, Any] = {"func": func_name}
                if include_args:
                    payload["args"] = _sanitize(
                        args,
                        max_depth=call_max_depth,
                        max_str_len=call_max_str_len,
                        mask_keys_lc=mask_keys_lc,
                        debug=True,
                    )
                if include_kwargs:
                    payload["kwargs"] = _sanitize(
                        kwargs,
                        max_depth=call_max_depth,
                        max_str_len=call_max_str_len,
                        mask_keys_lc=mask_keys_lc,
                        debug=True,
                    )
                logger.log(level, "api_call %s", payload)

            start = time.perf_counter()
            try:
                result = f(*args, **kwargs)
            except Exception as e:
                cost_ms = int((time.perf_counter() - start) * 1000)
                # KmvException 属于可预期业务错误：不要打印 traceback（会极大污染日志）。
                # 仍然保持抛出，让上层负责统一的业务响应。
                try:
                    from kmvpy.common.exception.kmv_exception import KmvException  # type: ignore

                    if isinstance(e, KmvException):
                        logger.debug(
                            "api_business_error func=%s cost_ms=%s err=%s",
                            func_name,
                            cost_ms,
                            e,
                        )
                    else:
                        logger.exception("api_error func=%s cost_ms=%s err=%s", func_name, cost_ms, e)
                except Exception:
                    logger.exception("api_error func=%s cost_ms=%s err=%s", func_name, cost_ms, e)
                raise

            if include_result and logger.isEnabledFor(level):
                cost_ms = int((time.perf_counter() - start) * 1000)

                effective_debug = _KMVPY_LOGGER_DEBUG if debug is None else debug
                if effective_debug:
                    safe_result = _sanitize(
                        result,
                        max_depth=max_depth,
                        max_str_len=max_str_len,
                        mask_keys_lc=mask_keys_lc,
                        debug=True,
                    )
                    logger.log(
                        level, "api_return func=%s cost_ms=%s result=%s", func_name, cost_ms, safe_result
                    )
                else:
                    logger.log(level, "api_return func=%s cost_ms=%s", func_name, cost_ms)

            return result

        return sync_wrapper

    if func is not None:
        return decorator(func)

    return decorator
