import json
import secrets
from datetime import datetime, timedelta
from typing import Any, cast

from kmvpy.common.exception.kmv_exception import KmvException
from kmvpy.common.kmv import kosmos
from kmvpy.common.tool.logger import logger
from kmvpy.core.main.service.auth_session_service import AuthSessionService
from kmvpy.core.main.service.jwt_service import JwtService, JwtUserInfo
from sqlalchemy.exc import IntegrityError

from __PROJECT_NAME__.common.dependencies.client import ClientRequestInfo
from __PROJECT_NAME__.common.infra.storage.default_storage import DefaultStorage
from __PROJECT_NAME__.common.dto.user.user_op import (
    EmailAuthRes,
    EmailCaptchaReq,
    EmailCaptchaRes,
    EmailLoginReq,
    EmailRegisterReq,
    UpdateUserProfileReq,
    UserProfileRes,
    UsernameLoginReq,
    PhoneLoginReq,
    AccountLoginReq,
)
from __PROJECT_NAME__.common.exception import user_op_errors as user_op_exc
from __PROJECT_NAME__.common.infra.orm.kv_conf import KvConf
from __PROJECT_NAME__.common.infra.orm.user_base import UserBase
from __PROJECT_NAME__.common.infra.orm.user_tree import UserTree
from __PROJECT_NAME__.core.main.hub.user_op import UserOpHub


class UserOpService:
    @staticmethod
    def _build_user_profile(user: UserBase) -> UserProfileRes:
        """将 ORM 对象转换为接口返回 DTO，避免直接暴露敏感字段。"""
        orm_user = cast(Any, user)
        return UserProfileRes(
            kid=str(orm_user.kid),
            user_type=int(orm_user.user_type),
            state=orm_user.state,
            country_code=orm_user.country_code,
            phone=orm_user.phone,
            email=orm_user.email,
            username=orm_user.username,
            nickname=orm_user.nickname,
            signature=orm_user.signature,
            avatar_uri=orm_user.avatar_uri,
            delete_at=orm_user.delete_at,
            gender=orm_user.gender,
            ip=orm_user.ip,
            deviceid=orm_user.deviceid,
            balance_power=orm_user.balance_power,
            create_time=orm_user.create_time,
            update_time=orm_user.update_time,
            comment=orm_user.comment,
        )

    @staticmethod
    async def _issue_user_token_for_user(
        user: UserBase,
        client_info: ClientRequestInfo,
        *,
        is_new_user: bool,
    ) -> EmailAuthRes:
        """统一普通用户端签发逻辑，确保 JWT 与 Redis 会话状态同步创建。"""
        orm_user = cast(Any, user)
        auth_token = await AuthSessionService.issue_token(
            JwtUserInfo(
                kid=orm_user.kid,
                user_type=orm_user.user_type,
            ),
            auth_role="user",
            device_id=client_info.device_id,
            device_name=client_info.device_model,
            platform=client_info.device_type or "web",
        )
        return EmailAuthRes(
            token=auth_token.token,
            token_type=auth_token.token_type,
            expire_hours=auth_token.expire_hours,
            expires_at=auth_token.expires_at,
            sid=auth_token.sid,
            is_new_user=is_new_user,
            user=UserOpService._build_user_profile(user),
            session_cookie_value=auth_token.session_cookie_value,
            session_cookie_max_age=auth_token.session_cookie_max_age,
        )

    @staticmethod
    def _get_redis_client():
        """仅在 Redis 已初始化时返回 client，避免直接访问属性触发运行时异常。"""
        storage = DefaultStorage.instance()
        if not storage.has_redis_client():
            return None
        return storage.redis_client

    @staticmethod
    async def _save_email_captcha(scene: str, email: str, code: str) -> None:
        """
        保存邮箱验证码。

        实现策略：
        1. 若当前应用已初始化 Redis，则优先使用 Redis，并设置 TTL，天然适合验证码短期存储。
        2. 若 Redis 未配置，则退化为写入 `kv_conf` 表，value 内保存验证码及过期时间。
        3. 使用统一 key 规则，保证同一邮箱同一场景仅保留最后一次验证码。
        """
        expire_at = datetime.now() + timedelta(seconds=UserOpHub.EMAIL_CAPTCHA_TTL_SECONDS)
        payload = json.dumps(
            {"code": code, "expire_at": expire_at.isoformat()},
            ensure_ascii=False,
        )
        cache_key = UserOpHub.build_email_captcha_key(scene, email)
        redis_client = UserOpService._get_redis_client()

        if redis_client is not None:
            await redis_client.set(cache_key, payload, ex=UserOpHub.EMAIL_CAPTCHA_TTL_SECONDS)
            return

        db = DefaultStorage.instance()
        async with db.session_scope() as session:
            kv_conf = await db.get_by_condition(KvConf, key=cache_key, session=session)
            if kv_conf is None:
                kv_conf = KvConf(kid=KvConf.gen_kid(),
                                 key=cache_key, value=payload)
                session.add(kv_conf)
            else:
                cast(Any, kv_conf).value = payload
            await session.flush()

    @staticmethod
    async def _load_email_captcha(scene: str, email: str) -> dict[str, str] | None:
        """
        读取并校验验证码是否过期。

        返回约定：
        - 返回 `None`：表示验证码不存在、反序列化失败或已过期；
        - 返回字典：至少包含 `code` 与 `expire_at` 两个字段。
        """
        cache_key = UserOpHub.build_email_captcha_key(scene, email)
        redis_client = UserOpService._get_redis_client()
        payload: str | None = None

        if redis_client is not None:
            cached_value = await redis_client.get(cache_key)
            if isinstance(cached_value, bytes):
                payload = cached_value.decode("utf-8")
            else:
                payload = cached_value
        else:
            kv_conf = await DefaultStorage.instance().get_by_condition(KvConf, key=cache_key)
            if kv_conf is not None:
                payload = cast(Any, kv_conf).value

        if not payload:
            return None

        data = UserOpHub.parse_email_captcha_payload(payload)
        if data is None:
            logger.warning("邮箱验证码缓存反序列化失败，key=%s", cache_key)
            return None

        expire_at_text = data.get("expire_at")
        if UserOpHub.is_email_captcha_expired(expire_at_text):
            await UserOpService._delete_email_captcha(scene=scene, email=email)
            return None

        return data

    @staticmethod
    async def _delete_email_captcha(scene: str, email: str) -> None:
        """注册成功后删除验证码，避免重复消费。"""
        cache_key = UserOpHub.build_email_captcha_key(scene, email)
        redis_client = UserOpService._get_redis_client()

        if redis_client is not None:
            await redis_client.delete(cache_key)
            return

        db = DefaultStorage.instance()
        async with db.session_scope() as session:
            kv_conf = await db.get_by_condition(KvConf, key=cache_key, session=session)
            if kv_conf is not None:
                await db.delete(kv_conf, session=session)

    @staticmethod
    def _send_email_captcha(email: str, scene: str, code: str) -> bool:
        """
        记录验证码发送日志。

        模板默认不集成真实邮箱能力，只保留验证码缓存与校验主流程。
        如需接入短信、邮件或第三方通知渠道，请在业务项目中自行扩展。
        """
        logger.info(
            "验证码已生成但未发送真实邮件: email=%s, scene=%s, code=%s",
            email,
            scene,
            code,
        )
        return False

    @staticmethod
    async def send_email_captcha(req: EmailCaptchaReq) -> EmailCaptchaRes:
        """
        获取邮箱验证码。

        处理流程：
        1. 校验邮箱格式与场景枚举。
        2. 当前联调环境固定生成 `666666` 作为验证码。
        3. 将验证码写入 Redis / `kv_conf`，有效期 300 秒。
        4. 模板默认不发送真实邮件，仅返回联调提示，方便前端先打通流程。
        """
        email = UserOpHub.normalize_email(req.email)
        scene = UserOpHub.normalize_email_scene(req.scene)
        code = UserOpHub.generate_email_captcha()
        await UserOpService._save_email_captcha(scene=scene, email=email, code=code)
        sent = UserOpService._send_email_captcha(email=email, scene=scene, code=code)

        return EmailCaptchaRes(
            email=email,
            scene=cast(Any, scene),
            expire_seconds=UserOpHub.EMAIL_CAPTCHA_TTL_SECONDS,
            sent=sent,
            message=f"验证码已生成，模板默认不发送真实邮件，当前联调验证码固定为 {code}",
        )

    @staticmethod
    async def email_register(
        req: EmailRegisterReq,
        client_info: ClientRequestInfo,
    ) -> EmailAuthRes:
        """
        使用邮箱 + 验证码完成注册，并直接签发登录 token。

        详细说明：
        1. 当前联调环境固定使用 `666666` 作为验证码。
        2. 通过固定验证码完成注册联调，避免依赖真实邮件通道。
        3. 账号创建后立即签发 JWT，前端可直接复用该 token 进入已登录态。
        4. 注册成功时同步创建 `user_tree`，用于后续推广上下级链路查询。
        5. 本方法只返回脱敏后的用户资料，不会回传 `password`、`salt` 等敏感字段。
        """
        email = UserOpHub.normalize_email(req.email)
        UserOpHub.verify_email_captcha_code(req.verify_code)

        invitation_code = UserOpHub.normalize_invitation_code(
            req.invitation_code)
        salt = secrets.token_hex(16)
        password_hash = UserOpHub.build_password_hash(req.password, salt)
        nickname = UserOpHub.default_nickname_from_email(email, req.nickname)
        db = DefaultStorage.instance()
        async with db.session_scope() as session:
            existing_user = await db.get_by_condition(UserBase, email=email, session=session)
            if existing_user is not None:
                raise KmvException(
                    error=user_op_exc.EMAIL_REGISTERED_ERROR)

            inviter_user_tree = None
            if invitation_code is not None:
                inviter_user_tree = await db.get_by_condition(
                    UserTree,
                    invitation_code=invitation_code,
                    session=session,
                )
                if inviter_user_tree is None:
                    raise KmvException(
                        error=user_op_exc.INVITATION_CODE_INVALID_ERROR)

            user_kid = UserBase.gen_kid()
            user = UserBase(
                kid=user_kid,
                username=email,
                email=email,
                nickname=nickname,
                salt=salt,
                password=password_hash,
                user_type=UserOpHub.USER_DB_USER_TYPE,
                state=1,
                ip=client_info.ip,
                deviceid=(client_info.device_id or client_info.user_agent)[:255] or None,
            )
            session.add(user)

            inviter_tree_orm = cast(Any, inviter_user_tree)
            user_tree = UserTree(
                kid=user_kid,
                invitation_code=UserTree._snowflake.gen_base36_for_int(
                    user_kid),
                p1_kid=inviter_tree_orm.kid if inviter_user_tree is not None else None,
                p2_kid=inviter_tree_orm.p1_kid if inviter_user_tree is not None else None,
                p3_kid=inviter_tree_orm.p2_kid if inviter_user_tree is not None else None,
                p4_kid=inviter_tree_orm.p3_kid if inviter_user_tree is not None else None,
                p5_kid=inviter_tree_orm.p4_kid if inviter_user_tree is not None else None,
                p6_kid=inviter_tree_orm.p5_kid if inviter_user_tree is not None else None,
                p7_kid=inviter_tree_orm.p6_kid if inviter_user_tree is not None else None,
                p8_kid=inviter_tree_orm.p7_kid if inviter_user_tree is not None else None,
                p9_kid=inviter_tree_orm.p8_kid if inviter_user_tree is not None else None,
            )
            session.add(user_tree)

            try:
                await session.flush()
            except IntegrityError as exc:
                logger.warning("邮箱注册写库失败，email=%s", email, exc_info=exc)
                raise KmvException(
                    error=user_op_exc.EMAIL_REGISTERED_ERROR) from exc

        await UserOpService._delete_email_captcha(scene="register", email=email)

        return await UserOpService._issue_user_token_for_user(
            user,
            client_info,
            is_new_user=True,
        )

    @staticmethod
    async def email_login(req: EmailLoginReq, client_info: ClientRequestInfo) -> EmailAuthRes:
        """
        使用邮箱与密码登录。

        说明：
        1. 登录账号统一使用邮箱，便于与注册流程保持一致。
        2. 服务端会从数据库读取该用户的 `salt`，再按相同规则计算密码哈希做比对。
        3. 登录成功后返回 JWT，可放入 `Authorization: Bearer <token>` 请求头中继续访问后续接口。
        4. 路由层会统一注入客户端上下文，便于后续扩展登录审计、设备识别等能力。
        """
        _ = client_info
        email = UserOpHub.normalize_email(req.email)
        user = await DefaultStorage.instance().get_by_condition(UserBase, email=email)
        if user is None:
            raise KmvException(error=user_op_exc.USER_NOT_FOUND_ERROR)

        user_salt = cast(Any, user).salt
        user_password = cast(Any, user).password
        UserOpHub.verify_password(req.password, user_salt, user_password)

        orm_user = cast(Any, user)
        UserOpHub.ensure_user_can_login_from_user_portal(orm_user.user_type)

        return await UserOpService._issue_user_token_for_user(
            user,
            client_info,
            is_new_user=False,
        )

    @staticmethod
    async def username_login(req: UsernameLoginReq, client_info: ClientRequestInfo) -> EmailAuthRes:
        """
        使用用户名与密码登录（仅按 `user_base.username` 匹配，不按邮箱解析）。

        与邮箱登录行为一致：校验密码、拒绝管理员走用户端入口、签发 JWT。
        """
        _ = client_info
        username = UserOpHub.normalize_username_for_login(req.username)
        user = await DefaultStorage.instance().get_by_condition(UserBase, username=username)
        if user is None:
            raise KmvException(error=user_op_exc.USER_NOT_FOUND_ERROR)

        user_salt = cast(Any, user).salt
        user_password = cast(Any, user).password
        UserOpHub.verify_password(req.password, user_salt, user_password)

        orm_user = cast(Any, user)
        UserOpHub.ensure_user_can_login_from_user_portal(orm_user.user_type)

        return await UserOpService._issue_user_token_for_user(
            user,
            client_info,
            is_new_user=False,
        )

    @staticmethod
    async def phone_login(req: PhoneLoginReq, client_info: ClientRequestInfo) -> EmailAuthRes:
        """
        使用手机号与密码登录（仅匹配 `user_base.phone`）。

        与邮箱/用户名登录行为一致：校验手机号格式、核验密码、拒绝管理员走用户端入口、签发 JWT。
        """
        _ = client_info
        phone = UserOpHub.normalize_phone_for_login(req.phone)
        user = await DefaultStorage.instance().get_by_condition(UserBase, phone=phone)
        if user is None:
            raise KmvException(error=user_op_exc.USER_NOT_FOUND_ERROR)

        user_salt = cast(Any, user).salt
        user_password = cast(Any, user).password
        UserOpHub.verify_password(req.password, user_salt, user_password)

        orm_user = cast(Any, user)
        UserOpHub.ensure_user_can_login_from_user_portal(orm_user.user_type)

        return await UserOpService._issue_user_token_for_user(
            user,
            client_info,
            is_new_user=False,
        )

    @staticmethod
    async def account_login(req: AccountLoginReq, client_info: ClientRequestInfo) -> EmailAuthRes:
        """
        使用统一账号（邮箱 / 手机号 / 用户名）登录。

        服务端按账号格式自动识别类型并分发到对应字段查询，避免前端判断与后端不一致：
        1. 含 @ -> 邮箱；
        2. 符合手机号格式 -> 手机号；
        3. 以字母开头 -> 用户名；
        4. 其余输入 -> 账号格式无法识别错误。
        """
        account_kind = UserOpHub.classify_login_account(req.account)
        if account_kind is None:
            raise KmvException(error=user_op_exc.ACCOUNT_TYPE_UNRECOGNIZED_ERROR)

        db = DefaultStorage.instance()
        if account_kind == UserOpHub.ACCOUNT_KIND_EMAIL:
            normalized = UserOpHub.normalize_email(req.account)
            user = await db.get_by_condition(UserBase, email=normalized)
        elif account_kind == UserOpHub.ACCOUNT_KIND_PHONE:
            normalized = UserOpHub.normalize_phone_for_login(req.account)
            user = await db.get_by_condition(UserBase, phone=normalized)
        else:
            normalized = UserOpHub.normalize_username_for_login(req.account)
            user = await db.get_by_condition(UserBase, username=normalized)

        if user is None:
            raise KmvException(error=user_op_exc.USER_NOT_FOUND_ERROR)

        user_salt = cast(Any, user).salt
        user_password = cast(Any, user).password
        UserOpHub.verify_password(req.password, user_salt, user_password)

        orm_user = cast(Any, user)
        UserOpHub.ensure_user_can_login_from_user_portal(orm_user.user_type)

        return await UserOpService._issue_user_token_for_user(
            user,
            client_info,
            is_new_user=False,
        )

    @staticmethod
    async def get_user_info(user_kid: int) -> UserProfileRes:
        """
        获取当前登录用户资料。

        处理流程：
        1. 调用方负责完成登录态校验，并传入当前登录用户 kid。
        2. 服务层按 kid 查询用户主表，统一转换成脱敏后的资料 DTO 返回给前端。
        """
        user = await DefaultStorage.instance().get_by_kid(UserBase, kid=user_kid, use_cache=True)
        if user is None:
            raise KmvException(error=user_op_exc.USER_NOT_FOUND_ERROR)
        return UserOpService._build_user_profile(user)

    @staticmethod
    async def update_user_profile(req: UpdateUserProfileReq, user_info: JwtUserInfo) -> UserProfileRes:
        """
        编辑当前登录用户资料。

        更新规则：
        1. `nickname`、`signature`、`phone` 均支持不传；传 `None` 表示维持原值不变。
        2. 非 None 字段会先去除首尾空格；若结果为空，则按清空该字段处理。
        3. 当前基于既有表结构做字段映射：`signature -> user_base.signature`，`phone -> user_base.phone`。
        """
        UserOpHub.ensure_profile_update_has_changes(
            nickname=req.nickname,
            signature=req.signature,
            phone=req.phone,
        )

        current_user_kid = user_info.kid
        normalized_nickname = UserOpHub.normalize_optional_profile_value(
            req.nickname)
        normalized_signature = UserOpHub.normalize_optional_profile_value(
            req.signature)
        normalized_phone = UserOpHub.normalize_optional_profile_value(
            req.phone)

        db = DefaultStorage.instance()
        async with db.session_scope() as session:
            user = await db.get_by_condition(UserBase, kid=current_user_kid, session=session)
            if user is None:
                raise KmvException(
                    error=user_op_exc.USER_NOT_FOUND_ERROR)

            orm_user = cast(Any, user)
            if req.nickname is not None:
                orm_user.nickname = normalized_nickname
            if req.signature is not None:
                orm_user.signature = normalized_signature
            if req.phone is not None:
                orm_user.phone = normalized_phone

            try:
                await session.flush()
                await session.refresh(user)
            except IntegrityError as exc:
                logger.warning("编辑用户资料写库失败，kid=%s",
                               current_user_kid, exc_info=exc)
                raise KmvException(
                    error=user_op_exc.CONTACT_DUPLICATED_ERROR) from exc
            return UserOpService._build_user_profile(user)
