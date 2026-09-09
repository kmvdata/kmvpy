import { postAdminApi } from '../../../boot/axios_admin';
import { AdminSocketClient } from '../../admin_socket';
import type {
  AdminCreateReviewerReq,
  AdminCreateUserReq,
  AdminDeleteUserReq,
  AdminLoginReq,
  AdminResetUserPasswordReq,
  AdminUpdateUserRoleReq,
  AdminUpdateUserStateReq,
  AdminUsernameLoginReq,
  AdminUserListReq,
  AdminUserListRes,
} from '../../dto/admin/admin_op';
import type { EmailAuthRes, UpdateUserProfileReq, UserProfileRes } from '../../dto/user/user_op';

const connectAdminSocketAfterAuth = (authRes: EmailAuthRes) => {
  AdminSocketClient.notifyAuthorizationChanged(`${authRes.token_type} ${authRes.token}`);
  return authRes;
};

export class ApiAdminOp {
  static emailLogin(requestData: AdminLoginReq): Promise<EmailAuthRes> {
    return postAdminApi<AdminLoginReq, EmailAuthRes>(
      '/api/admin/email/login',
      requestData,
      '管理员登录失败',
    ).then(connectAdminSocketAfterAuth);
  }

  static usernameLogin(requestData: AdminUsernameLoginReq): Promise<EmailAuthRes> {
    return postAdminApi<AdminUsernameLoginReq, EmailAuthRes>(
      '/api/admin/username/login',
      requestData,
      '管理员用户名登录失败',
    ).then(connectAdminSocketAfterAuth);
  }

  static getUserProfile(): Promise<UserProfileRes> {
    return postAdminApi<Record<string, never>, UserProfileRes>(
      '/api/admin/profile',
      {},
      '获取管理员资料失败',
    );
  }

  static updateUserProfile(requestData: UpdateUserProfileReq): Promise<UserProfileRes> {
    return postAdminApi<UpdateUserProfileReq, UserProfileRes>(
      '/api/admin/profile/update',
      requestData,
      '更新管理员资料失败',
    );
  }

  static adminUserList(requestData: AdminUserListReq): Promise<AdminUserListRes> {
    return postAdminApi<AdminUserListReq, AdminUserListRes>(
      '/api/admin/user/list',
      requestData,
      '获取用户列表失败',
    );
  }

  static createUser(requestData: AdminCreateUserReq): Promise<UserProfileRes> {
    return postAdminApi<AdminCreateUserReq, UserProfileRes>(
      '/api/admin/user/create',
      requestData,
      '创建用户失败',
    );
  }

  static resetUserPassword(requestData: AdminResetUserPasswordReq): Promise<{ kid: string }> {
    return postAdminApi<AdminResetUserPasswordReq, { kid: string }>(
      '/api/admin/user/password/reset',
      requestData,
      '重置用户密码失败',
    );
  }

  static deleteUser(requestData: AdminDeleteUserReq): Promise<{ kid: string }> {
    return postAdminApi<AdminDeleteUserReq, { kid: string }>(
      '/api/admin/user/delete',
      requestData,
      '删除用户失败',
    );
  }

  static createReviewer(requestData: AdminCreateReviewerReq): Promise<UserProfileRes> {
    return postAdminApi<AdminCreateReviewerReq, UserProfileRes>(
      '/api/admin/reviewer/create',
      requestData,
      '创建审核员失败',
    );
  }

  static updateUserRole(
    requestData: AdminUpdateUserRoleReq,
  ): Promise<{ kid: string; user_type: 0 | 1 | 2 }> {
    return postAdminApi<AdminUpdateUserRoleReq, { kid: string; user_type: 0 | 1 | 2 }>(
      '/api/admin/user/role/update',
      requestData,
      '更新用户角色失败',
    );
  }

  static updateUserState(
    requestData: AdminUpdateUserStateReq,
  ): Promise<{ kid: string; state: 0 | 1 }> {
    return postAdminApi<AdminUpdateUserStateReq, { kid: string; state: 0 | 1 }>(
      '/api/admin/user/state/update',
      requestData,
      '更新用户状态失败',
    );
  }

  static logout(): Promise<boolean> {
    return postAdminApi<Record<string, never>, boolean>('/api/admin/logout', {}, '退出登录失败').finally(() => {
      AdminSocketClient.broadcastLogout('manual');
    });
  }
}
