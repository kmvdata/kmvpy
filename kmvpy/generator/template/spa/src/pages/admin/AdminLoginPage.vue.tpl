<template>
  <q-layout view="lHh Lpr lFf" class="spa-layout admin-layout signal-tracker-page signal-tracker-admin admin-login-page">
    <q-page-container>
      <q-page class="flex flex-center q-pa-md column">
        <router-link to="/" class="admin-layout__logo-link admin-login-logo q-mb-lg" :aria-label="t('common.siteHome')">
          <AppLogo size="md" />
        </router-link>
        <q-card flat bordered class="spa-card spa-login-card spa-login-card--admin">
          <q-card-section>
            <div class="spa-card__label">{{ t('layouts.adminTitle') }}</div>
            <div class="spa-card__value">{{ t('auth.adminLoginTitle') }}</div>
            <div class="spa-card__hint">{{ t('auth.adminLoginHint') }}</div>
          </q-card-section>
          <q-separator class="spa-separator" inset />
          <q-card-section>
            <q-banner v-if="statusMessage" rounded dense class="spa-banner" :class="statusClass">
              {{ statusMessage }}
            </q-banner>
          </q-card-section>
          <q-card-section>
            <q-form class="column q-gutter-md" @submit.prevent="handleLogin">
              <q-input
                v-model.trim="account"
                outlined
                type="text"
                :label="t('auth.account')"
                autocomplete="username"
              />
              <q-input
                v-model="password"
                outlined
                :type="showPassword ? 'text' : 'password'"
                :label="t('auth.password')"
                autocomplete="current-password"
              >
                <template #append>
                  <q-btn
                    type="button"
                    flat
                    dense
                    round
                    color="primary"
                    :icon="showPassword ? 'visibility_off' : 'visibility'"
                    :aria-label="t(showPassword ? 'authPage.register.toggleAriaHide' : 'authPage.register.toggleAriaShow')"
                    @click="showPassword = !showPassword"
                  />
                </template>
              </q-input>
              <q-btn type="submit" color="primary" unelevated no-caps :loading="isSubmitting" :label="t('auth.adminLogin')" />
              <q-btn flat no-caps color="primary" :label="t('auth.userLoginEntry')" to="/login" />
            </q-form>
          </q-card-section>
        </q-card>
      </q-page>
    </q-page-container>
  </q-layout>
</template>

<script setup lang="ts">
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';

import AppLogo from 'src/components/AppLogo.vue';
import { getStoredAdminAuthorization, setStoredAdminAuthorization } from 'src/boot/axios_admin';
import { ApiAdminOp } from 'src/network/api/admin/admin_op';

const router = useRouter();
const route = useRoute();
const { t } = useI18n();
const account = ref('');
const password = ref('');
const showPassword = ref(false);
const isSubmitting = ref(false);
const statusMessage = ref('');
const statusType = ref<'info' | 'success' | 'error'>('info');

const statusClass = computed(() => {
  if (statusType.value === 'success') {
    return 'spa-banner--success';
  }
  if (statusType.value === 'error') {
    return 'spa-banner--error';
  }
  return 'spa-banner--info';
});

const getRedirectTarget = () => {
  const redirect = route.query.redirect;
  if (typeof redirect === 'string' && redirect.startsWith('/') && !redirect.startsWith('//')) {
    return redirect;
  }
  return undefined;
};

/** 与 /api/admin/email/login 语义对齐：明显为邮箱时走邮箱匹配；否则走 /api/admin/username/login（含 @ 也仅按用户名）。 */
function isLikelyEmailInput(raw: string): boolean {
  const t = raw.trim();
  if (!t.includes('@')) {
    return false;
  }
  const parts = t.split('@');
  if (parts.length !== 2) {
    return false;
  }
  const [local, domain] = parts;
  if (!local || !domain) {
    return false;
  }
  // 要求域名段含 .，避免 user@name 这类用户名被误走邮箱库
  return domain.includes('.');
}

const handleLogin = async () => {
  const raw = account.value.trim();
  account.value = raw;
  if (!raw || !password.value) {
    statusMessage.value = t('auth.errors.adminRequired');
    statusType.value = 'error';
    return;
  }

  isSubmitting.value = true;
  statusMessage.value = '';
  try {
    const authRes = isLikelyEmailInput(raw)
      ? await ApiAdminOp.emailLogin({
          account: raw.toLowerCase(),
          password: password.value,
        })
      : await ApiAdminOp.usernameLogin({
          username: raw,
          password: password.value,
        });
    setStoredAdminAuthorization(`${authRes.token_type} ${authRes.token}`);
    statusMessage.value = t('auth.messages.adminLoginSuccess');
    statusType.value = 'success';
    await router.push(getRedirectTarget() ?? { name: 'admin-home' });
  } catch (e) {
    statusMessage.value = e instanceof Error ? e.message : t('auth.errors.adminLoginFailed');
    statusType.value = 'error';
  } finally {
    isSubmitting.value = false;
  }
};

onMounted(() => {
  if (getStoredAdminAuthorization()) {
    void router.replace(getRedirectTarget() ?? { name: 'admin-home' });
  }
});
</script>
