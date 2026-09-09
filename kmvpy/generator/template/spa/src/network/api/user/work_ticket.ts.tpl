import { postUserApi } from '../../../boot/axios_user';
import type {
  UserWorkTicketCreateReq,
  UserWorkTicketDetailReq,
  UserWorkTicketDetailRes,
  UserWorkTicketListReq,
  UserWorkTicketListRes,
  UserWorkTicketReplyReq,
} from '../../dto/user/work_ticket';

export class ApiUserWorkTicket {
  static create(requestData: UserWorkTicketCreateReq): Promise<UserWorkTicketDetailRes> {
    return postUserApi<UserWorkTicketCreateReq, UserWorkTicketDetailRes>(
      '/api/user/work_ticket/create',
      requestData,
      '创建工单失败',
    );
  }

  static list(requestData: UserWorkTicketListReq): Promise<UserWorkTicketListRes> {
    return postUserApi<UserWorkTicketListReq, UserWorkTicketListRes>(
      '/api/user/work_ticket/list',
      requestData,
      '获取工单列表失败',
    );
  }

  static detail(requestData: UserWorkTicketDetailReq): Promise<UserWorkTicketDetailRes> {
    return postUserApi<UserWorkTicketDetailReq, UserWorkTicketDetailRes>(
      '/api/user/work_ticket/detail',
      requestData,
      '获取工单详情失败',
    );
  }

  static reply(requestData: UserWorkTicketReplyReq): Promise<UserWorkTicketDetailRes> {
    return postUserApi<UserWorkTicketReplyReq, UserWorkTicketDetailRes>(
      '/api/user/work_ticket/reply',
      requestData,
      '发送消息失败',
    );
  }
}
