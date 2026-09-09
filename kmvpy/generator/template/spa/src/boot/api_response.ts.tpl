export const API_SUCCESS_CODE = 0;
export const API_UNKNOWN_ERROR_CODE = 10000;

export interface PaginationDTO {
  page: number | null;
  size: number | null;
}

export interface ApiResponse<T = unknown> extends PaginationDTO {
  code: number;
  msg: string | null;
  data: T | null;
  total: number | null;
}

export type SocketioResponse<T = unknown> = ApiResponse<T>;

export interface ApiExceptionLike {
  error_code?: number;
  error_msg?: string;
  error_more_msg?: string | null;
  message?: string;
}

export interface UnwrapApiResponseOptions {
  fallbackMessage?: string;
  allowEmptyData?: boolean;
}

const isObject = (value: unknown): value is Record<string, unknown> =>
  value !== null && typeof value === 'object';

const hasNonEmptyText = (value: unknown): value is string =>
  typeof value === 'string' && value.trim().length > 0;

export const createApiResponse = <T = unknown>(params?: Partial<ApiResponse<T>>): ApiResponse<T> => ({
  code: params?.code ?? API_SUCCESS_CODE,
  msg: params?.msg ?? null,
  data: params?.data ?? null,
  page: params?.page ?? null,
  size: params?.size ?? null,
  total: params?.total ?? null,
});

export const isApiResponse = <T = unknown>(value: unknown): value is ApiResponse<T> => {
  if (!isObject(value)) {
    return false;
  }

  return typeof value.code === 'number' && 'data' in value;
};

export const isApiSuccess = (response: Pick<ApiResponse<unknown>, 'code'>): boolean =>
  response.code === API_SUCCESS_CODE;

export const getApiResponseMessage = (
  response: Pick<ApiResponse<unknown>, 'msg'> | null | undefined,
  fallbackMessage = '未知异常',
): string => (hasNonEmptyText(response?.msg) ? response.msg : fallbackMessage);

export class ApiResponseError<T = unknown> extends Error {
  readonly code: number;
  readonly response: ApiResponse<T>;

  constructor(response: ApiResponse<T>, fallbackMessage = '请求失败') {
    super(getApiResponseMessage(response, fallbackMessage));
    this.name = 'ApiResponseError';
    this.code = response.code;
    this.response = response;
  }
}

export const unwrapApiResponse = <T>(
  response: ApiResponse<T>,
  options: UnwrapApiResponseOptions = {},
): T => {
  const { fallbackMessage = '请求失败', allowEmptyData = false } = options;

  if (!isApiSuccess(response)) {
    throw new ApiResponseError(response, fallbackMessage);
  }

  if (!allowEmptyData && (response.data === undefined || response.data === null)) {
    throw new ApiResponseError(
      createApiResponse<T>({
        ...response,
        code: response.code || API_UNKNOWN_ERROR_CODE,
        msg: `${fallbackMessage}：服务器返回空数据`,
      }),
      fallbackMessage,
    );
  }

  return response.data as T;
};

export const normalizeExceptionToApiResponse = (error: unknown): ApiResponse<null> => {
  if (isApiResponse<null>(error)) {
    return error;
  }

  if (isObject(error)) {
    const exception = error as ApiExceptionLike;
    return createApiResponse<null>({
      code: typeof exception.error_code === 'number' ? exception.error_code : API_UNKNOWN_ERROR_CODE,
      msg: hasNonEmptyText(exception.error_more_msg)
        ? exception.error_more_msg
        : hasNonEmptyText(exception.error_msg)
          ? exception.error_msg
          : hasNonEmptyText(exception.message)
            ? exception.message
            : '未知异常',
      data: null,
    });
  }

  return createApiResponse<null>({
    code: API_UNKNOWN_ERROR_CODE,
    msg: hasNonEmptyText(error) ? error : '未知异常',
    data: null,
  });
};
