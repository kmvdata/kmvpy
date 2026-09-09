# KMVPy 首次发布到 PyPI

本文面向第一次发布 Python 包的维护者。目标是让普通用户最终可以直接执行：

```bash
python -m pip install kmvpy
```

仓库已经准备了基于 GitHub Actions 和 PyPI Trusted Publishing 的发布流程。该流程使用短期身份凭据，不需要把 PyPI 密码或长期 API Token 保存到 GitHub。

## 0. 当前状态

截至 **2026-09-08**，访问 PyPI JSON API 的 `kmvpy` 项目地址返回 HTTP 404，因此该名称当前看起来尚未被创建。发布前仍应再次打开 [`https://pypi.org/project/kmvpy/`](https://pypi.org/project/kmvpy/) 检查，因为 PyPI 项目名遵循标准化规则且全局唯一。

重要：PyPI 的 Pending Trusted Publisher **不会预留项目名**。在第一次发布真正完成之前，其他人仍可能先注册 `kmvpy`。建议完成下面的账号、仓库和发布设置后尽快首发。

仓库当前准备好的公开身份如下：

| 项目 | 值 |
|---|---|
| PyPI 发行名 | `kmvpy` |
| Python 导入名 | `kmvpy` |
| 安装后命令 | `kmvpy` |
| 作者/维护者 | `kermit.mei` |
| 公开邮箱 | `kermit.mei@gmail.com` |
| 计划中的 GitHub 仓库 | `kmvdata/kmvpy` |
| 当前版本 | `0.2.1` |

首发完成前，README 中的 `pip install kmvpy` 只能视为目标命令；本地验证请使用 `pip install .` 或安装构建出的 wheel。

## 1. 先把 GitHub 仓库改名

当前本地仓库的远端仍指向改名前的地址。代码和公开链接已经指向新地址，因此发布前需要先在 GitHub 完成仓库改名。

1. 打开 GitHub 上的原仓库。
2. 进入 **Settings → General**。
3. 在 **Repository name** 中把仓库名改为 `kmvpy`。
4. 确认仓库地址已变为 `https://github.com/kmvdata/kmvpy`。
5. 在本地仓库执行：

```bash
git remote set-url origin git@github.com:kmvdata/kmvpy.git
git remote -v
```

GitHub 会为多数旧链接保留重定向，但仍建议更新本地远端和对外文档。发布前还要确认仓库为 **Public**，并检查当前文件及完整 Git 历史中没有密码、私钥、API Token、生产配置或客户数据。发现真实密钥时，应先撤销或轮换密钥，再清理历史。

## 2. 注册并保护 PyPI 账号

正式 PyPI 与 TestPyPI 是两个独立网站，账号不互通。本项目正式发布只需要正式 PyPI 账号。

1. 打开 [PyPI 注册页](https://pypi.org/account/register/)。
2. 用户名填写 `kermit.mei`，邮箱填写 `kermit.mei@gmail.com`。
3. 如果用户名已经被占用，请先选择一个你愿意长期使用的登录名。PyPI 目前不支持直接修改用户名；登录名不同不会改变包元数据中公开展示的作者名和邮箱。
4. 使用密码管理器生成唯一强密码，完成验证码和注册。
5. 打开验证邮件并验证 `kermit.mei@gmail.com`。未验证邮箱不能创建项目或上传版本。
6. 在 **Account settings** 中启用双重验证（2FA）。建议配置至少两种可用方式，并生成恢复码，离线安全保存。

本仓库的 `pyproject.toml` 已包含：

```toml
authors = [{name = "kermit.mei", email = "kermit.mei@gmail.com"}]
maintainers = [{name = "kermit.mei", email = "kermit.mei@gmail.com"}]
```

作者元数据不等于上传权限。真正的权限由 PyPI 账号、项目 Owner/Maintainer 角色和 Trusted Publisher 决定。

## 3. 创建 GitHub 发布环境

在改名后的 `kmvdata/kmvpy` 仓库中：

1. 打开 **Settings → Environments → New environment**。
2. 创建名为 `pypi` 的环境，大小写必须完全一致。
3. 建议配置 **Required reviewers**，让正式上传前必须由你人工批准。
4. 如团队使用受保护标签，可进一步限制只有发布标签能够部署到该环境。

本项目不需要创建 `PYPI_API_TOKEN`、`PYPI_USERNAME` 或 `PYPI_PASSWORD` 等 GitHub Secrets。

## 4. 创建 Pending Trusted Publisher

完成仓库改名且工作流已推送到 GitHub 后，再配置 Pending Publisher：

1. 登录 [PyPI](https://pypi.org/)。
2. 打开账号侧栏中的 **Publishing**，或直接访问 [`https://pypi.org/manage/account/publishing/`](https://pypi.org/manage/account/publishing/)。
3. 在 **Add a new pending publisher** 中选择 GitHub Actions。
4. 精确填写以下值：

| PyPI 表单字段 | 填写值 |
|---|---|
| PyPI Project Name | `kmvpy` |
| Owner | `kmvdata` |
| Repository name | `kmvpy` |
| Workflow name | `publish.yml` |
| Environment name | `pypi` |

5. 保存后确认 Pending Publisher 出现在账号的 Publishing 页面。

首次工作流上传成功时，PyPI 会创建 `kmvpy` 项目，并把 Pending Publisher 自动转为该项目的普通 Trusted Publisher。仓库所有者、仓库名、工作流文件名和环境名必须与表格完全一致，否则 OIDC 认证会失败。

官方说明：[使用 Trusted Publisher 创建新项目](https://docs.pypi.org/trusted-publishers/creating-a-project-through-oidc/)。

## 5. 首发前的本地检查

建议在干净虚拟环境中执行：

```bash
python -m venv .venv-release
source .venv-release/bin/activate
python -m pip install --upgrade pip build twine
python -m pytest
python -m build
python -m twine check --strict dist/*
```

当前版本的唯一来源是 `kmvpy/__init__.py` 中的 `__version__`，`pyproject.toml` 会自动读取它。每次发布必须使用一个从未上传过的新版本号；PyPI 不允许覆盖同一版本已有的文件。

发布前逐项确认：

- `python -m pytest` 没有失败。
- 构建产物名是 `kmvpy-0.2.1-py3-none-any.whl` 和 `kmvpy-0.2.1.tar.gz`。
- `python -m twine check --strict dist/*` 通过。
- 在新虚拟环境安装 wheel 后，`import kmvpy` 和 `kmvpy --help` 都能工作。
- 改名前的旧名称不再作为导入包或命令出现。
- `LICENSE` 的 GPL-3.0-only 许可符合你的发布意图。
- README、依赖、版本和项目链接都正确。
- 所有待发布文件已提交并推送，工作区干净。

## 6. 通过 GitHub Release 正式发布

`.github/workflows/publish.yml` 只在 GitHub Release 被正式发布时运行。它会检查版本、构建 wheel 与源码包、校验元数据、检查安装内容，并通过 `pypi` 环境发布到正式 PyPI。

假设 `kmvpy/__init__.py` 中的版本为 `0.2.1`：

1. 在 GitHub 打开 **Releases → Draft a new release**。
2. 创建标签 `v0.2.1`。标签可以带一个 `v` 前缀，其余部分必须与包版本完全一致。
3. 填写变更说明，选择 **Publish release**。
4. 打开 **Actions → Publish kmvpy to PyPI** 查看构建过程。
5. 构建通过后，在 `pypi` 环境批准发布。
6. 工作流完成后，打开 [`https://pypi.org/project/kmvpy/`](https://pypi.org/project/kmvpy/) 检查版本、作者、README、许可证、项目链接和文件列表。

如果失败：

- 标签不一致：修正版本或使用匹配的新 Release 标签。
- OIDC 认证失败：逐字检查 Owner、Repository、Workflow、Environment 四个字段。
- PyPI 已收到该版本的部分文件：递增版本号后重新发布，不要尝试覆盖原版本。
- 名称被他人抢先注册：Pending Publisher 会失效，需要重新选择发行名；不要上传到无关项目。

## 7. 从公网验证普通用户体验

发布成功后，在新的临时环境中验证，避免命中本地源码或缓存：

```bash
python -m venv /tmp/kmvpy-pypi-check
/tmp/kmvpy-pypi-check/bin/python -m pip install --no-cache-dir kmvpy==0.2.1
cd /tmp
/tmp/kmvpy-pypi-check/bin/python -c "import kmvpy; print(kmvpy.__version__)"
/tmp/kmvpy-pypi-check/bin/kmvpy --help
```

确认版本输出为 `0.2.1`，命令名为 `kmvpy`，PyPI 项目链接指向 `https://github.com/kmvdata/kmvpy`。此时普通用户就可以正式使用 `pip install kmvpy`。

## 8. 后续版本固定流程

1. 修改 `kmvpy/__init__.py` 中的版本号。
2. 更新变更说明和文档，运行测试、构建和严格校验。
3. 提交并推送代码。
4. 创建与版本一致的 GitHub Release，例如 `v0.2.2`。
5. 审核并批准 `pypi` 环境发布。
6. 在全新环境中从 PyPI 安装验证。

不要把 PyPI 密码、2FA 验证码、恢复码或 API Token 提交到仓库、Issue、Actions 日志或聊天记录中。
