export interface UserWorkTicketCreateReq {
  title: string;
  category: string | null;
  body: string;
}

export interface UserWorkTicketListReq {
  page: number;
  size: number;
  status: 0 | 1 | 2 | 3 | 4 | null;
}

export interface UserWorkTicketListItemRes {
  kid: string;
  creator_user_kid: string;
  title: string;
  category: string | null;
  status: number;
  last_message_time: string | null;
  assigned_admin_kid: string | null;
  create_time: string | null;
}

export interface UserWorkTicketListRes {
  items: UserWorkTicketListItemRes[];
  total: number;
}

export interface UserWorkTicketDetailReq {
  kid: string;
}

export interface UserWorkTicketMessageItemRes {
  kid: string;
  sender_role: number;
  sender_user_kid: string;
  body: string;
  create_time: string | null;
}

export interface UserWorkTicketDetailRes {
  kid: string;
  creator_user_kid: string;
  title: string;
  category: string | null;
  status: number;
  last_message_time: string | null;
  assigned_admin_kid: string | null;
  create_time: string | null;
  messages: UserWorkTicketMessageItemRes[];
}

export interface UserWorkTicketReplyReq {
  ticket_kid: string;
  body: string;
}
