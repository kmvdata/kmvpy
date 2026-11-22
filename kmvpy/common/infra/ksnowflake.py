import hashlib
import os
from collections import Counter
import socket
import threading
import time
import uuid
from dataclasses import dataclass
from datetime import datetime, timezone


class ClockBackwardsError(RuntimeError):
    """系统时钟回拨导致无法安全生成 ID。"""


class KSnowflake:
    """
    雪花算法实现类（推荐：固定 worker_id，而不是每次随机）。

    64位 ID 组成结构：
    - 1位符号位（固定0）
    - 41位时间戳（毫秒级）
    - 10位 worker_id（0-1023，进程启动时确定一次）
    - 12位序列号（同一毫秒内的递增序号）
    """

    # bit 分配：1 + 41 + 10 + 12 = 64
    _TIMESTAMP_BITS = 41
    _WORKER_BITS = 10
    _SEQUENCE_BITS = 12

    _WORKER_MAX = (1 << _WORKER_BITS) - 1  # 1023
    _SEQUENCE_MASK = (1 << _SEQUENCE_BITS) - 1  # 4095

    _WORKER_SHIFT = _SEQUENCE_BITS
    _TIMESTAMP_SHIFT = _WORKER_BITS + _SEQUENCE_BITS

    # 默认 epoch：UTC 2020-01-01 00:00:00
    _CLS_EPOCH_: int = int(
        datetime(2020, 1, 1, tzinfo=timezone.utc).timestamp() * 1000)

    # 类属性单例实例
    _instance = None
    _instance_lock = threading.Lock()
    _configured_from_kosmos: bool = False

    def __init__(self, worker_id: int | None = None, *, max_backwards_ms: int = 5):
        self.sequence = 0  # 同一毫秒内的序列号
        self.last_timestamp = -1  # 上次生成ID的时间戳
        self.lock = threading.Lock()  # 线程锁保证原子操作
        self.max_backwards_ms = int(max_backwards_ms)
        self.worker_id = self._resolve_worker_id(worker_id)

        # # 时间戳起始点（2020-01-01）
        # self.epoch = int(time.mktime((2020, 1, 1, 0, 0, 0, 0, 0, 0)) * 1000)

    @classmethod
    def set_custom_epoch(cls, year: int, month: int, day: int):
        """设置时间戳起始点（自定义）"""
        # 避免运行中改变口径：一旦单例已生成过 ID，就不允许再修改 epoch。
        if cls._instance is not None and cls._instance.last_timestamp != -1:
            raise RuntimeError("KSnowflake 已生成过 ID，不允许再修改 epoch。")

        cls._CLS_EPOCH_ = int(
            datetime(year, month, day, tzinfo=timezone.utc).timestamp() * 1000)

    def _til_next_millis(self, last_timestamp):
        """等待下一毫秒"""
        timestamp = self._get_current_timestamp()
        while timestamp <= last_timestamp:
            # 避免忙等空转吃满 CPU（在高并发、序列号耗尽时尤其明显）
            time.sleep(0.0001)
            timestamp = self._get_current_timestamp()
        return timestamp

    @staticmethod
    def _get_current_timestamp():
        """获取当前时间戳（毫秒）"""
        # 使用 ns 避免 float 精度问题
        return time.time_ns() // 1_000_000

    @classmethod
    def _resolve_worker_id(cls, worker_id: int | None) -> int:
        """
        worker_id 获取优先级：
        - 显式传入
        - 环境变量 KMVPY_WORKER_ID
        - 兜底：根据 host/mac/pid 稳定 hash 后取低 10 bit
        """
        if worker_id is None:
            env = os.getenv("KMVPY_WORKER_ID")
            if env is not None and env != "":
                worker_id = int(env)

        if worker_id is None:
            host = socket.gethostname()
            mac = uuid.getnode()
            pid = os.getpid()
            raw = f"{host}-{mac}-{pid}".encode("utf-8")
            worker_id = int.from_bytes(hashlib.sha256(raw).digest()[
                                       :2], "big") & cls._WORKER_MAX

        worker_id = int(worker_id)
        if not (0 <= worker_id <= cls._WORKER_MAX):
            raise ValueError(
                f"worker_id 超出范围：{worker_id}，应为 0..{cls._WORKER_MAX}")
        return worker_id

    @classmethod
    def _maybe_load_snowflake_config_from_kosmos(cls):
        """
        尝试从 `kosmos.config.snowflake` 读取 SnowflakeConfig。

        说明：
        - 使用延迟导入，避免循环依赖（kosmos -> BaseConfig -> SnowflakeConfig）。
        - 若 kosmos/config 未初始化，返回 None。
        """
        try:
            from kmvpy.common.kmv import kosmos  # 延迟导入，避免循环依赖
        except Exception:
            return None

        cfg = getattr(kosmos, "config", None)
        if not cfg:
            return None
        return getattr(cfg, "snowflake", None)

    @classmethod
    def _apply_config_if_possible(cls, snow_cfg) -> tuple[int | None, int | None]:
        """
        将 SnowflakeConfig 应用到 KSnowflake 的类/实例初始化参数。

        返回：
        - (worker_id, max_backwards_ms) 供创建实例时使用；若配置缺失则返回 (None, None)
        """
        if snow_cfg is None:
            return None, None

        # epoch：仅允许在“尚未生成过 ID”时修改
        year = getattr(snow_cfg, "epoch_year", None)
        month = getattr(snow_cfg, "epoch_month", None)
        day = getattr(snow_cfg, "epoch_day", None)
        if year and month and day:
            try:
                cls.set_custom_epoch(int(year), int(month), int(day))
            except Exception:
                # 若运行中已生成过 ID，不强行修改 epoch
                pass

        worker_id = getattr(snow_cfg, "worker_id", None)
        max_backwards_ms = getattr(snow_cfg, "max_backwards_ms", None)

        # 若实例已存在且尚未发号，允许把参数写回实例（方便“先 import 后加载 config”的场景）
        inst = getattr(cls, "_instance", None)
        if inst is not None and getattr(inst, "last_timestamp", -1) == -1:
            if max_backwards_ms is not None:
                inst.max_backwards_ms = int(max_backwards_ms)
            if worker_id is not None:
                inst.worker_id = cls._resolve_worker_id(int(worker_id))

        cls._configured_from_kosmos = True
        return (int(worker_id) if worker_id is not None else None,
                int(max_backwards_ms) if max_backwards_ms is not None else None)

    def __gen_kid(self) -> int:
        """生成唯一 ID（固定 worker_id）。"""
        with self.lock:
            timestamp = self._get_current_timestamp()

            # 检测时间回拨
            if timestamp < self.last_timestamp:
                drift = self.last_timestamp - timestamp
                # 小幅回拨：阻塞等待到 last_timestamp（尽量保持可用性）
                if drift <= self.max_backwards_ms:
                    timestamp = self._til_next_millis(self.last_timestamp)
                else:
                    raise ClockBackwardsError(
                        f"时钟回拨 {drift} 毫秒（阈值 {self.max_backwards_ms}ms）")

            # 同一毫秒内序列号递增
            if timestamp == self.last_timestamp:
                # 12位序列号最大值4095
                self.sequence = (self.sequence + 1) & self._SEQUENCE_MASK
                if self.sequence == 0:
                    # 当前毫秒序列号已满，等待下一毫秒
                    timestamp = self._til_next_millis(self.last_timestamp)
            else:
                # 不同毫秒重置序列号
                self.sequence = 0

            self.last_timestamp = timestamp

            # 组装64位ID
            ts_part = (timestamp - self._CLS_EPOCH_) << self._TIMESTAMP_SHIFT
            worker_part = self.worker_id << self._WORKER_SHIFT
            return ts_part | worker_part | self.sequence

    def next_id(self) -> int:
        """实例方法：生成下一个 ID。"""
        return self.__gen_kid()

    @classmethod
    def gen_kid(cls) -> int:
        """类方法：使用单例生成 ID（兼容旧用法）。"""
        return cls.get_instance().__gen_kid()

    @classmethod
    def gen_sha256_kid(cls) -> str:
        kid = cls.get_instance().__gen_kid()
        return hashlib.sha256(str(kid).encode("utf-8")).hexdigest()

    @classmethod
    def gen_base36_random_code(cls, length: int = 6) -> str:
        alphabet = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        length = max(0, int(length))
        if length == 0:
            return ""

        # 用拒绝采样避免对 36 取模带来的分布偏差。
        chars: list[str] = []
        while len(chars) < length:
            for byte in os.urandom(length - len(chars)):
                if byte < 252:
                    chars.append(alphabet[byte % 36])
                    if len(chars) == length:
                        break
        return "".join(chars)

    @classmethod
    def gen_base36_for_int(cls, int_value: int) -> str:
        # 按 0-9A-Z 字母表做整数的 36 进制转换。
        alphabet = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        value = int(int_value)

        if value < 0:
            raise ValueError("int_value 必须大于等于 0")
        if value == 0:
            return alphabet[0]

        chars: list[str] = []
        while value > 0:
            value, remainder = divmod(value, 36)
            chars.append(alphabet[remainder])
        return "".join(reversed(chars))

    @dataclass(frozen=True, slots=True)
    class Parsed:
        timestamp_ms: int
        datetime_utc: datetime
        worker_id: int
        sequence: int

    @classmethod
    def parse_kid(cls, kid: int) -> "KSnowflake.Parsed":
        """反解析 ID，便于排障与观测。"""
        kid = int(kid)
        sequence = kid & cls._SEQUENCE_MASK
        worker_id = (kid >> cls._WORKER_SHIFT) & cls._WORKER_MAX
        ts_delta = kid >> cls._TIMESTAMP_SHIFT
        timestamp_ms = int(ts_delta + cls._CLS_EPOCH_)
        dt = datetime.fromtimestamp(timestamp_ms / 1000, tz=timezone.utc)
        return cls.Parsed(timestamp_ms=timestamp_ms, datetime_utc=dt, worker_id=worker_id, sequence=sequence)

    @classmethod
    def get_instance(cls):
        """
        获取KSnowflake单例实例
        """
        # 优先从 kosmos.config.snowflake 读取初始化参数（若可用）
        snow_cfg = cls._maybe_load_snowflake_config_from_kosmos()
        cfg_worker_id, cfg_max_backwards_ms = cls._apply_config_if_possible(
            snow_cfg)

        if cls._instance is None:
            with cls._instance_lock:
                if cls._instance is None:
                    kwargs = {}
                    if cfg_worker_id is not None:
                        kwargs["worker_id"] = cfg_worker_id
                    if cfg_max_backwards_ms is not None:
                        kwargs["max_backwards_ms"] = cfg_max_backwards_ms
                    cls._instance = cls(**kwargs)
        else:
            # 若此前在 kosmos.config 未就绪时创建过实例，则在首次 get_instance 时补一次配置（但不影响已发号实例）
            if not cls._configured_from_kosmos:
                cls._apply_config_if_possible(snow_cfg)
        return cls._instance


# 使用示例
if __name__ == "__main__":
    # 碰撞检测：默认 6 字符 base36，空间约 36^6；1e4 次采样期望几乎无碰撞。
    n = 10_000
    t0 = time.time_ns()
    cnt: Counter[str] = Counter()
    for _ in range(n):
        cnt[KSnowflake.gen_base36_random_code()] += 1
    unique = len(cnt)
    dup_total = n - unique  # 非首次出现的采样次数，O(n) 时间 / O(unique) 空间
    elapsed_ms = (time.time_ns() - t0) / 1_000_000
    print(f"{elapsed_ms:.3f}ms, n={n}, unique={unique}")
    if dup_total:
        dup_kinds = sum(1 for v in cnt.values() if v > 1)
        print(f"重复个数: {dup_total}（{dup_kinds} 种码发生碰撞）")
    else:
        print("无重复")
