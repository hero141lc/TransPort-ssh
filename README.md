# 端口映射小工具（macOS）

通过 SSH 本地转发将远程端口映射到本地端口：默认本地端口与远程端口相同，若本地被占用则自动 `+1` 递增，并自动拦截危险端口（如 `22`、常见数据库端口等）。

这是一个面向 **macOS** 终端环境（`bash/zsh`）的端口映射器。

## 文件说明

- `config.conf`：连接参数与端口策略配置
- `map.sh`：执行映射的主脚本

## 快速开始

1. 编辑配置文件（按需修改）：
   - `REMOTE_USER`
   - `REMOTE_HOST`
   - `REMOTE_SSH_PORT`
   - `SSH_PASSWORD`
   - `DEFAULT_REMOTE_PORTS`
   - `AUTO_OPEN_BROWSER`
   - `ENABLE_MINI_GAME`
   - `FORBIDDEN_PORTS`
2. 赋予脚本执行权限（macOS/Linux）：
   ```bash
   chmod +x map.sh
   ```
3. 运行脚本：
   ```bash
   ./map.sh
   ```
4. 成功后访问：
   - 脚本顶部输出的链接列表（多组端口会有多条链接）

## 行为说明

- 回车不输入端口时，使用 `DEFAULT_REMOTE_PORTS`（支持多端口，空格或逗号分隔）。
- 支持一次映射多组端口（如：`5173, 8080 3000`）。
- 如果输入端口位于 `FORBIDDEN_PORTS` 中，脚本会立即终止。
- 本地端口分配规则：优先使用与远程同端口；若占用则自动 `+1` 直到找到可用端口。
- 脚本会在最上方固定输出可点击链接：`http://localhost:<实际本地端口>`。
- 若配置了 `SSH_PASSWORD`，脚本会先检测 `sshpass`；若缺失则自动尝试通过 Homebrew 安装，安装失败时回退为手动输入密码。
- `AUTO_OPEN_BROWSER=true` 时，隧道建立后自动执行 `open` 打开全部映射链接。
- `ENABLE_MINI_GAME=true` 时，运行过程会显示一个简短字符小游戏。

## 安全说明

- `config.conf` 包含敏感信息（账号/主机/密码），请勿提交到 GitHub。
- 已通过 `.gitignore` 忽略 `config.conf`，建议只提交 `config.example.conf`。

## 免密登录建议

建议将本地公钥加入服务器 `authorized_keys`，避免每次输入密码：

```bash
ssh-copy-id -p 12224 LYZ@1.12.244.242
```

完成后可直接运行脚本建立映射。
