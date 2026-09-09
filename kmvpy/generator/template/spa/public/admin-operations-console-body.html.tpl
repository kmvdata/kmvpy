<div class="content-inner">

<div id="page-p01" class="page-section" style="display:block;">
<div class="section-header-wrapper">
  <span class="section-label">P8-01</span>
  <h1 class="section-title"><span class="gradient-text">后台管理中心</span></h1>
  <p class="section-sub">超级管理员专属 · 所有操作自动记录审计日志</p>
</div>

<div style="background:rgba(248,113,113,.08);border:1px solid rgba(248,113,113,.25);border-radius:10px;padding:10px 14px;margin-bottom:16px;font-size:12.5px;color:#F87171">⚠ <strong>仅超级管理员可访问此后台</strong>（演示）</div>
<div class="kpi-grid" style="margin-bottom:16px">
  <div class="kpi-card"><div class="kpi-label">总注册用户</div><div class="kpi-value" style="color:var(--text-200)">1,248</div></div>
  <div class="kpi-card"><div class="kpi-label">付费用户</div><div class="kpi-value" style="color:#4ADE80">382</div></div>
  <div class="kpi-card"><div class="kpi-label">今日新增</div><div class="kpi-value" style="color:#00d4aa">+12</div></div>
  <div class="kpi-card"><div class="kpi-label">MRR</div><div class="kpi-value" style="color:#4ADE80;font-size:18px">$22.9K</div></div>
  <div class="kpi-card"><div class="kpi-label">Agent告警</div><div class="kpi-value" style="color:#FBBF24">2</div></div>
  <div class="kpi-card"><div class="kpi-label">待处工单</div><div class="kpi-value" style="color:#F87171">7</div></div>
  <div class="kpi-card"><div class="kpi-label">付费转化</div><div class="kpi-value" style="font-size:18px">44%</div></div>
</div>
<div class="g3" style="margin-bottom:16px">
  <a class="card-compact" style="cursor:pointer;display:block;text-decoration:none;color:inherit" href="/admin/users"><div style="padding:8px 0;font-size:13px;font-weight:600">用户账户管理 →</div></a>
  <div class="card-compact" style="cursor:pointer" onclick="showPage('p12')"><div style="padding:8px 0;font-size:13px;font-weight:600">AI Agent 监控（P8-12）</div></div>
  <a class="card-compact" style="cursor:pointer;display:block;text-decoration:none;color:inherit" href="/admin/work-tickets"><div style="padding:8px 0;font-size:13px;font-weight:600">帮助工单 →</div></a>
  <a class="card-compact" style="cursor:pointer;display:block;text-decoration:none;color:inherit" href="/admin/kol"><div style="padding:8px 0;font-size:13px;font-weight:600">KOL 推广管理 →</div></a>
  <div class="card-compact" style="cursor:pointer" onclick="showPage('p05')"><div style="padding:8px 0;font-size:13px;font-weight:600">运营活动（P8-05）</div></div>
  <div class="card-compact" style="cursor:pointer" onclick="showPage('p15')"><div style="padding:8px 0;font-size:13px;font-weight:600">数据大盘（P8-15）</div></div>
</div>
<p class="section-sub">以下为按 PRD 划分的区块占位；将对话中提供的完整 HTML 粘贴至本文件可替换为像素级原型。</p>

</div>

<div id="page-p02" class="page-section" style="display:none;">
<div class="section-header-wrapper">
  <span class="section-label">P8-02</span>
  <h1 class="section-title"><span class="gradient-text">合规审计日志</span></h1>
  <p class="section-sub">全操作链路 · 永久保留</p>
</div>

<div class="alert-info" style="margin-bottom:14px">ℹ 演示：筛选与导出为占位。</div>
<div class="tab-bar" style="margin-bottom:12px">
  <button type="button" class="tab-item active" onclick="filterAudit(this,'all')">全部</button>
  <button type="button" class="tab-item" onclick="filterAudit(this,'user')">账户操作</button>
</div>
<div style="background:var(--bg-600);border:1px solid var(--border);border-radius:16px;overflow:hidden;padding:12px">
  <table class="data-table"><thead><tr><th>时间</th><th>操作类型</th><th>目标</th></tr></thead>
  <tbody><tr><td class="mono">今天 14:22</td><td><span class="tag tag-amber">套餐变更</span></td><td>user_8821</td></tr></tbody></table>
</div>

</div>

<div id="page-p03" class="page-section" style="display:none;">
<div class="section-header-wrapper">
  <span class="section-label">P8-03</span>
  <h1 class="section-title"><span class="gradient-text">用户账户管理</span></h1>
  <p class="section-sub">查询 · 封禁 · 套餐 · 退款</p>
</div>

<p class="section-sub">正式列表请使用 <a href="/admin/users" style="color:var(--accent-1)">用户列表（实盘）</a>。</p>
<div style="background:var(--bg-600);border:1px solid var(--border);border-radius:16px;overflow:hidden;margin-top:12px">
<table class="data-table"><thead><tr><th>用户</th><th>套餐</th><th>操作</th></tr></thead>
<tbody><tr><td>JohnDoe88</td><td><span class="tag tag-blue">Pro</span></td><td><button type="button" class="btn-ghost-sm" onclick="openUserPanel()">详情</button></td></tr></tbody></table>
</div>

</div>

<div id="page-p04" class="page-section" style="display:none;">
<div class="section-header-wrapper">
  <span class="section-label">P8-04</span>
  <h1 class="section-title"><span class="gradient-text">KOL 推广合作管理</span></h1>
  <p class="section-sub">佣金 · 优惠码</p>
</div>
<p class="section-sub">实盘请前往 <a href="/admin/kol" style="color:var(--accent-1)">KOL管理</a>。</p>
</div>

<div id="page-p05" class="page-section" style="display:none;">
<div class="section-header-wrapper">
  <span class="section-label">P8-05</span>
  <h1 class="section-title"><span class="gradient-text">运营活动管理</span></h1>
  <p class="section-sub">活动生命周期 · 审批</p>
</div>
<div class="alert-warning">⚠ 草稿需超管审批上线（演示）。</div>
</div>

<div id="page-p06" class="page-section" style="display:none;">
<div class="section-header-wrapper">
  <span class="section-label">P8-06</span>
  <h1 class="section-title"><span class="gradient-text">内容管理 · 研报</span></h1>
  <p class="section-sub">上传 · AI 提取 · 审核</p>
</div>
<div class="alert-warning">⚠ 版权授权 D-5 必须（演示文案）。</div>
</div>

<div id="page-p07" class="page-section" style="display:none;">
<div class="section-header-wrapper">
  <span class="section-label">P8-07</span>
  <h1 class="section-title"><span class="gradient-text">内容管理 · K线图 & 财报</span></h1>
  <p class="section-sub">T1 视觉 / FMP 同步</p>
</div>
<p class="section-sub">演示占位。</p>
</div>

<div id="page-p08" class="page-section" style="display:none;">
<div class="section-header-wrapper">
  <span class="section-label">P8-08</span>
  <h1 class="section-title"><span class="gradient-text">规则学习素材</span></h1>
  <p class="section-sub">Trim · 测验</p>
</div>
<p class="section-sub">演示占位。</p>
</div>

<div id="page-p09" class="page-section" style="display:none;">
<div class="section-header-wrapper">
  <span class="section-label">P8-09</span>
  <h1 class="section-title"><span class="gradient-text">Telegram 白名单</span></h1>
  <p class="section-sub">Agent D1 来源</p>
</div>
<p class="section-sub">演示占位。</p>
</div>

<div id="page-p10" class="page-section" style="display:none;">
<div class="section-header-wrapper">
  <span class="section-label">P8-10</span>
  <h1 class="section-title"><span class="gradient-text">AI 投资知识库</span></h1>
  <p class="section-sub">RAG · 向量索引</p>
</div>
<p class="section-sub">演示占位。</p>
</div>

<div id="page-p11" class="page-section" style="display:none;">
<div class="section-header-wrapper">
  <span class="section-label">P8-11</span>
  <h1 class="section-title"><span class="gradient-text">系统设置</span></h1>
  <p class="section-sub">合规开关 · 导出</p>
</div>
<div class="alert-danger">⚠ 超管专属（演示）。</div>
</div>

<div id="page-p12" class="page-section" style="display:none;">
<div class="section-header-wrapper">
  <span class="section-label">P8-12</span>
  <h1 class="section-title"><span class="gradient-text">AI Agent 运维监控</span></h1>
  <p class="section-sub">告警 · Token · Prompt</p>
</div>

<div class="tab-bar" style="margin-bottom:12px">
<button type="button" class="tab-item active" onclick="switchTab(this,'agent-status')">状态</button>
<button type="button" class="tab-item" onclick="switchTab(this,'agent-alerts')">告警</button>
</div>
<div id="agent-status"><p class="section-sub">Agent G1 / D1 等为演示数据。</p></div>
<div id="agent-alerts" style="display:none"><div class="alert-warning">P1：I4 成功率异常（演示）</div></div>

</div>

<div id="page-p13" class="page-section" style="display:none;">
<div class="section-header-wrapper">
  <span class="section-label">P8-13</span>
  <h1 class="section-title"><span class="gradient-text">套餐与订阅管理</span></h1>
  <p class="section-sub">Pending · 欧盟冷静期</p>
</div>
<p class="section-sub">演示占位。</p>
</div>

<div id="page-p14" class="page-section" style="display:none;">
<div class="section-header-wrapper">
  <span class="section-label">P8-14</span>
  <h1 class="section-title"><span class="gradient-text">帮助中心 FAQ 管理</span></h1>
  <p class="section-sub">FAQ · 工单</p>
</div>
<p class="section-sub">工单实盘：<a href="/admin/work-tickets" style="color:var(--accent-1)">工单处理</a></p>
</div>

<div id="page-p15" class="page-section" style="display:none;">
<div class="section-header-wrapper">
  <span class="section-label">P8-15</span>
  <h1 class="section-title"><span class="gradient-text">数据大盘 & 运营分析</span></h1>
  <p class="section-sub">DAU / MRR / 漏斗</p>
</div>
<div class="kpi-grid-4"><div class="kpi-card"><div class="kpi-label">DAU</div><div class="kpi-value">341</div></div></div>
</div>

<div id="page-p16" class="page-section" style="display:none;">
<div class="section-header-wrapper">
  <span class="section-label">P8-16</span>
  <h1 class="section-title"><span class="gradient-text">Watchlist 内容管理</span></h1>
  <p class="section-sub">信号质量</p>
</div>
<p class="section-sub">演示占位。</p>
</div>

<div id="page-p17" class="page-section" style="display:none;">
<div class="section-header-wrapper">
  <span class="section-label">P8-17</span>
  <h1 class="section-title"><span class="gradient-text">AI 信号人工维护</span></h1>
  <p class="section-sub">Discord 补录</p>
</div>
<div class="alert-warning">⚠ super_admin 专属（演示）。</div>
</div>

<div id="page-p18" class="page-section" style="display:none;">
<div class="section-header-wrapper">
  <span class="section-label">P8-18</span>
  <h1 class="section-title"><span class="gradient-text">AI 综合分析内容补录</span></h1>
  <p class="section-sub">content_corpus</p>
</div>
<p class="section-sub">演示占位。</p>
</div>

</div>
