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
              <template v-for="item in section.items" :key="item.id">
                <div class="admin-nav-row">
                  <a
                    v-if="item.toUri"
                    :id="`nav-${item.id}`"
                    class="nav-item admin-nav-row__link"
                    :class="{ active: isNavItemActive(item) }"
                    :href="item.toUri"
                    :aria-current="isNavItemActive(item) ? 'page' : undefined"
                    @click.prevent="openNavItem(item)"
                  >
                    <span class="nav-icon">
                      <q-icon :name="item.icon" size="18px" />
                    </span>
                    <span class="nav-label">{{ item.label }}</span>
                  </a>
                  <div
                    v-else
                    :id="`nav-${item.id}`"
                    class="nav-item admin-nav-row__link admin-nav-row__group"
                    role="button"
                    tabindex="0"
                    :aria-expanded="isNavItemExpanded(item.id)"
                    @click="toggleNavItem(item.id)"
                    @keydown.enter.prevent="toggleNavItem(item.id)"
                    @keydown.space.prevent="toggleNavItem(item.id)"
                  >
                    <span class="nav-icon">
                      <q-icon :name="item.icon" size="18px" />
                    </span>
                    <span class="nav-label">{{ item.label }}</span>
                    <q-icon
                      :name="
                        isNavItemExpanded(item.id) ? 'expand_less' : 'expand_more'
                      "
                      size="18px"
                      class="admin-nav-row__group-chevron"
                    />
                  </div>
                  <q-btn
                    v-if="item.toUri && item.children.length > 0"
                    flat
                    dense
                    round
                    size="sm"
                    class="admin-nav-row__toggle"
                    :icon="
                      isNavItemExpanded(item.id) ? 'expand_less' : 'expand_more'
                    "
                    :aria-label="navChildrenToggleLabel(item)"
                    :aria-expanded="isNavItemExpanded(item.id)"
                    @click="toggleNavItem(item.id)"
                  />
                </div>
                <div
                  v-if="item.children.length > 0 && isNavItemExpanded(item.id)"
                  class="admin-nav-children"
                >
                  <template v-for="child in item.children" :key="child.id">
                    <div
                      class="nav-item admin-nav-child admin-nav-row__group"
                      :class="{ active: isDatabaseChildActive(child) }"
                      role="button"
                      tabindex="0"
                      :aria-current="
                        isDatabaseChildActive(child) ? 'page' : undefined
                      "
                      :aria-expanded="isDatabaseItemExpanded(child.id)"
                      @click="activateDatabaseRow(child)"
                      @keydown.enter.prevent="activateDatabaseRow(child)"
                      @keydown.space.prevent="activateDatabaseRow(child)"
                    >
                      <span
                        class="nav-icon admin-nav-child__dot"
                        aria-hidden="true"
                      >
                        <q-icon name="circle" size="8px" />
                      </span>
                      <span class="nav-label admin-nav-child__label">
                        {{ child.label }}
                      </span>
                      <span
                        v-if="child.metaLabel"
                        class="admin-nav-child__meta mono"
                      >
                        {{ child.metaLabel }}
                      </span>
                      <q-icon
                        :name="
                          isDatabaseItemExpanded(child.id)
                            ? 'expand_less'
                            : 'expand_more'
                        "
                        size="18px"
                        class="admin-nav-row__group-chevron"
                        aria-hidden="true"
                      />
                    </div>
                    <div
                      v-if="
                        child.expandable && isDatabaseItemExpanded(child.id)
                      "
                      class="admin-nav-children admin-nav-children--nested"
                    >
                      <template
                        v-for="table in child.children"
                        :key="table.id"
                      >
                        <div class="admin-nav-row">
                          <a
                            class="nav-item admin-nav-leaf admin-nav-row__link"
                            :class="{
                              active: isTableNavActive(table),
                              'is-expanded': isTableItemExpanded(table.id),
                            }"
                            :href="table.toUri"
                            :aria-current="
                              isTableNavActive(table) ? 'page' : undefined
                            "
                            @click.prevent="openTableNav(table)"
                          >
                            <span class="nav-icon admin-nav-leaf__icon">
                              <q-icon name="table_chart" size="12px" />
                            </span>
                            <span
                              class="nav-label admin-nav-leaf__label mono"
                            >
                              {{ table.label }}
                            </span>
                          </a>
                          <q-btn
                            flat
                            dense
                            round
                            size="sm"
                            class="admin-nav-leaf__toggle"
                            :icon="
                              isTableItemExpanded(table.id)
                                ? 'expand_less'
                                : 'expand_more'
                            "
                            :aria-label="tableItemToggleLabel(table)"
                            :aria-expanded="isTableItemExpanded(table.id)"
                            @click="toggleTableItem(table.id)"
                          />
                        </div>
                        <div
                          v-if="isTableItemExpanded(table.id)"
                          class="admin-nav-children admin-nav-children--deep"
                        >
                          <a
                            v-for="view in table.views"
                            :key="view.id"
                            class="nav-item admin-nav-leaf admin-nav-leaf--deep"
                            :class="{ active: isTableLeafActive(view) }"
                            :href="view.toUri"
                            :aria-current="
                              isTableLeafActive(view) ? 'page' : undefined
                            "
                            @click.prevent="openTableView(view)"
                          >
                            <span class="nav-icon admin-nav-leaf__icon">
                              <q-icon
                                :name="
                                  view.view === 'data'
                                    ? 'dataset'
                                    : 'view_column'
                                "
                                size="12px"
                              />
                            </span>
                            <span class="nav-label admin-nav-leaf__label">
                              {{ view.label }}
                            </span>
                          </a>
                        </div>
                      </template>
                      <div
                        v-if="child.children.length === 0"
                        class="admin-nav-empty admin-nav-empty--nested"
                      >
                        <template
                          v-if="
                            databaseTablesPlaceholder(child) === 'loading'
                          "
                        >
                          {{ t("layouts.adminNav.tablesLoading") }}
                        </template>
                        <q-btn
                          v-else-if="
                            databaseTablesPlaceholder(child) === 'error'
                          "
                          flat
                          dense
                          no-caps
                          size="sm"
                          icon="refresh"
                          :label="t('common.retry')"
                          @click="retryDatabaseTables(child)"
                        />
                        <template v-else>
                          {{ t("layouts.adminNav.tablesEmpty") }}
                        </template>
                      </div>
                    </div>
                  </template>
                </div>
                <div
                  v-if="item.children.length === 0 && item.emptyChildrenLabel"
                  class="admin-nav-empty"
                >
                  {{ item.emptyChildrenLabel }}
                </div>
              </template>
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
import { useDatabaseCatalogStore } from "src/stores/databaseCatalog";

type AdminSectionKey = "adminSection" | "systemSection";

/** 导航目标：既能作为一级入口，也能作为“数据库”下的动态子菜单。 */
type AdminNavTarget = {
  id: string;
  toUri: string;
  name: string;
  params?: Record<string, string>;
  query?: Record<string, string>;
  label: string;
  subtitle: string;
};

/** 四级菜单项：某张数据表下的视图入口（结构 / 数据）。 */
type AdminNavViewLink = {
  id: string;
  /** 结构视图不带 view query；数据视图带 view=data。 */
  view: "structure" | "data";
  label: string;
  toUri: string;
  name: string;
  params: Record<string, string>;
  query: Record<string, string>;
};

/** 三级菜单项：数据库下的每张数据表，跳转时携带 `?table=` 定位。 */
type AdminNavTableLink = {
  id: string;
  label: string;
  toUri: string;
  name: string;
  params: Record<string, string>;
  query: Record<string, string>;
  /** 四级视图入口：整行点击进结构视图，右侧箭头展开这两项。 */
  views: AdminNavViewLink[];
};

/**
 * 二级菜单项：识别到的数据库。它既能作为跳转链接，也能像一级分组一样
 * 展开第三级菜单（该库的每张数据表）。
 */
type AdminNavChild = AdminNavTarget & {
  metaLabel?: string | null;
  expandable?: boolean;
  children: AdminNavTableLink[];
};

/**
 * 一级菜单项：带 `toUri` 时可跳转；仅作为分组（如“数据库”）时
 * 点击只展开下拉子菜单，不再进入独立页面。
 */
type AdminNavItem = {
  id: string;
  label: string;
  icon: string;
  children: AdminNavChild[];
  emptyChildrenLabel?: string;
  toUri?: string;
  name?: string;
  subtitle?: string;
};

type AdminNavSection = {
  key: AdminSectionKey;
  titleKey: string;
  items: AdminNavItem[];
};

const ADMIN_DRAWER_WIDTH = 260;
const ADMIN_DRAWER_BREAKPOINT = 1024;
const ADMIN_LAYOUT_GAP = 8;

const route = useRoute();
const router = useRouter();
const { t } = useI18n();
const databaseCatalog = useDatabaseCatalogStore();

const drawerOpen = ref(true);
const drawerHasLayout = ref(true);
const adminLayoutStyle: Record<string, string> = {
  "--admin-drawer-width": `${ADMIN_DRAWER_WIDTH}px`,
  "--admin-layout-gap": `${ADMIN_LAYOUT_GAP}px`,
  "--admin-layout-hidden-page-x": `${ADMIN_DRAWER_WIDTH / 2 + ADMIN_LAYOUT_GAP}px`,
};
const expandedAdminSections = reactive<Record<AdminSectionKey, boolean>>({
  adminSection: true,
  systemSection: false,
});
/** 未显式收起即视为展开，新增子菜单默认可见。 */
const collapsedNavItems = reactive<Record<string, boolean>>({});
/**
 * 数据库项默认收起：展开意味着为该库单独建连读取表清单，
 * 因此只保留显式展开，避免进入后台即为每个库发起探测。
 */
const expandedDatabaseItems = reactive<Record<string, boolean>>({});
/**
 * 四级视图菜单默认收起：表项整行点击仍直达结构视图，
 * 只有显式展开才显示「结构 / 数据」两个入口。
 */
const expandedTableItems = reactive<Record<string, boolean>>({});

const databaseChildren = computed<AdminNavChild[]>(() =>
  databaseCatalog.databases.map((database) => ({
    id: `database-${database.name}`,
    toUri: `/admin/database/${encodeURIComponent(database.name)}`,
    name: "admin-database-tables",
    params: { databaseName: database.name },
    label: database.name,
    subtitle: t("layouts.adminNav.databaseTablesSub"),
    metaLabel:
      database.table_count === null ? null : String(database.table_count),
    expandable: true,
    children: databaseCatalog.tablesOf(database.name).map((table) => {
      const baseUri = `/admin/database/${encodeURIComponent(database.name)}`;
      const tableUri = `${baseUri}?table=${encodeURIComponent(table.name)}`;
      const structureQuery = { table: table.name };
      const dataQuery = { table: table.name, view: "data" };
      const views: AdminNavViewLink[] = [
        {
          id: `database-table-${database.name}-${table.name}-structure`,
          view: "structure",
          label: t("layouts.adminNav.tableStructure"),
          toUri: tableUri,
          name: "admin-database-tables",
          params: { databaseName: database.name },
          query: structureQuery,
        },
        {
          id: `database-table-${database.name}-${table.name}-data`,
          view: "data",
          label: t("layouts.adminNav.tableData"),
          toUri: `${tableUri}&view=data`,
          name: "admin-database-tables",
          params: { databaseName: database.name },
          query: dataQuery,
        },
      ];
      return {
        id: `database-table-${database.name}-${table.name}`,
        label: table.name,
        toUri: tableUri,
        name: "admin-database-tables",
        params: { databaseName: database.name },
        query: structureQuery,
        views,
      };
    }),
  })),
);

const adminNavSections = computed<AdminNavSection[]>(() => [
  {
    key: "adminSection",
    titleKey: "adminSection",
    items: [
      {
        id: "users",
        toUri: "/admin/users",
        name: "admin-users",
        label: t("layouts.adminNav.users"),
        subtitle: t("layouts.adminNav.usersSub"),
        icon: "group",
        children: [],
      },
      {
        id: "workTickets",
        toUri: "/admin/work-tickets",
        name: "admin-work-tickets",
        label: t("layouts.adminNav.workTickets"),
        subtitle: t("layouts.adminNav.workTicketsSub"),
        icon: "support_agent",
        children: [],
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
        name: "admin-system-settings",
        label: t("layouts.adminNav.systemSettings"),
        subtitle: t("layouts.adminNav.systemSettingsSub"),
        icon: "settings",
        children: [],
      },
      {
        id: "databases",
        label: t("layouts.adminNav.databases"),
        icon: "storage",
        children: databaseChildren.value,
        emptyChildrenLabel: databaseCatalog.isLoading
          ? t("layouts.adminNav.databasesLoading")
          : t("layouts.adminNav.databasesEmpty"),
      },
    ],
  },
]);

const allNavTargets = computed<AdminNavTarget[]>(() =>
  adminNavSections.value.flatMap((section) =>
    section.items.flatMap((item) => {
      const link = navLinkOf(item);
      return link ? [link, ...item.children] : [...item.children];
    }),
  ),
);

function navLinkOf(item: AdminNavItem): AdminNavTarget | null {
  if (!item.toUri || !item.name) {
    return null;
  }
  return {
    id: item.id,
    toUri: item.toUri,
    name: item.name,
    label: item.label,
    subtitle: item.subtitle ?? item.label,
  };
}

function isAdminSectionExpanded(sectionKey: AdminSectionKey): boolean {
  return expandedAdminSections[sectionKey] === true;
}

function toggleAdminSection(sectionKey: AdminSectionKey) {
  expandedAdminSections[sectionKey] = !expandedAdminSections[sectionKey];
}

function isNavItemExpanded(itemId: string): boolean {
  return collapsedNavItems[itemId] !== true;
}

function toggleNavItem(itemId: string) {
  // 状态以“未收起的 id 不在 collapsedNavItems 中”表达，
  // 展开时写入 true 表示收起，收起时清除标记才会重新展开。
  collapsedNavItems[itemId] = isNavItemExpanded(itemId);
}

function navChildrenToggleLabel(item: AdminNavItem): string {
  return t(
    isNavItemExpanded(item.id)
      ? "layouts.adminNav.collapseChildren"
      : "layouts.adminNav.expandChildren",
    { label: item.label },
  );
}

function normalizeAdminPath(path: string): string {
  const base = path.split("?")[0] ?? path;
  if (base.length > 1 && base.endsWith("/")) {
    return base.slice(0, -1);
  }
  return base;
}

function isNavTargetActive(toUri: string, path?: string): boolean {
  const current = normalizeAdminPath(path ?? currentAdminPath.value);
  const target = normalizeAdminPath(toUri);
  return current === target || current.startsWith(`${target}/`);
}

/** 当前路由的 `?table=` 参数，用于高亮三级菜单中的数据表。 */
function currentTableName(): string {
  const raw = route.query.table;
  const value = Array.isArray(raw) ? raw[0] : raw;
  return typeof value === "string" ? value : "";
}

/** 数据库项只有在其页面未指定数据表时才算当前页，避免与三级项重复。 */
function isDatabaseChildActive(child: AdminNavChild): boolean {
  if (!isNavTargetActive(child.toUri)) {
    return false;
  }
  return !currentTableName();
}

/** 当前路由的 `?view=` 参数：只有 `data` 表示数据视图，其余均为结构视图。 */
function currentView(): string {
  const raw = route.query.view;
  const value = Array.isArray(raw) ? raw[0] : raw;
  return typeof value === "string" ? value : "";
}

/**
 * 三级项只在结构视图高亮：数据视图由四级项承担页标记，
 * 保证全页只有一处 ``aria-current="page"``。
 */
function isTableNavActive(table: AdminNavTableLink): boolean {
  if (!isNavTargetActive(table.toUri)) {
    return false;
  }
  if (currentTableName() !== table.query.table) {
    return false;
  }
  return currentView() !== "data";
}

/** 四级项只在「表 + 视图」同时命中时高亮。 */
function isTableLeafActive(view: AdminNavViewLink): boolean {
  if (!isNavTargetActive(view.toUri)) {
    return false;
  }
  if (currentTableName() !== view.query.table) {
    return false;
  }
  return currentView() === (view.view === "data" ? "data" : "");
}

function isTableItemExpanded(itemId: string): boolean {
  return expandedTableItems[itemId] === true;
}

function toggleTableItem(itemId: string) {
  expandedTableItems[itemId] = !isTableItemExpanded(itemId);
}

function tableItemToggleLabel(table: AdminNavTableLink): string {
  return t(
    isTableItemExpanded(table.id)
      ? "layouts.adminNav.collapseTable"
      : "layouts.adminNav.expandTable",
    { label: table.label },
  );
}

function isDatabaseItemExpanded(itemId: string): boolean {
  return expandedDatabaseItems[itemId] === true;
}

function toggleDatabaseItem(itemId: string) {
  expandedDatabaseItems[itemId] = !isDatabaseItemExpanded(itemId);
}

/** 数据表占位状态：尚未加载完也按加载中呈现，避免闪现空态。 */
function databaseTablesPlaceholder(
  child: AdminNavChild,
): "loading" | "error" | "empty" {
  const status = databaseCatalog.tableStatusOf(child.label);
  if (status === "error") {
    return "error";
  }
  if (status === "ready") {
    return "empty";
  }
  return "loading";
}

function retryDatabaseTables(child: AdminNavChild) {
  void databaseCatalog.ensureTablesLoaded(child.label).catch(() => undefined);
}

/** 有子菜单的一级导航仅在自身页面高亮，避免与子项同时标记为当前页。 */
function isNavItemActive(item: AdminNavItem): boolean {
  if (!item.toUri) {
    return false;
  }
  if (item.children.length > 0) {
    return (
      normalizeAdminPath(currentAdminPath.value) ===
      normalizeAdminPath(item.toUri)
    );
  }
  return isNavTargetActive(item.toUri);
}

const currentAdminPath = computed(() =>
  normalizeAdminPath(route?.path ?? "/admin/users"),
);

const currentNavTarget = computed<AdminNavTarget | null>(() => {
  const matches = allNavTargets.value.filter((target) =>
    isNavTargetActive(target.toUri),
  );
  if (!matches.length) {
    return null;
  }
  return matches.reduce((best, current) =>
    current.toUri.length > best.toUri.length ? current : best,
  );
});

/** 一级项自身或其子项命中当前路由时，自动展开所属分组。 */
function navItemOwnsRoute(item: AdminNavItem): boolean {
  if (item.toUri && isNavTargetActive(item.toUri)) {
    return true;
  }
  return item.children.some((child) => isNavTargetActive(child.toUri));
}

function openCurrentAdminSection() {
  const section = adminNavSections.value.find((sectionItem) =>
    sectionItem.items.some(navItemOwnsRoute),
  );
  if (section) {
    expandedAdminSections[section.key] = true;
  }
}

/** 当前路由落在某个数据库页面时，自动展开该库的数据表菜单。 */
function openCurrentDatabaseItem() {
  const currentPath = currentAdminPath.value;
  for (const child of databaseChildren.value) {
    if (normalizeAdminPath(child.toUri) === currentPath) {
      expandedDatabaseItems[child.id] = true;
    }
  }
}

/** 当前路由落在某张表的视图上时，自动展开该表的四级菜单。 */
function openCurrentTableItem() {
  const tableName = currentTableName();
  if (!tableName) {
    return;
  }
  const currentPath = currentAdminPath.value;
  for (const child of databaseChildren.value) {
    if (normalizeAdminPath(child.toUri) !== currentPath) {
      continue;
    }
    for (const table of child.children) {
      if (table.query.table === tableName) {
        expandedTableItems[table.id] = true;
      }
    }
  }
}

function openCurrentNavPath() {
  openCurrentAdminSection();
  openCurrentDatabaseItem();
  openCurrentTableItem();
}

function setDrawerLayout(value: boolean) {
  drawerHasLayout.value = value;
}

/** 同一页面内切换数据表只改 query，因此导航前需要比较 query 是否一致。 */
function sameNavQuery(nextQuery: Record<string, unknown>): boolean {
  const current = route.query;
  const keys = new Set([...Object.keys(current), ...Object.keys(nextQuery)]);
  for (const key of keys) {
    const rawCurrent = current[key];
    const rawNext = nextQuery[key];
    const currentValue = Array.isArray(rawCurrent) ? rawCurrent[0] : rawCurrent;
    const nextValue = Array.isArray(rawNext) ? rawNext[0] : rawNext;
    if (String(currentValue ?? "") !== String(nextValue ?? "")) {
      return false;
    }
  }
  return true;
}

async function openNavTarget(
  target: AdminNavTarget,
  nextQuery?: Record<string, string>,
) {
  const query = nextQuery ?? target.query ?? route.query;
  if (
    normalizeAdminPath(route.path) === normalizeAdminPath(target.toUri) &&
    sameNavQuery(query)
  ) {
    return;
  }
  // exactOptionalPropertyTypes 下 params 不接受 undefined，仅在存在时传入。
  if (target.params) {
    await router.push({ name: target.name, params: target.params, query });
    return;
  }
  await router.push({ name: target.name, query });
}

/**
 * 整行点击数据库项：不在该库页面时先进入该库并展开数据表，
 * 已在该库页面时只切换数据表的展开/收起。
 */
async function activateDatabaseRow(child: AdminNavChild) {
  // 停留在该库的数据表明细视图（`?table=`）时，路径虽然已经命中，
  // 但必须清除 `?table=` 才能回到该库的表清单，因此与跨库点击同样导航。
  if (!isNavTargetActive(child.toUri) || currentTableName() !== "") {
    expandedDatabaseItems[child.id] = true;
    await openNavTarget(child, {});
    return;
  }
  toggleDatabaseItem(child.id);
}

/** 点击数据表：进入所属数据库页面并用 `?table=` 定位该表。 */
async function openTableNav(table: AdminNavTableLink) {
  await openNavTarget(
    {
      id: table.id,
      toUri: table.toUri,
      name: table.name,
      params: table.params,
      label: table.label,
      subtitle: t("layouts.adminNav.databaseTablesSub"),
    },
    table.query,
  );
}

/** 点击四级视图项：进入该表的结构视图或数据视图。 */
async function openTableView(view: AdminNavViewLink) {
  await openNavTarget(
    {
      id: view.id,
      toUri: view.toUri,
      name: view.name,
      params: view.params,
      label: view.label,
      subtitle: t("layouts.adminNav.databaseTablesSub"),
    },
    view.query,
  );
}

/** 分组项没有可跳转目标，点击时只切换下拉菜单。 */
function openNavItem(item: AdminNavItem): void {
  const link = navLinkOf(item);
  if (link) {
    void openNavTarget(link);
  }
}

watch(
  () => route.fullPath,
  () => {
    openCurrentNavPath();
    // “数据库”下拉子菜单需要目录数据，首次进入或上次失败时补一次加载。
    if (databaseCatalog.status !== "ready" && !databaseCatalog.isLoading) {
      void databaseCatalog.ensureLoaded().catch(() => undefined);
    }
  },
  { immediate: true },
);

// 目录是异步加载的：数据到位后需要重新定位当前库，深链才能自动展开。
watch(
  () =>
    databaseChildren.value
      .map((child) => child.id)
      .join("|"),
  () => {
    openCurrentNavPath();
  },
);

/**
 * 仅对展开中的数据库按需请求表清单。用 NUL 拼接成字符串键，
 * 避免目录重新加载产生同名新数组时触发重复请求。
 */
const expandedDatabaseNames = computed<string>(() =>
  databaseChildren.value
    .filter((child) => isDatabaseItemExpanded(child.id))
    .map((child) => child.label)
    .join("\u0000"),
);

watch(
  expandedDatabaseNames,
  (joined) => {
    for (const name of joined.split("\u0000")) {
      if (!name) {
        continue;
      }
      if (databaseCatalog.tableStatusOf(name) === "ready") {
        continue;
      }
      void databaseCatalog.ensureTablesLoaded(name).catch(() => undefined);
    }
  },
  { immediate: true },
);

const headerTitle = computed(
  () => currentNavTarget.value?.label ?? t("layouts.adminTitle"),
);

const headerSubtitle = computed(
  () => currentNavTarget.value?.subtitle ?? t("layouts.adminNav.usersSub"),
);
</script>