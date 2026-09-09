export interface AdminWorkTicketListReq {
  page: number;
  size: number;
  status: 0 | 1 | 2 | 3 | 4 | null;
}

export interface AdminWorkTicketListItemRes {
  kid: string;
  creator_user_kid: string;
  title: string;
  category: string | null;
  status: number;
  last_message_time: string | null;
  assigned_admin_kid: string | null;
  create_time: string | null;
}

export interface AdminWorkTicketListRes {
  items: AdminWorkTicketListItemRes[];
  total: number;
}

export interface AdminWorkTicketDetailReq {
  kid: string;
}

export interface AdminWorkTicketMessageItemRes {
  kid: string;
  sender_role: number;
  sender_user_kid: string;
  body: string;
  create_time: string | null;
}

export interface AdminWorkTicketDetailRes {
  kid: string;
  creator_user_kid: string;
  title: string;
  category: string | null;
  status: number;
  last_message_time: string | null;
  assigned_admin_kid: string | null;
  create_time: string | null;
  messages: AdminWorkTicketMessageItemRes[];
}

export interface AdminWorkTicketReplyReq {
  ticket_kid: string;
  body: string;
  status: 0 | 1 | 2 | 3 | 4 | null;
}

export interface AdminWorkTicketUpdateStatusReq {
  ticket_kid: string;
  status: 0 | 1 | 2 | 3 | 4;
}
