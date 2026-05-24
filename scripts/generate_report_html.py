#!/usr/bin/env python3
"""Generate a simple HTML report from final_summary.md using only stdlib."""
import html
import re
import sys

def md_to_html(md_text):
    lines = md_text.split('\n')
    out = []
    out.append('<!DOCTYPE html>')
    out.append('<html><head><meta charset="utf-8">')
    out.append('<style>')
    out.append('body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;max-width:900px;margin:40px auto;padding:0 20px;color:#333;line-height:1.6}')
    out.append('h1{color:#1a1a1a;border-bottom:2px solid #e0e0e0;padding-bottom:8px}')
    out.append('h2{color:#2a2a2a;border-bottom:1px solid #eee;padding-bottom:4px}')
    out.append('h3{color:#444}')
    out.append('table{border-collapse:collapse;width:100%;margin:12px 0}')
    out.append('td,th{border:1px solid #ddd;padding:8px 12px;text-align:left;font-size:14px}')
    out.append('th{background:#f5f5f5;font-weight:600}')
    out.append('tr:nth-child(even){background:#fafafa}')
    out.append('code{background:#f0f0f0;padding:2px 6px;border-radius:3px;font-size:13px}')
    out.append('pre{background:#f5f5f5;padding:12px 16px;border-radius:4px;overflow-x:auto}')
    out.append('pre code{background:none;padding:0}')
    out.append('</style>')
    out.append(f'<title>MySQL Optimization Report</title>')
    out.append('</head><body>')

    in_code = False
    in_table = False
    i = 0
    while i < len(lines):
        line = lines[i]
        if line.startswith('```'):
            if in_code:
                out.append('</code></pre>')
                in_code = False
            else:
                out.append('<pre><code>')
                in_code = True
            i += 1
            continue
        if in_code:
            out.append(html.escape(line))
            i += 1
            continue
        if line.startswith('# '):
            out.append(f'<h1>{html.escape(line[2:])}</h1>')
        elif line.startswith('## '):
            out.append(f'<h2>{html.escape(line[3:])}</h2>')
        elif line.startswith('### '):
            out.append(f'<h3>{html.escape(line[4:])}</h3>')
        elif line.startswith('|'):
            cells = [c.strip() for c in line.strip('|').split('|')]
            if all(re.match(r'^[-: ]+$', c) for c in cells):
                i += 1
                continue
            if not in_table:
                out.append('<table>')
                in_table = True
            tag = 'th' if i+1 < len(lines) and lines[i+1].startswith('|---') else 'td'
            out.append('<tr>' + ''.join(f'<{tag}>{html.escape(c)}</{tag}>' for c in cells) + '</tr>')
        else:
            if in_table:
                out.append('</table>')
                in_table = False
            if line.startswith('- '):
                out.append(f'<li>{html.escape(line[2:])}</li>')
            elif line.strip() == '':
                out.append('<br>')
            else:
                out.append(f'<p>{html.escape(line)}</p>')
        i += 1

    if in_table:
        out.append('</table>')
    if in_code:
        out.append('</code></pre>')
    out.append('</body></html>')
    return '\n'.join(out)

if __name__ == '__main__':
    src = sys.argv[1] if len(sys.argv) > 1 else 'results/final_summary.md'
    dst = sys.argv[2] if len(sys.argv) > 2 else src.replace('.md', '.html')
    html_content = md_to_html(open(src).read())
    open(dst, 'w').write(html_content)
    print(f'Generated: {dst}')
