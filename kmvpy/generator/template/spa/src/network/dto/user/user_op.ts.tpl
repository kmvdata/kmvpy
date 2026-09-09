export interface EmailCaptchaReq {
  email: string;
  scene: 'register' | 'login';
}

export interface EmailCaptchaRes {
  email: string;
  scene: 'register' | 'login';
  expire_seconds: number;
  sent: boolean;
  message: string;
}

export interface EmailRegisterReq {
  email: string;
  verify_code: string;
  password: string;
  nickname: string | null;
  invitation_code: string | null;
}

export interface EmailLoginReq {
  email: string;
  password: string;
}

export interface UsernameLoginReq {
  username: string;
  password: string;
}

export interface PhoneLoginReq {
  phone: string;
  password: string;
}

export interface AccountLoginReq {
  account: string;
  password: string;
}

export interface UpdateUserProfileReq {
  nickname: string | null;
  signature: string | null;
  phone: string | null;
}

export interface UserProfileRes {
  kid: string;
  user_type: number;
  state: number | null;
  country_code: string | null;
  phone: string | null;
  email: string | null;
  username: string | null;
  nickname: string | null;
  signature: string | null;
  avatar_uri: string | null;
  delete_at: string | null;
  gender: number | null;
  ip: string | null;
  deviceid: string | null;
  balance_power: number | null;
  create_time: string | null;
  update_time: string | null;
  comment: string | null;
}

export interface EmailAuthRes {
  token: string;
  token_type: string;
  expire_hours: number;
  expires_at: number;
  sid: string;
  is_new_user: boolean;
  user: UserProfileRes;
}
