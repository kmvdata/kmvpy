<template>
  <q-layout
    view="lHh Lpr lFf"
    class="spa-layout home-layout"
    :class="{ 'home-layout--marketing': isMarketingShell }"
  >
    <q-header
      v-if="showLandingNav"
      bordered
      class="home-layout__landing-qheader"
    >
      <nav id="landing-top-nav">
        <a href="#" class="nav-logo" @click.prevent="landingGo('index')">
          <AppLogo size="sm" />
        </a>
        <ul class="nav-links">
          <li>
            <a
              href="#"
              id="nav-quickstart"
              @click.prevent="landingGo('quickstart')"
              >{{ t("landing.nav.quickstart") }}</a
            >
          </li>
          <li>
            <a
              href="#"
              id="nav-capabilities"
              @click.prevent="landingGo('capabilities')"
              >{{ t("landing.nav.capabilities") }}</a
            >
          </li>
          <li>
            <a
              href="#"
              id="nav-workflow"
              @click.prevent="landingGo('workflow')"
              >{{ t("landing.nav.workflow") }}</a
            >
          </li>
          <li>
            <a href="#" id="nav-faq" @click.prevent="landingGo('faq')">{{
              t("landing.nav.faq")
            }}</a>
          </li>
        </ul>
        <div class="nav-cta">
          <AccountStyleMenu account-kind="user">
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
        </div>
      </nav>
    </q-header>

    <q-page-container>
      <router-view />
    </q-page-container>
  </q-layout>
</template>

<script setup lang="ts">
import { computed } from "vue";
import { useI18n } from "vue-i18n";
import { useRoute } from "vue-router";

import AccountStyleMenu from "src/components/AccountStyleMenu.vue";
import AppLogo from "src/components/AppLogo.vue";
type LandingPageKey =
  | "index"
  | "quickstart"
  | "capabilities"
  | "workflow"
  | "faq";

type WindowWithLandingGo = Window & {
  go?: (page: LandingPageKey, sid?: string) => void;
};

const route = useRoute();
const { t } = useI18n();

const isMarketingShell = computed(
  () => ["/auth", "/login"].includes(route.path) || route.path === "/",
);

const showLandingNav = computed(() => route.name === "home");

const landingGo = (page: LandingPageKey) => {
  (window as WindowWithLandingGo).go?.(page);
};
</script>

<style scoped>
@media (max-width: 760px) {
  #landing-top-nav {
    min-height: 72px;
    height: auto;
    padding: 10px 16px;
    gap: 10px;
    flex-wrap: wrap;
  }

  .nav-links {
    order: 3;
    width: 100%;
    gap: 20px;
    padding-bottom: 2px;
    overflow-x: auto;
    scrollbar-width: none;
  }

  .nav-links::-webkit-scrollbar {
    display: none;
  }

  .nav-links a {
    white-space: nowrap;
  }

  .nav-cta {
    margin-left: 0;
  }
}
</style>
