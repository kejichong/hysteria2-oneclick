# GitHub 发布步骤

建议将本目录作为一个独立 GitHub 仓库上传，仓库名称使用：

```text
hysteria2-oneclick
```

## 首次发布

在本目录打开 PowerShell，依次执行：

```powershell
git init
git add .
git commit -m "Release v1.0.0"
git branch -M main
git remote add origin https://github.com/kejichong/hysteria2-oneclick.git
git push -u origin main
git tag -a v1.0.0 -m "v1.0.0"
git push origin v1.0.0
```

如果 GitHub 仓库已有内容，不要直接照抄上述命令覆盖远程历史，应先核对远程分支。

## 发布后检查

确认以下地址能够在浏览器中显示脚本文本：

```text
https://raw.githubusercontent.com/kejichong/hysteria2-oneclick/refs/tags/v1.0.0/hysteria2-oneclick.sh
```

然后在测试服务器上执行：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/kejichong/hysteria2-oneclick/refs/tags/v1.0.0/hysteria2-oneclick.sh) --show-link
```

每次修改脚本后应更新 `VERSION`、`CHANGELOG.md` 和 `SHA256SUMS`，并创建新的版本标签，不要移动或覆盖已经发布的标签。
