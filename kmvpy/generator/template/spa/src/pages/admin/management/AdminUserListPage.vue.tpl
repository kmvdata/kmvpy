<template>
  <q-page class="spa-page admin-user-list-page">
    <div class="spa-shell spa-shell--wide">
      <div class="admin-user-list__toolbar">
        <q-input
          v-model="searchQuery"
          dense
          outlined
          clearable
          debounce="150"
          class="admin-user-list__search"
          :label="t('adminUsers.search')"
          :placeholder="t('adminUsers.searchPlaceholder')"
        >
          <template #prepend>
            <q-icon name="search" />
          </template>
        </q-input>
        <q-select
          v-model="roleFilter"
          dense
          outlined
          emit-value
          map-options
          class="admin-user-list__filter"
          :options="roleFilterOptions"
          :label="t('adminUsers.typeFilter')"
        />
        <q-select
          v-model="stateFilter"
          dense
          outlined
          emit-value
          map-options
          class="admin-user-list__filter"
          :options="stateFilterOptions"
          :label="t('adminUsers.stateFilter')"
        />
        <q-btn
          flat
          no-caps
          color="primary"
          icon="refresh"
          :label="t('common.refresh')"
          :loading="loading"
          @click="loadUsers"
        />
        <q-btn
          unelevated
          no-caps
          color="primary"
          icon="person_add"
          :label="t('adminUsers.create')"
          @click="openCreateDialog"
        />
      </div>

      <q-banner v-if="listError" rounded class="spa-inline-alert--error q-mb-md">
        {{ listError }}
      </q-banner>

      <q-card flat bordered class="spa-card admin-user-list__table-card">
        <q-inner-loading :showing="loading" color="primary" />
        <div class="admin-user-list__table-scroll">
          <table class="data-table admin-user-list__table">
            <thead>
              <tr>
                <th>{{ t("adminUsers.columns.username") }}</th>
                <th>{{ t("adminUsers.columns.email") }}</th>
                <th>{{ t("adminUsers.columns.nickname") }}</th>
                <th>{{ t("adminUsers.columns.type") }}</th>
                <th>{{ t("adminUsers.columns.state") }}</th>
                <th>{{ t("adminUsers.columns.createTime") }}</th>
                <th class="admin-table-th--actions">
                  {{ t("adminUsers.columns.action") }}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr v-if="!loading && filteredRows.length === 0">
                <td colspan="7" class="admin-user-list__empty">
                  {{ t("adminUsers.noUsers") }}
                </td>
              </tr>
              <tr v-for="row in filteredRows" :key="row.kid">
                <td>
                  <div class="admin-user-list__user-cell">
                    <q-avatar
                      size="34px"
                      color="primary"
                      text-color="on-primary"
                      font-size="13px"
                    >
                      {{ avatarLetter(row) }}
                    </q-avatar>
                    <div class="admin-user-list__identity">
                      <div class="admin-user-list__main-text">
                        {{ row.username || t("common.emptyValue") }}
                      </div>
                      <div class="admin-user-list__meta mono">{{ row.kid }}</div>
                    </div>
                  </div>
                </td>
                <td>{{ row.email || t("common.emptyValue") }}</td>
                <td>{{ row.nickname || t("common.emptyValue") }}</td>
                <td>
                  <q-badge outline color="primary">
                    {{ roleLabel(row.user_type) }}
                  </q-badge>
                </td>
                <td>
                  <q-badge :color="stateColor(row.state)" outline>
                    {{ stateLabel(row.state) }}
                  </q-badge>
                </td>
                <td class="mono">{{ formatDate(row.create_time) }}</td>
                <td class="admin-table-td--actions">
                  <q-btn
                    flat
                    dense
                    no-caps
                    color="primary"
                    icon="visibility"
                    :label="t('common.details')"
                    @click="openUserDialog(row)"
                  />
                </td>
              </tr>
            </tbody>
          </table>
        </div>
        <div class="admin-user-list__footer mono">
          {{ t("adminUsers.showing", { shown: filteredRows.length, total }) }}
        </div>
      </q-card>
    </div>

    <q-dialog v-model="detailDialogOpen">
      <q-card class="spa-card spa-dialog-card spa-dialog-card--md signal-tracker-admin-dialog">
        <q-card-section class="row items-center q-pb-none">
          <div class="spa-section-title">{{ t("adminUsers.detailDialog") }}</div>
          <q-space />
          <q-btn v-close-popup icon="close" flat round dense />
        </q-card-section>
        <q-card-section v-if="detailRow" class="admin-user-list__detail">
          <div class="admin-user-list__detail-head">
            <q-avatar
              size="44px"
              color="primary"
              text-color="on-primary"
              font-size="16px"
            >
              {{ avatarLetter(detailRow) }}
            </q-avatar>
            <div>
              <div class="admin-user-list__detail-name">
                {{ userDisplayName(detailRow) }}
              </div>
              <div class="admin-user-list__meta mono">{{ detailRow.kid }}</div>
            </div>
          </div>

          <div class="admin-user-list__detail-grid">
            <div>
              <span>{{ t("adminUsers.columns.email") }}</span>
              <strong>{{ detailRow.email || t("common.emptyValue") }}</strong>
            </div>
            <div>
              <span>{{ t("adminUsers.columns.username") }}</span>
              <strong>{{ detailRow.username || t("common.emptyValue") }}</strong>
            </div>
            <div>
              <span>{{ t("adminUsers.columns.nickname") }}</span>
              <strong>{{ detailRow.nickname || t("common.emptyValue") }}</strong>
            </div>
            <div>
              <span>{{ t("adminUsers.columns.createTime") }}</span>
              <strong>{{ formatDate(detailRow.create_time) }}</strong>
            </div>
          </div>

          <q-select
            v-model="detailRole"
            dense
            outlined
            emit-value
            map-options
            :options="roleOptions"
            :label="t('adminUsers.columns.type')"
            :disable="isSelfRow(detailRow.kid) || roleUpdating"
          />
          <q-btn
            flat
            no-caps
            color="primary"
            icon="manage_accounts"
            class="admin-user-list__full-button"
            :label="t('adminUsers.saveRole')"
            :loading="roleUpdating"
            :disable="isSelfRow(detailRow.kid)"
            @click="submitRoleUpdate"
          />

          <q-separator />

          <div class="spa-section-title">{{ t("adminUsers.resetPassword") }}</div>
          <q-input
            v-model="resetPassword"
            dense
            outlined
            type="password"
            autocomplete="new-password"
            :label="t('adminUsers.newPassword')"
            :disable="isSelfRow(detailRow.kid) || resetPasswordSubmitting"
          />
          <q-input
            v-model="resetPassword2"
            dense
            outlined
            type="password"
            autocomplete="new-password"
            :label="t('adminUsers.confirmNewPassword')"
            :disable="isSelfRow(detailRow.kid) || resetPasswordSubmitting"
          />
          <q-btn
            flat
            no-caps
            color="primary"
            icon="password"
            class="admin-user-list__full-button"
            :label="t('common.savePassword')"
            :loading="resetPasswordSubmitting"
            :disable="isSelfRow(detailRow.kid)"
            @click="submitResetPassword"
          />

          <q-separator />

          <div class="admin-user-list__dialog-actions">
            <q-btn
              flat
              no-caps
              :color="detailRow.state === 1 ? 'warning' : 'primary'"
              :icon="detailRow.state === 1 ? 'block' : 'check_circle'"
              :label="
                detailRow.state === 1
                  ? t('adminUsers.disable')
                  : t('adminUsers.enable')
              "
              :disable="isSelfRow(detailRow.kid)"
              @click="toggleUserState(detailRow)"
            />
            <q-btn
              flat
              no-caps
              color="negative"
              icon="delete"
              :label="t('common.delete')"
              :disable="isSelfRow(detailRow.kid)"
              @click="confirmDeleteUser(detailRow)"
            />
          </div>
        </q-card-section>
      </q-card>
    </q-dialog>

    <q-dialog v-model="createDialogOpen" persistent>
      <q-card class="spa-card spa-dialog-card spa-dialog-card--md signal-tracker-admin-dialog">
        <q-card-section class="row items-center q-pb-none">
          <div class="spa-section-title">{{ t("adminUsers.createDialog") }}</div>
          <q-space />
          <q-btn v-close-popup icon="close" flat round dense @click="resetCreateForm" />
        </q-card-section>
        <q-card-section>
          <q-form class="q-gutter-md" @submit.prevent="submitCreateUser">
            <q-input
              v-model="createForm.username"
              :label="t('adminUsers.columns.username')"
              outlined
              dense
              no-error-icon
            />
            <q-input
              v-model="createForm.password"
              :label="t('auth.password')"
              type="password"
              outlined
              dense
              no-error-icon
            />
            <q-select
              v-model="createForm.user_type"
              :options="roleOptions"
              :label="t('adminUsers.columns.type')"
              outlined
              dense
              emit-value
              map-options
            />
          </q-form>
        </q-card-section>
        <q-card-actions align="right" class="q-px-md q-pb-md">
          <q-btn v-close-popup flat no-caps :label="t('common.cancel')" @click="resetCreateForm" />
          <q-btn
            color="primary"
            unelevated
            no-caps
            :label="t('common.confirm')"
            :loading="createSubmitting"
            @click="submitCreateUser"
          />
        </q-card-actions>
      </q-card>
    </q-dialog>
  </q-page>
</template>

<script setup lang="ts">
import { computed, onMounted, ref } from "vue";
import { Dialog, useQuasar } from "quasar";
import { useI18n } from "vue-i18n";
import { useRouter } from "vue-router";

import { ApiAdminOp } from "src/network/api/admin/admin_op";
import type { AdminUserListItemRes } from "src/network/dto/admin/admin_op";

type RoleValue = 0 | 1 | 2;
type StateValue = 0 | 1;

const $q = useQuasar();
const router = useRouter();
const { t } = useI18n();

const loading = ref(false);
const listError = ref("");
const rows = ref<AdminUserListItemRes[]>([]);
const total = ref(0);
const myKid = ref<string | null>(null);

const searchQuery = ref("");
const roleFilter = ref<RoleValue | null>(null);
const stateFilter = ref<StateValue | null>(null);

const detailDialogOpen = ref(false);
const detailRow = ref<AdminUserListItemRes | null>(null);
const detailRole = ref<RoleValue>(0);
const roleUpdating = ref(false);
const resetPassword = ref("");
const resetPassword2 = ref("");
const resetPasswordSubmitting = ref(false);

const createDialogOpen = ref(false);
const createSubmitting = ref(false);
const createForm = ref<{
  username: string;
  password: string;
  user_type: RoleValue;
}>({
  username: "",
  password: "",
  user_type: 0,
});

const roleOptions = computed(() => [
  { label: t("adminUsers.roles.normal"), value: 0 },
  { label: t("adminUsers.roles.admin"), value: 1 },
  { label: t("adminUsers.roles.reviewer"), value: 2 },
]);

const roleFilterOptions = computed(() => [
  { label: t("adminUsers.allTypes"), value: null },
  ...roleOptions.value,
]);

const stateFilterOptions = computed(() => [
  { label: t("adminUsers.allStates"), value: null },
  { label: t("adminUsers.available"), value: 1 },
  { label: t("adminUsers.unavailable"), value: 0 },
]);

const filteredRows = computed(() => {
  const query = searchQuery.value.trim().toLowerCase();
  return rows.value.filter((row) => {
    const matchesQuery =
      !query ||
      row.kid.toLowerCase().includes(query) ||
      (row.email ?? "").toLowerCase().includes(query) ||
      (row.username ?? "").toLowerCase().includes(query) ||
      (row.nickname ?? "").toLowerCase().includes(query);
    const matchesRole =
      roleFilter.value === null || normalizeRole(row.user_type) === roleFilter.value;
    const matchesState = stateFilter.value === null || row.state === stateFilter.value;
    return matchesQuery && matchesRole && matchesState;
  });
});

function normalizeRole(userType: number): RoleValue {
  if (userType === 1 || userType === 100) {
    return 1;
  }
  if (userType === 2) {
    return 2;
  }
  return 0;
}

function roleLabel(userType: number): string {
  const role = normalizeRole(userType);
  if (role === 1) {
    return t("adminUsers.roles.admin");
  }
  if (role === 2) {
    return t("adminUsers.roles.reviewer");
  }
  return t("adminUsers.roles.normal");
}

function stateLabel(state: number): string {
  return state === 1 ? t("adminUsers.available") : t("adminUsers.unavailable");
}

function stateColor(state: number): string {
  return state === 1 ? "positive" : "negative";
}

function formatDate(raw: string | null): string {
  if (!raw) {
    return "-";
  }
  const text = raw.trim();
  if (text.length >= 10 && text[4] === "-" && text[7] === "-") {
    return text.slice(0, 10);
  }
  return text || "-";
}

function userDisplayName(row: AdminUserListItemRes): string {
  return row.nickname || row.username || row.email || row.kid;
}

function avatarLetter(row: AdminUserListItemRes): string {
  return userDisplayName(row).trim().slice(0, 1).toUpperCase() || "U";
}

function isSelfRow(kid: string): boolean {
  return myKid.value !== null && kid === myKid.value;
}

function resolveErrorMessage(error: unknown, fallbackKey: string): string {
  return error instanceof Error && error.message ? error.message : t(fallbackKey);
}

async function loadMyProfile() {
  try {
    const profile = await ApiAdminOp.getUserProfile();
    myKid.value = profile.kid;
  } catch {
    myKid.value = null;
  }
}

async function loadUsers() {
  loading.value = true;
  listError.value = "";
  try {
    const res = await ApiAdminOp.adminUserList({ page: 1, size: 1000 });
    rows.value = res.items;
    total.value = res.total;
  } catch (error) {
    listError.value = resolveErrorMessage(error, "adminUsers.loadFailed");
    $q.notify({
      type: "negative",
      message: listError.value,
      actions: [
        {
          label: t("common.goLogin"),
          color: "on-status",
          handler: () => void router.push({ name: "admin-login" }),
        },
      ],
    });
  } finally {
    loading.value = false;
  }
}

function openUserDialog(row: AdminUserListItemRes) {
  detailRow.value = row;
  detailRole.value = normalizeRole(row.user_type);
  resetPassword.value = "";
  resetPassword2.value = "";
  detailDialogOpen.value = true;
}

function syncDetailRowAfterList(kid: string) {
  const updated = rows.value.find((row) => row.kid === kid);
  if (updated && detailRow.value?.kid === kid) {
    detailRow.value = updated;
    detailRole.value = normalizeRole(updated.user_type);
  }
}

function openCreateDialog() {
  resetCreateForm();
  createDialogOpen.value = true;
}

function resetCreateForm() {
  createForm.value = { username: "", password: "", user_type: 0 };
}

async function submitCreateUser() {
  const username = createForm.value.username.trim();
  if (!username || createForm.value.password.length < 6) {
    $q.notify({ type: "negative", message: t("adminUsers.validUserRequired") });
    return;
  }
  createSubmitting.value = true;
  try {
    await ApiAdminOp.createUser({
      username,
      password: createForm.value.password,
      user_type: createForm.value.user_type,
    });
    $q.notify({ type: "positive", message: t("adminUsers.userCreated") });
    createDialogOpen.value = false;
    resetCreateForm();
    await loadUsers();
  } catch (error) {
    $q.notify({
      type: "negative",
      message: resolveErrorMessage(error, "adminUsers.createFailed"),
    });
  } finally {
    createSubmitting.value = false;
  }
}

async function submitRoleUpdate() {
  if (!detailRow.value || isSelfRow(detailRow.value.kid)) {
    return;
  }
  roleUpdating.value = true;
  try {
    await ApiAdminOp.updateUserRole({
      kid: detailRow.value.kid,
      user_type: detailRole.value,
    });
    $q.notify({ type: "positive", message: t("adminUsers.roleUpdated") });
    await loadUsers();
    syncDetailRowAfterList(detailRow.value.kid);
  } catch (error) {
    $q.notify({
      type: "negative",
      message: resolveErrorMessage(error, "adminUsers.roleUpdateFailed"),
    });
  } finally {
    roleUpdating.value = false;
  }
}

async function submitResetPassword() {
  if (!detailRow.value) {
    return;
  }
  if (isSelfRow(detailRow.value.kid)) {
    $q.notify({ type: "warning", message: t("adminUsers.cannotEditSelfPassword") });
    return;
  }
  if (resetPassword.value.length < 6) {
    $q.notify({ type: "negative", message: t("adminUsers.newPasswordTooShort") });
    return;
  }
  if (resetPassword.value !== resetPassword2.value) {
    $q.notify({ type: "negative", message: t("adminUsers.passwordMismatch") });
    return;
  }
  resetPasswordSubmitting.value = true;
  try {
    await ApiAdminOp.resetUserPassword({
      kid: detailRow.value.kid,
      password: resetPassword.value,
    });
    $q.notify({ type: "positive", message: t("adminUsers.passwordUpdated") });
    resetPassword.value = "";
    resetPassword2.value = "";
  } catch (error) {
    $q.notify({
      type: "negative",
      message: resolveErrorMessage(error, "adminUsers.saveFailed"),
    });
  } finally {
    resetPasswordSubmitting.value = false;
  }
}

function toggleUserState(row: AdminUserListItemRes) {
  const next: StateValue = row.state === 1 ? 0 : 1;
  const verb = next === 0 ? t("adminUsers.disable") : t("adminUsers.enable");
  Dialog.create({
    title: t("adminUsers.confirmToggleTitle", { verb }),
    message: t("adminUsers.confirmToggleMessage", {
      verb,
      user: userDisplayName(row),
    }),
    cancel: true,
    persistent: true,
  }).onOk(() => {
    void updateUserState(row, next, verb);
  });
}

async function updateUserState(
  row: AdminUserListItemRes,
  state: StateValue,
  verb: string,
) {
  try {
    await ApiAdminOp.updateUserState({ kid: row.kid, state });
    $q.notify({ type: "positive", message: t("adminUsers.toggled", { verb }) });
    await loadUsers();
    syncDetailRowAfterList(row.kid);
  } catch (error) {
    $q.notify({
      type: "negative",
      message: resolveErrorMessage(error, "adminUsers.operationFailed"),
    });
  }
}

function confirmDeleteUser(row: AdminUserListItemRes) {
  Dialog.create({
    title: t("adminUsers.confirmDeleteTitle"),
    message: t("adminUsers.confirmDeleteMessage", { user: userDisplayName(row) }),
    ok: { label: t("common.delete"), color: "negative" },
    cancel: true,
    persistent: true,
  }).onOk(() => {
    void deleteUser(row);
  });
}

async function deleteUser(row: AdminUserListItemRes) {
  try {
    await ApiAdminOp.deleteUser({ kid: row.kid });
    $q.notify({ type: "positive", message: t("adminUsers.deleted") });
    if (detailRow.value?.kid === row.kid) {
      detailDialogOpen.value = false;
      detailRow.value = null;
    }
    await loadUsers();
  } catch (error) {
    $q.notify({
      type: "negative",
      message: resolveErrorMessage(error, "adminUsers.deleteFailed"),
    });
  }
}

onMounted(() => {
  void loadMyProfile();
  void loadUsers();
});
</script>

<style scoped>
.admin-user-list__toolbar {
  display: flex;
  align-items: center;
  gap: 10px;
  flex-wrap: wrap;
  margin-bottom: 14px;
}

.admin-user-list__search {
  flex: 1 1 280px;
}

.admin-user-list__filter {
  width: 160px;
}

.admin-user-list__table-card {
  position: relative;
  overflow: hidden;
}

.admin-user-list__table-scroll {
  overflow-x: auto;
}

.admin-user-list__table {
  min-width: 860px;
}

.admin-user-list__user-cell,
.admin-user-list__detail-head,
.admin-user-list__dialog-actions {
  display: flex;
  align-items: center;
  gap: 12px;
}

.admin-user-list__identity {
  min-width: 0;
}

.admin-user-list__main-text,
.admin-user-list__detail-name {
  font-weight: 700;
  color: var(--text-primary);
}

.admin-user-list__meta {
  margin-top: 2px;
  color: var(--text-muted);
  font-size: var(--spa-font-size-overline);
}

.admin-user-list__empty {
  padding: 28px;
  text-align: center;
  color: var(--text-muted);
}

.admin-user-list__footer {
  padding: 12px 14px;
  border-top: 1px solid var(--border);
  color: var(--text-muted);
  font-size: var(--spa-font-size-small);
}

.admin-user-list__detail {
  display: flex;
  flex-direction: column;
  gap: 14px;
}

.admin-user-list__detail-grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 10px;
}

.admin-user-list__detail-grid > div {
  min-width: 0;
  border: 1px solid var(--border);
  border-radius: var(--spa-radius-md);
  background: var(--bg-secondary);
  padding: 10px 12px;
}

.admin-user-list__detail-grid span {
  display: block;
  margin-bottom: 4px;
  color: var(--text-muted);
  font-size: var(--spa-font-size-overline);
}

.admin-user-list__detail-grid strong {
  display: block;
  color: var(--text-primary);
  font-size: var(--spa-font-size-small);
  overflow-wrap: anywhere;
}

.admin-user-list__full-button {
  align-self: flex-start;
}

@media (max-width: 720px) {
  .admin-user-list__filter {
    width: 100%;
  }

  .admin-user-list__toolbar :deep(.q-btn) {
    flex: 1 1 auto;
  }

  .admin-user-list__detail-grid {
    grid-template-columns: 1fr;
  }
}
</style>
