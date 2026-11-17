<template>
  <q-page class="spa-page personal-profile-page">
    <div class="content-area spa-content-area spa-shell--wide">
      <div class="row q-mb-md items-start justify-between personal-profile__toolbar">
        <div class="section-header-wrapper personal-profile__intro">
          <h2 class="personal-profile__heading">
            <span class="gradient-text">{{ t("userProfile.title") }}</span>
          </h2>
          <p class="personal-profile__sub">
            {{ t("userProfile.subtitle") }}
          </p>
        </div>
        <q-btn
          outline
          color="primary"
          no-caps
          icon="refresh"
          :label="t('userProfile.reload')"
          :loading="isLoading"
          @click="loadProfile"
        />
      </div>

      <q-banner
        v-if="loadError"
        rounded
        class="spa-banner spa-banner--error q-mb-md"
      >
        {{ loadError }}
        <template #action>
          <q-btn
            flat
            color="primary"
            no-caps
            :label="t('common.retry')"
            :loading="isLoading"
            @click="loadProfile"
          />
        </template>
      </q-banner>

      <q-card flat bordered class="spa-card personal-profile__card">
        <q-card-section class="personal-profile__card-body">
          <q-inner-loading :showing="isLoading" color="primary" />

          <template v-if="profile">
            <div class="personal-profile__summary">
              <q-avatar
                size="72px"
                color="primary"
                text-color="on-primary"
                class="personal-profile__avatar"
              >
                <img
                  v-if="profile.avatar_uri"
                  :src="profile.avatar_uri"
                  :alt="t('accountMenu.avatarAlt')"
                />
                <span v-else>{{ avatarText }}</span>
              </q-avatar>

              <div class="personal-profile__summary-main">
                <div class="personal-profile__name">{{ displayName }}</div>
                <div class="personal-profile__meta spa-muted">
                  {{ primaryAccount }}
                </div>
                <div class="personal-profile__badges">
                  <q-badge color="primary" outline>
                    {{ userTypeLabel(profile.user_type) }}
                  </q-badge>
                  <q-badge :color="stateColor(profile.state)" outline>
                    {{ stateLabel(profile.state) }}
                  </q-badge>
                </div>
              </div>
            </div>

            <q-separator class="q-my-md spa-separator" />

            <div class="personal-profile__notice">
              <q-icon name="verified_user" />
              <span>{{ t("userProfile.safeFieldsNotice") }}</span>
            </div>

            <section
              v-for="section in fieldSections"
              :key="section.title"
              class="personal-profile__section"
            >
              <h3 class="personal-profile__section-title">
                {{ section.title }}
              </h3>
              <div class="personal-profile__fields">
                <div
                  v-for="item in section.items"
                  :key="item.key"
                  class="personal-profile-field"
                >
                  <span class="personal-profile-field__label">{{
                    item.label
                  }}</span>
                  <span class="personal-profile-field__value">{{
                    item.value
                  }}</span>
                </div>
              </div>
            </section>
          </template>
        </q-card-section>
      </q-card>
    </div>
  </q-page>
</template>

<script setup lang="ts">
import { computed, onMounted, ref } from "vue";
import { useI18n } from "vue-i18n";

import { ApiUserOp } from "src/network/api/user/user_op";
import type { UserProfileRes } from "src/network/dto/user/user_op";

interface ProfileField {
  key: string;
  label: string;
  value: string;
}

interface ProfileFieldSection {
  title: string;
  items: ProfileField[];
}

const { t } = useI18n();

const profile = ref<UserProfileRes | null>(null);
const isLoading = ref(false);
const loadError = ref("");

const emptyValue = computed(() => t("common.emptyValue"));

const formatNullable = (value: string | number | null): string => {
  if (value === null || value === "") {
    return emptyValue.value;
  }
  return String(value);
};

const formatDateTime = (value: string | null): string => {
  if (!value) {
    return emptyValue.value;
  }
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return value;
  }
  return date.toLocaleString();
};

const formatPhone = (userProfile: UserProfileRes): string => {
  if (!userProfile.phone) {
    return emptyValue.value;
  }
  return userProfile.country_code
    ? `${userProfile.country_code} ${userProfile.phone}`
    : userProfile.phone;
};

const displayName = computed(
  () =>
    profile.value?.nickname ||
    profile.value?.username ||
    profile.value?.email ||
    t("userProfile.currentUser"),
);

const primaryAccount = computed(
  () =>
    profile.value?.email ||
    profile.value?.username ||
    profile.value?.kid ||
    emptyValue.value,
);

const avatarText = computed(
  () => displayName.value.trim().slice(0, 1).toUpperCase() || "U",
);

const userTypeLabel = (userType: number | null): string => {
  if (userType === 0) {
    return t("userProfile.userTypes.normal");
  }
  if (userType === 100) {
    return t("userProfile.userTypes.admin");
  }
  if (userType === 2) {
    return t("userProfile.userTypes.reviewer");
  }
  return userType === null
    ? emptyValue.value
    : t("userProfile.userTypes.unknown", { type: userType });
};

const stateLabel = (state: number | null): string => {
  if (state === 1) {
    return t("userProfile.states.available");
  }
  if (state === 0) {
    return t("userProfile.states.unavailable");
  }
  return emptyValue.value;
};

const stateColor = (state: number | null): string => {
  if (state === 1) {
    return "positive";
  }
  if (state === 0) {
    return "negative";
  }
  return "neutral";
};

const genderLabel = (gender: number | null): string => {
  if (gender === 0) {
    return t("userProfile.genders.female");
  }
  if (gender === 1) {
    return t("userProfile.genders.male");
  }
  return emptyValue.value;
};

const fieldSections = computed<ProfileFieldSection[]>(() => {
  const userProfile = profile.value;
  if (!userProfile) {
    return [];
  }
  return [
    {
      title: t("userProfile.sections.account"),
      items: [
        {
          key: "kid",
          label: t("userProfile.fields.kid"),
          value: userProfile.kid || emptyValue.value,
        },
        {
          key: "username",
          label: t("userProfile.fields.username"),
          value: formatNullable(userProfile.username),
        },
        {
          key: "email",
          label: t("userProfile.fields.email"),
          value: formatNullable(userProfile.email),
        },
        {
          key: "nickname",
          label: t("userProfile.fields.nickname"),
          value: formatNullable(userProfile.nickname),
        },
        {
          key: "user_type",
          label: t("userProfile.fields.userType"),
          value: userTypeLabel(userProfile.user_type),
        },
        {
          key: "state",
          label: t("userProfile.fields.state"),
          value: stateLabel(userProfile.state),
        },
      ],
    },
    {
      title: t("userProfile.sections.profile"),
      items: [
        {
          key: "phone",
          label: t("userProfile.fields.phone"),
          value: formatPhone(userProfile),
        },
        {
          key: "country_code",
          label: t("userProfile.fields.countryCode"),
          value: formatNullable(userProfile.country_code),
        },
        {
          key: "gender",
          label: t("userProfile.fields.gender"),
          value: genderLabel(userProfile.gender),
        },
        {
          key: "avatar_uri",
          label: t("userProfile.fields.avatarUri"),
          value: formatNullable(userProfile.avatar_uri),
        },
        {
          key: "signature",
          label: t("userProfile.fields.signature"),
          value: formatNullable(userProfile.signature),
        },
        {
          key: "comment",
          label: t("userProfile.fields.comment"),
          value: formatNullable(userProfile.comment),
        },
      ],
    },
    {
      title: t("userProfile.sections.system"),
      items: [
        {
          key: "ip",
          label: t("userProfile.fields.ip"),
          value: formatNullable(userProfile.ip),
        },
        {
          key: "deviceid",
          label: t("userProfile.fields.deviceid"),
          value: formatNullable(userProfile.deviceid),
        },
        {
          key: "balance_power",
          label: t("userProfile.fields.balancePower"),
          value:
            userProfile.balance_power === null
              ? emptyValue.value
              : t("userProfile.balancePowerValue", {
                  value: userProfile.balance_power,
                }),
        },
        {
          key: "create_time",
          label: t("userProfile.fields.createTime"),
          value: formatDateTime(userProfile.create_time),
        },
        {
          key: "update_time",
          label: t("userProfile.fields.updateTime"),
          value: formatDateTime(userProfile.update_time),
        },
        {
          key: "delete_at",
          label: t("userProfile.fields.deleteAt"),
          value: formatDateTime(userProfile.delete_at),
        },
      ],
    },
  ];
});

const loadProfile = async () => {
  isLoading.value = true;
  loadError.value = "";
  try {
    profile.value = await ApiUserOp.getUserProfile();
  } catch {
    loadError.value = t("userProfile.loadFailed");
  } finally {
    isLoading.value = false;
  }
};

onMounted(() => {
  void loadProfile();
});
</script>

<style scoped>
.personal-profile__intro {
  margin-bottom: 0;
  min-width: 0;
}

.personal-profile__heading {
  margin: 0 0 6px;
  font-size: 22px;
  font-weight: 700;
  line-height: 1.25;
  color: var(--spa-text-heading);
}

.personal-profile__sub {
  margin: 0;
  font-size: var(--spa-font-size-small);
  line-height: 1.5;
  max-width: 640px;
  color: var(--spa-text-muted);
}

.personal-profile__toolbar {
  gap: 12px;
}

.personal-profile__card {
  position: relative;
  overflow: hidden;
}

.personal-profile__card-body {
  position: relative;
  min-height: 220px;
}

.personal-profile__summary {
  display: flex;
  align-items: center;
  gap: 16px;
  min-height: 80px;
}

.personal-profile__avatar {
  flex-shrink: 0;
  font-weight: 700;
}

.personal-profile__summary-main {
  min-width: 0;
}

.personal-profile__name {
  font-size: var(--spa-font-size-title);
  font-weight: 700;
  line-height: 1.25;
  color: var(--spa-text-heading);
}

.personal-profile__meta {
  margin-top: 4px;
  font-size: var(--spa-font-size-body);
  overflow-wrap: anywhere;
}

.personal-profile__badges {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
  margin-top: 10px;
}

.personal-profile__notice {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  margin-bottom: 18px;
  color: var(--spa-text-muted);
  font-size: var(--spa-font-size-small);
}

.personal-profile__section + .personal-profile__section {
  margin-top: 22px;
}

.personal-profile__section-title {
  margin: 0 0 10px;
  color: var(--spa-text-heading);
  font-size: var(--spa-font-size-body);
  font-weight: 700;
  line-height: 1.35;
}

.personal-profile__fields {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: 12px;
}

.personal-profile-field {
  border: 1px solid var(--spa-border);
  border-radius: var(--spa-radius-md);
  padding: 12px;
  background: var(--spa-surface-muted);
  min-width: 0;
}

.personal-profile-field__label {
  display: block;
  margin-bottom: 4px;
  color: var(--spa-text-muted);
  font-size: var(--spa-font-size-small);
  font-weight: 600;
}

.personal-profile-field__value {
  display: block;
  color: var(--spa-text-body);
  font-size: var(--spa-font-size-body);
  overflow-wrap: anywhere;
}

@media (max-width: 900px) {
  .personal-profile__fields {
    grid-template-columns: repeat(2, minmax(0, 1fr));
  }
}

@media (max-width: 640px) {
  .personal-profile__toolbar {
    flex-direction: column;
    align-items: stretch;
  }

  .personal-profile__heading {
    font-size: 18px;
  }

  .personal-profile__summary {
    align-items: flex-start;
  }

  .personal-profile__fields {
    grid-template-columns: 1fr;
  }
}
</style>
