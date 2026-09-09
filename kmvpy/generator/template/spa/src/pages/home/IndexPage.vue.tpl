<template>
  <q-page class="kmvpy-home-page">
    <section id="hero" class="kmvpy-hero" aria-labelledby="kmvpy-hero-title">
      <div class="kmvpy-shell kmvpy-hero__grid">
        <div class="kmvpy-hero__copy">
          <div class="kmvpy-eyebrow">
            <span class="kmvpy-eyebrow__mark"></span>
            {{ t("landing.hero.badge") }}
          </div>
          <h1 id="kmvpy-hero-title">{{ t("landing.hero.title") }}</h1>
          <p class="kmvpy-hero__subtitle">{{ t("landing.hero.subtitle") }}</p>
          <div class="kmvpy-hero__actions">
            <a
              class="btn-primary btn-large kmvpy-button"
              href="#quickstart"
              @click.prevent="scrollToSection('quickstart')"
            >
              <q-icon name="rocket_launch" size="18px" />
              {{ t("landing.hero.ctaStart") }}
            </a>
            <a
              class="btn-ghost btn-large kmvpy-button"
              :href="githubUrl"
              target="_blank"
              rel="noreferrer"
            >
              <q-icon name="code" size="18px" />
              {{ t("landing.hero.ctaGithub") }}
            </a>
          </div>
          <div
            class="kmvpy-hero__facts"
            :aria-label="t('landing.hero.factsLabel')"
          >
            <div
              v-for="fact in heroFacts"
              :key="fact.label"
              class="kmvpy-fact"
            >
              <strong>{{ fact.value }}</strong>
              <span>{{ fact.label }}</span>
            </div>
          </div>
        </div>

        <div
          class="kmvpy-dev-visual"
          :aria-label="t('landing.hero.visualAria')"
        >
          <div class="kmvpy-window kmvpy-window--terminal">
            <div class="kmvpy-window__bar">
              <span></span>
              <span></span>
              <span></span>
              <strong>{{ t("landing.hero.terminalTitle") }}</strong>
            </div>
            <div class="kmvpy-terminal">
              <div
                v-for="command in heroCommands"
                :key="command"
                class="kmvpy-terminal__line"
              >
                <span>$</span>
                <code>{{ command }}</code>
              </div>
            </div>
          </div>

          <div class="kmvpy-visual-grid">
            <div class="kmvpy-window kmvpy-window--tree">
              <div class="kmvpy-window__label">
                {{ t("landing.hero.treeTitle") }}
              </div>
              <ul>
                <li>demo_project/</li>
                <li><span>├─</span> __PY_PROJECT_NAME__/</li>
                <li><span>│ ├─</span> app/etc/develop/config.yaml</li>
                <li><span>│ ├─</span> app/st_test/</li>
                <li><span>│ └─</span> __PROJECT_NAME__/core/main/</li>
                <li><span>└─</span> __SPA_PROJECT_NAME__/</li>
              </ul>
            </div>

            <div class="kmvpy-window kmvpy-window--flow">
              <div class="kmvpy-window__label">
                {{ t("landing.hero.flowTitle") }}
              </div>
              <div class="kmvpy-flow">
                <span>YAML</span>
                <i></i>
                <span>Pydantic</span>
                <i></i>
                <span>FastAPI</span>
                <i></i>
                <span>Deploy</span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>

    <section
      id="quickstart"
      class="kmvpy-section"
      aria-labelledby="quickstart-title"
    >
      <div class="kmvpy-shell">
        <div class="kmvpy-section__header">
          <div class="section-label">{{ t("landing.quickstart.section") }}</div>
          <h2 id="quickstart-title" class="section-title">
            {{ t("landing.quickstart.title") }}
          </h2>
          <p class="section-desc">{{ t("landing.quickstart.desc") }}</p>
        </div>
        <ol class="kmvpy-quickstart">
          <li
            v-for="step in quickstartSteps"
            :key="step.command"
            class="kmvpy-step-card"
          >
            <span class="kmvpy-step-card__index">{{ step.index }}</span>
            <code>{{ step.command }}</code>
            <p>{{ step.note }}</p>
          </li>
        </ol>
      </div>
    </section>

    <section
      id="capabilities"
      class="kmvpy-section kmvpy-section--muted"
      aria-labelledby="capabilities-title"
    >
      <div class="kmvpy-shell">
        <div class="kmvpy-section__header">
          <div class="section-label">
            {{ t("landing.capabilities.section") }}
          </div>
          <h2 id="capabilities-title" class="section-title">
            {{ t("landing.capabilities.title") }}
          </h2>
          <p class="section-desc">{{ t("landing.capabilities.desc") }}</p>
        </div>
        <div class="kmvpy-capability-grid">
          <article
            v-for="item in capabilityItems"
            :key="item.title"
            class="kmvpy-card kmvpy-capability"
          >
            <div class="kmvpy-card__icon">
              <q-icon :name="item.icon" size="22px" />
            </div>
            <h3>{{ item.title }}</h3>
            <p>{{ item.body }}</p>
          </article>
        </div>
      </div>
    </section>

    <section
      id="workflow"
      class="kmvpy-section"
      aria-labelledby="workflow-title"
    >
      <div class="kmvpy-shell">
        <div class="kmvpy-section__header">
          <div class="section-label">{{ t("landing.workflow.section") }}</div>
          <h2 id="workflow-title" class="section-title">
            {{ t("landing.workflow.title") }}
          </h2>
          <p class="section-desc">{{ t("landing.workflow.desc") }}</p>
        </div>
        <div class="kmvpy-workflow">
          <div
            v-for="step in workflowSteps"
            :key="step"
            class="kmvpy-workflow__item"
          >
            <span>{{ step }}</span>
          </div>
        </div>
      </div>
    </section>

    <section
      id="examples"
      class="kmvpy-section kmvpy-section--muted"
      aria-labelledby="examples-title"
    >
      <div class="kmvpy-shell">
        <div class="kmvpy-section__header">
          <div class="section-label">{{ t("landing.examples.section") }}</div>
          <h2 id="examples-title" class="section-title">
            {{ t("landing.examples.title") }}
          </h2>
          <p class="section-desc">{{ t("landing.examples.desc") }}</p>
        </div>
        <div class="kmvpy-code-panel">
          <div
            class="kmvpy-code-tabs"
            role="tablist"
            :aria-label="t('landing.examples.tabsLabel')"
          >
            <button
              v-for="tab in codeExamples"
              :key="tab.key"
              type="button"
              role="tab"
              :aria-selected="activeCodeTab === tab.key"
              :class="{ 'is-active': activeCodeTab === tab.key }"
              @click="activeCodeTab = tab.key"
            >
              <q-icon :name="tab.icon" size="18px" />
              {{ tab.label }}
            </button>
          </div>
          <pre><code>{{ activeCodeExample.code }}</code></pre>
        </div>
      </div>
    </section>

    <section
      id="security"
      class="kmvpy-section"
      aria-labelledby="security-title"
    >
      <div class="kmvpy-shell kmvpy-split">
        <div>
          <div class="section-label">{{ t("landing.security.section") }}</div>
          <h2 id="security-title" class="section-title">
            {{ t("landing.security.title") }}
          </h2>
          <p class="section-desc">{{ t("landing.security.desc") }}</p>
        </div>
        <div class="kmvpy-security-list">
          <div
            v-for="point in securityPoints"
            :key="point"
            class="kmvpy-check-row"
          >
            <q-icon name="verified_user" size="18px" />
            <span>{{ point }}</span>
          </div>
        </div>
      </div>
    </section>

    <section
      id="usecases"
      class="kmvpy-section kmvpy-section--muted"
      aria-labelledby="usecases-title"
    >
      <div class="kmvpy-shell">
        <div class="kmvpy-section__header">
          <div class="section-label">{{ t("landing.usecases.section") }}</div>
          <h2 id="usecases-title" class="section-title">
            {{ t("landing.usecases.title") }}
          </h2>
          <p class="section-desc">{{ t("landing.usecases.desc") }}</p>
        </div>
        <div class="kmvpy-usecase-grid">
          <article
            v-for="item in useCases"
            :key="item.title"
            class="kmvpy-card kmvpy-usecase"
          >
            <h3>{{ item.title }}</h3>
            <p>{{ item.body }}</p>
          </article>
        </div>
      </div>
    </section>

    <section id="stack" class="kmvpy-section" aria-labelledby="stack-title">
      <div class="kmvpy-shell">
        <div class="kmvpy-section__header">
          <div class="section-label">{{ t("landing.stack.section") }}</div>
          <h2 id="stack-title" class="section-title">
            {{ t("landing.stack.title") }}
          </h2>
          <p class="section-desc">{{ t("landing.stack.desc") }}</p>
        </div>
        <div class="kmvpy-stack-tags">
          <span v-for="item in stackItems" :key="item">{{ item }}</span>
        </div>
      </div>
    </section>

    <section
      id="faq"
      class="kmvpy-section kmvpy-section--muted"
      aria-labelledby="faq-title"
    >
      <div class="kmvpy-shell kmvpy-faq-shell">
        <div class="kmvpy-section__header">
          <div class="section-label">{{ t("landing.faq.section") }}</div>
          <h2 id="faq-title" class="section-title">
            {{ t("landing.faq.title") }}
          </h2>
          <p class="section-desc">{{ t("landing.faq.desc") }}</p>
        </div>
        <div class="kmvpy-status-grid">
          <div
            v-for="status in statusItems"
            :key="status.label"
            class="kmvpy-status"
          >
            <strong>{{ status.value }}</strong>
            <span>{{ status.label }}</span>
          </div>
        </div>
        <div class="kmvpy-faq-list">
          <article
            v-for="(item, index) in faqItems"
            :key="item.question"
            class="kmvpy-faq-item"
          >
            <button
              type="button"
              :aria-expanded="openFaqIndex === index"
              @click="openFaqIndex = openFaqIndex === index ? -1 : index"
            >
              <span>{{ item.question }}</span>
              <q-icon
                :name="openFaqIndex === index ? 'remove' : 'add'"
                size="20px"
              />
            </button>
            <p v-show="openFaqIndex === index">{{ item.answer }}</p>
          </article>
        </div>
      </div>
    </section>

    <section
      class="kmvpy-section kmvpy-final-cta"
      aria-labelledby="final-cta-title"
    >
      <div class="kmvpy-shell kmvpy-final-cta__inner">
        <div>
          <div class="section-label">{{ t("landing.cta.section") }}</div>
          <h2 id="final-cta-title" class="section-title">
            {{ t("landing.cta.title") }}
          </h2>
          <p class="section-desc">{{ t("landing.cta.desc") }}</p>
        </div>
        <div class="kmvpy-final-cta__actions">
          <a
            class="btn-primary btn-large kmvpy-button"
            href="#quickstart"
            @click.prevent="scrollToSection('quickstart')"
          >
            <q-icon name="rocket_launch" size="18px" />
            {{ t("landing.hero.ctaStart") }}
          </a>
          <a
            class="btn-ghost btn-large kmvpy-button"
            :href="githubUrl"
            target="_blank"
            rel="noreferrer"
          >
            <q-icon name="code" size="18px" />
            {{ t("landing.hero.ctaGithub") }}
          </a>
        </div>
      </div>
    </section>
  </q-page>
</template>

<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from "vue";
import { useI18n } from "vue-i18n";

type SectionKey =
  | "index"
  | "quickstart"
  | "capabilities"
  | "workflow"
  | "examples"
  | "security"
  | "usecases"
  | "stack"
  | "faq";
type WindowWithLandingHelpers = Window & {
  go?: (page: SectionKey) => void;
};
type CapabilityIcon =
  | "hub"
  | "settings_suggest"
  | "storage"
  | "rule"
  | "vpn_key"
  | "schedule"
  | "sync_alt"
  | "science"
  | "account_tree";
type CodeTabKey = "cli" | "asgi" | "jwt" | "smoke";

interface LabelValueItem {
  value: string;
  label: string;
}

interface QuickstartStep {
  index: string;
  command: string;
  note: string;
}

interface CapabilityItem {
  icon: CapabilityIcon;
  title: string;
  body: string;
}

interface UseCaseItem {
  title: string;
  body: string;
}

interface CodeExample {
  key: CodeTabKey;
  label: string;
  icon: string;
  code: string;
}

interface FaqItem {
  question: string;
  answer: string;
}

const { t, locale } = useI18n();
const activeCodeTab = ref<CodeTabKey>("cli");
const openFaqIndex = ref(0);
const githubUrl = "https://github.com/kmvdata/kmvpy";

const heroCommands = [
  "pip install kmvpy",
  "kmvpy create demo_project",
  "cd demo_project/__PY_PROJECT_NAME__",
  "python app/run.py",
];

const codeExampleSnippets = computed<Record<CodeTabKey, string>>(() => {
  void locale.value;
  const cliSourceComment = t("landing.examples.cliSourceComment");

  return {
    cli: `pip install kmvpy
# ${cliSourceComment}
pip install .

kmvpy create demo_project
cd demo_project/__PY_PROJECT_NAME__
python app/run.py

kmvpy rotate-jwt-keys app/etc/release/config.yaml`,
  asgi: `from contextlib import asynccontextmanager
from fastapi import FastAPI
from kmvpy.core.main import get_config_path, init_asgi_app

from __PROJECT_NAME__.common.conf import AppConfig
from __PROJECT_NAME__.core.main.router import routers
from __PROJECT_NAME__.core.main.schedule import register_app_schedule_jobs


def gen_asgi_app(config_path: str | None = None) -> FastAPI:
    resolved = get_config_path(config_path)
    config = AppConfig.load_config(resolved)
    app = init_asgi_app(config, routers)
    existing_lifespan = app.router.lifespan_context

    @asynccontextmanager
    async def lifespan(app_: FastAPI):
        async with existing_lifespan(app_):
            register_app_schedule_jobs()
            yield

    app.router.lifespan_context = lifespan
    return app`,
  jwt: `auth_config:
  user:
    jwt:
      algorithm: RS256
      active_kid: k-user-active
      private_key_path: ./secrets/jwt-private-user-k-user-active.pem
      public_keys:
        - kid: k-user-active
          public_key_path: ./secrets/jwt-public-user-k-user-active.pem
        - kid: k-user-previous
          public_key_path: ./secrets/jwt-public-user-k-user-previous.pem
      issuer: kmvpy
      audience: kmvpy-user-api
    session:
      idle_timeout_hours: 24
  admin:
    jwt:
      algorithm: RS256
      active_kid: k-admin-active`,
  smoke: `test_send_email_verify_code:
  comment: user email verification smoke test
  case_list:
    - comment: send registration verification code
      steps:
        - step_kid: STEP_SEND_EMAIL_VERIFY_CODE
          action: POST /api/user/email/verify-code
          request:
            email: smoke@example.com
            scene: register
      expected:
        code: 0
        data:
          sent: false`,
  };
});

const heroFacts = computed<LabelValueItem[]>(() => [
  { value: "FastAPI", label: t("landing.hero.factFramework") },
  { value: ">= 3.11", label: t("landing.hero.factPython") },
  { value: "0.2.3", label: t("landing.hero.factVersion") },
  { value: "RS256", label: t("landing.hero.factJwt") },
]);

const quickstartSteps = computed<QuickstartStep[]>(() => [
  {
    index: "01",
    command: "pip install kmvpy",
    note: t("landing.quickstart.stepInstall"),
  },
  {
    index: "02",
    command: "kmvpy create demo_project",
    note: t("landing.quickstart.stepCreate"),
  },
  {
    index: "03",
    command: "python app/run.py",
    note: t("landing.quickstart.stepRun"),
  },
  {
    index: "04",
    command: "kmvpy rotate-jwt-keys app/etc/release/config.yaml",
    note: t("landing.quickstart.stepRotate"),
  },
]);

const capabilityItems = computed<CapabilityItem[]>(() => [
  {
    icon: "hub",
    title: t("landing.capabilities.asgiTitle"),
    body: t("landing.capabilities.asgiBody"),
  },
  {
    icon: "settings_suggest",
    title: t("landing.capabilities.configTitle"),
    body: t("landing.capabilities.configBody"),
  },
  {
    icon: "storage",
    title: t("landing.capabilities.storageTitle"),
    body: t("landing.capabilities.storageBody"),
  },
  {
    icon: "rule",
    title: t("landing.capabilities.responseTitle"),
    body: t("landing.capabilities.responseBody"),
  },
  {
    icon: "vpn_key",
    title: t("landing.capabilities.jwtTitle"),
    body: t("landing.capabilities.jwtBody"),
  },
  {
    icon: "schedule",
    title: t("landing.capabilities.scheduleTitle"),
    body: t("landing.capabilities.scheduleBody"),
  },
  {
    icon: "sync_alt",
    title: t("landing.capabilities.socketTitle"),
    body: t("landing.capabilities.socketBody"),
  },
  {
    icon: "science",
    title: t("landing.capabilities.smokeTitle"),
    body: t("landing.capabilities.smokeBody"),
  },
  {
    icon: "account_tree",
    title: t("landing.capabilities.generatorTitle"),
    body: t("landing.capabilities.generatorBody"),
  },
]);

const workflowSteps = computed(() => [
  t("landing.workflow.create"),
  t("landing.workflow.configure"),
  t("landing.workflow.extend"),
  t("landing.workflow.test"),
  t("landing.workflow.deploy"),
  t("landing.workflow.rotate"),
]);

const codeExamples = computed<CodeExample[]>(() => [
  {
    key: "cli",
    label: t("landing.examples.cliLabel"),
    icon: "terminal",
    code: codeExampleSnippets.value.cli,
  },
  {
    key: "asgi",
    label: t("landing.examples.asgiLabel"),
    icon: "integration_instructions",
    code: codeExampleSnippets.value.asgi,
  },
  {
    key: "jwt",
    label: t("landing.examples.jwtLabel"),
    icon: "vpn_key",
    code: codeExampleSnippets.value.jwt,
  },
  {
    key: "smoke",
    label: t("landing.examples.smokeLabel"),
    icon: "science",
    code: codeExampleSnippets.value.smoke,
  },
]);

const activeCodeExample = computed<CodeExample>(() => {
  const fallback: CodeExample = {
    key: "cli",
    label: "",
    icon: "terminal",
    code: "",
  };
  return (
    codeExamples.value.find((item) => item.key === activeCodeTab.value) ??
    codeExamples.value[0] ??
    fallback
  );
});

const securityPoints = computed(() => [
  t("landing.security.pointRs256"),
  t("landing.security.pointPemPath"),
  t("landing.security.pointRoles"),
  t("landing.security.pointRotation"),
  t("landing.security.pointSession"),
  t("landing.security.pointDeploy"),
]);

const useCases = computed<UseCaseItem[]>(() => [
  {
    title: t("landing.usecases.realtimeTitle"),
    body: t("landing.usecases.realtimeBody"),
  },
  {
    title: t("landing.usecases.contractTitle"),
    body: t("landing.usecases.contractBody"),
  },
  {
    title: t("landing.usecases.scaffoldTitle"),
    body: t("landing.usecases.scaffoldBody"),
  },
  {
    title: t("landing.usecases.ideTitle"),
    body: t("landing.usecases.ideBody"),
  },
]);

const stackItems = computed(() => [
  t("landing.stack.fastapi"),
  t("landing.stack.uvicorn"),
  t("landing.stack.pydantic"),
  t("landing.stack.sqlalchemy"),
  t("landing.stack.redis"),
  t("landing.stack.apscheduler"),
  t("landing.stack.pyjwt"),
  t("landing.stack.socketio"),
  t("landing.stack.pyyaml"),
  t("landing.stack.openai"),
  t("landing.stack.asyncpg"),
  t("landing.stack.aiosqlite"),
  t("landing.stack.cassandra"),
]);

const statusItems = computed<LabelValueItem[]>(() => [
  { value: "Python >= 3.11", label: t("landing.status.python") },
  { value: "0.2.3", label: t("landing.status.version") },
  { value: "Pre-Alpha", label: t("landing.status.stage") },
  { value: "MySQL", label: t("landing.status.mysql") },
]);

const faqItems = computed<FaqItem[]>(() => [
  { question: t("landing.faq.q1"), answer: t("landing.faq.a1") },
  { question: t("landing.faq.q2"), answer: t("landing.faq.a2") },
  { question: t("landing.faq.q3"), answer: t("landing.faq.a3") },
  { question: t("landing.faq.q4"), answer: t("landing.faq.a4") },
]);

const updateActiveNav = (section: SectionKey) => {
  document
    .querySelectorAll("#landing-top-nav .nav-links a")
    .forEach((anchor) => anchor.classList.remove("nav-active"));
  const navTarget = section === "index" ? "" : `#nav-${section}`;
  if (navTarget) {
    document.querySelector(navTarget)?.classList.add("nav-active");
  }
};

const scrollToSection = (section: SectionKey) => {
  if (section === "index") {
    window.scrollTo({ top: 0, behavior: "smooth" });
    updateActiveNav(section);
    return;
  }

  document
    .getElementById(section)
    ?.scrollIntoView({ behavior: "smooth", block: "start" });
  updateActiveNav(section);
};

const handleScroll = () => {
  const sectionIds: SectionKey[] = [
    "quickstart",
    "capabilities",
    "workflow",
    "faq",
  ];
  let current: SectionKey | null = null;

  sectionIds.forEach((section) => {
    const element = document.getElementById(section);
    if (element && element.getBoundingClientRect().top <= 120) {
      current = section;
    }
  });

  updateActiveNav(current ?? "index");
};

onMounted(() => {
  const landingWindow = window as WindowWithLandingHelpers;
  landingWindow.go = (page) => scrollToSection(page);
  window.addEventListener("scroll", handleScroll, { passive: true });

  const initialHash = window.location.hash.replace("#", "") as SectionKey;
  if (initialHash) {
    window.setTimeout(() => scrollToSection(initialHash), 80);
  }
});

onBeforeUnmount(() => {
  const landingWindow = window as WindowWithLandingHelpers;
  delete landingWindow.go;
  window.removeEventListener("scroll", handleScroll);
});
</script>

<style scoped>
.kmvpy-home-page {
  min-height: 100vh;
  background:
    linear-gradient(var(--surface-grid-line) 1px, transparent 1px),
    linear-gradient(90deg, var(--surface-grid-line) 1px, transparent 1px),
    var(--bg-primary);
  background-size: 56px 56px;
  color: var(--text-primary);
}

.kmvpy-shell {
  width: min(1180px, calc(100% - 48px));
  margin: 0 auto;
}

.kmvpy-hero {
  padding: 128px 0 84px;
}

.kmvpy-hero__grid {
  display: grid;
  grid-template-columns: minmax(0, 0.9fr) minmax(420px, 1.1fr);
  gap: 48px;
  align-items: center;
}

.kmvpy-hero__copy {
  display: grid;
  gap: 24px;
}

.kmvpy-eyebrow {
  display: inline-flex;
  align-items: center;
  gap: 10px;
  width: fit-content;
  padding: 7px 10px;
  border: 1px solid var(--status-info-border);
  border-radius: 8px;
  background: var(--status-info-bg);
  color: var(--status-info-text);
  font-family: var(--spa-mono-font-family);
  font-size: var(--spa-font-size-small);
  font-weight: 700;
}

.kmvpy-eyebrow__mark {
  width: 8px;
  height: 8px;
  border-radius: 50%;
  background: var(--accent-2);
}

.kmvpy-hero h1 {
  margin: 0;
  color: var(--text-primary);
  font-size: 64px;
  font-weight: 800;
  line-height: 1.02;
  letter-spacing: 0;
}

.kmvpy-hero__subtitle {
  max-width: 680px;
  margin: 0;
  color: var(--text-secondary);
  font-size: var(--spa-font-size-h3);
  line-height: 1.75;
}

.kmvpy-hero__actions,
.kmvpy-final-cta__actions {
  display: flex;
  flex-wrap: wrap;
  gap: 14px;
  align-items: center;
}

.kmvpy-button {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 8px;
  min-height: 52px;
}

.kmvpy-hero__facts {
  display: grid;
  grid-template-columns: repeat(4, minmax(0, 1fr));
  gap: 10px;
  max-width: 720px;
}

.kmvpy-fact,
.kmvpy-status {
  min-width: 0;
  padding: 14px;
  border: 1px solid var(--border);
  border-radius: 8px;
  background: var(--surface-glass);
}

.kmvpy-fact strong,
.kmvpy-status strong {
  display: block;
  margin-bottom: 6px;
  color: var(--text-primary);
  font-family: var(--spa-mono-font-family);
  font-size: var(--spa-font-size-body);
}

.kmvpy-fact span,
.kmvpy-status span {
  color: var(--text-secondary);
  font-size: var(--spa-font-size-small);
  line-height: 1.5;
}

.kmvpy-dev-visual {
  display: grid;
  gap: 14px;
}

.kmvpy-window {
  overflow: hidden;
  border: 1px solid var(--border);
  border-radius: 8px;
  background: var(--bg-card);
  box-shadow: var(--shadow-middle);
}

.kmvpy-window__bar {
  display: flex;
  align-items: center;
  gap: 7px;
  padding: 12px 14px;
  border-bottom: 1px solid var(--border);
  background: var(--bg-secondary);
}

.kmvpy-window__bar span {
  width: 10px;
  height: 10px;
  border-radius: 50%;
}

.kmvpy-window__bar span:nth-child(1) {
  background: var(--error);
}

.kmvpy-window__bar span:nth-child(2) {
  background: var(--warning);
}

.kmvpy-window__bar span:nth-child(3) {
  background: var(--success);
}

.kmvpy-window__bar strong,
.kmvpy-window__label {
  margin-left: 6px;
  color: var(--text-secondary);
  font-family: var(--spa-mono-font-family);
  font-size: var(--spa-font-size-small);
}

.kmvpy-terminal {
  display: grid;
  gap: 10px;
  padding: 18px;
  font-family: var(--spa-mono-font-family);
}

.kmvpy-terminal__line {
  display: grid;
  grid-template-columns: 18px minmax(0, 1fr);
  gap: 10px;
  align-items: start;
}

.kmvpy-terminal__line span {
  color: var(--accent-1);
}

.kmvpy-terminal__line code {
  min-width: 0;
  color: var(--text-primary);
  white-space: pre-wrap;
  word-break: break-word;
}

.kmvpy-visual-grid {
  display: grid;
  grid-template-columns: 1.08fr 0.92fr;
  gap: 14px;
}

.kmvpy-window--tree,
.kmvpy-window--flow {
  padding: 16px;
}

.kmvpy-window--tree ul {
  display: grid;
  gap: 8px;
  margin: 12px 0 0;
  padding: 0;
  color: var(--text-secondary);
  font-family: var(--spa-mono-font-family);
  font-size: var(--spa-font-size-small);
  list-style: none;
}

.kmvpy-window--tree span {
  color: var(--accent-2);
}

.kmvpy-flow {
  display: grid;
  gap: 10px;
  margin-top: 14px;
}

.kmvpy-flow span {
  display: block;
  padding: 10px 12px;
  border: 1px solid var(--status-success-border);
  border-radius: 8px;
  background: var(--status-success-bg);
  color: var(--status-success-text);
  font-family: var(--spa-mono-font-family);
  font-weight: 700;
}

.kmvpy-flow i {
  width: 1px;
  height: 14px;
  margin-left: 18px;
  background: var(--border);
}

.kmvpy-section {
  padding: 88px 0;
  scroll-margin-top: 88px;
}

.kmvpy-section--muted {
  background: color-mix(in srgb, var(--bg-secondary) 78%, transparent);
  border-top: 1px solid var(--border);
  border-bottom: 1px solid var(--border);
}

.kmvpy-section__header {
  max-width: 760px;
  margin-bottom: 34px;
}

.kmvpy-section__header .section-title,
.kmvpy-split .section-title,
.kmvpy-final-cta .section-title {
  margin: 0 0 14px;
}

.kmvpy-section__header .section-desc,
.kmvpy-split .section-desc,
.kmvpy-final-cta .section-desc {
  margin: 0;
}

.kmvpy-quickstart {
  display: grid;
  grid-template-columns: repeat(4, minmax(0, 1fr));
  gap: 14px;
  margin: 0;
  padding: 0;
  list-style: none;
}

.kmvpy-step-card,
.kmvpy-card,
.kmvpy-status,
.kmvpy-faq-item {
  border: 1px solid var(--border);
  border-radius: 8px;
  background: var(--bg-card);
}

.kmvpy-step-card {
  display: grid;
  gap: 16px;
  padding: 18px;
}

.kmvpy-step-card__index {
  width: fit-content;
  padding: 4px 8px;
  border-radius: 6px;
  background: var(--status-warning-bg);
  color: var(--status-warning-text);
  font-family: var(--spa-mono-font-family);
  font-weight: 700;
}

.kmvpy-step-card code {
  color: var(--text-primary);
  font-family: var(--spa-mono-font-family);
  line-height: 1.6;
  white-space: pre-wrap;
  word-break: break-word;
}

.kmvpy-step-card p,
.kmvpy-card p,
.kmvpy-faq-item p {
  margin: 0;
  color: var(--text-secondary);
  line-height: 1.7;
}

.kmvpy-capability-grid {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: 14px;
}

.kmvpy-card {
  padding: 20px;
}

.kmvpy-capability {
  display: grid;
  gap: 12px;
}

.kmvpy-card__icon {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 42px;
  height: 42px;
  border: 1px solid var(--status-info-border);
  border-radius: 8px;
  background: var(--status-info-bg);
  color: var(--status-info-text);
}

.kmvpy-card h3,
.kmvpy-usecase h3 {
  margin: 0;
  color: var(--text-primary);
  font-size: var(--spa-font-size-h4);
  line-height: 1.35;
}

.kmvpy-workflow {
  display: grid;
  grid-template-columns: repeat(6, minmax(0, 1fr));
  gap: 10px;
}

.kmvpy-workflow__item {
  position: relative;
  min-height: 92px;
  padding: 16px;
  border: 1px solid var(--border);
  border-radius: 8px;
  background: var(--bg-card);
}

.kmvpy-workflow__item::after {
  content: "";
  position: absolute;
  top: 50%;
  right: -10px;
  width: 10px;
  height: 1px;
  background: var(--border);
}

.kmvpy-workflow__item:last-child::after {
  content: none;
}

.kmvpy-workflow__item span {
  color: var(--text-primary);
  font-weight: 700;
  line-height: 1.5;
}

.kmvpy-code-panel {
  overflow: hidden;
  border: 1px solid var(--border);
  border-radius: 8px;
  background: var(--bg-card);
  box-shadow: var(--shadow-light);
}

.kmvpy-code-tabs {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
  padding: 12px;
  border-bottom: 1px solid var(--border);
  background: var(--bg-secondary);
}

.kmvpy-code-tabs button {
  display: inline-flex;
  align-items: center;
  gap: 7px;
  min-height: 40px;
  padding: 8px 12px;
  border: 1px solid var(--border);
  border-radius: 8px;
  background: var(--bg-card);
  color: var(--text-secondary);
  font: inherit;
  cursor: pointer;
}

.kmvpy-code-tabs button.is-active {
  border-color: var(--status-success-border);
  background: var(--status-success-bg);
  color: var(--status-success-text);
}

.kmvpy-code-panel pre {
  margin: 0;
  padding: 22px;
  overflow-x: auto;
  color: var(--text-primary);
  font-family: var(--spa-mono-font-family);
  line-height: 1.65;
}

.kmvpy-code-panel code {
  white-space: pre;
}

.kmvpy-split {
  display: grid;
  grid-template-columns: minmax(0, 0.86fr) minmax(360px, 1fr);
  gap: 44px;
  align-items: start;
}

.kmvpy-security-list {
  display: grid;
  gap: 10px;
}

.kmvpy-check-row {
  display: grid;
  grid-template-columns: 24px minmax(0, 1fr);
  gap: 10px;
  align-items: start;
  padding: 14px;
  border: 1px solid var(--border);
  border-radius: 8px;
  background: var(--bg-card);
  color: var(--text-secondary);
  line-height: 1.65;
}

.kmvpy-check-row .q-icon {
  color: var(--status-success-text);
  margin-top: 2px;
}

.kmvpy-usecase-grid {
  display: grid;
  grid-template-columns: repeat(4, minmax(0, 1fr));
  gap: 14px;
}

.kmvpy-usecase {
  display: grid;
  gap: 10px;
}

.kmvpy-stack-tags {
  display: flex;
  flex-wrap: wrap;
  gap: 10px;
}

.kmvpy-stack-tags span {
  padding: 9px 12px;
  border: 1px solid var(--border);
  border-radius: 8px;
  background: var(--bg-card);
  color: var(--text-primary);
  font-family: var(--spa-mono-font-family);
}

.kmvpy-faq-shell {
  max-width: 980px;
}

.kmvpy-status-grid {
  display: grid;
  grid-template-columns: repeat(4, minmax(0, 1fr));
  gap: 12px;
  margin-bottom: 24px;
}

.kmvpy-faq-list {
  display: grid;
  gap: 10px;
}

.kmvpy-faq-item {
  overflow: hidden;
}

.kmvpy-faq-item button {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 14px;
  width: 100%;
  padding: 18px;
  border: none;
  background: transparent;
  color: var(--text-primary);
  font: inherit;
  font-weight: 700;
  text-align: left;
  cursor: pointer;
}

.kmvpy-faq-item p {
  padding: 0 18px 18px;
}

.kmvpy-final-cta {
  padding-bottom: 104px;
}

.kmvpy-final-cta__inner {
  display: grid;
  grid-template-columns: minmax(0, 1fr) auto;
  gap: 32px;
  align-items: center;
  padding: 28px;
  border: 1px solid var(--border);
  border-radius: 8px;
  background: var(--bg-card);
}

@media (max-width: 1100px) {
  .kmvpy-hero__grid,
  .kmvpy-split {
    grid-template-columns: 1fr;
  }

  .kmvpy-workflow,
  .kmvpy-quickstart,
  .kmvpy-usecase-grid {
    grid-template-columns: repeat(2, minmax(0, 1fr));
  }

  .kmvpy-workflow__item::after {
    content: none;
  }
}

@media (max-width: 820px) {
  .kmvpy-shell {
    width: min(100% - 32px, 1180px);
  }

  .kmvpy-hero {
    padding: 104px 0 64px;
  }

  .kmvpy-hero h1 {
    font-size: 52px;
  }

  .kmvpy-hero__facts,
  .kmvpy-capability-grid,
  .kmvpy-status-grid,
  .kmvpy-visual-grid {
    grid-template-columns: 1fr;
  }

  .kmvpy-final-cta__inner {
    grid-template-columns: 1fr;
  }
}

@media (max-width: 640px) {
  .kmvpy-hero h1 {
    font-size: 44px;
  }

  .kmvpy-quickstart,
  .kmvpy-workflow,
  .kmvpy-usecase-grid {
    grid-template-columns: 1fr;
  }

  .kmvpy-hero__actions,
  .kmvpy-final-cta__actions {
    align-items: stretch;
    flex-direction: column;
  }

  .kmvpy-button {
    width: 100%;
  }

  .kmvpy-code-tabs {
    display: grid;
    grid-template-columns: 1fr;
  }
}
</style>
