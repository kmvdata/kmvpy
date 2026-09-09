import { postUserApi } from '../../../boot/axios_user';
import type {
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
} from '../../dto/user/user_op';
import { UserSocketClient } from '../../socket';

const connectUserSocketAfterAuth = (authRes: EmailAuthRes) => {
  UserSocketClient.notifyAuthorizationChanged(`${authRes.token_type} ${authRes.token}`);
  return authRes;
};

export class ApiUserOp {
  static sendEmailVerifyCode(requestData: EmailCaptchaReq): Promise<EmailCaptchaRes> {
    return postUserApi<EmailCaptchaReq, EmailCaptchaRes>(
      '/api/user/email/verify-code',
      requestData,
      '发送邮箱验证码失败',
    );
  }

  static emailRegister(requestData: EmailRegisterReq): Promise<EmailAuthRes> {
    return postUserApi<EmailRegisterReq, EmailAuthRes>(
      '/api/user/email/register',
      requestData,
      '邮箱注册失败',
    ).then(connectUserSocketAfterAuth);
  }

  static emailLogin(requestData: EmailLoginReq): Promise<EmailAuthRes> {
    return postUserApi<EmailLoginReq, EmailAuthRes>(
      '/api/user/email/login',
      requestData,
      '邮箱登录失败',
    ).then(connectUserSocketAfterAuth);
  }

  static usernameLogin(requestData: UsernameLoginReq): Promise<EmailAuthRes> {
    return postUserApi<UsernameLoginReq, EmailAuthRes>(
      '/api/user/username/login',
      requestData,
      '用户名登录失败',
    ).then(connectUserSocketAfterAuth);
  }

  static phoneLogin(requestData: PhoneLoginReq): Promise<EmailAuthRes> {
    return postUserApi<PhoneLoginReq, EmailAuthRes>(
      '/api/user/phone/login',
      requestData,
      '手机号登录失败',
    ).then(connectUserSocketAfterAuth);
  }

  static accountLogin(requestData: AccountLoginReq): Promise<EmailAuthRes> {
    return postUserApi<AccountLoginReq, EmailAuthRes>(
      '/api/user/account/login',
      requestData,
      '账号登录失败',
    ).then(connectUserSocketAfterAuth);
  }

  static getUserProfile(): Promise<UserProfileRes> {
    return postUserApi<Record<string, never>, UserProfileRes>(
      '/api/user/profile',
      {},
      '获取用户资料失败',
    );
  }

  static updateUserProfile(requestData: UpdateUserProfileReq): Promise<UserProfileRes> {
    return postUserApi<UpdateUserProfileReq, UserProfileRes>(
      '/api/user/profile/update',
      requestData,
      '更新用户资料失败',
    );
  }

  static logout(): Promise<boolean> {
    return postUserApi<Record<string, never>, boolean>('/api/user/logout', {}, '退出登录失败').finally(() => {
      UserSocketClient.broadcastLogout('manual');
    });
  }
}
