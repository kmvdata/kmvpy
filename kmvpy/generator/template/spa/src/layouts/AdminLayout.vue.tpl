<template>
  <q-layout
    view="hHh Lpr fff"
    class="spa-layout admin-layout signal-tracker-page signal-tracker-admin"
    :class="{
      'admin-layout--drawer-open': drawerHasLayout,
      'admin-layout--drawer-hidden': !drawerHasLayout,
    }"
    :style="adminLayoutStyle"
  >
    <q-header bordered class="spa-header">
      <q-toolbar class="spa-toolbar admin-layout__toolbar">
        <q-btn
          flat
          dense
          round
          color="primary"
          :icon="drawerOpen ? 'menu_open' : 'menu'"
          :aria-label="
            drawerOpen ? t('layouts.collapseNav') : t('layouts.expandNav')
          "
          @click="drawerOpen = !drawerOpen"
        />
        <router-link
          to="/"
          class="admin-layout__logo-link q-mr-sm"
          :aria-label="t('common.siteHome')"
        >
          <AppLogo size="sm" />
        </router-link>
        <q-toolbar-title class="admin-layout__toolbar-title">
          <div class="section-header-wrapper admin-layout__section-header">
            <h1 class="section-title">
              <span class="gradient-text">{{ headerTitle }}</span>
            </h1>
            <p class="section-sub">{{ headerSubtitle }}</p>
          </div>
        </q-toolbar-title>
        <AccountStyleMenu
          account-kind="admin"
          class="admin-layout__avatar-trigger"
        />
      </q-toolbar>
    </q-header>

    <q-drawer
      v-model="drawerOpen"
      show-if-above
      bordered
      class="admin-layout__drawer"
      :width="ADMIN_DRAWER_WIDTH"
      :breakpoint="ADMIN_DRAWER_BREAKPOINT"
      @on-layout="setDrawerLayout"
    >
      <q-scroll-area class="fit">
        <aside class="sidebar">
          <div
            v-for="section in adminNavSections"
            :key="section.key"
            class="sb-section"
            :class="`admin-layout__nav-section--${section.key}`"
          >
            <div
              class="nav-item admin-nav-section-label"
              :class="{ 'is-expanded': isAdminSectionExpanded(section.key) }"
              role="button"
              tabindex="0"
              @click="toggleAdminSection(section.key)"
              @keydown.enter.prevent="toggleAdminSection(section.key)"
              @keydown.space.prevent="toggleAdminSection(section.key)"
            >
              <span class="nav-label">
                {{ t(`layouts.adminNav.${section.titleKey}`) }}
              </span>
              <q-icon
                name="chevron_right"
                size="18px"
                class="nav-chevron"
                :class="{ 'is-expanded': isAdminSectionExpanded(section.key) }"
              />
            </div>
            <template v-if="isAdminSectionExpanded(section.key)">
              <a
                v-for="item in section.items"
                :id="`nav-${item.id}`"
                :key="item.id"
                class="nav-item"
                :href="item.toUri"
                :class="{ active: isActiveNavItem(item.id) }"
                @click.prevent="showPage(item.id)"
              >
                <span class="nav-icon">
                  <q-icon :name="item.icon" size="18px" />
                </span>
                <span class="nav-label">
                  {{ t(`layouts.adminNav.${item.titleKey}`) }}
                </span>
              </a>
            </template>
          </div>
        </aside>
      </q-scroll-area>
    </q-drawer>

    <q-page-container>
      <router-view />
    </q-page-container>
  </q-layout>
</template>

<script setup lang="ts">
import { computed, reactive, ref, watch } from "vue";
import { useI18n } from "vue-i18n";
import { useRoute, useRouter } from "vue-router";

import AccountStyleMenu from "src/components/AccountStyleMenu.vue";
import AppLogo from "src/components/AppLogo.vue";

type AdminSectionKey = "adminSection" | "systemSection";

type AdminNavItem = {
  id: string;
  toUri: string;
  titleKey: string;
  subtitleKey: string;
  icon: string;
};

type AdminNavSection = {
  key: AdminSectionKey;
  titleKey: string;
  items: AdminNavItem[];
};

const ADMIN_DRAWER_WIDTH = 260;
const ADMIN_DRAWER_BREAKPOINT = 1024;
const ADMIN_LAYOUT_GAP = 8;

const adminNavSections: AdminNavSection[] = [
  {
    key: "adminSection",
    titleKey: "adminSection",
    items: [
      {
        id: "users",
        toUri: "/admin/users",
        titleKey: "users",
        subtitleKey: "usersSub",
        icon: "group",
      },
      {
        id: "workTickets",
        toUri: "/admin/work-tickets",
        titleKey: "workTickets",
        subtitleKey: "workTicketsSub",
        icon: "support_agent",
      },
    ],
  },
  {
    key: "systemSection",
    titleKey: "systemSection",
    items: [
      {
        id: "systemSettings",
        toUri: "/admin/system-settings",
        titleKey: "systemSettings",
        subtitleKey: "systemSettingsSub",
        icon: "settings",
      },
      {
        id: "databaseTables",
        toUri: "/admin/database-tables",
        titleKey: "databaseTables",
        subtitleKey: "databaseTablesSub",
        icon: "table_chart",
      },
    ],
  },
];

const adminNavItems = adminNavSections.flatMap((section) => section.items);
const adminNavItemById = Object.fromEntries(
  adminNavItems.map((item) => [item.id, item]),
) as Record<string, AdminNavItem>;
const adminSectionById = Object.fromEntries(
  adminNavSections.flatMap((section) =>
    section.items.map((item) => [item.id, section.key]),
  ),
) as Record<string, AdminSectionKey>;

const route = useRoute();
const router = useRouter();
const drawerOpen = ref(true);
const drawerHasLayout = ref(true);
const adminLayoutStyle: Record<string, string> = {
  "--admin-drawer-width": `${ADMIN_DRAWER_WIDTH}px`,
  "--admin-layout-gap": `${ADMIN_LAYOUT_GAP}px`,
  "--admin-layout-hidden-page-x": `${ADMIN_DRAWER_WIDTH / 2 + ADMIN_LAYOUT_GAP}px`,
};
const { t } = useI18n();
const expandedAdminSections = reactive<Record<AdminSectionKey, boolean>>({
  adminSection: true,
  systemSection: false,
});

function isAdminSectionExpanded(sectionKey: AdminSectionKey): boolean {
  return expandedAdminSections[sectionKey] === true;
}

function toggleAdminSection(sectionKey: AdminSectionKey) {
  expandedAdminSections[sectionKey] = !expandedAdminSections[sectionKey];
}

function openCurrentAdminSection() {
  const currentNavId = currentAdminNavItem.value?.id;
  const sectionKey = currentNavId ? adminSectionById[currentNavId] : null;
  if (sectionKey) {
    expandedAdminSections[sectionKey] = true;
  }
}

function setDrawerLayout(value: boolean) {
  drawerHasLayout.value = value;
}

const currentAdminPath = computed(() => {
  return normalizeAdminPath(route?.path ?? "/admin/users");
});

function normalizeAdminPath(path: string): string {
  const base = path.split("?")[0] ?? path;
  if (base.length > 1 && base.endsWith("/")) {
    return base.slice(0, -1);
  }
  return base;
}

function isNavItemActive(navItem: AdminNavItem, path: string): boolean {
  const p = normalizeAdminPath(path);
  const u = normalizeAdminPath(navItem.toUri);
  return p === u || p.startsWith(`${u}/`);
}

function resolveAdminNavItem(path: string): AdminNavItem | null {
  const matches = adminNavItems.filter((item) => isNavItemActive(item, path));
  if (!matches.length) {
    return null;
  }
  return matches.reduce((best, cur) =>
    cur.toUri.length > best.toUri.length ? cur : best,
  );
}

const currentAdminNavItem = computed(() =>
  resolveAdminNavItem(currentAdminPath.value),
);

watch(
  () => route.fullPath,
  () => {
    openCurrentAdminSection();
  },
  { immediate: true },
);

const isActiveNavItem = (id: string): boolean => {
  const navItem = adminNavItemById[id];
  if (!navItem) {
    return false;
  }
  return isNavItemActive(navItem, currentAdminPath.value);
};

const showPage = async (pageId: string) => {
  const navItem = adminNavItemById[pageId];
  if (!navItem) {
    return;
  }
  if (route.path !== navItem.toUri) {
    await router.push({
      path: navItem.toUri,
      query: route.query,
    });
  }
};

const headerTitle = computed(() =>
  currentAdminNavItem.value
    ? t(`layouts.adminNav.${currentAdminNavItem.value.titleKey}`)
    : t("layouts.adminTitle"),
);

const headerSubtitle = computed(() =>
  currentAdminNavItem.value
    ? t(`layouts.adminNav.${currentAdminNavItem.value.subtitleKey}`)
    : t("layouts.adminNav.usersSub"),
);
</script>
