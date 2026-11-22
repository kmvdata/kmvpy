<template>
  <q-page class="auth-page">
    <div class="auth-bg">
      <div class="auth-orb auth-orb--one"></div>
      <div class="auth-orb auth-orb--two"></div>
      <div class="auth-grid"></div>
    </div>

    <section class="auth-shell">
      <div class="auth-copy">
        <a href="/" class="brand" @click.prevent="router.push('/')">
          <AppLogo size="md" />
        </a>

        <h1>
          {{ t('authPage.heroTitleBefore') }}<span class="gradient-text">{{ t('layouts.siteTitle') }}</span
          >{{ t('authPage.heroTitleAfter') }}
        </h1>
        <p>
          {{ t('authPage.heroLead') }}
        </p>

        <div class="copy-points">
          <div class="copy-point">
            <div class="copy-point__icon">{{ t('authPage.point1Badge') }}</div>
            <div>
              <strong>{{ t('authPage.point1Title') }}</strong>
              <span>{{ t('authPage.point1Desc') }}</span>
            </div>
          </div>
          <div class="copy-point">
            <div class="copy-point__icon">{{ t('authPage.point2Badge') }}</div>
            <div>
              <strong>{{ t('authPage.point2Title') }}</strong>
              <span>{{ t('authPage.point2Desc') }}</span>
            </div>
          </div>
        </div>
      </div>

      <div class="auth-card">
        <div class="auth-switcher">
          <button
            type="button"
            class="auth-switcher__item"
            :class="{ 'auth-switcher__item--active': mode === 'login' }"
            @click="switchMode('login')"
          >
            {{ t('authPage.tabs.login') }}
          </button>
          <button
            type="button"
            class="auth-switcher__item"
            :class="{ 'auth-switcher__item--active': mode === 'register' }"
            @click="switchMode('register')"
          >
            {{ t('authPage.tabs.register') }}
          </button>
        </div>

        <div v-if="statusMessage" class="status-banner" :class="`status-banner--${statusType}`">
          {{ statusMessage }}
        </div>

        <form v-if="mode === 'login'" class="auth-form" @submit.prevent="handleLogin">
          <div class="auth-form__header">
            <div class="section-label">{{ t('authPage.login.eyebrow') }}</div>
            <h2>{{ t('authPage.login.title') }}</h2>
            <p>{{ t('authPage.login.subtitle') }}</p>
          </div>

          <label class="field">
            <span class="field__label">{{ t('authPage.login.fieldAccountLabel') }}</span>
            <input
              v-model.trim="loginForm.account"
              class="field__input"
              type="text"
              autocomplete="username"
              :placeholder="t('authPage.login.fieldAccountPlaceholder')"
            />
          </label>

          <label class="field">
            <span class="field__label">{{ t('authPage.login.fieldPasswordLabel') }}</span>
            <input
              v-model="loginForm.password"
              class="field__input"
              type="password"
              autocomplete="current-password"
              :placeholder="t('authPage.login.fieldPasswordPlaceholder')"
            />
          </label>

          <button type="submit" class="btn-primary btn-primary--full" :disabled="isLoggingIn">
            {{ loginButtonText }}
          </button>

          <div class="auth-footnote">
            {{ t('authPage.login.footLead') }}
            <button type="button" class="inline-link" @click="switchMode('register')">
              {{ t('authPage.login.footGoRegister') }}
            </button>
          </div>
        </form>

        <form v-else class="auth-form" @submit.prevent="handleRegister">
          <div class="auth-form__header">
            <div class="section-label">{{ t('authPage.register.eyebrow') }}</div>
            <h2>{{ t('authPage.register.title') }}</h2>
            <p>{{ t('authPage.register.subtitle') }}</p>
          </div>

          <label class="field">
            <span class="field__label">{{ t('authPage.register.fieldEmailLabel') }}</span>
            <input
              v-model.trim="registerForm.email"
              class="field__input"
              type="email"
              autocomplete="email"
              :placeholder="t('authPage.register.fieldEmailPlaceholder')"
            />
          </label>

          <div class="field-group">
            <label class="field field--code">
              <span class="field__label">{{ t('authPage.register.codeLabel') }}</span>
              <input
                v-model.trim="registerForm.code"
                class="field__input"
                inputmode="numeric"
                maxlength="6"
                :placeholder="t('authPage.register.codePlaceholder')"
              />
            </label>
            <button
              type="button"
              class="btn-ghost btn-ghost--code"
              :disabled="sendCodeCountdown > 0 || isSendingCode"
              @click="handleSendCode"
            >
              {{ sendCodeButtonText }}
            </button>
          </div>

          <label class="field">
            <span class="field__label">{{ t('authPage.register.passwordLabel') }}</span>
            <div class="field__control">
              <input
                v-model="registerForm.password"
                class="field__input field__input--with-action"
                :type="showRegisterPassword ? 'text' : 'password'"
                autocomplete="new-password"
                :placeholder="t('authPage.register.passwordPlaceholder')"
              />
              <button
                type="button"
                class="field__toggle"
                :aria-label="
                  showRegisterPassword
                    ? t('authPage.register.toggleAriaHide')
                    : t('authPage.register.toggleAriaShow')
                "
                @click="showRegisterPassword = !showRegisterPassword"
              >
                {{
                  showRegisterPassword
                    ? t('authPage.register.toggleHide')
                    : t('authPage.register.toggleShow')
                }}
              </button>
            </div>
          </label>

          <label class="field">
            <span class="field__label">{{ t('authPage.register.confirmPasswordLabel') }}</span>
            <div class="field__control">
              <input
                v-model="registerForm.confirmPassword"
                class="field__input field__input--with-action"
                :type="showRegisterConfirmPassword ? 'text' : 'password'"
                autocomplete="new-password"
                :placeholder="t('authPage.register.confirmPasswordPlaceholder')"
              />
              <button
                type="button"
                class="field__toggle"
                :aria-label="
                  showRegisterConfirmPassword
                    ? t('authPage.register.toggleAriaHide')
                    : t('authPage.register.toggleAriaShow')
                "
                @click="showRegisterConfirmPassword = !showRegisterConfirmPassword"
              >
                {{
                  showRegisterConfirmPassword
                    ? t('authPage.register.toggleHide')
                    : t('authPage.register.toggleShow')
                }}
              </button>
            </div>
          </label>

          <label class="field">
            <span class="field__label">{{ t('authPage.register.invitationOptional') }}</span>
            <input
              v-model.trim="registerForm.invitationCode"
              class="field__input"
              :class="{ 'field__input--readonly': isInvitationCodeLocked }"
              maxlength="16"
              :placeholder="invitationPlaceholder"
              :readonly="isInvitationCodeLocked"
            />
          </label>

          <div v-if="sendCodeHint" class="hint-text">
            {{ sendCodeHint }}
          </div>

          <button type="submit" class="btn-primary btn-primary--full" :disabled="isRegistering">
            {{ registerButtonText }}
          </button>

          <div class="auth-footnote">
            {{ t('authPage.register.footLead') }}
            <button type="button" class="inline-link" @click="switchMode('login')">{{
              t('authPage.register.footGoLogin')
            }}</button>
          </div>
        </form>
      </div>
    </section>
  </q-page>
</template>

<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter, type LocationQuery, type LocationQueryValue } from 'vue-router';

import AppLogo from 'src/components/AppLogo.vue';
import { setStoredUserAuthorization } from 'src/boot/axios_user';
import { extractKmvApiErrorPayload } from 'src/i18n/kmv/extractKmvApiErrorPayload';
import { useKmvApiErrorMessage } from 'src/i18n/kmv/useKmvApiErrorMessage';
import { ApiUserOp } from 'src/network/api/user/user_op';
import type { EmailAuthRes } from 'src/network/dto/user/user_op';

type AuthMode = 'login' | 'register';
type StatusType = 'info' | 'success' | 'error';

const LAST_REGISTERED_EMAIL_KEY = 'signal-tracker:last-registered-email';
const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const PHONE_PATTERN = /^1[3-9]\d{9}$/;
const USERNAME_PATTERN = /^[A-Za-z][A-Za-z0-9_]{0,63}$/;
const VERIFY_CODE_PATTERN = /^\d{6}$/;
const SEND_CODE_COUNTDOWN_SECONDS = 60;

const route = useRoute();
const router = useRouter();
const { t } = useI18n();
const { resolveFromPayload } = useKmvApiErrorMessage();

const getRedirectTarget = () => {
  const redirect = route.query.redirect;
  if (typeof redirect === 'string' && redirect.startsWith('/') && !redirect.startsWith('//')) {
    return redirect;
  }
  return undefined;
};

const getQueryValue = (value?: LocationQueryValue | LocationQueryValue[]) =>
  (Array.isArray(value) ? value[0] : value) ?? '';
const normalizeEmail = (email: string) => email.trim().toLowerCase();
const normalizeInvitationCode = (code: string) => code.trim().toUpperCase();
const getInvitationCodeFromQuery = (query: LocationQuery) =>
  normalizeInvitationCode(
    getQueryValue(
      query.invitation_code ?? query.invitationCode ?? query.invite_code ?? query.inviteCode,
    ),
  );
const getModeFromQuery = (query: LocationQuery): AuthMode =>
  getQueryValue(query.mode) === 'register' ||
  (!getQueryValue(query.mode) && Boolean(getInvitationCodeFromQuery(query)))
    ? 'register'
    : 'login';

const lockedInvitationCode = ref(getInvitationCodeFromQuery(route.query));
const mode = computed<AuthMode>(() => getModeFromQuery(route.query));
const statusMessage = ref('');
const statusType = ref<StatusType>('info');
const sendCodeCountdown = ref(0);
const sendCodeHint = ref('');
const lastCodeSentEmail = ref('');
const isSendingCode = ref(false);
const isRegistering = ref(false);
const isLoggingIn = ref(false);
const showRegisterPassword = ref(false);
const showRegisterConfirmPassword = ref(false);

const invitationPlaceholder = computed(() =>
  isInvitationCodeLocked.value
    ? t('authPage.register.invitationPlaceholderFilled')
    : t('authPage.register.invitationPlaceholderOpen'),
);

const loginForm = reactive({
  account: '',
  password: '',
});

const registerForm = reactive({
  email: '',
  code: '',
  password: '',
  confirmPassword: '',
  invitationCode: '',
});

let countdownTimer: ReturnType<typeof setInterval> | null = null;

const sendCodeButtonText = computed(() =>
  isSendingCode.value
    ? t('authPage.register.sendCodeLoading')
    : sendCodeCountdown.value > 0
      ? t('authPage.register.sendCodeCooldown', { seconds: sendCodeCountdown.value })
      : t('authPage.register.sendCode'),
);

const loginButtonText = computed(() =>
  isLoggingIn.value ? t('authPage.login.submitLoading') : t('authPage.login.submit'),
);

const registerButtonText = computed(() =>
  isRegistering.value ? t('authPage.register.submitLoading') : t('authPage.register.submit'),
);

const isInvitationCodeLocked = computed(() => Boolean(lockedInvitationCode.value));

const setStatus = (message: string, type: StatusType = 'info') => {
  statusMessage.value = message;
  statusType.value = type;
};

const getErrorMessage = (error: unknown, fallbackMessage: string) =>
  error instanceof Error && error.message ? error.message : fallbackMessage;

/** 业务错误按 Kmv code 走 i18n；否则沿用 Error.message 或页面兜底文案。 */
const resolveApiErrorForBanner = (error: unknown, pageFallback: string) => {
  const payload = extractKmvApiErrorPayload(error);
  if (payload !== null) {
    return resolveFromPayload(payload);
  }
  return getErrorMessage(error, pageFallback);
};

const getStatusMessageForMode = (currentMode: AuthMode) =>
  currentMode === 'login' ? t('authPage.hints.login') : t('authPage.hints.register');

const storeLastRegisteredEmail = (email: string) => {
  window.localStorage.setItem(LAST_REGISTERED_EMAIL_KEY, email);
};

const getStoredLastRegisteredEmail = () =>
  window.localStorage.getItem(LAST_REGISTERED_EMAIL_KEY) ?? '';

const assignLockedInvitationCode = () => {
  if (lockedInvitationCode.value) {
    registerForm.invitationCode = lockedInvitationCode.value;
  }
};

const validateEmail = (email: string, errorMessage: string) => {
  if (EMAIL_PATTERN.test(email)) {
    return true;
  }

  setStatus(errorMessage, 'error');
  return false;
};

const resetRegisterFlowState = () => {
  registerForm.code = '';
  registerForm.password = '';
  registerForm.confirmPassword = '';
  registerForm.invitationCode = '';
  showRegisterPassword.value = false;
  showRegisterConfirmPassword.value = false;
  sendCodeHint.value = '';
  lastCodeSentEmail.value = '';
  stopCountdown();
  sendCodeCountdown.value = 0;
};

const validateRegisterForm = (email: string) => {
  if (!validateEmail(email, t('authPage.errors.invalidRegisterEmail'))) {
    return false;
  }

  if (!VERIFY_CODE_PATTERN.test(registerForm.code)) {
    setStatus(t('authPage.errors.verifyCodeDigits'), 'error');
    return false;
  }

  if (registerForm.password.length < 6) {
    setStatus(t('authPage.errors.passwordMin'), 'error');
    return false;
  }

  if (registerForm.password !== registerForm.confirmPassword) {
    setStatus(t('authPage.errors.passwordMismatch'), 'error');
    return false;
  }

  return true;
};

const resolveLoginAccountKind = (account: string): 'email' | 'phone' | 'username' | null => {
  const normalized = account.trim();
  if (!normalized) {
    return null;
  }
  if (normalized.includes('@')) {
    return EMAIL_PATTERN.test(normalized) ? 'email' : null;
  }
  if (PHONE_PATTERN.test(normalized)) {
    return 'phone';
  }
  if (USERNAME_PATTERN.test(normalized)) {
    return 'username';
  }
  return null;
};

const validateLoginForm = (account: string) => {
  if (resolveLoginAccountKind(account) === null) {
    setStatus(t('authPage.errors.loginAccountUnrecognized'), 'error');
    return false;
  }

  if (!loginForm.password) {
    setStatus(t('authPage.errors.loginPasswordMissing'), 'error');
    return false;
  }

  return true;
};

const completeAuth = async (authRes: EmailAuthRes, successMessage: string) => {
  const authorization = `${authRes.token_type} ${authRes.token}`;
  const email = authRes.user.email || authRes.user.username || '';

  setStoredUserAuthorization(authorization);
  if (email) {
    storeLastRegisteredEmail(email);
  }

  setStatus(successMessage, 'success');
  await router.replace(getRedirectTarget() ?? { name: 'user-profile' });
};

const loadLastRegisteredEmail = () => {
  const savedEmail = getStoredLastRegisteredEmail();
  if (savedEmail && !loginForm.account) {
    loginForm.account = savedEmail;
  }
};

const stopCountdown = () => {
  if (countdownTimer !== null) {
    window.clearInterval(countdownTimer);
    countdownTimer = null;
  }
};

const startCountdown = () => {
  stopCountdown();
  sendCodeCountdown.value = SEND_CODE_COUNTDOWN_SECONDS;
  countdownTimer = setInterval(() => {
    if (sendCodeCountdown.value <= 1) {
      sendCodeCountdown.value = 0;
      stopCountdown();
      return;
    }
    sendCodeCountdown.value -= 1;
  }, 1000);
};

const loginEntryRouteName = computed(() => (route.name === 'login' ? 'login' : 'home-auth'));

const switchMode = (nextMode: AuthMode) => {
  void router.replace({
    name: loginEntryRouteName.value,
    query: {
      mode: nextMode,
      ...(route.query.redirect ? { redirect: route.query.redirect } : {}),
      ...(lockedInvitationCode.value ? { invitation_code: lockedInvitationCode.value } : {}),
    },
  });

  if (nextMode === 'login') {
    loadLastRegisteredEmail();
  }

  if (!statusMessage.value) {
    setStatus(getStatusMessageForMode(nextMode), 'info');
  }
};

const syncModeFromRoute = () => {
  lockedInvitationCode.value = getInvitationCodeFromQuery(route.query);
  assignLockedInvitationCode();

  if (mode.value === 'login') {
    loadLastRegisteredEmail();
  }
};

const handleSendCode = async () => {
  const email = normalizeEmail(registerForm.email);
  registerForm.email = email;

  if (!validateEmail(email, t('authPage.errors.sendCodeEmailInvalid'))) {
    sendCodeHint.value = '';
    return;
  }

  isSendingCode.value = true;
  try {
    const response = await ApiUserOp.sendEmailVerifyCode({
      email,
      scene: 'register',
    });

    startCountdown();
    lastCodeSentEmail.value = email;
    sendCodeHint.value = t('authPage.sendCodeSuffix', { serverMessage: response.message });
    setStatus(t('authPage.hints.sendSuccessDev'), 'success');
  } catch (error) {
    sendCodeHint.value = '';
    setStatus(resolveApiErrorForBanner(error, t('authPage.errors.sendFailed')), 'error');
  } finally {
    isSendingCode.value = false;
  }
};

const handleRegister = async () => {
  const email = normalizeEmail(registerForm.email);
  registerForm.email = email;

  if (!validateRegisterForm(email)) {
    return;
  }

  isRegistering.value = true;
  try {
    const invitationCode = normalizeInvitationCode(registerForm.invitationCode);
    const authRes = await ApiUserOp.emailRegister({
      email,
      verify_code: registerForm.code,
      password: registerForm.password,
      nickname: null,
      invitation_code: invitationCode || null,
    });

    storeLastRegisteredEmail(email);
    loginForm.account = email;
    loginForm.password = '';
    resetRegisterFlowState();

    await completeAuth(authRes, t('authPage.success.registerDone'));
  } catch (error) {
    setStatus(resolveApiErrorForBanner(error, t('authPage.errors.registerFailed')), 'error');
  } finally {
    isRegistering.value = false;
  }
};

const handleLogin = async () => {
  const account = loginForm.account.trim();
  loginForm.account = account;

  if (!validateLoginForm(account)) {
    return;
  }

  isLoggingIn.value = true;
  try {
    const authRes = await ApiUserOp.accountLogin({
      account,
      password: loginForm.password,
    });

    await completeAuth(authRes, t('authPage.success.loginDone'));
  } catch (error) {
    setStatus(resolveApiErrorForBanner(error, t('authPage.errors.loginFailed')), 'error');
  } finally {
    isLoggingIn.value = false;
  }
};

watch(
  () => route.fullPath,
  () => {
    syncModeFromRoute();
  },
  { immediate: true },
);

onMounted(() => {
  if (!statusMessage.value) {
    setStatus(t('authPage.hints.entry'), 'info');
  }
});

onBeforeUnmount(() => {
  stopCountdown();
});
</script>
