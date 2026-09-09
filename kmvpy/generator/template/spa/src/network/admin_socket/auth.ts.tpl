export const normalizeAdminSocketAuthorization = (authorization: string | null | undefined) => {
  const value = authorization?.trim();
  if (!value) {
    return '';
  }
  return /^Bearer\s+/i.test(value) ? value : `Bearer ${value}`;
};

export const isAdminSocketAuthorizationUsable = (authorization: string) => {
  const normalizedAuthorization = normalizeAdminSocketAuthorization(authorization);
  return Boolean(normalizedAuthorization);
};
