# SnowBros

使用 Godot **4.7 stable** 开发的游戏项目。当前提供可启动的项目骨架与标题场景，具体玩法待确定。

## 开发

在 Godot 4.7 中导入 `project.godot`，按 F6 运行当前场景或 F5 运行项目。

当前云环境引擎路径：
`/workspace/tools/godot-4.7/Godot_v4.7-stable_linux.x86_64`

```sh
export XDG_CACHE_HOME=/workspace/.cache
export XDG_CONFIG_HOME=/workspace/.config
export XDG_DATA_HOME=/workspace/.local/share
cd /workspace/SnowBros
/workspace/tools/godot-4.7/Godot_v4.7-stable_linux.x86_64 --headless --editor --import
/workspace/tools/godot-4.7/Godot_v4.7-stable_linux.x86_64 --headless --quit-after 120
```

目前不需要第三方插件、数据库或 API 密钥。`.godot/` 缓存和构建输出不提交。

## 开发记录与提交

在 `docs/DEVELOPMENT.md` 记录每次完成的功能、验证结果和待办事项。
按功能提交代码并推送到本仓库；已有分支上的工作先同步，再按需创建功能分支。
只记录项目相关的实现与验证信息，不上传凭据或聊天内容。
