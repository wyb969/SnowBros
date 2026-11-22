"""Publish text-only gameplay notes; reference videos stay local."""
from pathlib import Path
import html
import re

STYLE = '''*{box-sizing:border-box}body{margin:0;background:#081725;color:#deeff8;font:16px/1.85 system-ui,sans-serif}main,nav{max-width:1050px;margin:auto;padding:24px}nav{border-bottom:1px solid #294859;display:flex;flex-wrap:wrap;gap:20px}a{color:#a8e5ff}h1{font-size:28px}h2{font-size:21px;margin-top:32px;color:#b8eafa}p,li{color:#b8ceda;overflow-wrap:anywhere}table{border-collapse:collapse;width:100%;font-size:14px}td{padding:12px;border:1px solid #345263;vertical-align:top}tr:first-child{background:#17384a;color:#fff}code{color:#f6d69e}ul{padding-left:24px}.table-wrap{overflow-x:auto}'''

def inline(line):
    escaped = html.escape(line)
    escaped = re.sub(r'`([^`]+)`', r'<code>\1</code>', escaped)
    return re.sub(r'https://[^\s，。]+', lambda m: f'<a href="{m[0]}" target="_blank" rel="noopener">{m[0]}</a>', escaped)

def render(markdown):
    blocks = []
    table = False
    listing = False
    for line in markdown.splitlines():
        if table and not line.startswith('|'):
            blocks.append('</table></div>')
            table = False
        if listing and not line.startswith('- '):
            blocks.append('</ul>')
            listing = False
        if line.startswith('|'):
            if re.match(r'^\|[\s|:-]+$', line):
                continue
            if not table:
                blocks.append('<div class="table-wrap"><table>')
                table = True
            blocks.append('<tr>' + ''.join('<td>' + inline(c.strip()) + '</td>' for c in line.strip('|').split('|')) + '</tr>')
        elif line.startswith('#'):
            level = len(line) - len(line.lstrip('#'))
            blocks.append(f'<h{level}>' + inline(line[level:].strip()) + f'</h{level}>')
        elif line.startswith('- '):
            if not listing:
                blocks.append('<ul>')
                listing = True
            blocks.append('<li>' + inline(line[2:]) + '</li>')
        elif line:
            blocks.append('<p>' + inline(line) + '</p>')
    if table:
        blocks.append('</table></div>')
    if listing:
        blocks.append('</ul>')
    return ''.join(blocks)

def build_reports(output):
    docs = Path(__file__).resolve().parents[1] / 'docs'
    navigation = '<nav><a href="game.html">返回试玩</a><a href="analysis-feel.html">样本手感校准</a><a href="analysis-shots.html">雪片与降层</a><a href="analysis-jump.html">跳跃复查</a><a href="analysis.html">第一段分析</a><a href="analysis-2.html">连续攻击与连锁</a></nav>'
    for source, target in [('VIDEO_ANALYSIS.md', 'analysis'), ('VIDEO_ANALYSIS_2.md', 'analysis-2'), ('JUMP_REVIEW.md', 'analysis-jump'), ('SHOT_LAYER_REVIEW.md', 'analysis-shots'), ('REFERENCE_FEEL_REVIEW.md', 'analysis-feel')]:
        markdown = (docs / source).read_text()
        title = markdown.splitlines()[0].lstrip('# ').strip()
        page = '<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>' + html.escape(title) + '</title><style>' + STYLE + '</style>' + navigation + '<main>' + render(markdown) + '</main></html>'
        (output / (target + '.html')).write_text(page)
        (output / (target + '.md')).write_text(markdown)
