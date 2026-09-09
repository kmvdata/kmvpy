<template>
  <q-page class="spa-page kmvpy-help-page">
    <div class="content-area spa-content-area spa-shell--wide">
      <section id="help-topic-overview" class="kmvpy-help__hero">
        <div>
          <div class="kmvpy-help__eyebrow">{{ t("helpCenter.eyebrow") }}</div>
          <h2 class="kmvpy-help__title">
            <span class="gradient-text">{{ t("helpCenter.title") }}</span>
          </h2>
          <p class="kmvpy-help__lead">{{ t("helpCenter.lead") }}</p>
        </div>
        <q-btn
          color="primary"
          unelevated
          no-caps
          icon="forum"
          :label="t('helpCenter.askSupport')"
          :to="{ name: 'user-work-tickets' }"
        />
      </section>

      <div class="kmvpy-help__stats">
        <div
          v-for="stat in stats"
          :key="stat.label"
          class="kmvpy-help-stat"
        >
          <span class="kmvpy-help-stat__label">{{ stat.label }}</span>
          <strong class="kmvpy-help-stat__value">{{ stat.value }}</strong>
          <span class="kmvpy-help-stat__detail">{{ stat.detail }}</span>
        </div>
      </div>

      <div class="kmvpy-help__grid">
        <section
          v-for="section in sections"
          :id="`help-topic-${section.id}`"
          :key="section.id"
          class="kmvpy-help-section"
        >
          <div class="kmvpy-help-section__icon">
            <q-icon :name="section.icon" />
          </div>
          <h3 class="kmvpy-help-section__title">{{ section.title }}</h3>
          <p class="kmvpy-help-section__body">{{ section.body }}</p>
          <ul class="kmvpy-help-section__list">
            <li v-for="item in section.items" :key="item">{{ item }}</li>
          </ul>
        </section>
      </div>

      <section id="help-topic-quick-start" class="kmvpy-help__commands">
        <div class="kmvpy-help__section-heading">
          <h3>{{ t("helpCenter.quickStart.title") }}</h3>
          <p>{{ t("helpCenter.quickStart.subtitle") }}</p>
        </div>
        <div class="kmvpy-help-command-grid">
          <article
            v-for="commandGroup in commandGroups"
            :key="commandGroup.title"
            class="kmvpy-help-command"
          >
            <h4>{{ commandGroup.title }}</h4>
            <pre><code>{{ commandGroup.commands.join("\n") }}</code></pre>
          </article>
        </div>
      </section>

      <section class="kmvpy-help__topics">
        <div class="kmvpy-help__section-heading">
          <h3>{{ t("helpCenter.details.title") }}</h3>
          <p>{{ t("helpCenter.details.subtitle") }}</p>
        </div>
        <q-list bordered separator class="kmvpy-help-topic-list">
          <q-expansion-item
            v-for="topic in detailTopics"
            :key="topic.title"
            expand-separator
            :icon="topic.icon"
            :label="topic.title"
            :caption="topic.caption"
          >
            <div class="kmvpy-help-topic__body">
              <p>{{ topic.body }}</p>
              <ul>
                <li v-for="item in topic.items" :key="item">{{ item }}</li>
              </ul>
            </div>
          </q-expansion-item>
        </q-list>
      </section>
    </div>
  </q-page>
</template>

<script setup lang="ts">
import { computed, nextTick, watch } from "vue";
import { useI18n } from "vue-i18n";
import { useRoute } from "vue-router";

interface HelpStat {
  label: string;
  value: string;
  detail: string;
}

interface HelpSection {
  id: string;
  icon: string;
  title: string;
  body: string;
  items: string[];
}

interface CommandGroup {
  title: string;
  commands: string[];
}

interface DetailTopic {
  icon: string;
  title: string;
  caption: string;
  body: string;
  items: string[];
}

const { t } = useI18n();
const route = useRoute();

const stats = computed<HelpStat[]>(() => [
  {
    label: t("helpCenter.stats.framework.label"),
    value: t("helpCenter.stats.framework.value"),
    detail: t("helpCenter.stats.framework.detail"),
  },
  {
    label: t("helpCenter.stats.python.label"),
    value: t("helpCenter.stats.python.value"),
    detail: t("helpCenter.stats.python.detail"),
  },
  {
    label: t("helpCenter.stats.version.label"),
    value: t("helpCenter.stats.version.value"),
    detail: t("helpCenter.stats.version.detail"),
  },
  {
    label: t("helpCenter.stats.jwt.label"),
    value: t("helpCenter.stats.jwt.value"),
    detail: t("helpCenter.stats.jwt.detail"),
  },
]);

const sections = computed<HelpSection[]>(() => [
  {
    id: "foundation",
    icon: "foundation",
    title: t("helpCenter.sections.foundation.title"),
    body: t("helpCenter.sections.foundation.body"),
    items: [
      t("helpCenter.sections.foundation.items.app"),
      t("helpCenter.sections.foundation.items.config"),
      t("helpCenter.sections.foundation.items.response"),
    ],
  },
  {
    id: "structure",
    icon: "schema",
    title: t("helpCenter.sections.structure.title"),
    body: t("helpCenter.sections.structure.body"),
    items: [
      t("helpCenter.sections.structure.items.backend"),
      t("helpCenter.sections.structure.items.frontend"),
      t("helpCenter.sections.structure.items.deploy"),
    ],
  },
  {
    id: "security",
    icon: "security",
    title: t("helpCenter.sections.security.title"),
    body: t("helpCenter.sections.security.body"),
    items: [
      t("helpCenter.sections.security.items.jwt"),
      t("helpCenter.sections.security.items.redis"),
      t("helpCenter.sections.security.items.cors"),
    ],
  },
  {
    id: "testing",
    icon: "task_alt",
    title: t("helpCenter.sections.quality.title"),
    body: t("helpCenter.sections.quality.body"),
    items: [
      t("helpCenter.sections.quality.items.pytest"),
      t("helpCenter.sections.quality.items.yaml"),
      t("helpCenter.sections.quality.items.expect"),
    ],
  },
]);

const scrollToTopic = async (value: unknown) => {
  const topic = typeof value === "string" && value ? value : "overview";
  await nextTick();
  document
    .getElementById(`help-topic-${topic}`)
    ?.scrollIntoView({ behavior: "smooth", block: "start" });
};

watch(
  () => route.query.topic,
  (topic) => {
    void scrollToTopic(topic);
  },
  { immediate: true },
);

const commandGroups = computed<CommandGroup[]>(() => [
  {
    title: t("helpCenter.quickStart.createTitle"),
    commands: [
      t("helpCenter.quickStart.commands.install"),
      t("helpCenter.quickStart.commands.create"),
      t("helpCenter.quickStart.commands.enterBackend"),
      t("helpCenter.quickStart.commands.runBackend"),
    ],
  },
  {
    title: t("helpCenter.quickStart.repoTitle"),
    commands: [
      t("helpCenter.quickStart.commands.enterSisyphusPy"),
      t("helpCenter.quickStart.commands.createVenv"),
      t("helpCenter.quickStart.commands.activateVenv"),
      t("helpCenter.quickStart.commands.installRepo"),
      t("helpCenter.quickStart.commands.runRepo"),
    ],
  },
  {
    title: t("helpCenter.quickStart.frontendTitle"),
    commands: [
      t("helpCenter.quickStart.commands.enterSpa"),
      t("helpCenter.quickStart.commands.bunInstall"),
      t("helpCenter.quickStart.commands.bunDev"),
      t("helpCenter.quickStart.commands.bunBuild"),
    ],
  },
]);

const detailTopics = computed<DetailTopic[]>(() => [
  {
    icon: "hub",
    title: t("helpCenter.details.runtime.title"),
    caption: t("helpCenter.details.runtime.caption"),
    body: t("helpCenter.details.runtime.body"),
    items: [
      t("helpCenter.details.runtime.items.config"),
      t("helpCenter.details.runtime.items.lifespan"),
      t("helpCenter.details.runtime.items.schedule"),
    ],
  },
  {
    icon: "storage",
    title: t("helpCenter.details.storage.title"),
    caption: t("helpCenter.details.storage.caption"),
    body: t("helpCenter.details.storage.body"),
    items: [
      t("helpCenter.details.storage.items.sqlalchemy"),
      t("helpCenter.details.storage.items.redis"),
      t("helpCenter.details.storage.items.kid"),
    ],
  },
  {
    icon: "key",
    title: t("helpCenter.details.jwt.title"),
    caption: t("helpCenter.details.jwt.caption"),
    body: t("helpCenter.details.jwt.body"),
    items: [
      t("helpCenter.details.jwt.items.algorithm"),
      t("helpCenter.details.jwt.items.paths"),
      t("helpCenter.details.jwt.items.rotation"),
    ],
  },
  {
    icon: "science",
    title: t("helpCenter.details.testing.title"),
    caption: t("helpCenter.details.testing.caption"),
    body: t("helpCenter.details.testing.body"),
    items: [
      t("helpCenter.details.testing.items.pytest"),
      t("helpCenter.details.testing.items.client"),
      t("helpCenter.details.testing.items.assertions"),
    ],
  },
]);
</script>

<style scoped>
.kmvpy-help__hero {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 16px;
  margin-bottom: 18px;
}

.kmvpy-help__eyebrow {
  color: var(--spa-text-muted);
  font-size: var(--spa-font-size-small);
  font-weight: 700;
  margin-bottom: 6px;
}

.kmvpy-help__title {
  margin: 0 0 8px;
  color: var(--spa-text-heading);
  font-size: 24px;
  font-weight: 800;
  line-height: 1.25;
}

.kmvpy-help__lead {
  margin: 0;
  max-width: 760px;
  color: var(--spa-text-muted);
  font-size: var(--spa-font-size-body);
  line-height: 1.7;
}

.kmvpy-help__stats,
.kmvpy-help__grid,
.kmvpy-help-command-grid {
  display: grid;
  gap: 12px;
}

.kmvpy-help__stats {
  grid-template-columns: repeat(4, minmax(0, 1fr));
  margin-bottom: 18px;
}

.kmvpy-help-stat,
.kmvpy-help-section,
.kmvpy-help-command {
  border: 1px solid var(--spa-border);
  border-radius: var(--spa-radius-md);
  background: var(--spa-surface-muted);
}

.kmvpy-help-stat {
  padding: 14px;
}

.kmvpy-help-stat__label,
.kmvpy-help-stat__detail {
  display: block;
  color: var(--spa-text-muted);
  font-size: var(--spa-font-size-small);
}

.kmvpy-help-stat__value {
  display: block;
  margin: 5px 0;
  color: var(--spa-text-heading);
  font-size: var(--spa-font-size-title);
  line-height: 1.2;
}

.kmvpy-help__grid {
  grid-template-columns: repeat(2, minmax(0, 1fr));
  margin-bottom: 22px;
}

.kmvpy-help-section {
  padding: 16px;
}

.kmvpy-help-section__icon {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 34px;
  height: 34px;
  border-radius: var(--spa-radius-sm);
  color: var(--spa-primary);
  background: var(--spa-primary-soft);
  margin-bottom: 12px;
}

.kmvpy-help-section__title,
.kmvpy-help__section-heading h3,
.kmvpy-help-command h4 {
  margin: 0;
  color: var(--spa-text-heading);
  font-weight: 700;
  line-height: 1.35;
}

.kmvpy-help-section__title {
  font-size: var(--spa-font-size-title);
}

.kmvpy-help-section__body,
.kmvpy-help__section-heading p,
.kmvpy-help-topic__body p {
  color: var(--spa-text-muted);
  font-size: var(--spa-font-size-body);
  line-height: 1.65;
}

.kmvpy-help-section__body {
  margin: 8px 0 10px;
}

.kmvpy-help-section__list,
.kmvpy-help-topic__body ul {
  margin: 0;
  padding-left: 18px;
  color: var(--spa-text-body);
  font-size: var(--spa-font-size-body);
  line-height: 1.7;
}

.kmvpy-help__commands,
.kmvpy-help__topics {
  margin-top: 22px;
}

.kmvpy-help__section-heading {
  margin-bottom: 12px;
}

.kmvpy-help__section-heading h3 {
  font-size: var(--spa-font-size-title);
}

.kmvpy-help__section-heading p {
  margin: 4px 0 0;
}

.kmvpy-help-command-grid {
  grid-template-columns: repeat(3, minmax(0, 1fr));
}

.kmvpy-help-command {
  min-width: 0;
  padding: 14px;
}

.kmvpy-help-command h4 {
  font-size: var(--spa-font-size-body);
  margin-bottom: 10px;
}

.kmvpy-help-command pre {
  margin: 0;
  overflow-x: auto;
  color: var(--spa-text-body);
  font-size: var(--spa-font-size-small);
  line-height: 1.6;
}

.kmvpy-help-topic-list {
  border-radius: var(--spa-radius-md);
  overflow: hidden;
  background: var(--spa-surface);
}

.kmvpy-help-topic__body {
  padding: 0 20px 16px 56px;
}

.kmvpy-help-topic__body p {
  margin: 0 0 8px;
}

@media (max-width: 1023px) {
  .kmvpy-help__stats,
  .kmvpy-help-command-grid {
    grid-template-columns: repeat(2, minmax(0, 1fr));
  }
}

@media (max-width: 700px) {
  .kmvpy-help__hero {
    flex-direction: column;
  }

  .kmvpy-help__stats,
  .kmvpy-help__grid,
  .kmvpy-help-command-grid {
    grid-template-columns: 1fr;
  }

  .kmvpy-help__title {
    font-size: 20px;
  }

  .kmvpy-help-topic__body {
    padding-left: 20px;
  }
}
</style>
