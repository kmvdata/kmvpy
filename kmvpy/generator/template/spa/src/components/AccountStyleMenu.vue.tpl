<template>
  <q-btn
    ref="trigger"
    flat
    round
    dense
    class="account-style-menu__trigger"
    :aria-label="menuAriaLabel"
    aria-haspopup="menu"
    :aria-expanded="menuOpen"
    :aria-controls="menuOpen ? menuId : undefined"
  >
    <q-avatar size="32px" class="account-style-menu__avatar">
      <img
        v-if="isLoggedIn && profileAvatarUri"
        :src="profileAvatarUri"
        :alt="t('accountMenu.avatarAlt')"
      />
      <span v-else-if="isLoggedIn">{{ accountInitial }}</span>
      <q-icon v-else name="account_circle" />
    </q-avatar>

    <q-menu
      ref="mainMenu"
      :id="menuId"
      v-model="menuOpen"
      anchor="bottom right"
      self="top right"
      class="account-style-menu"
      :aria-label="menuAriaLabel"
      @before-hide="closePreferences"
      @hide="restoreTriggerFocus"
      @click="finishPointerInteraction"
      @keydown.up.prevent="moveEntry($event, -1)"
      @keydown.down.prevent="moveEntry($event, 1)"
    >
      <q-resize-observer :debounce="0" @resize="mainMenu?.updatePosition()" />
      <q-list class="account-style-menu__list" role="presentation">
        <q-item v-if="isLoggedIn" class="account-style-menu__profile">
          <q-item-section avatar>
            <q-avatar class="account-style-menu__avatar">
              <img
                v-if="profileAvatarUri"
                :src="profileAvatarUri"
                :alt="t('accountMenu.avatarAlt')"
              />
              <span v-else>{{ accountInitial }}</span>
            </q-avatar>
          </q-item-section>
          <q-item-section>
            <q-item-label>{{ accountLabel }}</q-item-label>
            <q-item-label v-if="profile?.email" caption>{{
              profile.email
            }}</q-item-label>
            <q-item-label v-if="profileLoading" caption role="status">
              {{ t("common.loadingEllipsis") }}
            </q-item-label>
            <q-item-label v-if="profileError" caption role="alert">
              {{ profileError }}
              <q-btn
                flat
                dense
                no-caps
                :label="t('common.retry')"
                @click="loadProfile"
              />
            </q-item-label>
          </q-item-section>
        </q-item>
        <q-item v-else class="account-style-menu__profile">
          <q-item-section avatar>
            <q-avatar class="account-style-menu__avatar">
              <q-icon name="account_circle" />
            </q-avatar>
          </q-item-section>
          <q-item-section>
            <q-btn
              v-close-popup
              flat
              no-caps
              color="primary"
              :label="t('accountMenu.loginRegister')"
              class="account-style-menu__login"
              @click="goLogin"
            />
          </q-item-section>
        </q-item>

        <q-separator />

        <template v-if="isLoggedIn && hasActionsSlot">
          <slot
            name="actions"
            :profile="profile"
            :account-label="accountLabel"
          />
          <q-separator />
        </template>

        <AccountPreferenceItem
          v-for="preference in preferences"
          :key="preference.id"
          :label="preference.label"
          :icon="preference.icon"
          :value="preference.value"
          :options="preference.options"
          :open="activePreference === preference.id"
          :reserve-space="reservedPreference === preference.id"
          @update:open="setPreferenceOpen(preference.id, $event)"
          @select="preference.update"
          @return="reservedPreference = null"
        />

        <q-separator v-if="isLoggedIn" />

        <q-item
          v-if="isLoggedIn"
          v-close-popup
          clickable
          role="menuitem"
          @click="handleLogout"
        >
          <q-item-section avatar>
            <q-icon name="logout" />
          </q-item-section>
          <q-item-section>{{ t("accountMenu.logout") }}</q-item-section>
        </q-item>
      </q-list>
    </q-menu>
  </q-btn>
</template>

<script setup lang="ts">
import { computed, onMounted, ref, useId } from "vue";
import type { QBtn, QMenu } from "quasar";
import { useI18n } from "vue-i18n";
import { useRouter } from "vue-router";

import AccountPreferenceItem from "./AccountPreferenceItem.vue";
import { useStylePreferences } from "src/composables/useStylePreferences";
import { useKmvApiErrorMessage } from "src/i18n/kmv/useKmvApiErrorMessage";
import {
  clearStoredAdminAuthorization,
  getStoredAdminAuthorization,
} from "src/boot/axios_admin";
import {
  clearStoredUserAuthorization,
  getStoredUserAuthorization,
} from "src/boot/axios_user";
import { ApiAdminOp } from "src/network/api/admin/admin_op";
import { ApiUserOp } from "src/network/api/user/user_op";
import type { UserProfileRes } from "src/network/dto/user/user_op";

const props = defineProps<{
  accountKind: "user" | "admin";
}>();

const slots = defineSlots<{
  actions?: (props: {
    profile: UserProfileRes | null;
    accountLabel: string;
  }) => unknown;
}>();

const { t } = useI18n({ useScope: "global" });
const { resolveFromError } = useKmvApiErrorMessage();
const {
  locale,
  fontSize,
  theme,
  localeOptions,
  fontSizeOptions,
  themeOptions,
  updateLocale,
  updateFontSize,
  updateTheme,
} = useStylePreferences();
const router = useRouter();
const profile = ref<UserProfileRes | null>(null);
const isLoggedIn = ref(false);
const profileLoading = ref(false);
const profileFailure = ref<unknown>(null);
const profileError = computed(() =>
  profileFailure.value ? resolveFromError(profileFailure.value) : "",
);
const menuOpen = ref(false);
const menuId = `account-menu-${useId()}`;
const trigger = ref<QBtn>();
const mainMenu = ref<QMenu>();
const activePreference = ref<string | null>(null);
// QMenu dismisses on mousedown. Retain the gap until click so sibling targets
// cannot move between pointer-down and pointer-up on narrow screens.
const reservedPreference = ref<string | null>(null);
const preferences = computed(() => [
  {
    id: "language",
    label: t("accountMenu.language"),
    icon: "language",
    value: locale.value,
    options: localeOptions.value,
    update: updateLocale,
  },
  {
    id: "fontSize",
    label: t("accountMenu.fontSize"),
    icon: "format_size",
    value: fontSize.value,
    options: fontSizeOptions.value,
    update: updateFontSize,
  },
  {
    id: "style",
    label: t("accountMenu.style"),
    icon: "palette",
    value: theme.value,
    options: themeOptions.value,
    update: updateTheme,
  },
]);

function setPreferenceOpen(id: string, open: boolean) {
  if (open) {
    activePreference.value = id;
    reservedPreference.value = id;
  } else if (activePreference.value === id) activePreference.value = null;
}
function finishPointerInteraction() {
  if (!activePreference.value) reservedPreference.value = null;
}
function closePreferences() {
  activePreference.value = null;
  reservedPreference.value = null;
}
function restoreTriggerFocus() {
  if (!menuOpen.value)
    (trigger.value?.$el as HTMLElement | undefined)?.focus({
      preventScroll: true,
    });
}
function moveEntry(event: KeyboardEvent, step: number) {
  const items = Array.from(
    document
      .getElementById(menuId)
      ?.querySelectorAll<HTMLElement>(
        '.account-style-menu__list > [tabindex="0"], .account-style-menu__login',
      ) ?? [],
  );
  const index = items.findIndex((item) => item.contains(event.target as Node));
  items[(index + step + items.length) % items.length]?.focus();
}

const storageAuthorization = () =>
  props.accountKind === "admin"
    ? getStoredAdminAuthorization()
    : getStoredUserAuthorization();

const loadProfile = async () => {
  isLoggedIn.value = Boolean(storageAuthorization());
  if (!isLoggedIn.value) {
    profile.value = null;
    return;
  }

  profileLoading.value = true;
  profileFailure.value = null;
  try {
    profile.value =
      props.accountKind === "admin"
        ? await ApiAdminOp.getUserProfile()
        : await ApiUserOp.getUserProfile();
  } catch (error) {
    profile.value = null;
    profileFailure.value = error;
  } finally {
    profileLoading.value = false;
  }
};

const accountName = computed(() => {
  const value = profile.value;
  return value?.nickname || value?.username || value?.email || value?.kid || "";
});

const accountInitial = computed(() => {
  const initial = accountName.value.trim().charAt(0);
  if (initial) {
    return initial.toUpperCase();
  }
  return props.accountKind === "admin" ? "A" : "U";
});

const accountLabel = computed(() => {
  if (!isLoggedIn.value) {
    return t("accountMenu.loginRegister");
  }
  return (
    accountName.value ||
    t(
      props.accountKind === "admin"
        ? "accountMenu.adminAccount"
        : "accountMenu.userAccount",
    )
  );
});

const profileAvatarUri = computed(() => profile.value?.avatar_uri || "");
const menuAriaLabel = computed(() =>
  t("accountMenu.menuAriaLabel", { account: accountLabel.value }),
);
const hasActionsSlot = computed(() => Boolean(slots.actions));

const goLogin = () => {
  void router.push({
    name: props.accountKind === "admin" ? "admin-login" : "login",
  });
};

const handleLogout = async () => {
  try {
    if (props.accountKind === "admin") {
      await ApiAdminOp.logout();
    } else {
      await ApiUserOp.logout();
    }
  } finally {
    if (props.accountKind === "admin") {
      clearStoredAdminAuthorization();
      await router.push({ name: "admin-login" });
    } else {
      clearStoredUserAuthorization();
      await router.push({ name: "login" });
    }
  }
};

onMounted(() => {
  void loadProfile();
});
</script>
