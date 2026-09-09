export interface AdminLoginReq {
  account: string;
  password: string;
}

export interface AdminUsernameLoginReq {
  username: string;
  password: string;
}

export interface AdminUserListReq {
  page: number;
  size: number;
}

export interface AdminUserListItemRes {
  kid: string;
  email: string | null;
  username: string | null;
  nickname: string | null;
  user_type: number;
  state: number;
  create_time: string | null;
}

export interface AdminUserListRes {
  items: AdminUserListItemRes[];
  total: number;
}

export interface AdminCreateReviewerReq {
  email: string;
  password: string;
  nickname: string | null;
}

export interface AdminUpdateUserRoleReq {
  kid: string;
  user_type: 0 | 1 | 2;
}

export interface AdminUpdateUserStateReq {
  kid: string;
  state: 0 | 1;
}

export interface AdminCreateUserReq {
  username: string;
  password: string;
  user_type: 0 | 1 | 2;
}

export interface AdminResetUserPasswordReq {
  kid: string;
  password: string;
}

export interface AdminDeleteUserReq {
  kid: string;
}
