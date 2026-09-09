<template>
  <q-page class="spa-page admin-system-settings-page">
    <div class="spa-shell admin-system-settings">
      <q-card flat bordered class="spa-card admin-system-settings__ops-card">
        <div class="admin-system-settings__ops-copy">
          <div class="spa-section-title">
            {{ t("adminSystemSettings.operations.title") }}
          </div>
          <div class="spa-page-subtitle admin-system-settings__ops-subtitle">
            {{ t("adminSystemSettings.operations.subtitle") }}
          </div>
          <q-banner rounded class="spa-inline-alert--warning q-mt-md">
            {{ t("adminSystemSettings.operations.status") }}
          </q-banner>
        </div>
        <q-btn
          unelevated
          no-caps
          color="negative"
          icon="restart_alt"
          :label="
            restartLoading
              ? t('adminSystemSettings.operations.restarting')
              : t('adminSystemSettings.operations.restart')
          "
          :loading="restartLoading"
          :disable="restartLoading"
          @click="openRestartDialog"
        />
      </q-card>
    </div>
  </q-page>
</template>

<script setup lang="ts">
import { ref } from "vue";
import { Dialog, useQuasar } from "quasar";
import { useI18n } from "vue-i18n";

import { useKmvApiErrorMessage } from "src/i18n/kmv/useKmvApiErrorMessage";
import { ApiAdminSystem } from "src/network/api/admin/system";

const { t } = useI18n();
const $q = useQuasar();
const { resolveFromError } = useKmvApiErrorMessage();
const restartLoading = ref(false);
const RESTART_CONFIRM_TEXT = "RESTART_SERVICE";

function resolveErrorMessage(error: unknown): string {
  const fallback = t("adminSystemSettings.errors.restartFailed");
  const kmvMessage = resolveFromError(error);
  if (kmvMessage && kmvMessage !== t("api.kmv.fallback")) {
    return kmvMessage;
  }
  return error instanceof Error && error.message ? error.message : fallback;
}

function openRestartDialog() {
  Dialog.create({
    title: t("adminSystemSettings.dialog.restartTitle"),
    message: t("adminSystemSettings.dialog.restartMessage", {
      confirmText: RESTART_CONFIRM_TEXT,
    }),
    prompt: {
      model: "",
      type: "text",
      label: t("adminSystemSettings.dialog.restartConfirmLabel"),
    },
    cancel: {
      label: t("common.cancel"),
      flat: true,
      noCaps: true,
    },
    ok: {
      label: t("adminSystemSettings.operations.restart"),
      color: "negative",
      unelevated: true,
      noCaps: true,
    },
  }).onOk((confirmText: string) => {
    void restartService(confirmText);
  });
}

async function restartService(confirmText: string) {
  const normalized = confirmText.trim();
  if (normalized !== RESTART_CONFIRM_TEXT) {
    $q.notify({
      type: "negative",
      message: t("adminSystemSettings.errors.restartConfirmRequired"),
    });
    return;
  }

  restartLoading.value = true;
  try {
    await ApiAdminSystem.restartService({
      confirm_text: normalized,
    });
    $q.notify({
      type: "positive",
      message: t("adminSystemSettings.messages.restartAccepted"),
    });
  } catch (error) {
    $q.notify({
      type: "negative",
      message: resolveErrorMessage(error),
    });
  } finally {
    restartLoading.value = false;
  }
}
</script>

<style scoped>
.admin-system-settings {
  max-width: 960px;
}

.admin-system-settings__ops-card {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  padding: 18px;
  border-radius: var(--spa-radius-lg);
}

.admin-system-settings__ops-copy {
  min-width: 0;
}

.admin-system-settings__ops-subtitle {
  margin-top: 6px;
}

@media (max-width: 768px) {
  .admin-system-settings__ops-card {
    align-items: stretch;
    flex-direction: column;
  }
}
</style>
