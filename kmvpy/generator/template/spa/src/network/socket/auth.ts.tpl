export const normalizeAuthorization = (authorization: string | null | undefined) => {
  const value = authorization?.trim();
  if (!value) {
    return '';
  }
  return /^Bearer\s+/i.test(value) ? value : `Bearer ${value}`;
};

export const isAuthorizationUsable = (authorization: string) => {
  const normalizedAuthorization = normalizeAuthorization(authorization);
  return Boolean(normalizedAuthorization);
};
