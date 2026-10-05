"""Build an offline review gallery and an honest queue from the real catalog.

Only media with a completed export appears as playable. Unknown exercises never
receive a similar animation by name/category. This file does not publish assets.
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

from export_media import sha256

PROJECT = Path(__file__).resolve().parents[2]
VISUALS = PROJECT / "output/exercise_visuals"


def load_exports(rows: list[dict], visuals: Path) -> tuple[dict, list]:
    by_id = {row["exerciseId"]: row for row in rows}
    media = {}
    invalid = []
    def version(path):
        match = re.fullmatch(r"v([0-9]+)", path.parent.name)
        return (path.parent.parent.name, int(match.group(1)) if match else -1)
    for path in sorted(visuals.glob("*/v*/media.json"), key=version):
        try:
            item = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            invalid.append(path.relative_to(visuals).as_posix())
            continue
        if not isinstance(item, dict) or item.get("status") != "rendered":
            continue
        if not isinstance(item.get("exerciseId"), str):
            invalid.append(path.relative_to(visuals).as_posix())
            continue
        if item["exerciseId"] not in by_id:
            raise ValueError(f"Media ID is absent from catalog: {item['exerciseId']}")
        if path.parent.parent.name != item["exerciseId"]:
            invalid.append(path.relative_to(visuals).as_posix())
            continue
        required = ("exercise.mp4", "exercise.gif", "pose-start.png", "pose-middle.png", "pose-peak.png", "contact-sheet.png")
        records = item.get("files", {})
        if not isinstance(records, dict):
            invalid.append(path.relative_to(visuals).as_posix())
            continue
        if not all((path.parent / name).is_file() and isinstance(records.get(name), dict)
                   and records[name].get("bytes") == (path.parent / name).stat().st_size
                   and records[name].get("sha256") == sha256(path.parent / name)
                   for name in required):
            invalid.append(path.relative_to(visuals).as_posix())
            continue
        item["directory"] = path.parent.relative_to(visuals).as_posix()
        media[item["exerciseId"]] = item
    return media, invalid


def build(catalog_path: Path, output: Path) -> dict:
    catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
    rows = catalog["exercises"]
    media, invalid = load_exports(rows, VISUALS)
    entries = []
    for row in rows:
        item = {key: row.get(key, "") for key in ("exerciseId", "name", "muscle", "category", "equipmentKey", "equipmentName", "brand")}
        item["media"] = media.get(item["exerciseId"])
        item["status"] = "rendered" if item["media"] else "queued"
        entries.append(item)
    # UTF-8 JSON in an inert element, escaped against accidental HTML/script tags.
    data = json.dumps(entries, ensure_ascii=False).replace("<", "\\u003c").replace("&", "\\u0026")
    document = TEMPLATE.replace("__DATA__", data)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(document, encoding="utf-8")
    summary = {"total": len(entries), "renderedDemos": len(media), "queued": len(entries) - len(media), "invalidExports": invalid}
    (output.parent / "coverage.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    return summary


TEMPLATE = r'''<!doctype html>
<html lang="ko"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Setflow 운동 동작</title>
<style>
:root{color-scheme:light;--ink:#181818;--muted:#686868;--line:#dedede;--surface:#f5f5f5;--brand:#ccff00}
*{box-sizing:border-box}body{margin:0;font:16px/1.6 system-ui,"Malgun Gothic",sans-serif;color:var(--ink);background:#fff}
main{max-width:1280px;margin:auto;padding:32px 18px}header{margin-bottom:24px}.wordmark{font-size:22px;font-weight:800;letter-spacing:-1px}
h1{font-size:32px;line-height:1.3;margin:24px 0 12px}h2{font-size:18px;line-height:1.4;margin:0}
p{margin:8px 0;color:var(--muted)}.stats{display:flex;gap:24px;flex-wrap:wrap;margin:24px 0}.stats strong{font-size:28px;color:var(--ink);display:block}
.controls{display:flex;gap:12px;flex-wrap:wrap;margin:24px 0}input,select,button{font:inherit;color:inherit;min-height:44px;border:1px solid var(--line);border-radius:12px;padding:8px 14px;background:#fff}
input{flex:1;min-width:160px}button{cursor:pointer}button:hover{background:var(--surface)}button:focus-visible,input:focus-visible,select:focus-visible,a:focus-visible{outline:3px solid var(--ink);outline-offset:3px}
button[aria-pressed=true]{background:var(--brand);border-color:var(--ink)}.tabs{display:flex;gap:8px}.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(min(100%,280px),1fr));gap:20px}
article{border:1px solid var(--line);border-radius:18px;overflow:hidden;background:#fff}video{width:100%;aspect-ratio:1;display:block;object-fit:contain;background:#f8f8f8}
.info{padding:18px}.badge{display:inline-block;font-size:12px;background:var(--surface);border-radius:6px;padding:2px 8px;margin:8px 0}
.actions{display:flex;gap:14px;flex-wrap:wrap;align-items:center;font-size:14px}.actions button{min-height:36px;padding:4px 10px}.actions a{color:var(--ink)}
table{width:100%;border-collapse:collapse;font-size:14px}th,td{text-align:left;padding:12px;border-bottom:1px solid var(--line)}th{background:var(--surface)}.table-wrap{overflow:auto;border:1px solid var(--line);border-radius:14px}
td:first-child{min-width:200px}.empty{padding:32px 0}.note{border-left:3px solid var(--line);padding-left:14px;margin:24px 0}footer{margin-top:36px;font-size:13px}
@media(max-width:480px){main{padding-top:18px}h1{font-size:26px}.stats{gap:18px}.stats strong{font-size:24px}select{flex:1}}
</style>
<main>
<header><div class="wordmark">Setflow</div><h1>운동 동작 보기</h1>
<p>보디빌더 체형으로 보는 운동별 동작과 주요 근육</p>
<div class="stats"><div><strong id="total"></strong>전체 종목</div><div><strong id="rendered"></strong>동작 시안</div><div><strong id="queued"></strong>제작 대기</div></div>
<p class="note">동작 시안은 트레이너 검수 전 데모입니다. 붉은색은 주요 운동 부위를 안내하며, 근육 활성도의 측정값을 나타내지 않습니다.</p>
</header>
<div class="tabs" aria-label="보기 선택"><button id="demos-tab" aria-pressed="true">동작 시안</button><button id="queue-tab" aria-pressed="false">전체 제작 목록</button></div>
<div class="controls"><input id="search" type="search" aria-label="운동 검색" placeholder="운동 이름 또는 기구 검색"><select id="category" aria-label="운동 부위"><option value="">모든 부위</option></select><select id="state" aria-label="제작 상태"><option value="">모든 상태</option><option value="rendered">동작 시안</option><option value="queued">제작 대기</option></select></div>
<p id="result" role="status" aria-live="polite"></p><div id="content"></div>
<footer>인체 원본: MakeHuman / MPFB의 CC0 자산 · 체형 조형, 기구, 동작, 부위 표시: Setflow 제작<br><a href="bodyweight_squat/v5/README.md">인체 출처와 제작 기록</a> · <a href="catalog.json">전체 제작 목록</a></footer>
</main>
<script id="catalog-data" type="application/json">__DATA__</script>
<script>
'use strict';
const rows=JSON.parse(document.getElementById('catalog-data').textContent), $=id=>document.getElementById(id);
let view='demos';
const categories=[...new Set(rows.map(row=>row.muscle||row.category).filter(Boolean))].sort();
for(const name of categories){const option=document.createElement('option');option.value=name;option.textContent=name;$('category').append(option)}
$('total').textContent=rows.length.toLocaleString('ko-KR');$('rendered').textContent=rows.filter(row=>row.media).length;$('queued').textContent=rows.filter(row=>!row.media).length.toLocaleString('ko-KR');
function node(tag,text,cls){const element=document.createElement(tag);if(text!==undefined)element.textContent=text;if(cls)element.className=cls;return element}
function link(label,href){const element=node('a',label);element.href=href;return element}
function show(){
 document.querySelectorAll('video').forEach(video=>video.pause());
 const term=$('search').value.trim().toLocaleLowerCase(), category=$('category').value, state=$('state').value;
 const selected=rows.filter(row=>(view!=='demos'||row.media)&&(!category||(row.muscle||row.category)===category)&&(!state||row.status===state)&&(!term||[row.name,row.exerciseId,row.equipmentKey,row.equipmentName,row.brand].join(' ').toLocaleLowerCase().includes(term)));
 const content=$('content');content.replaceChildren();$('result').textContent=`${selected.length.toLocaleString('ko-KR')}개 종목`;
 if(!selected.length){content.append(node('p','검색 조건에 맞는 종목이 없습니다.','empty'));return}
 if(view==='demos'){
  const grid=node('div',undefined,'grid');
  for(const row of selected){
   const directory=row.media.directory, card=node('article'), video=node('video');
   video.controls=true;video.loop=true;video.muted=true;video.playsInline=true;video.preload='none';video.poster=directory+'/pose-start.png';video.src=directory+'/exercise.mp4';video.setAttribute('aria-label',row.name+' 동작 데모');
   video.addEventListener('play',()=>document.querySelectorAll('video').forEach(other=>{if(other!==video)other.pause()}));
   const info=node('div',undefined,'info');info.append(node('h2',row.name),node('span','데모 · 검수 전','badge'));
   const actions=node('div',undefined,'actions'), slow=node('button','0.5배속');slow.type='button';slow.setAttribute('aria-pressed','false');
   slow.addEventListener('click',()=>{const enabled=video.playbackRate!==.5;video.playbackRate=enabled?.5:1;slow.setAttribute('aria-pressed',String(enabled))});
   actions.append(slow,link('자세 비교',directory+'/contact-sheet.png'),link('GIF',directory+'/exercise.gif'));
   info.append(actions);card.append(video,info);grid.append(card);
  }content.append(grid);
 }else{
  const wrap=node('div',undefined,'table-wrap'), table=node('table'), head=node('thead'), heading=node('tr');
  for(const title of ['운동','부위','기구 / 제조사','제작 상태'])heading.append(node('th',title));head.append(heading);table.append(head);const body=node('tbody');
  for(const row of selected){const line=node('tr');for(const value of [row.name,row.muscle||row.category||'—',[row.equipmentName,row.brand].filter(Boolean).join(' / ')||'—',row.media?'동작 시안 · 검수 전':'제작 대기'])line.append(node('td',value));body.append(line)}table.append(body);wrap.append(table);content.append(wrap);
 }
}
for(const id of ['search','category','state'])$(id).addEventListener(id==='search'?'input':'change',show);
for(const [id,type] of [['demos-tab','demos'],['queue-tab','queue']])$(id).addEventListener('click',()=>{view=type;$('demos-tab').setAttribute('aria-pressed',String(view==='demos'));$('queue-tab').setAttribute('aria-pressed',String(view==='queue'));show()});
document.addEventListener('visibilitychange',()=>{if(document.hidden)document.querySelectorAll('video').forEach(video=>video.pause())});
show();
</script></html>'''


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--catalog", type=Path, default=VISUALS / "catalog.json")
    parser.add_argument("--output", type=Path, default=VISUALS / "index.html")
    arguments = parser.parse_args()
    print(json.dumps(build(arguments.catalog, arguments.output)))
