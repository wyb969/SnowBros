# SnowBros · 雪人兄弟

Godot 4.7 单人第一关。用雪片把敌人冻成球，贴近按攻击踢出，利用平台高差和反弹连续撞敌。角色与敌人使用本工程绘制的像素动画。

[在线试玩](https://snowbro-frost-arcade.whiteber.chatgpt.site)

| 操作 | 键盘 |
| --- | --- |
| 左右移动、慢推雪球 | 方向键或 A / D |
| 跳跃、从底下顶球、从滚球跳出 | 空格、W 或上方向键 |
| 喷雪、贴近后踢球 | J 或 Z，支持点按和按住连发 |
| 开始、暂停、重试 | Enter、P、R |
| 练习场 | 1–4 直选，Q 切换，T 返回第一关 |

手机横屏时，左手摇杆移动，右手可同时跳跃和喷雪。设置中可以调整按钮位置、大小和透明度。浏览器需支持 WebGL 2，声音默认关闭。

## 试玩路线

- 在第一关从底层跳上第一层平台，试着在落地前轻按一次跳，连续向上爬。基础跳高约 154 个逻辑像素，到顶约 0.36 秒。同层落地约 0.68 秒，跳上高出 104 像素的平台约 0.55 秒。顶层和雪球顶也能跳满相同高度，视野随高跳上移。
- 在练习场 2，把底层的雪球往右踢，可以看到它接连撞飞四名敌人，到右墙碎裂。练习场 3 的球从高处出发，在上层碰墙会折返，落到最底层才会在侧墙碎裂。先向左拿红瓶，松手即可看到原地快步，再向右试双球错位。被滚球卷入时有 0.75 秒无敌。
- 在练习场 4，站在白线上向右喷雪，观察第一发落在敌人前方。向左拿黄瓶，走回白线再向右发射，就能打中同一个敌人。白线右边有普通和黄瓶的落点刻度。按同层最远可命中的敌人中心测量，普通约 209 像素，黄瓶约 414 像素。普通需要 6 发冻成球，单独喝蓝瓶或黄瓶需要 3 发，两瓶都有时需要 2 发。停火后积雪会分层融化，最后一层化完敌人便恢复移动。点按最快约每 0.10 秒一发，按住约每 0.20 秒一发。

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
