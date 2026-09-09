/** KMVPy landing-page copy for IndexPage.vue */
export default {
  nav: {
    quickstart: "Quick Start",
    capabilities: "Capabilities",
    workflow: "Flow",
    faq: "FAQ",
  },
  hero: {
    badge: "FastAPI backend foundation and project scaffold",
    title: "KMVPy",
    subtitle:
      "A FastAPI backend foundation and project scaffold that moves a backend from an empty directory to runnable, testable, and deployable.",
    ctaStart: "Get Started",
    ctaGithub: "View on GitHub",
    factsLabel: "KMVPy project status",
    factFramework: "Backend framework",
    factPython: "Python version",
    factVersion: "Current version",
    factJwt: "Default JWT algorithm",
    visualAria: "KMVPy project generation and runtime preview",
    terminalTitle: "terminal",
    treeTitle: "generated workspace",
    flowTitle: "runtime flow",
  },
  quickstart: {
    section: "Quick Start",
    title: "The shortest path from install to running service",
    desc: "KMVPy is built for backend developers and engineering teams that want a runnable, configurable, testable, and deployable service foundation first.",
    stepInstall:
      "Install the published package; from source, run pip install . instead.",
    stepCreate:
      "Generate a workspace with Python backend, SPA, editor config, deployment files, and templates.",
    stepRun:
      "Load YAML config and start the FastAPI plus Uvicorn ASGI service.",
    stepRotate:
      "Rotate JWT keys before release and keep previous public keys for a smooth transition.",
  },
  capabilities: {
    section: "Capabilities",
    title: "Standardize the infrastructure every new FastAPI project repeats",
    desc: "KMVPy is not a plain template. It is a foundation library, runtime convention, and project generator for service entrypoints, config, storage, security, realtime APIs, schedules, and tests.",
    asgiTitle: "ASGI application entry",
    asgiBody:
      "init_asgi_app, lifespan, router aggregation, global exceptions, logging, and i18n in one path.",
    configTitle: "YAML configuration",
    configBody:
      "YAML to Pydantic config models for database, Redis, CORS, Socket.IO, JWT, and logging.",
    storageTitle: "Async storage layer",
    storageBody:
      "SQLAlchemy 2 async, pagination, safe sorting, Redis cache, and Snowflake kid generation.",
    responseTitle: "Unified responses and errors",
    responseBody:
      "ApiResponse, SocketioResponse, KmvException, and error-code conventions for frontend/backend contracts.",
    jwtTitle: "JWT and sessions",
    jwtBody:
      "Asymmetric algorithms, kid, key file paths, Redis sessions, automatic renewal, and key rotation.",
    scheduleTitle: "Scheduled jobs",
    scheduleBody:
      "APScheduler cron jobs, startup jobs, and unified lifecycle management.",
    socketTitle: "Socket.IO",
    socketBody:
      "Bound to the FastAPI app for REST plus realtime API scenarios.",
    smokeTitle: "Smoke tests",
    smokeBody:
      "pytest, YAML cases, and StExpect minimal assertions to avoid repetitive test code.",
    generatorTitle: "Project generator",
    generatorBody:
      "Python subproject, SPA subproject, VS Code/Cursor config, Nginx templates, and deployment config.",
  },
  workflow: {
    section: "Scaffold Flow",
    title: "From project creation to operational maintenance",
    desc: "The generator gives teams a default path while leaving routers, ORM models, schedules, and deployment details open for domain code.",
    create: "Create Project",
    configure: "Configure YAML",
    extend: "Add Routers / ORM / Schedules",
    test: "Run Smoke Tests",
    deploy: "Deploy",
    rotate: "Rotate JWT Keys",
  },
  examples: {
    section: "Code Examples",
    title: "Interfaces and config developers can inspect quickly",
    desc: "Commands, ASGI entrypoints, JWT config, and YAML smoke tests stay explicit so teams can judge whether KMVPy fits their service foundation.",
    tabsLabel: "Code example tabs",
    cliLabel: "CLI scaffold",
    asgiLabel: "init_asgi_app",
    jwtLabel: "JWT YAML",
    smokeLabel: "YAML smoke test",
    cliSourceComment: "or from the source directory",
  },
  security: {
    section: "Security & Ops",
    title: "Security and operational defaults belong in the foundation",
    desc: "KMVPy focuses on the default security posture of a backend foundation: key paths, sessions, CORS, deployment templates, and release/develop config should all be reviewable and replaceable.",
    pointRs256:
      "JWT defaults to asymmetric algorithms such as RS256 and uses kid to identify active keys.",
    pointPemPath:
      "Config files reference key file paths instead of embedding PEM content directly.",
    pointRoles:
      "Separate user/admin JWT config isolates issuer, audience, session lifetime, and Redis DBs.",
    pointRotation:
      "Key rotation keeps previous public keys available during client transition.",
    pointSession:
      "Redis sessions, HttpOnly cookies, and CORS restrictions provide runtime boundaries for auth.",
    pointDeploy:
      "Nginx templates plus release/develop config support deployment and local integration.",
  },
  usecases: {
    section: "Use Cases",
    title: "Where KMVPy fits",
    desc: "KMVPy is for engineering teams that need a microservice foundation quickly, not buyers looking for a complete business system.",
    realtimeTitle: "REST plus realtime APIs",
    realtimeBody:
      "Backend services that need ordinary HTTP APIs and Socket.IO realtime notifications together.",
    contractTitle: "Shared config and error contracts",
    contractBody:
      "Teams that want consistent response formats, error codes, config structure, and logging across services.",
    scaffoldTitle: "One-command frontend/backend workspace",
    scaffoldBody:
      "Teams that need Python backend, SPA, test templates, Nginx, and deployment config generated together.",
    ideTitle: "Cursor / VS Code Python backend work",
    ideBody:
      "Projects that should start with debugger config, workspace structure, and runnable examples.",
  },
  stack: {
    section: "Tech Stack",
    title: "Built on the mature Python backend ecosystem",
    desc: "KMVPy integrates these libraries into a default project path instead of replacing them.",
    fastapi: "FastAPI",
    uvicorn: "Uvicorn",
    pydantic: "Pydantic v2",
    sqlalchemy: "SQLAlchemy 2 Async",
    redis: "Redis",
    apscheduler: "APScheduler",
    pyjwt: "PyJWT",
    socketio: "Socket.IO",
    pyyaml: "PyYAML",
    openai: "OpenAI SDK",
    asyncpg: "asyncpg",
    aiosqlite: "aiosqlite",
    cassandra: "Cassandra driver",
  },
  status: {
    python: "Runtime requirement",
    version: "Current version",
    stage: "Development Status",
    mysql: "Optional dependency",
  },
  faq: {
    section: "Honest Status & FAQ",
    title: "A clear view of the current state",
    desc: "KMVPy is still early. It fits teams willing to understand the foundation conventions and help sharpen them.",
    q1: "Is KMVPy a complete business system?",
    a1: "No. KMVPy is a backend foundation library and project generator. It helps teams generate the service base; domain models, workflows, and product rules are still yours to build.",
    q2: "What Python version does it require?",
    a2: "Python >= 3.11. Generated projects are organized around modern typing, async I/O, and Pydantic v2.",
    q3: "What is the current version and maturity?",
    a3: "The current version is 0.2.3 and the Development Status is Beta. It fits internal foundations, pilot services, and teams ready to provide fast feedback.",
    q4: "Is MySQL required?",
    a4: "No. MySQL is optional. Projects can use PostgreSQL, SQLite, or another configured storage path as needed.",
  },
  cta: {
    section: "Get Started",
    title: "Start with a FastAPI project that already runs",
    desc: "Begin from the default generated service, then replace routers, ORM models, config, and deployment details around your own boundaries.",
  },
};
