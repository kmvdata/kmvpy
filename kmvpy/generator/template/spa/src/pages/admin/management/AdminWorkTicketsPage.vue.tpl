<template>
  <q-page class="spa-page">
    <div class="spa-shell spa-shell--wide">
      <div class="spa-section-header q-mb-md">
        <div>
          <div class="spa-section-subtitle">
            {{ t('adminTickets.subtitle') }}
          </div>
        </div>
        <q-btn flat no-caps color="primary" icon="refresh" :label="t('common.refreshList')" @click="loadList" />
      </div>

      <q-banner v-if="listError" rounded class="spa-inline-alert--error q-mb-md">
        {{ listError }}
      </q-banner>

      <q-card flat bordered class="spa-card admin-work-tickets__card">
        <div class="admin-work-tickets__split row no-wrap">
          <div
            v-show="!$q.screen.lt.md || !selectedKid"
            class="admin-work-tickets__list col-12 col-md-4"
          >
            <div class="q-pa-md row items-center q-gutter-sm">
              <q-select
                v-model="filterStatus"
                class="col"
                dense
                outlined
                emit-value
                map-options
                :options="statusFilterOptions"
                :label="t('workTickets.statusFilter')"
              />
              <q-btn flat dense round icon="refresh" color="primary" @click="loadList" />
            </div>
            <q-separator />
            <q-inner-loading :showing="listLoading" color="primary" />
            <q-scroll-area class="admin-work-tickets__list-scroll">
              <q-list separator>
                <q-item v-if="!listLoading && tickets.length === 0">
                  <q-item-section class="spa-muted text-center q-py-lg">{{ t('workTickets.emptyAdminList') }}</q-item-section>
                </q-item>
                <q-item
                  v-for="ticket in tickets"
                  :key="ticket.kid"
                  v-ripple
                  clickable
                  :active="ticket.kid === selectedKid"
                  active-class="admin-work-tickets__item--active"
                  @click="selectTicket(ticket.kid)"
                >
                  <q-item-section>
                    <q-item-label class="text-weight-medium ellipsis">{{ ticket.title }}</q-item-label>
                    <q-item-label caption class="ellipsis">
                      {{ t('adminTickets.userKid', { kid: ticket.creator_user_kid }) }}
                      <span v-if="ticket.last_message_time" class="q-ml-xs">
                        · {{ formatShortTime(ticket.last_message_time) }}
                      </span>
                    </q-item-label>
                  </q-item-section>
                  <q-item-section side>
                    <q-badge :color="ticketStatusColor(ticket.status)" outline>
                      {{ ticketStatusLabel(ticket.status) }}
                    </q-badge>
                  </q-item-section>
                </q-item>
              </q-list>
            </q-scroll-area>
            <q-separator />
            <div class="row justify-center q-pa-sm">
              <q-pagination
                v-model="page"
                :max="totalPages"
                :max-pages="5"
                direction-links
                boundary-links
                dense
                color="primary"
                @update:model-value="onPageChange"
              />
            </div>
          </div>

          <div
            v-show="!$q.screen.lt.md || selectedKid"
            class="admin-work-tickets__chat col-12 col-md-8"
          >
            <template v-if="selectedKid">
              <q-toolbar class="admin-work-tickets__chat-head">
                <q-btn
                  v-if="$q.screen.lt.md"
                  flat
                  dense
                  round
                  icon="arrow_back"
                  class="q-mr-sm"
                  @click="clearSelection"
                />
                <div class="column min-width-0">
                  <div class="text-subtitle1 text-weight-bold ellipsis">
                    {{ detail?.title ?? t('common.loadingEllipsis') }}
                  </div>
                  <div v-if="detail" class="text-caption spa-muted">
                    {{ t('adminTickets.detailMeta', { ticketKid: detail.kid, userKid: detail.creator_user_kid }) }}
                  </div>
                </div>
                <q-space />
                <q-btn-dropdown
                  v-if="detail"
                  flat
                  dense
                  no-caps
                  color="primary"
                  :label="t('adminTickets.status')"
                >
                  <q-list dense>
                    <q-item
                      v-for="opt in statusMenuOptions"
                      :key="opt.value"
                      v-close-popup
                      clickable
                      @click="setTicketStatus(opt.value)"
                    >
                      <q-item-section>{{ opt.label }}</q-item-section>
                    </q-item>
                  </q-list>
                </q-btn-dropdown>
                <q-btn
                  flat
                  dense
                  no-caps
                  color="primary"
                  icon="refresh"
                  :label="t('common.refresh')"
                  @click="loadDetail"
                />
              </q-toolbar>
              <q-separator />
              <q-inner-loading :showing="detailLoading" color="primary" />
              <q-scroll-area ref="chatScrollRef" class="admin-work-tickets__messages">
                <div class="q-pa-md column q-gutter-md">
                  <q-chat-message
                    v-for="m in detail?.messages ?? []"
                    :key="m.kid"
                    :sent="m.sender_role === 1"
                    :name="m.sender_role === 1 ? t('workTickets.admin') : t('workTickets.user')"
                    :text="[m.body]"
                    :stamp="formatFullTime(m.create_time)"
                    :bg-color="m.sender_role === 1 ? 'primary' : 'surface-muted'"
                    :text-color="m.sender_role === 1 ? 'on-primary' : 'main'"
                  />
                  <template v-for="message in visiblePendingReplies" :key="message.id">
                    <div class="admin-work-tickets__pending-message">
                      <q-chat-message
                        sent
                        :name="t('workTickets.admin')"
                        :text="[message.body]"
                        :stamp="formatPendingTime(message.createdAt)"
                        :bg-color="message.status === 'failed' ? 'negative' : 'primary'"
                        :text-color="message.status === 'failed' ? 'on-status' : 'on-primary'"
                      />
                      <div
                        class="admin-work-tickets__message-state"
                        :class="{
                          'admin-work-tickets__message-state--failed': message.status === 'failed',
                        }"
                      >
                        <template v-if="message.status === 'sending'">
                          <q-spinner size="14px" />
                          <span>{{ t('workTickets.sending') }}</span>
                        </template>
                        <template v-else>
                          <q-icon name="error_outline" size="16px" />
                          <span>{{ message.errorMessage || t('workTickets.messageSendFailed') }}</span>
                          <q-btn
                            flat
                            dense
                            no-caps
                            color="negative"
                            icon="refresh"
                            :label="t('workTickets.retrySend')"
                            :disable="replySending"
                            @click="retryReply(message.id)"
                          />
                        </template>
                      </div>
                    </div>
                  </template>
                  <div
                    v-if="detail && detail.messages.length === 0 && visiblePendingReplies.length === 0"
                    class="spa-muted text-center"
                  >
                    {{ t('workTickets.noMessages') }}
                  </div>
                </div>
              </q-scroll-area>
              <q-separator />
              <div class="admin-work-tickets__composer q-pa-md column q-gutter-sm">
                <q-select
                  v-model="replyStatus"
                  dense
                  outlined
                  emit-value
                  map-options
                  clearable
                  :options="replyStatusOptions"
                  :label="t('adminTickets.replyStatus')"
                />
                <q-input
                  v-model="draft"
                  type="textarea"
                  autogrow
                  outlined
                  dense
                  :placeholder="t('adminTickets.replyPlaceholder')"
                  :disable="detailLoading || replySending"
                  @keydown.enter.exact.prevent="sendReply"
                >
                  <template #append>
                    <q-btn
                      round
                      dense
                      flat
                      icon="send"
                      color="primary"
                      :loading="replySending"
                      :disable="!draft.trim() || detailLoading"
                      @click="sendReply"
                    />
                  </template>
                </q-input>
              </div>
            </template>
            <div v-else class="admin-work-tickets__empty flex flex-center column q-pa-xl spa-empty-state">
              <q-icon name="headset_mic" size="48px" class="q-mb-md" />
              <div>{{ t('adminTickets.selectTicket') }}</div>
            </div>
          </div>
        </div>
      </q-card>
    </div>
  </q-page>
</template>

<script setup lang="ts">
import { Dialog, useQuasar } from 'quasar';
import { computed, nextTick, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';

import { onAdminSocketPageMessages } from 'src/composables/onAdminSocketPageMessages';
import {
  ADMIN_WORK_TICKET_DETAIL_API_URI,
  ApiAdminWorkTicket,
} from 'src/network/api/admin/work_ticket';
import type {
  AdminWorkTicketDetailRes,
  AdminWorkTicketListItemRes,
} from 'src/network/dto/admin/work_ticket';

const $q = useQuasar();
const route = useRoute();
const router = useRouter();
const { t } = useI18n();

const ticketStatusMap = computed<Record<number, string>>(() => ({
  0: t('workTickets.statuses.pending'),
  1: t('workTickets.statuses.processing'),
  2: t('workTickets.statuses.userFeedback'),
  3: t('workTickets.statuses.resolved'),
  4: t('workTickets.statuses.closed'),
}));
type WorkTicketStatus = 0 | 1 | 2 | 3 | 4;
type PendingReplyStatus = 'sending' | 'failed';

interface PendingReplyMessage {
  id: string;
  ticketKid: string;
  body: string;
  statusUpdate: WorkTicketStatus | null;
  status: PendingReplyStatus;
  errorMessage: string;
  createdAt: number;
}

const statusFilterOptions = computed<{ label: string; value: number | null }[]>(() => [
  { label: t('workTickets.statuses.all'), value: null },
  { label: t('workTickets.statuses.pending'), value: 0 },
  { label: t('workTickets.statuses.processing'), value: 1 },
  { label: t('workTickets.statuses.userFeedback'), value: 2 },
  { label: t('workTickets.statuses.resolved'), value: 3 },
  { label: t('workTickets.statuses.closed'), value: 4 },
]);

const statusMenuOptions = computed(() => [0, 1, 2, 3, 4].map((value) => ({
  value: value as 0 | 1 | 2 | 3 | 4,
  label: ticketStatusMap.value[value]!,
})));

const replyStatusOptions = statusMenuOptions;

const page = ref(1);
const pageSize = 20;
const total = ref(0);
const filterStatus = ref<number | null>(null);
const tickets = ref<AdminWorkTicketListItemRes[]>([]);
const listLoading = ref(false);
const listError = ref('');

const selectedKid = ref<string | null>(null);
const detail = ref<AdminWorkTicketDetailRes | null>(null);
const detailLoading = ref(false);
const draft = ref('');
const replySending = ref(false);
const replyStatus = ref<WorkTicketStatus | null>(null);
const pendingReplies = ref<PendingReplyMessage[]>([]);

const chatScrollRef = ref<{ setScrollPosition: (axis: 'vertical', offset: number) => void } | null>(
  null,
);

const totalPages = computed(() => Math.max(1, Math.ceil(total.value / pageSize)));
const visiblePendingReplies = computed(() =>
  pendingReplies.value.filter((message) => message.ticketKid === selectedKid.value),
);

const ticketStatusLabel = (s: number) => ticketStatusMap.value[s] ?? t('workTickets.statusUnknown', { status: s });

const ticketStatusColor = (s: number) => {
  if (s === 4) return 'neutral';
  if (s === 3) return 'positive';
  if (s === 2) return 'warning';
  return 'primary';
};

const formatShortTime = (iso: string | null) => {
  if (!iso) return '';
  const d = new Date(iso);
  return Number.isNaN(d.getTime()) ? iso : d.toLocaleString();
};

const formatFullTime = (iso: string | null) => formatShortTime(iso);
const formatPendingTime = (time: number) => {
  const d = new Date(time);
  return Number.isNaN(d.getTime()) ? '' : d.toLocaleString();
};

const createPendingReplyId = () => {
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
    return crypto.randomUUID();
  }
  return `pending-admin-work-ticket-reply:${Date.now()}:${Math.random().toString(16).slice(2)}`;
};

const updatePendingReply = (
  id: string,
  patch: Partial<Pick<PendingReplyMessage, 'status' | 'errorMessage'>>,
) => {
  const index = pendingReplies.value.findIndex((message) => message.id === id);
  if (index < 0) {
    return;
  }
  pendingReplies.value[index] = {
    ...pendingReplies.value[index]!,
    ...patch,
  };
};

const removePendingReply = (id: string) => {
  pendingReplies.value = pendingReplies.value.filter((message) => message.id !== id);
};

const scrollChatToBottom = async () => {
  await nextTick();
  requestAnimationFrame(() => {
    chatScrollRef.value?.setScrollPosition('vertical', 999999);
  });
};

const syncQueryKid = (kid: string | null) => {
  const q: Record<string, string | string[]> = { ...route.query } as Record<
    string,
    string | string[]
  >;
  if (kid) q.kid = kid;
  else delete q.kid;
  void router.replace({ query: q });
};

const selectTicket = (kid: string) => {
  selectedKid.value = kid;
  replyStatus.value = null;
  syncQueryKid(kid);
  void loadDetail();
};

const clearSelection = () => {
  selectedKid.value = null;
  detail.value = null;
  draft.value = '';
  replyStatus.value = null;
  syncQueryKid(null);
};

const loadList = async () => {
  listLoading.value = true;
  listError.value = '';
  try {
    const res = await ApiAdminWorkTicket.list({
      page: page.value,
      size: pageSize,
      status: filterStatus.value === null ? null : (filterStatus.value as 0 | 1 | 2 | 3 | 4),
    });
    tickets.value = res.items;
    total.value = res.total;
  } catch (e) {
    listError.value = e instanceof Error ? e.message : t('workTickets.listFailed');
  } finally {
    listLoading.value = false;
  }
};

const loadDetail = async () => {
  if (!selectedKid.value) return;
  detailLoading.value = true;
  try {
    detail.value = await ApiAdminWorkTicket.detail({ kid: selectedKid.value });
    await scrollChatToBottom();
  } catch (e) {
    $q.notify({
      type: 'negative',
      message: e instanceof Error ? e.message : t('workTickets.detailFailed'),
    });
  } finally {
    detailLoading.value = false;
  }
};

const onPageChange = () => {
  void loadList();
};

const sendReply = async () => {
  const text = draft.value.trim();
  if (!selectedKid.value || !text || replySending.value) return;
  const pendingMessage: PendingReplyMessage = {
    id: createPendingReplyId(),
    ticketKid: selectedKid.value,
    body: text,
    statusUpdate: replyStatus.value,
    status: 'sending',
    errorMessage: '',
    createdAt: Date.now(),
  };
  pendingReplies.value.push(pendingMessage);
  draft.value = '';
  replyStatus.value = null;
  await scrollChatToBottom();

  replySending.value = true;
  try {
    const res = await ApiAdminWorkTicket.reply({
      ticket_kid: pendingMessage.ticketKid,
      body: text,
      status: pendingMessage.statusUpdate,
    });
    removePendingReply(pendingMessage.id);
    if (selectedKid.value === pendingMessage.ticketKid) {
      detail.value = res;
      await scrollChatToBottom();
    }
    void loadList();
  } catch (e) {
    updatePendingReply(pendingMessage.id, {
      status: 'failed',
      errorMessage: e instanceof Error ? e.message : t('workTickets.messageSendFailed'),
    });
    await scrollChatToBottom();
  } finally {
    replySending.value = false;
  }
};

const retryReply = async (messageId: string) => {
  if (replySending.value) return;
  const pendingMessage = pendingReplies.value.find((message) => message.id === messageId);
  if (!pendingMessage || pendingMessage.status !== 'failed') {
    return;
  }

  updatePendingReply(messageId, { status: 'sending', errorMessage: '' });
  await scrollChatToBottom();
  replySending.value = true;
  try {
    const res = await ApiAdminWorkTicket.reply({
      ticket_kid: pendingMessage.ticketKid,
      body: pendingMessage.body,
      status: pendingMessage.statusUpdate,
    });
    removePendingReply(messageId);
    if (selectedKid.value === pendingMessage.ticketKid) {
      detail.value = res;
      await scrollChatToBottom();
    }
    void loadList();
  } catch (e) {
    updatePendingReply(messageId, {
      status: 'failed',
      errorMessage: e instanceof Error ? e.message : t('workTickets.messageSendFailed'),
    });
    await scrollChatToBottom();
  } finally {
    replySending.value = false;
  }
};

const setTicketStatus = (status: 0 | 1 | 2 | 3 | 4) => {
  if (!selectedKid.value) return;
  Dialog.create({
    title: t('adminTickets.updateStatus'),
    message: t('adminTickets.updateStatusConfirm', { status: ticketStatusMap.value[status] }),
    cancel: true,
    persistent: true,
  }).onOk(() => {
    void (async () => {
      try {
        detail.value = await ApiAdminWorkTicket.updateStatus({
          ticket_kid: selectedKid.value as string,
          status,
        });
        $q.notify({ type: 'positive', message: t('adminTickets.statusUpdated') });
        void loadList();
        await scrollChatToBottom();
      } catch (e) {
        $q.notify({
          type: 'negative',
          message: e instanceof Error ? e.message : t('adminTickets.updateFailed'),
        });
      }
    })();
  });
};

watch(filterStatus, () => {
  page.value = 1;
  void loadList();
});

watch(
  () => detail.value?.messages.length,
  () => {
    void scrollChatToBottom();
  },
);

onAdminSocketPageMessages((ctx) => {
  const workTicketNotices = ctx.getApiNotices(
    (notice) =>
      notice.api_uri === ADMIN_WORK_TICKET_DETAIL_API_URI && notice.kid_for_api !== null,
  );
  if (workTicketNotices.length === 0) {
    return;
  }

  void loadList();
  const currentKid = selectedKid.value;
  const shouldRefreshDetail =
    currentKid !== null &&
    workTicketNotices.some((message) => String(message.payload.kid_for_api) === currentKid);

  if (shouldRefreshDetail) {
    void loadDetail();
  }

  ctx.removeConsumed(workTicketNotices);
});

onMounted(async () => {
  await loadList();
  const qkid = route.query.kid;
  if (typeof qkid === 'string' && qkid) {
    selectTicket(qkid);
  }
});
</script>

<style scoped>
.admin-work-tickets__card {
  overflow: hidden;
}

.admin-work-tickets__split {
  min-height: min(72vh, 720px);
}

.admin-work-tickets__list {
  border-right: 1px solid var(--border);
  display: flex;
  flex-direction: column;
  min-width: 0;
}

.admin-work-tickets__list-scroll {
  flex: 1 1 auto;
  height: 48vh;
  min-height: 200px;
}

.admin-work-tickets__item--active {
  background: var(--glow-green);
}

.admin-work-tickets__chat {
  display: flex;
  flex-direction: column;
  min-width: 0;
  min-height: 48vh;
}

.admin-work-tickets__chat-head {
  min-height: 56px;
  background: var(--bg-secondary);
}

.admin-work-tickets__messages {
  flex: 1 1 auto;
  min-height: 240px;
}

.admin-work-tickets__pending-message {
  display: flex;
  flex-direction: column;
}

.admin-work-tickets__message-state {
  align-self: flex-end;
  display: flex;
  align-items: center;
  gap: 6px;
  max-width: min(520px, 82%);
  color: var(--text-muted);
}

.admin-work-tickets__message-state--failed {
  color: var(--q-negative);
}

.admin-work-tickets__composer {
  background: var(--bg-secondary);
}

.admin-work-tickets__empty {
  min-height: 320px;
}

.min-width-0 {
  min-width: 0;
}

@media (max-width: 1023px) {
  .admin-work-tickets__list {
    border-right: none;
  }

  .admin-work-tickets__list-scroll {
    height: 40vh;
  }
}
</style>
