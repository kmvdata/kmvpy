<template>
  <q-layout
    view="hHh Lpr fff"
    class="spa-layout user-layout kmvpy-user-layout"
  >
    <q-header bordered class="spa-header">
      <q-toolbar class="spa-toolbar admin-layout__toolbar user-layout__toolbar">
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
          account-kind="user"
          class="admin-layout__avatar-trigger"
        >
          <template #actions>
            <q-item
              clickable
              v-close-popup
              class="admin-layout__user-menu-item"
              :to="{ name: 'user-profile' }"
            >
              <q-item-section avatar>
                <q-icon name="person" color="primary" />
              </q-item-section>
              <q-item-section>{{
                t("layouts.userNav.profile")
              }}</q-item-section>
            </q-item>
            <q-item
              clickable
              v-close-popup
              class="admin-layout__user-menu-item"
              :to="{ name: 'user-work-tickets' }"
            >
              <q-item-section avatar>
                <q-icon name="forum" color="accent" />
              </q-item-section>
              <q-item-section>{{ t("workTickets.title") }}</q-item-section>
            </q-item>
          </template>
        </AccountStyleMenu>
      </q-toolbar>
    </q-header>

    <q-drawer
      v-model="drawerOpen"
      show-if-above
      bordered
      class="admin-layout__drawer"
      :width="260"
      :breakpoint="1024"
    >
      <q-scroll-area class="fit">
        <aside class="sidebar kmvpy-user-layout__sidebar">
          <div
            v-for="section in userNavSections"
            :key="section.key"
            class="sb-section"
            :class="`kmvpy-user-layout__nav-section--${section.key}`"
          >
            <div
              class="nav-item admin-nav-section-label"
              :class="{ 'is-expanded': isUserSectionExpanded(section.key) }"
              role="button"
              tabindex="0"
              @click="toggleUserSection(section.key)"
              @keydown.enter.prevent="toggleUserSection(section.key)"
              @keydown.space.prevent="toggleUserSection(section.key)"
            >
              <span class="nav-label">
                {{ t(`layouts.userNav.${section.titleKey}`) }}
              </span>
              <q-icon
                name="chevron_right"
                size="18px"
                class="nav-chevron"
                :class="{ 'is-expanded': isUserSectionExpanded(section.key) }"
              />
            </div>
            <template v-if="isUserSectionExpanded(section.key)">
              <a
                v-for="item in section.items"
                :id="`nav-${item.id}`"
                :key="item.id"
                class="nav-item kmvpy-user-layout__nav-item"
                :href="item.toUri"
                :class="{ active: isActiveNavItem(item.id) }"
                @click.prevent="showPage(item.id)"
              >
                <span class="nav-icon">
                  <q-icon :name="item.icon" size="18px" />
                </span>
                <span class="nav-label">
                  {{ t(`layouts.userNav.${item.titleKey}`) }}
                </span>
              </a>
            </template>
          </div>

          <div class="sb-footer">
            <span class="status-dot" />
            {{ t("layouts.userNav.kmvpyReady") }}<br />
            &copy; 2026 Sisyphus<br />
            KMVPy
          </div>
        </aside>
      </q-scroll-area>
    </q-drawer>

    <q-page-container class="user-page-container">
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

interface UserNavItem {
  id: string;
  toUri: string;
  icon: string;
  titleKey: string;
  subtitleKey: string;
  query?: Record<string, string>;
}

type UserSectionKey = "userSection" | "helpSection";

interface UserNavSection {
  key: UserSectionKey;
  titleKey: string;
  items: UserNavItem[];
}

const route = useRoute();
const router = useRouter();
const { t } = useI18n();

const drawerOpen = ref(true);

const userNavSections: UserNavSection[] = [
  {
    key: "userSection",
    titleKey: "sections.user",
    items: [
      {
        id: "profile",
        toUri: "/app/personal/profile",
        icon: "person",
        titleKey: "profile",
        subtitleKey: "profileSub",
      },
      {
        id: "workTickets",
        toUri: "/app/work-tickets/user-work-tickets",
        icon: "forum",
        titleKey: "workTickets",
        subtitleKey: "workTicketsSub",
      },
    ],
  },
  {
    key: "helpSection",
    titleKey: "sections.help",
    items: [
      {
        id: "helpOverview",
        toUri: "/app/help/help",
        icon: "help_outline",
        titleKey: "helpOverview",
        subtitleKey: "helpOverviewSub",
        query: { topic: "overview" },
      },
      {
        id: "helpQuickStart",
        toUri: "/app/help/help",
        icon: "rocket_launch",
        titleKey: "helpQuickStart",
        subtitleKey: "helpQuickStartSub",
        query: { topic: "quick-start" },
      },
      {
        id: "helpStructure",
        toUri: "/app/help/help",
        icon: "schema",
        titleKey: "helpStructure",
        subtitleKey: "helpStructureSub",
        query: { topic: "structure" },
      },
      {
        id: "helpSecurity",
        toUri: "/app/help/help",
        icon: "security",
        titleKey: "helpSecurity",
        subtitleKey: "helpSecuritySub",
        query: { topic: "security" },
      },
    ],
  },
];

const navItems = userNavSections.flatMap((section) => section.items);
const navItemById = Object.fromEntries(
  navItems.map((item) => [item.id, item]),
) as Record<string, UserNavItem>;
const navSectionById = Object.fromEntries(
  userNavSections.flatMap((section) =>
    section.items.map((item) => [item.id, section.key]),
  ),
) as Record<string, UserSectionKey>;

const expandedUserSections = reactive<Record<UserSectionKey, boolean>>({
  userSection: true,
  helpSection: false,
});

function isUserSectionExpanded(sectionKey: UserSectionKey): boolean {
  return expandedUserSections[sectionKey] === true;
}

function toggleUserSection(sectionKey: UserSectionKey) {
  expandedUserSections[sectionKey] = !expandedUserSections[sectionKey];
}

function openCurrentUserSection() {
  const currentNavId = currentNavItem.value?.id;
  const sectionKey = currentNavId ? navSectionById[currentNavId] : null;
  if (sectionKey) {
    expandedUserSections[sectionKey] = true;
  }
}

function normalizeUserPath(path: string): string {
  const base = path.split("?")[0] ?? path;
  if (base.length > 1 && base.endsWith("/")) {
    return base.slice(0, -1);
  }
  return base;
}

function queryCompatible(
  routeQuery: Record<string, unknown>,
  needed: Record<string, string> | undefined,
): boolean {
  if (!needed) {
    return true;
  }
  for (const [key, value] of Object.entries(needed)) {
    const raw = routeQuery[key];
    const routeValue = Array.isArray(raw) ? raw[0] : raw;
    if (String(routeValue ?? "") !== value) {
      return false;
    }
  }
  return true;
}

function isNavItemActive(navItem: UserNavItem): boolean {
  const currentPath = normalizeUserPath(route.path);
  const targetPath = normalizeUserPath(navItem.toUri);
  if (currentPath !== targetPath && !currentPath.startsWith(`${targetPath}/`)) {
    return false;
  }
  if (targetPath === "/app/help/help") {
    const currentTopic =
      typeof route.query.topic === "string" ? route.query.topic : "overview";
    return (navItem.query?.topic ?? "overview") === currentTopic;
  }
  return queryCompatible(route.query, navItem.query);
}

function resolveUserNavItem(): UserNavItem | null {
  const matches = navItems.filter((item) => isNavItemActive(item));
  if (!matches.length) {
    return null;
  }
  return matches.reduce((best, cur) =>
    cur.toUri.length > best.toUri.length ? cur : best,
  );
}

const currentNavItem = computed(() => resolveUserNavItem());

const headerTitle = computed(() =>
  currentNavItem.value
    ? t(`layouts.userNav.${currentNavItem.value.titleKey}`)
    : t("layouts.userNav.userCenter"),
);

const headerSubtitle = computed(() =>
  currentNavItem.value
    ? t(`layouts.userNav.${currentNavItem.value.subtitleKey}`)
    : t("layouts.userNav.userCenterSub"),
);

const isActiveNavItem = (id: string): boolean => {
  const navItem = navItemById[id];
  if (!navItem) {
    return false;
  }
  return isNavItemActive(navItem);
};

const showPage = async (pageId: string) => {
  const navItem = navItemById[pageId];
  if (!navItem) {
    return;
  }
  const targetQuery = { ...navItem.query };
  if (
    route.path !== navItem.toUri ||
    !queryCompatible(route.query, navItem.query)
  ) {
    await router.push({
      path: navItem.toUri,
      query: targetQuery,
    });
  }
};

watch(
  () => route.fullPath,
  () => {
    openCurrentUserSection();
  },
  { immediate: true },
);
</script>

<style scoped>
.user-page-container {
  padding-inline: 16px;
}

.kmvpy-user-layout__nav-list {
  display: grid;
  gap: 6px;
}

.kmvpy-user-layout__nav-item {
  min-height: 58px;
  padding-block: 8px;
}

.kmvpy-user-layout__nav-sub {
  color: var(--spa-text-muted);
  font-size: var(--spa-font-size-caption);
  line-height: 1.35;
}
</style>
