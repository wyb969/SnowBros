# SnowBros · 雪人兄弟

Godot 4.7 单人第一关。用雪片把敌人冻成球，贴近按攻击踢出，利用平台高差和反弹连续撞敌。角色与敌人使用本工程绘制的像素动画。

[在线试玩](https://snowbro-frost-arcade.whiteber.chatgpt.site)

| 操作 | 键盘 |
| --- | --- |
| 左右移动、慢推雪球 | 方向键或 A / D |
| 跳跃、从底下顶球、从滚球跳出 | 空格、W 或上方向键 |
| 连续喷雪、贴近后踢球 | 按住 J 或 Z |
| 开始、暂停、重试 | Enter、P、R |
| 练习场 | 1–4 直选，Q 切换，T 返回第一关 |

手机横屏时，左手摇杆移动，右手可同时跳跃和喷雪。设置中可以调整按钮位置、大小和透明度。浏览器需支持 WebGL 2，声音默认关闭。

## 试玩路线

- 在第一关从底层跳上第一层平台，试着在落地前轻按一次跳，连续向上爬。基础跳高约 154 个逻辑像素，到顶约 0.36 秒。同层落地约 0.68 秒，跳上高出 104 像素的平台约 0.55 秒。顶层和雪球顶也能跳满相同高度，视野随高跳上移。
- 在练习场 2 把面前的雪球往右踢，看它依次撞飞四名敌人。在练习场 3 先向左拿红瓶，松手即可看到原地快步。向右连续推两个雪球，两球中心错开 14 个逻辑像素，其中一颗呈蓝色或红色。近身按攻击可以一起踢出。玩家被滚动雪球卷入时触发 0.75 秒无敌。
- 在练习场 4 对比普通、蓝瓶和黄瓶的雪片。蓝瓶增大雪片并强化积雪，黄瓶延长射程；先向前喷出，再减速、翻转和飘落。红瓶加快行走和推球。

## 本地运行与导出

用 Godot 4.7 stable 导入仓库根目录的 `project.godot`，按 F5 开始。运行测试前先导入项目资源。

```sh
godot --headless --editor --import
godot --headless --script res://tests/interactions_test.gd
godot --headless --script res://tests/jump_test.gd
godot --headless --script res://tests/shot_arc_test.gd
node web/controls.test.mjs
node web/ui-runtime.test.mjs
```

安装同版本的官方 Web 导出模板后，以下命令可生成带触屏操作的网页。将整个 `../snowbro-web` 目录放到支持 WebAssembly 的 HTTPS 服务（本机开发可用 localhost）即可试玩。

```sh
mkdir -p ../snowbro-web
godot --headless --export-release Web ../snowbro-web/game.html
python3 web/build_web.py ../snowbro-web
```

## 参考与素材

参考街机教学录像、FC 观感和既有实测样本，按本关的平台布局调校。数值、角色帧与关卡均为本工程实现。原版规则见[东亚企划作品介绍](https://www.toaplangames.co.jp/en/license/license-20.html)。历次参考记录见 [docs](docs)，开发与验证记录见 [DEVELOPMENT.md](docs/DEVELOPMENT.md)。

音乐 *House In a Forest Loop* 来自 HorrorPen，2012，CC BY 3.0。字体 *Press Start 2P* 使用 SIL OFL 1.1。详见 [音乐说明](assets/MUSIC-CREDITS.md) 与 [字体授权](assets/FONT-LICENSE.txt)。Snow Bros. 原作权利归其权利人所有。
