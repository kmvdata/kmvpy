<template>
  <q-page class="spa-page user-work-tickets">
    <div class="content-area spa-content-area user-work-tickets__shell">
      <div class="row q-mb-md items-center justify-between">
        <div>
          <h2 class="user-work-tickets__title">{{ t('workTickets.title') }}</h2>
          <p class="user-work-tickets__sub spa-muted">
            {{ t('workTickets.subtitle') }}
          </p>
        </div>
        <q-btn
          color="primary"
          unelevated
          no-caps
          icon="add_comment"
          :label="t('workTickets.create')"
          @click="openCreateDialog"
        />
      </div>

      <q-banner v-if="listError" rounded class="spa-banner spa-banner--error q-mb-md">
        {{ listError }}
        <template #action>
          <q-btn flat color="primary" no-caps :label="t('common.retry')" @click="loadList" />
        </template>
      </q-banner>

      <q-card flat bordered class="spa-card user-work-tickets__card">
        <div class="user-work-tickets__split row no-wrap">
          <!-- 列表 -->
          <div
            v-show="!$q.screen.lt.md || !selectedKid"
            class="user-work-tickets__list col-12 col-md-4"
          >
            <div class="user-work-tickets__list-head q-pa-md row items-center q-gutter-sm">
              <q-select
                v-model="filterStatus"
                dense
                outlined
                emit-value
                map-options
                :options="statusFilterOptions"
                :label="t('workTickets.statusFilter')"
                class="col"
              />
              <q-btn flat dense round icon="refresh" color="primary" :aria-label="t('common.refresh')" @click="loadList" />
            </div>
            <q-separator />
            <q-inner-loading :showing="listLoading" color="primary" />
            <q-scroll-area class="user-work-tickets__list-scroll">
              <q-list separator>
                <q-item v-if="!listLoading && tickets.length === 0">
                  <q-item-section class="spa-muted text-center q-py-lg">
                    {{ t('workTickets.emptyUserList') }}
                  </q-item-section>
                </q-item>
                <q-item
                  v-for="t in tickets"
                  :key="t.kid"
                  v-ripple
                  clickable
                  :active="t.kid === selectedKid"
                  active-class="user-work-tickets__item--active"
                  @click="selectTicket(t.kid)"
                >
                  <q-item-section>
                    <q-item-label class="text-weight-medium ellipsis">{{ t.title }}</q-item-label>
                    <q-item-label caption class="ellipsis-2-lines">
                      {{ ticketStatusLabel(t.status) }}
                      <span v-if="t.last_message_time" class="q-ml-xs">
                        · {{ formatShortTime(t.last_message_time) }}
                      </span>
                    </q-item-label>
                  </q-item-section>
                  <q-item-section side>
                    <q-badge :color="ticketStatusColor(t.status)" outline>
                      {{ t.status }}
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

          <!-- 对话 -->
          <div
            v-show="!$q.screen.lt.md || selectedKid"
            class="user-work-tickets__chat col-12 col-md-8"
          >
            <template v-if="selectedKid">
              <q-toolbar class="user-work-tickets__chat-head">
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
                    {{ ticketStatusLabel(detail.status) }}
                    <span v-if="detail.category" class="q-ml-sm">{{ t('workTickets.category', { category: detail.category }) }}</span>
                  </div>
                </div>
                <q-space />
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
              <q-scroll-area ref="chatScrollRef" class="user-work-tickets__messages">
                <div class="q-pa-md column q-gutter-md">
                  <q-chat-message
                    v-for="m in detail?.messages ?? []"
                    :key="m.kid"
                    :sent="m.sender_role === 0"
                    :name="m.sender_role === 0 ? t('workTickets.me') : t('workTickets.customerService')"
                    :text="[m.body]"
                    :stamp="formatFullTime(m.create_time)"
                    :bg-color="m.sender_role === 0 ? 'primary' : 'surface-muted'"
                    :text-color="m.sender_role === 0 ? 'on-primary' : 'main'"
                  />
                  <template v-for="message in visiblePendingReplies" :key="message.id">
                    <div class="user-work-tickets__pending-message">
                      <q-chat-message
                        sent
                        :name="t('workTickets.me')"
                        :text="[message.body]"
                        :stamp="formatPendingTime(message.createdAt)"
                        :bg-color="message.status === 'failed' ? 'negative' : 'primary'"
                        :text-color="message.status === 'failed' ? 'on-status' : 'on-primary'"
                      />
                      <div
                        class="user-work-tickets__message-state"
                        :class="{
                          'user-work-tickets__message-state--failed': message.status === 'failed',
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
              <div class="user-work-tickets__composer q-pa-md">
                <q-input
                  v-model="draft"
                  type="textarea"
                  autogrow
                  outlined
                  dense
                  :placeholder="t('workTickets.composerPlaceholder')"
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
            <div v-else class="user-work-tickets__empty flex flex-center column q-pa-xl spa-muted">
              <q-icon name="forum" size="48px" class="q-mb-md" />
              <div>{{ t('workTickets.selectTicket') }}</div>
            </div>
          </div>
        </div>
      </q-card>
    </div>

    <q-dialog v-model="createOpen" persistent>
      <q-card class="spa-card" style="min-width: min(100vw - 32px, 420px)">
        <q-card-section class="row items-center">
          <div class="text-h6">{{ t('workTickets.create') }}</div>
          <q-space />
          <q-btn v-close-popup flat round dense icon="close" :aria-label="t('common.cancel')" @click="resetCreate" />
        </q-card-section>
        <q-separator />
        <q-card-section>
          <q-form class="column q-gutter-md" @submit.prevent="submitCreate">
            <q-input
              v-model="createTitle"
              outlined
              dense
              :label="t('workTickets.createTitle')"
              :rules="[(v: string) => !!v.trim() || t('workTickets.titleRequired')]"
              lazy-rules
            />
            <q-input v-model="createCategory" outlined dense :label="t('workTickets.createCategory')" />
            <q-input
              v-model="createBody"
              outlined
              type="textarea"
              autogrow
              :label="t('workTickets.createBody')"
              :rules="[(v: string) => !!v.trim() || t('workTickets.bodyRequired')]"
              lazy-rules
            />
            <div class="row justify-end q-gutter-sm">
              <q-btn v-close-popup flat no-caps :label="t('common.cancel')" @click="resetCreate" />
              <q-btn
                type="submit"
                color="primary"
                unelevated
                no-caps
                :label="t('common.submit')"
                :loading="createSending"
              />
            </div>
          </q-form>
        </q-card-section>
      </q-card>
    </q-dialog>
  </q-page>
</template>

<script setup lang="ts">
import { useQuasar } from 'quasar';
import { computed, nextTick, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';

import { onSocketPageMessages } from 'src/composables/onSocketPageMessages';
import { ApiUserWorkTicket } from 'src/network/api/user/work_ticket';
import type {
  UserWorkTicketDetailRes,
  UserWorkTicketListItemRes,
} from 'src/network/dto/user/work_ticket';

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

const USER_WORK_TICKET_DETAIL_API_URI = '/api/user/work_ticket/detail';
type PendingReplyStatus = 'sending' | 'failed';

interface PendingReplyMessage {
  id: string;
  ticketKid: string;
  body: string;
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

const page = ref(1);
const pageSize = 20;
const total = ref(0);
const filterStatus = ref<number | null>(null);
const tickets = ref<UserWorkTicketListItemRes[]>([]);
const listLoading = ref(false);
const listError = ref('');

const selectedKid = ref<string | null>(null);
const detail = ref<UserWorkTicketDetailRes | null>(null);
const detailLoading = ref(false);
const draft = ref('');
const replySending = ref(false);
const pendingReplies = ref<PendingReplyMessage[]>([]);

const createOpen = ref(false);
const createTitle = ref('');
const createCategory = ref('');
const createBody = ref('');
const createSending = ref(false);

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
  return `pending-work-ticket-reply:${Date.now()}:${Math.random().toString(16).slice(2)}`;
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
  syncQueryKid(kid);
  void loadDetail();
};

const clearSelection = () => {
  selectedKid.value = null;
  detail.value = null;
  draft.value = '';
  syncQueryKid(null);
};

const loadList = async () => {
  listLoading.value = true;
  listError.value = '';
  try {
    const res = await ApiUserWorkTicket.list({
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
    detail.value = await ApiUserWorkTicket.detail({ kid: selectedKid.value });
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
    status: 'sending',
    errorMessage: '',
    createdAt: Date.now(),
  };
  pendingReplies.value.push(pendingMessage);
  draft.value = '';
  await scrollChatToBottom();

  replySending.value = true;
  try {
    const res = await ApiUserWorkTicket.reply({
      ticket_kid: pendingMessage.ticketKid,
      body: text,
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
    const res = await ApiUserWorkTicket.reply({
      ticket_kid: pendingMessage.ticketKid,
      body: pendingMessage.body,
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

const openCreateDialog = () => {
  resetCreate();
  createOpen.value = true;
};

const resetCreate = () => {
  createTitle.value = '';
  createCategory.value = '';
  createBody.value = '';
};

const submitCreate = async () => {
  createSending.value = true;
  try {
    const res = await ApiUserWorkTicket.create({
      title: createTitle.value.trim(),
      category: createCategory.value.trim() || null,
      body: createBody.value.trim(),
    });
    createOpen.value = false;
    resetCreate();
    $q.notify({ type: 'positive', message: t('workTickets.created') });
    await loadList();
    selectTicket(res.kid);
  } catch (e) {
    $q.notify({
      type: 'negative',
      message: e instanceof Error ? e.message : t('workTickets.createFailed'),
    });
  } finally {
    createSending.value = false;
  }
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

onSocketPageMessages((ctx) => {
  const workTicketNotices = ctx.getApiNotices(
    (notice) =>
      notice.api_uri === USER_WORK_TICKET_DETAIL_API_URI && notice.kid_for_api !== null,
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
.user-work-tickets__title {
  font-size: var(--spa-font-size-page-title);
  font-weight: 600;
  color: var(--spa-text-heading);
  margin: 0 0 4px 0;
}

.user-work-tickets__sub {
  margin: 0;
  font-size: var(--spa-font-size-meta);
  max-width: 560px;
}

.user-work-tickets__card {
  border-radius: 12px;
  overflow: hidden;
}

.user-work-tickets__split {
  min-height: min(72vh, 720px);
}

.user-work-tickets__list {
  border-right: 1px solid var(--spa-border);
  display: flex;
  flex-direction: column;
  min-width: 0;
}

.user-work-tickets__list-scroll {
  flex: 1 1 auto;
  height: 48vh;
  min-height: 200px;
}

.user-work-tickets__item--active {
  background: var(--spa-primary-soft);
}

.user-work-tickets__chat {
  display: flex;
  flex-direction: column;
  min-width: 0;
  min-height: 48vh;
}

.user-work-tickets__chat-head {
  min-height: 56px;
}

.user-work-tickets__messages {
  flex: 1 1 auto;
  min-height: 240px;
}

.user-work-tickets__pending-message {
  display: flex;
  flex-direction: column;
}

.user-work-tickets__message-state {
  align-self: flex-end;
  display: flex;
  align-items: center;
  gap: 6px;
  max-width: min(520px, 82%);
  color: var(--spa-text-muted);
}

.user-work-tickets__message-state--failed {
  color: var(--q-negative);
}

.user-work-tickets__composer {
  background: var(--spa-bg);
}

.user-work-tickets__empty {
  min-height: 320px;
}

.min-width-0 {
  min-width: 0;
}

@media (max-width: 1023px) {
  .user-work-tickets__list {
    border-right: none;
  }

  .user-work-tickets__list-scroll {
    height: 40vh;
  }
}
</style>
