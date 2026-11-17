from datetime import datetime
from typing import Any, cast

import secrets

from kmvpy.common.exception.kmv_exception import KmvException
from kmvpy.common.tool.logger import logger
from kmvpy.core.main.service.jwt_service import JwtUserInfo
from sqlalchemy.exc import IntegrityError

from __PROJECT_NAME__.common.dependencies.client import ClientRequestInfo
from __PROJECT_NAME__.common.auth_session import AuthSessionService
from __PROJECT_NAME__.common.infra.storage.default_storage import DefaultStorage
from __PROJECT_NAME__.common.dto.admin.admin_op import (
    AdminCreateReviewerReq,
    AdminCreateUserReq,
    AdminDeleteUserReq,
    AdminLoginReq,
    AdminResetUserPasswordReq,
    AdminUpdateUserRoleReq,
    AdminUpdateUserStateReq,
    AdminUserListItemRes,
    AdminUserListReq,
    AdminUserListRes,
    AdminUsernameLoginReq,
)
from __PROJECT_NAME__.common.dto.user.user_op import (
    EmailAuthRes,
    UpdateUserProfileReq,
    UserProfileRes,
)
from __PROJECT_NAME__.common.exception import user_op_errors as user_op_exc
from __PROJECT_NAME__.common.infra.orm.user_base import UserBase
from __PROJECT_NAME__.core.main.hub.user_op import UserOpHub

# 审核员在 user_base.user_type 中的取值（与 DTO 一致）。
REVIEWER_DB_USER_TYPE = UserOpHub.REVIEWER_DB_USER_TYPE


class AdminOpService:
    """后台管理员账号相关能力；登录仅允许 `user_type` 为管理员的账号。"""

    @staticmethod
    def _build_user_profile(user: UserBase) -> UserProfileRes:
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
    async def _issue_admin_token_for_user(
        user: UserBase,
        client_info: ClientRequestInfo,
    ) -> EmailAuthRes:
        orm_user = cast(Any, user)
        auth_token = await AuthSessionService.issue_token(
            JwtUserInfo(
                kid=orm_user.kid,
                user_type=orm_user.user_type,
            ),
            auth_role="admin",
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
            is_new_user=False,
            user=AdminOpService._build_user_profile(user),
            session_cookie_value=auth_token.session_cookie_value,
            session_cookie_max_age=auth_token.session_cookie_max_age,
        )

    @staticmethod
    def _verify_admin_password_and_role(user: UserBase, password: str) -> None:
        orm_user = cast(Any, user)
        UserOpHub.verify_password(password, orm_user.salt, orm_user.password)
        UserOpHub.ensure_admin_login_allowed(orm_user.user_type)

    @staticmethod
    async def admin_login(
        req: AdminLoginReq,
        client_info: ClientRequestInfo,
    ) -> EmailAuthRes:
        _ = client_info
        raw = UserOpHub.normalize_admin_account(req.account)

        db = DefaultStorage.instance()
        if "@" in raw:
            email = UserOpHub.normalize_email(raw)
            user = await db.get_by_condition(UserBase, email=email)
        else:
            username = raw.lower()
            user = await db.get_by_condition(UserBase, username=username)
        if user is None:
            raise KmvException(error=user_op_exc.USER_NOT_FOUND_ERROR)

        AdminOpService._verify_admin_password_and_role(user, req.password)
        return await AdminOpService._issue_admin_token_for_user(user, client_info)

    @staticmethod
    async def admin_login_by_username(
        req: AdminUsernameLoginReq,
        client_info: ClientRequestInfo,
    ) -> EmailAuthRes:
        _ = client_info
        username = UserOpHub.normalize_username_for_admin_create(req.username)
        user = await DefaultStorage.instance().get_by_condition(
            UserBase, username=username
        )
        if user is None:
            raise KmvException(error=user_op_exc.USER_NOT_FOUND_ERROR)
        AdminOpService._verify_admin_password_and_role(user, req.password)
        return await AdminOpService._issue_admin_token_for_user(user, client_info)

    @staticmethod
    async def get_user_info(user_kid: int) -> UserProfileRes:
        user = await DefaultStorage.instance().get_by_kid(UserBase, kid=user_kid, use_cache=True)
        if user is None:
            raise KmvException(error=user_op_exc.USER_NOT_FOUND_ERROR)
        return AdminOpService._build_user_profile(user)

    @staticmethod
    async def update_user_profile(
        req: UpdateUserProfileReq,
        user_info: JwtUserInfo,
    ) -> UserProfileRes:
        UserOpHub.ensure_profile_update_has_changes(
            nickname=req.nickname,
            signature=req.signature,
            phone=req.phone,
        )
        current_user_kid = user_info.kid
        normalized_nickname = UserOpHub.normalize_optional_profile_value(req.nickname)
        normalized_signature = UserOpHub.normalize_optional_profile_value(req.signature)
        normalized_phone = UserOpHub.normalize_optional_profile_value(req.phone)

        db = DefaultStorage.instance()
        async with db.session_scope() as session:
            user = await db.get_by_condition(UserBase, kid=current_user_kid, session=session)
            if user is None:
                raise KmvException(error=user_op_exc.USER_NOT_FOUND_ERROR)

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
                logger.warning("编辑管理员资料写库失败，kid=%s", current_user_kid, exc_info=exc)
                raise KmvException(error=user_op_exc.CONTACT_DUPLICATED_ERROR) from exc
            return AdminOpService._build_user_profile(user)


    @staticmethod
    async def list_users(req: AdminUserListReq) -> AdminUserListRes:
        """分页查询未软删除的用户基础信息，按创建时间倒序。"""
        db = DefaultStorage.instance()
        result = await db.gets_by_filters(
            UserBase,
            (UserBase.delete_at.is_(None),),
            page=req.page,
            size=req.size,
            sort=(("create_time", "desc"),),
        )
        if result is None:
            return AdminUserListRes(items=[], total=0)
        rows, total = result
        items = [
            AdminUserListItemRes(
                kid=str(cast(Any, row).kid),
                email=cast(Any, row).email,
                username=cast(Any, row).username,
                nickname=cast(Any, row).nickname,
                user_type=int(cast(Any, row).user_type),
                state=int(cast(Any, row).state),
                create_time=cast(Any, row).create_time,
            )
            for row in rows
        ]
        return AdminUserListRes(items=items, total=total)

    @staticmethod
    async def create_reviewer(req: AdminCreateReviewerReq) -> UserProfileRes:
        email = UserOpHub.normalize_email(req.email)
        salt = secrets.token_hex(16)
        password_hash = UserOpHub.build_password_hash(req.password, salt)
        nickname = UserOpHub.default_nickname_from_email(email, req.nickname)

        db = DefaultStorage.instance()
        async with db.session_scope() as session:
            existing_user = await db.get_by_condition(UserBase, email=email, session=session)
            if existing_user is not None:
                raise KmvException(error=user_op_exc.EMAIL_REGISTERED_ERROR)

            user_kid = UserBase.gen_kid()
            user = UserBase(
                kid=user_kid,
                username=email,
                email=email,
                nickname=nickname,
                salt=salt,
                password=password_hash,
                user_type=REVIEWER_DB_USER_TYPE,
                state=1,
            )
            session.add(user)

            try:
                await session.flush()
            except IntegrityError as exc:
                logger.warning("创建审核员写库失败，email=%s", email, exc_info=exc)
                raise KmvException(error=user_op_exc.REVIEWER_CREATE_ERROR) from exc

        return AdminOpService._build_user_profile(user)

    @staticmethod
    async def create_user(req: AdminCreateUserReq) -> UserProfileRes:
        username = UserOpHub.normalize_username_for_login(req.username)
        salt = secrets.token_hex(16)
        password_hash = UserOpHub.build_password_hash(req.password, salt)
        db_user_type = UserOpHub.db_user_type_for_admin_create(int(req.user_type))
        nickname = UserOpHub.default_nickname_from_username(username)

        db = DefaultStorage.instance()
        async with db.session_scope() as session:
            existing = await db.get_by_condition(UserBase, username=username, session=session)
            if existing is not None:
                raise KmvException(error=user_op_exc.USERNAME_TAKEN_ERROR)

            user_kid = UserBase.gen_kid()
            user = UserBase(
                kid=user_kid,
                username=username,
                email=None,
                nickname=nickname,
                salt=salt,
                password=password_hash,
                user_type=db_user_type,
                state=1,
            )
            session.add(user)

            try:
                await session.flush()
            except IntegrityError as exc:
                logger.warning("管理员创建用户写库失败，username=%s", username, exc_info=exc)
                raise KmvException(error=user_op_exc.USER_CREATE_ERROR) from exc

        return AdminOpService._build_user_profile(user)

    @staticmethod
    async def reset_user_password(
        req: AdminResetUserPasswordReq,
        admin_info: JwtUserInfo,
    ) -> dict:
        UserOpHub.ensure_not_target_self(req.kid, admin_info.kid)
        salt = secrets.token_hex(16)
        password_hash = UserOpHub.build_password_hash(req.password, salt)
        db = DefaultStorage.instance()
        async with db.session_scope() as session:
            user = await db.get_by_condition(UserBase, kid=int(req.kid), session=session)
            UserOpHub.ensure_target_user_available(
                exists=user is not None,
                is_deleted=user is not None and cast(Any, user).delete_at is not None,
            )
            cast(Any, user).salt = salt
            cast(Any, user).password = password_hash
            try:
                await session.flush()
            except IntegrityError as exc:
                logger.warning("重置用户密码写库失败，kid=%s", req.kid, exc_info=exc)
                raise KmvException(error=user_op_exc.USER_PASSWORD_RESET_ERROR) from exc
        await AuthSessionService.revoke_user_sessions(auth_role="user", kid=int(req.kid))
        await AuthSessionService.revoke_user_sessions(auth_role="admin", kid=int(req.kid))
        return {"kid": req.kid}

    @staticmethod
    async def delete_user(req: AdminDeleteUserReq, admin_info: JwtUserInfo) -> dict:
        UserOpHub.ensure_not_target_self(req.kid, admin_info.kid)
        db = DefaultStorage.instance()
        async with db.session_scope() as session:
            user = await db.get_by_condition(UserBase, kid=int(req.kid), session=session)
            UserOpHub.ensure_target_user_available(
                exists=user is not None,
                is_deleted=user is not None and cast(Any, user).delete_at is not None,
            )
            cast(Any, user).delete_at = datetime.now()
            try:
                await session.flush()
            except IntegrityError as exc:
                logger.warning("软删除用户写库失败，kid=%s", req.kid, exc_info=exc)
                raise KmvException(error=user_op_exc.USER_DELETE_ERROR) from exc
        await AuthSessionService.revoke_user_sessions(auth_role="user", kid=int(req.kid))
        await AuthSessionService.revoke_user_sessions(auth_role="admin", kid=int(req.kid))
        return {"kid": req.kid}

    @staticmethod
    async def update_user_role(req: AdminUpdateUserRoleReq) -> dict:
        db = DefaultStorage.instance()
        async with db.session_scope() as session:
            user = await db.get_by_condition(UserBase, kid=int(req.kid), session=session)
            UserOpHub.ensure_target_user_available(
                exists=user is not None,
                is_deleted=user is not None and cast(Any, user).delete_at is not None,
            )

            db_user_type = UserOpHub.db_user_type_for_admin_create(int(req.user_type))
            cast(Any, user).user_type = db_user_type

            try:
                await session.flush()
            except IntegrityError as exc:
                logger.warning("更新用户角色写库失败，kid=%s", req.kid, exc_info=exc)
                raise KmvException(error=user_op_exc.USER_ROLE_UPDATE_ERROR) from exc

        await AuthSessionService.revoke_user_sessions(auth_role="user", kid=int(req.kid))
        await AuthSessionService.revoke_user_sessions(auth_role="admin", kid=int(req.kid))
        return {"kid": req.kid, "user_type": req.user_type}

    @staticmethod
    async def update_user_state(
        req: AdminUpdateUserStateReq,
        admin_info: JwtUserInfo,
    ) -> dict:
        UserOpHub.ensure_not_target_self(req.kid, admin_info.kid)
        db = DefaultStorage.instance()
        async with db.session_scope() as session:
            user = await db.get_by_condition(UserBase, kid=int(req.kid), session=session)
            UserOpHub.ensure_target_user_available(
                exists=user is not None,
                is_deleted=user is not None and cast(Any, user).delete_at is not None,
            )

            cast(Any, user).state = req.state

            try:
                await session.flush()
            except IntegrityError as exc:
                logger.warning("更新用户状态写库失败，kid=%s", req.kid, exc_info=exc)
                raise KmvException(error=user_op_exc.USER_STATE_UPDATE_ERROR) from exc

        if UserOpHub.should_revoke_sessions_after_state_update(req.state):
            await AuthSessionService.revoke_user_sessions(auth_role="user", kid=int(req.kid))
            await AuthSessionService.revoke_user_sessions(auth_role="admin", kid=int(req.kid))
        return {"kid": req.kid, "state": req.state}
