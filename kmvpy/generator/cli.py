from __future__ import annotations

import argparse
from pathlib import Path

from kmvpy.generator.jwt_key_rotation import rotate_jwt_keys
from kmvpy.generator.project_generator import (
    create_project,
    generate_template_from_project,
    update_project,
)

NGINX_TEMPLATE_DIR = Path(__file__).with_name("nginx")
NGINX_TEMPLATE_FILES = {
    "api": "__API_HOST__.conf.tpl",
    "spa": "__SPA_HOST__.conf.tpl",
}


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="KMVPy 命令行工具")
    subparsers = parser.add_subparsers(dest="command")

    create_parser = subparsers.add_parser("create", help="创建依赖于 kmvpy 的工程")
    create_parser.add_argument(
        "name",
        nargs="?",
        help=(
            "工程名称（不含路径分隔符时在 -d 目录下创建子目录），"
            "或工程根目录的完整/相对路径（最后一级目录名为工程名，此时忽略 -d）"
        ),
    )
    create_parser.add_argument(
        "-d",
        "--directory",
        type=Path,
        default=Path.cwd(),
        help=(
            "当第一个参数为工程名称时使用：在此目录下创建「名称」子目录；"
            "默认为当前目录。若参数为工程根路径则忽略本选项。"
        ),
    )
    update_parser = subparsers.add_parser("update", help="增量更新依赖于 kmvpy 的工程")
    update_parser.add_argument(
        "name",
        nargs="?",
        help=(
            "工程名称（不含路径分隔符时在 -d 目录下定位子目录），"
            "或工程根目录的完整/相对路径（最后一级目录名为工程名，此时忽略 -d）"
        ),
    )
    update_parser.add_argument(
        "-d",
        "--directory",
        type=Path,
        default=Path.cwd(),
        help=(
            "当第一个参数为工程名称时使用：在此目录下定位「名称」子目录；"
            "默认为当前目录。若参数为工程根路径则忽略本选项。"
        ),
    )
    gentpl_parser = subparsers.add_parser(
        "gentpl", help="从已生成工程反向生成 kmvpy 模板"
    )
    gentpl_parser.add_argument(
        "name",
        nargs="?",
        help=(
            "当前目录下的工程目录名，或工程根目录的完整/相对路径；"
            "工程名取最后一级目录名"
        ),
    )
    gentpl_parser.add_argument(
        "-d",
        "--directory",
        type=Path,
        default=Path.cwd(),
        help=(
            "模板输出父目录，模板会写入此目录下的 template/；"
            "默认为当前目录，不影响工程路径解析。"
        ),
    )
    nginx_parser = subparsers.add_parser("nginx", help="输出 nginx 配置模板")
    nginx_parser.add_argument(
        "target",
        choices=sorted(NGINX_TEMPLATE_FILES),
        help="api 输出 API 反向代理模板；spa 输出 SPA 静态站点模板",
    )
    rotate_jwt_parser = subparsers.add_parser(
        "rotate-jwt-keys",
        help="轮换配置文件中的 user/admin JWT 密钥对",
    )
    rotate_jwt_parser.add_argument(
        "config_path",
        type=Path,
        help="需要自动轮换 JWT 密钥对的 config.yaml 路径",
    )

    return parser


def prompt_project_name() -> str:
    while True:
        project_name = input("请输入工程名称: ").strip()
        if project_name:
            return project_name
        print("工程名称不能为空，请重新输入。")


def handle_create(args: argparse.Namespace) -> int:
    project_spec = args.name or prompt_project_name()
    project_root = create_project(
        project_spec, base_directory=args.directory)

    print(f"工程已创建: {project_root}。")
    return 0


def handle_update(args: argparse.Namespace) -> int:
    if args.name is None or args.name.strip() == ".":
        current_project_root = Path.cwd()
        project_spec = current_project_root.name
        base_directory = current_project_root.parent
    else:
        project_spec = args.name
        base_directory = args.directory

    project_root = update_project(
        project_spec, base_directory=base_directory)

    print(f"工程已更新: {project_root}。")
    return 0


def handle_gentpl(args: argparse.Namespace) -> int:
    project_spec = args.name or prompt_project_name()
    template_root = generate_template_from_project(
        project_spec,
        template_parent_directory=args.directory,
    )

    print(f"模板已生成: {template_root}。")
    return 0


def handle_nginx(args: argparse.Namespace) -> int:
    template_path = NGINX_TEMPLATE_DIR / NGINX_TEMPLATE_FILES[args.target]
    if not template_path.is_file():
        raise FileNotFoundError(f"nginx 模板不存在: {template_path}")

    content = template_path.read_text(encoding="utf-8")
    print(content, end="" if content.endswith("\n") else "\n")
    return 0


def handle_rotate_jwt_keys(args: argparse.Namespace) -> int:
    result = rotate_jwt_keys(args.config_path)
    print(f"JWT 密钥已轮换: {result.config_path}")
    print(f"原配置已备份: {result.backup_path}")
    for role in result.roles:
        print(
            f"- {role.role}: kid={role.kid}, "
            f"private_key_path={role.private_key_path}, "
            f"public_key_path={role.public_key_path}"
        )
    return 0


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()

    if args.command == "create":
        try:
            return handle_create(args)
        except (FileExistsError, NotADirectoryError, OSError, ValueError) as exc:
            parser.error(str(exc))
        except KeyboardInterrupt:
            print("\n已取消创建。")
            return 130

    if args.command == "update":
        try:
            return handle_update(args)
        except (NotADirectoryError, OSError, ValueError) as exc:
            parser.error(str(exc))
        except KeyboardInterrupt:
            print("\n已取消更新。")
            return 130

    if args.command == "gentpl":
        try:
            return handle_gentpl(args)
        except (FileNotFoundError, NotADirectoryError, OSError, ValueError) as exc:
            parser.error(str(exc))
        except KeyboardInterrupt:
            print("\n已取消生成模板。")
            return 130

    if args.command == "nginx":
        try:
            return handle_nginx(args)
        except (FileNotFoundError, OSError, ValueError) as exc:
            parser.error(str(exc))
        except KeyboardInterrupt:
            print("\n已取消输出 nginx 模板。")
            return 130

    if args.command == "rotate-jwt-keys":
        try:
            return handle_rotate_jwt_keys(args)
        except (FileNotFoundError, OSError, ValueError, RuntimeError) as exc:
            parser.error(str(exc))
        except KeyboardInterrupt:
            print("\n已取消轮换 JWT 密钥。")
            return 130

    parser.print_help()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
