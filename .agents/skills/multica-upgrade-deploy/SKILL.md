---
name: multica-upgrade-deploy
version: 1.0.0
description: Use when upgrading and redeploying the Multica self-hosted cloud instance on the ubuntu server, especially when changes touch Dockerfile, Dockerfile.web, docker-compose.selfhost.yml, remote .env, or the rebuild/health-check workflow.
---

# Multica Upgrade Deploy

用于把当前仓库代码升级到云端 `ubuntu` 服务器并完成重建验证。

## 适用范围

- 目标机器：SSH 别名 `ubuntu`
- 云端目录：`/home/ubuntu/services/multica`
- 当前仓库：本地 `multica` git repo
- 典型变更：`Dockerfile`、`Dockerfile.web`、`docker-compose.selfhost.yml`、云端 `.env`

## 工作流

1. 先检查本地改动和目标分支，避免在错误分支上部署。

```bash
git status --short --branch
git branch --show-current
```

2. 如涉及自部署构建，优先检查这几项是否一致：

- `Dockerfile` 支持 `HTTP_PROXY` / `HTTPS_PROXY` / `ALL_PROXY` / `NO_PROXY`
- `Dockerfile` 使用可配置 `ALPINE_REPO`
- `docker-compose.selfhost.yml` 给 `backend` 和 `frontend` 传递 build args
- `backend.environment` 显式透传 `ALLOWED_ORIGINS`

3. 修改云端 `.env` 前，先备份，再只改本次需要的键。

```bash
ssh ubuntu 'sudo cp /home/ubuntu/services/multica/.env /home/ubuntu/services/multica/.env.bak-$(date +%Y%m%d-%H%M%S)'
```

本项目当前云端升级至少核对：

- `APP_ENV=production`
- `ALLOWED_ORIGINS=http://101.35.232.18:3000,http://localhost:3000`
- `CORS_ALLOWED_ORIGINS=http://101.35.232.18:3000,http://localhost:3000`
- `HTTP_PROXY=`
- `HTTPS_PROXY=`
- `ALL_PROXY=`
- `NO_PROXY=localhost,127.0.0.1,postgres,backend,frontend`

4. 只同步必要文件到服务器，不整仓 rsync。

```bash
scp Dockerfile ubuntu:/tmp/multica.Dockerfile.new
scp Dockerfile.web ubuntu:/tmp/multica.Dockerfile.web.new
scp docker-compose.selfhost.yml ubuntu:/tmp/multica.docker-compose.selfhost.yml.new
```

5. 用 `sudo` 在云端覆盖部署文件，因为运行中的目录属于 `ubuntu` 用户。

```bash
cat <<'EOF' | ssh ubuntu 'sudo bash -s'
set -euo pipefail
cd /home/ubuntu/services/multica
install -m 644 /tmp/multica.Dockerfile.new Dockerfile
install -m 644 /tmp/multica.Dockerfile.web.new Dockerfile.web
install -m 644 /tmp/multica.docker-compose.selfhost.yml.new docker-compose.selfhost.yml
docker compose -f docker-compose.selfhost.yml config >/tmp/multica-compose-config.yaml
docker compose -f docker-compose.selfhost.yml up -d --build
EOF
```

6. 部署后必须做健康检查，不能只看 build 日志。

```bash
ssh ubuntu 'sudo docker compose -f /home/ubuntu/services/multica/docker-compose.selfhost.yml ps'
ssh ubuntu 'curl -sS http://127.0.0.1:8080/health'
ssh ubuntu 'curl -I -sS http://127.0.0.1:3000 | sed -n "1,10p"'
```

## 注意事项

- 远端部署目录默认需要 `sudo` 访问；普通用户 `louis.ning` 可能只能通过 Docker label 看到工作目录，不能直接 `cd`。
- 如果用户要求“前往 ubuntu 服务器更新”，优先直接改远端生效目录，不要只停留在本地仓库。
- 构建慢点通常出在前端 `pnpm install` 拉包，不要把“还在下载”误判成卡死。
- 没有 fresh 的 `ps`、`/health` 和前端 `HTTP 200` 证据，不要声称部署完成。
