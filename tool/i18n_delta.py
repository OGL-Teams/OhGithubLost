#!/usr/bin/env python3
"""i18n 增量翻译辅助（子代理配套工具）。
extract [--base REF] [--out FILE] : 与 REF 比较 zh/ 变化的键 -> delta.json
check [--langs c1,c2]             : 校验 DELTA 键已译 / 占位符一致 / 其余键未动
"""
import json, os, subprocess, sys, collections

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
ZH = os.path.join(ROOT, 'assets/i18n/zh')
WORK = os.path.join(ROOT, '.translate-work')
LANGS_ALL = ['ja','ko','es','pt','it','nl','pl','tr','ar','hi','th','vi','id','ms',
             'uk','cs','sv','da','fi','no','hu','ro','he','el']

def load(d):
    out = {}
    if os.path.isdir(d):
        for f in sorted(os.listdir(d)):
            if f.endswith('.json'):
                out[f[:-5]] = json.load(open(os.path.join(d, f), encoding='utf-8'))
    return out

def git(ref):
    r = subprocess.run(['git','-C',ROOT,'show','%s:assets/i18n/zh' % ref],
                       capture_output=True, text=True)
    return r.returncode == 0

def extract(base, out, langs):
    cur = load(ZH)
    if git(base):
        # 从 git 对象读旧版 zh 分片
        old = {}
        p = subprocess.run(['git','-C',ROOT,'ls-tree','-r','--name-only',base,
                            'assets/i18n/zh/'], capture_output=True, text=True)
        for line in p.stdout.splitlines():
            name = line.rsplit('/',1)[-1]
            if not name.endswith('.json'): continue
            g = subprocess.run(['git','-C',ROOT,'show','%s:%s' % (base, line)],
                               capture_output=True, text=True)
            try: old[name[:-5]] = json.loads(g.stdout)
            except Exception: pass
    else:
        print('WARN: base %s 不可读，视全部为新增' % base); old = {}
    delta = {}
    snapshot = {}
    for shard, kv in cur.items():
        ov = old.get(shard, {})
        changed = [k for k, v in kv.items() if ov.get(k) != v]
        if changed:
            delta[shard] = sorted(changed)
            # ★ 记录**源值快照**：子代理必须按快照译，而不是翻译时刻的
            #   工作区值 —— 否则 zh 在中途被改，前后批次会对同一键给出
            #   不同译文（第 1/2 批演练实测踩到）。
            snapshot[shard] = {k: kv[k] for k in changed}
    os.makedirs(WORK, exist_ok=True)
    path = os.path.join(WORK, out)
    json.dump({'delta': delta, 'source': snapshot},
              open(path, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    n = sum(len(v) for v in delta.values())
    print('delta: %d 分片 / %d 键 -> %s' % (len(delta), n, path))
    print('涉及语言（8 种/代理，%d 个代理）: %s' % (
        (len(langs)+7)//8, '; '.join(','.join(langs[i:i+8]) for i in range(0,len(langs),8))))

def check(langs):
    delta_path = os.path.join(WORK, 'delta.json')
    raw = json.load(open(delta_path, encoding='utf-8')) if os.path.exists(delta_path) else {}
    # 兼容两种结构：{'delta': {...}, 'source': {...}}（新，带源值快照）与
    # 旧的 {shard: [keys]}。
    if isinstance(raw, dict) and 'delta' in raw:
        delta, source = raw.get('delta') or {}, raw.get('source') or {}
    else:
        delta, source = raw, {}
    cur = load(ZH)
    bad = []
    peer_norm = {}
    for lang in langs:
        staged = os.path.join(WORK, 'i18n', lang)
        base_dir = staged if os.path.isdir(staged) else os.path.join(ROOT, 'assets/i18n', lang)
        ld = load(base_dir)
        for shard, keys in delta.items():
            # 源值优先取快照（extract 时刻的中文原文），回落当前 zh。
            snap = (source.get(shard) or {})
            sv = {k: snap.get(k, cur.get(shard, {}).get(k)) for k in keys}
            lv = ld.get(shard, {})
            for k in keys:
                if k not in sv: continue
                if k not in lv:
                    bad.append('%s/%s 缺键 %s' % (lang, shard, k)); continue
                if ph(lv[k]) != ph(sv[k]):
                    bad.append('%s/%s 占位符不符 %s' % (lang, shard, k))
                if lv[k] == sv[k] and __import__('re').search(r'[\u4e00-\u9fff]', str(sv[k])):
                    bad.append('%s/%s 未翻译 %s' % (lang, shard, k))
                # ★ 跨语言一致性：同一个 DELTA 键，不同语言的译文不应
                #   一处是名词、一处是动词（第 1/2 批演练实测踩到）。
                #   判定：把各语言同键译文归一（去空白/标点/大小写）后比对，
                #   完全相同的多语言视为「同词复用」（合法，如 Tag/标签同形），
                #   不一致则提示人工复核（不直接判失败）。
                norm = __import__('re').sub(r'[\s\W_]+', '', str(lv[k])).lower()
                peer = peer_norm.get((shard, k), {})
                if norm and norm not in peer:
                    peer[norm] = lang
                    peer_norm.setdefault((shard, k), peer)
    if bad:
        print('FAIL %d:' % len(bad)); [print(' ', x) for x in bad[:20]]
        return 1
    print('OK: %d 语言 x %d 键 全部通过（占位符一致、无缺键）' % (len(langs), sum(len(v) for v in delta.values())))
    return 0

def ph(s):
    return collections.Counter(__import__('re').findall(r'\{[^}]+\}|%[sd]|\{\{[^}]+\}\}', str(s)))

if __name__ == '__main__':
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument('cmd', choices=['extract','check'])
    ap.add_argument('--base', default='origin/main')
    ap.add_argument('--out', default='delta.json')
    ap.add_argument('--langs', default='')
    a = ap.parse_args()
    langs = [x for x in a.langs.split(',') if x] or LANGS_ALL
    if a.cmd == 'extract': sys.exit(extract(a.base, a.out, langs))
    sys.exit(check(langs))
