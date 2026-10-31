#!/usr/bin/env python3
"""Build a self-contained HTML inventory from local text reports (stdlib only)."""
import argparse
from collections import Counter, defaultdict
import csv
from datetime import datetime, timezone
import html
from pathlib import Path
import re


def esc(value):
    return html.escape(str(value), quote=True)


def read(path):
    return path.read_text(encoding='utf-8', errors='replace') if path.is_file() else ''


def field(text, key, default='Not recorded'):
    match = re.search(r'^\s*' + re.escape(key) + r'\s*:\s*(.+)$', text, re.M)
    return match.group(1).strip() if match else default


def render(directory):
    directory = Path(directory).resolve()
    if not directory.is_dir():
        raise ValueError('Inventory directory does not exist')
    reports = {p.stem: read(p) for p in sorted(directory.glob('*.txt')) if p.is_file()}
    summary = reports.get('summary', '')
    cpu = reports.get('cpu-info', '')
    system = reports.get('system-info', '')
    memory = reports.get('memory-info', '')
    host = field(summary, 'Host', field(system, 'Static hostname', 'Inventory snapshot'))
    os_match = re.search(r'^PRETTY_NAME=[\'"]?([^\n\'"]+)', system, re.M)
    distro = os_match.group(1) if os_match else field(system, 'Operating System')
    cpu_name = field(cpu, 'Model name')
    cores = field(cpu, 'CPU(s)')
    total_match = re.search(r'^MemTotal:\s+(\d+)\s+kB', memory, re.M)
    ram = f'{int(total_match.group(1)) / 1048576:.1f} GiB' if total_match else 'Not recorded'
    rows = []
    status_path = directory / 'collection-status.tsv'
    if status_path.is_file():
        with status_path.open(encoding='utf-8', errors='replace', newline='') as stream:
            rows = list(csv.DictReader(stream, delimiter='\t'))
    by_section = defaultdict(list)
    counts = Counter()
    for row in rows:
        status = row.get('status') or 'UNKNOWN'
        state = 'ok' if status == 'OK' else 'skipped' if status == 'SKIPPED' else 'failed'
        counts[state] += 1
        by_section[row.get('section', '')].append((state, status, row.get('command', '')))
    issues = [(section, state, status, command) for section, items in by_section.items()
              for state, status, command in items if state != 'ok']
    issue_html = ''.join(
        f'<tr><td>{esc(section)}</td><td><span class="badge {state}">{esc(status)}</span></td><td>{esc(command)}</td></tr>'
        for section, state, status, command in issues)
    if not rows:
        issue_html = '<tr><td colspan="3">No collection-status log found. Collection completeness is unknown.</td></tr>'
    elif not issues:
        issue_html = '<tr><td colspan="3">All recorded collection commands completed successfully.</td></tr>'
    sections = []
    nav = []
    excluded = {'summary', 'reinstall-helper-unavailable', 'reinstall-query-errors', 'dnf-user-package-names'}
    for index, (name, text) in enumerate(reports.items()):
        if name in excluded:
            continue
        states = {item[0] for item in by_section.get(name, [])}
        state = 'failed' if 'failed' in states else 'skipped' if 'skipped' in states else 'ok' if states else 'unknown'
        label = {'ok': 'Collected', 'failed': 'Collection error', 'skipped': 'Partial / skipped', 'unknown': 'Untracked'}[state]
        title = name.replace('-', ' ').capitalize()
        ident = f'section-{index}'
        sections.append(f'''<details class="report" id="{ident}" data-state="{state}">
<summary><span>{esc(title)}</span><span class="badge {state}">{label}</span></summary>
<div class="report-body"><div class="section-note">{len(text.splitlines()):,} lines · {len(text.encode('utf-8')):,} bytes · escaped raw command output</div>
<pre tabindex="0">{esc(text)}</pre></div></details>''')
        nav.append(f'<a href="#{ident}">{esc(title)}</a>')
    disks = []
    for line in reports.get('filesystem-usage', '').splitlines():
        cols = line.split()
        if len(cols) >= 7 and re.fullmatch(r'\d+%', cols[5]):
            pct = min(100, max(0, int(cols[5][:-1])))
            disks.append(f'<tr><td>{esc(" ".join(cols[6:]))}<small>{esc(cols[0])} · {esc(cols[1])}</small></td>'
                         f'<td>{esc(cols[3])} / {esc(cols[2])}</td><td><div class="meter" role="img" aria-label="{pct}% used"><i style="width:{pct}%"></i></div><small>{pct}% used</small></td></tr>')
    storage = ''.join(disks) or '<tr><td colspan="3">Filesystem capacity data not recorded.</td></tr>'
    helper_notice = reports.get('reinstall-helper-unavailable', '').strip()
    if not helper_notice and not (directory / 'reinstall-dnf-userinstalled.sh').is_file():
        helper_notice = 'No reinstall helper was generated in this inventory.'
        package_text = reports.get('dnf-user-package-names', '')
        invalid = [line for line in package_text.splitlines() if line.strip()
                   and not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9+_.-]*', line)]
        if invalid:
            helper_notice += ' Package-query output contains non-package text; helper generation was not safe.'
    completion = ('Collector summary found.' if summary else
                  'Collector summary missing: completion is unconfirmed. Available reports are shown below.')
    stamp = field(summary, 'Generated', 'Collection time not recorded')
    # Text is HTML escaped and never inserted as executable script or markup.
    document = TEMPLATE.replace('@@HOST@@', esc(host)).replace('@@DISTRO@@', esc(distro))
    values = {
        'CPU': esc(cpu_name), 'THREADS': esc(cores), 'RAM': esc(ram),
        'SECTIONS': str(len(sections)), 'OK': str(counts['ok']),
        'FAILED': str(counts['failed']), 'SKIPPED': str(counts['skipped']),
        'ISSUES': issue_html, 'REPORTS': '\n'.join(sections), 'NAV': '\n'.join(nav),
        'STORAGE': storage, 'STAMP': esc(stamp),
        'HELPER': esc(helper_notice) if helper_notice else 'Review the generated reinstall helper before use. It is never executed by the collector.',
        'COMPLETION': esc(completion),
        'BUILT': datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M UTC'),
    }
    for key, value in values.items():
        document = document.replace(f'@@{key}@@', value)
    output = directory / 'index.html'
    output.write_text(document, encoding='utf-8')
    output.chmod(0o600)
    return output


TEMPLATE = r'''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>@@HOST@@ · Linux System Inventory</title>
<style>
:root{color-scheme:dark;--bg:#10151d;--panel:#19212c;--line:#2d3948;--text:#e8eef5;--muted:#a8b6c8;--accent:#91e1c3;--bad:#ffad9c;--warn:#f3d08c}*{box-sizing:border-box}html{scroll-behavior:smooth}body{margin:0;background:var(--bg);color:var(--text);font:15px/1.6 system-ui,sans-serif}a{color:inherit;text-decoration:none}button,input,select{font:inherit}button,select{cursor:pointer}button:focus-visible,a:focus-visible,input:focus-visible,select:focus-visible,summary:focus-visible{outline:3px solid var(--accent);outline-offset:4px}.layout{display:grid;grid-template-columns:248px minmax(0,1fr);max-width:1720px;margin:auto}aside{height:100vh;position:sticky;top:0;border-right:1px solid var(--line);padding:32px 22px;overflow:auto}.brand{font-weight:750;font-size:18px;letter-spacing:-.5px}.brand b{color:var(--accent)}.eyebrow{text-transform:uppercase;font-size:11px;letter-spacing:2px;color:var(--accent);font-weight:700}aside .eyebrow{margin:28px 0 12px}aside a{display:block;font-size:12px;color:var(--muted);padding:6px 0}aside a:hover{color:var(--accent)}main{padding:44px clamp(20px,4vw,64px);min-width:0}.topline{display:flex;justify-content:space-between;align-items:center;gap:20px}.local{border:1px solid var(--line);border-radius:30px;padding:5px 12px;font-size:11px;color:var(--muted)}h1{font-size:clamp(32px,4vw,54px);line-height:1.1;letter-spacing:-2px;margin:22px 0 14px;overflow-wrap:anywhere}h2{font-size:22px;letter-spacing:-.5px;margin:0 0 6px}p{color:var(--muted);margin:8px 0}.lede{max-width:740px;font-size:16px}.overview{display:grid;grid-template-columns:2fr 1fr 1fr;gap:16px;margin:30px 0 18px}.card,.panel{background:var(--panel);border:1px solid var(--line);border-radius:12px}.card{padding:22px}.card .label{color:var(--muted);font-size:12px}.card .value{font-size:27px;font-weight:650;margin-top:10px;line-height:1.3}.card:first-child .value{font-size:18px}.card small{color:var(--muted)}.status-strip{display:flex;gap:12px;flex-wrap:wrap;padding:14px 0 25px}.pill{border:1px solid var(--line);padding:7px 14px;border-radius:7px;font-size:12px}.pill strong{font-size:17px;margin-right:5px}.ok{color:var(--accent)}.failed{color:var(--bad)}.skipped{color:var(--warn)}.unknown{color:var(--muted)}.panel{padding:24px;margin:16px 0 28px;overflow:auto}.panel p{font-size:13px}.table-wrap{overflow:auto}table{width:100%;border-collapse:collapse;font-size:13px;text-align:left;margin-top:18px}td,th{padding:12px 10px;border-bottom:1px solid var(--line);vertical-align:top;overflow-wrap:anywhere}th{color:var(--muted);font-size:11px;text-transform:uppercase;letter-spacing:1px}td small{display:block;color:var(--muted);font-size:11px}.meter{height:7px;background:#354353;border-radius:7px;min-width:110px;margin:7px 0}.meter i{display:block;height:100%;border-radius:7px;background:var(--accent)}.badge{font-size:10px;text-transform:uppercase;letter-spacing:.6px;font-weight:650;border:1px solid currentColor;border-radius:5px;padding:3px 7px;white-space:nowrap}.toolbar{display:flex;gap:10px;flex-wrap:wrap;margin:20px 0 12px}input,select,button{border:1px solid var(--line);border-radius:7px;background:var(--panel);color:var(--text);padding:10px 12px}input{flex:1;min-width:190px}input::placeholder{color:var(--muted)}button:hover{border-color:var(--accent)}.result-count{font-size:12px;color:var(--muted);margin:10px 0 16px}.report{border:1px solid var(--line);border-radius:9px;margin:10px 0;background:var(--panel);scroll-margin-top:20px}.report summary{cursor:pointer;padding:16px 18px;display:flex;justify-content:space-between;gap:12px;align-items:center;font-weight:550;font-size:14px}.report summary:before{content:'+';color:var(--accent);margin-right:2px}.report[open] summary:before{content:'−'}.report summary>span:first-child{flex:1}.report[open] summary{border-bottom:1px solid var(--line)}.report-body{padding:16px}.section-note{font-size:11px;color:var(--muted);margin-bottom:12px}pre{font:12px/1.65 ui-monospace,SFMono-Regular,Consolas,monospace;white-space:pre;overflow:auto;max-height:560px;margin:0;padding:16px;background:#111821;border-radius:6px;color:#d5e1ef}.note{border-left:2px solid var(--warn);padding:8px 16px;margin:20px 0;font-size:12px;color:var(--muted)}footer{margin-top:35px;padding-top:20px;border-top:1px solid var(--line);font-size:11px;color:var(--muted)}[hidden]{display:none!important}@media(max-width:900px){.layout{grid-template-columns:1fr}aside{display:none}main{padding:28px 18px}.overview{grid-template-columns:1fr 1fr}.overview .card:first-child{grid-column:1/-1}}@media print{aside,.toolbar{display:none}.layout{display:block}main{padding:0}body{background:white;color:black}.panel,.card,.report{break-inside:avoid;background:white}.muted,p{color:#444}pre{white-space:pre-wrap;max-height:none;color:black;background:#eee}}
</style></head><body><div class="layout">
<aside><div class="brand"><b>◈</b> SYSTEM INVENTORY</div><p style="font-size:12px">Linux · local report</p><div class="eyebrow">Snapshot</div><a href="#overview">System overview</a><a href="#health">Collection status</a><a href="#storage">Filesystem capacity</a><div class="eyebrow">Collected sections</div>@@NAV@@</aside>
<main><header id="overview"><div class="topline"><span class="eyebrow">Infrastructure / Inventory snapshot</span><span class="local">OFFLINE · SELF-CONTAINED</span></div><h1>@@HOST@@</h1><p class="lede">@@DISTRO@@</p><p class="lede">A searchable record of the hardware, software and services collected from this machine.</p></header>
<div class="overview"><div class="card"><div class="label">PROCESSOR</div><div class="value">@@CPU@@</div><small>@@THREADS@@ logical CPUs recorded</small></div><div class="card"><div class="label">PHYSICAL MEMORY</div><div class="value">@@RAM@@</div><small>Total reported by /proc/meminfo</small></div><div class="card"><div class="label">REPORT SECTIONS</div><div class="value">@@SECTIONS@@</div><small>Expand a section to inspect output</small></div></div>
<div class="note">@@COMPLETION@@</div>
<div class="status-strip"><div class="pill ok"><strong>@@OK@@</strong> commands completed</div><div class="pill failed"><strong>@@FAILED@@</strong> collection errors</div><div class="pill skipped"><strong>@@SKIPPED@@</strong> commands skipped</div></div>
<section class="panel" id="health"><span class="eyebrow">Coverage / Diagnostics</span><h2>Know what was collected.</h2><p>These are collection outcomes, not a system-health score. Missing tools, permissions and cached repository metadata can leave partial reports.</p><div class="table-wrap"><table><thead><tr><th>Section</th><th>Outcome</th><th>Command</th></tr></thead><tbody>@@ISSUES@@</tbody></table></div><div class="note">@@HELPER@@</div></section>
<section class="panel" id="storage"><span class="eyebrow">Storage / Snapshot</span><h2>Filesystem capacity</h2><p>Usage recorded by df; temporary and virtual filesystems may also appear.</p><div class="table-wrap"><table><thead><tr><th>Mount / Filesystem</th><th>Used / Total</th><th>Capacity used</th></tr></thead><tbody>@@STORAGE@@</tbody></table></div></section>
<section id="reports"><span class="eyebrow">Evidence / Command output</span><h2>Explore the inventory</h2><p>Search section titles and the full collected text. Everything stays in this file.</p>
<div class="toolbar"><input id="search" type="search" aria-label="Search all report text" placeholder="Search packages, devices, services…"><select id="filter" aria-label="Filter by collection status"><option value="all">All sections</option><option value="failed">Collection errors</option><option value="skipped">Partial / skipped</option><option value="ok">Collected</option><option value="unknown">Untracked</option></select><button id="expand" type="button">Expand visible</button><button id="collapse" type="button">Collapse all</button></div><div class="result-count" id="results" role="status" aria-live="polite"></div>@@REPORTS@@</section>
<footer>Collection: @@STAMP@@ · HTML built: @@BUILT@@<br>Contains machine and network details. Review before sharing. This snapshot is an inventory, not a backup.</footer>
</main></div><script>
'use strict';
const sections=Array.from(document.querySelectorAll('.report'));
const query=document.querySelector('#search'),filter=document.querySelector('#filter');
const corpus=new Map(sections.map(el=>[el,el.textContent.toLowerCase()]));
function update(){const terms=query.value.toLowerCase().trim().split(/\s+/).filter(Boolean);let count=0;for(const el of sections){const match=terms.every(term=>corpus.get(el).includes(term))&&(filter.value==='all'||el.dataset.state===filter.value);el.hidden=!match;if(match)count++;}document.querySelector('#results').textContent=`${count} of ${sections.length} sections shown`;}
query.addEventListener('input',update);filter.addEventListener('change',update);
document.querySelector('#expand').addEventListener('click',()=>sections.filter(el=>!el.hidden).forEach(el=>el.open=true));
document.querySelector('#collapse').addEventListener('click',()=>sections.forEach(el=>el.open=false));
function revealHash(){const el=document.getElementById(location.hash.slice(1));if(el&&el.classList.contains('report')){query.value='';filter.value='all';update();el.open=true;el.scrollIntoView();}}
window.addEventListener('hashchange',revealHash);update();revealHash();
</script></body></html>'''


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    args = parser.parse_args()
    try:
        print(f'HTML report: {render(args.directory)}')
    except (OSError, ValueError) as error:
        parser.exit(1, f'Cannot render report: {error}\n')
