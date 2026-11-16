#!/usr/bin/env python3
"""i18n 暂存/主干语言包逐分片自检：键集合/顺序、占位符、未译值。"""
import sys, json, os, re, collections
ROOT='/root/OhGithubLost'
PH=re.compile(r'%\d*\$?[@a-zA-Z]|\{\w+\}|\$\d+|\\n|\\t')
def phset(s): return collections.Counter(PH.findall(s))
# 技术词白名单：允许与 zh 同形（原文保留）
KEEP={'github','release','actions','pr','token','pages','commit','ohgithublost',
      'gist','readme','doh','dns','issue','sha','apk','api','ui','url','oauth',
      'yaml','json','git','id','ok','http','https','md','css','html','debug','info','log',
      'feedissue'}
def check(lang, base):
    src_dir=os.path.join(ROOT,'assets/i18n/zh')
    dst_dir=base if os.path.isabs(base) else os.path.join(ROOT,base)
    shards=sorted(f[:-5] for f in os.listdir(src_dir) if f.endswith('.json'))
    problems=[]
    total=0
    for sh in shards:
        sp=os.path.join(src_dir,sh+'.json'); dp=os.path.join(dst_dir,sh+'.json')
        src=json.load(open(sp,encoding='utf-8'),object_pairs_hook=collections.OrderedDict)
        if not os.path.exists(dp):
            problems.append(f'{sh}: 缺失'); continue
        dst=json.load(open(dp,encoding='utf-8'),object_pairs_hook=collections.OrderedDict)
        if list(src)!=list(dst):
            problems.append(f'{sh}: 键集合/顺序不一致'); continue
        for k,v in src.items():
            total+=1
            d=dst[k]
            if not isinstance(d,str) or not d.strip():
                problems.append(f'{sh}/{k}: 值非字符串或空'); continue
            if phset(d)!=phset(v):
                problems.append(f'{sh}/{k}: 占位符不一致 {phset(v)} vs {phset(d)}'); continue
            # 真正的未翻译信号：值与 en 基线相同（且源文非纯技术词/符号）。
            # 不能拿 zh 同形判断——日语等语言大量词与简中同形（保存/通知/行），
            # 那是正确译文，不是未翻译。
            en_shard = os.path.join(ROOT, 'assets/i18n/en', sh + '.json')
            en_val = None
            if os.path.exists(en_shard):
                en_val = json.load(open(en_shard, encoding='utf-8')).get(k)
            if lang != 'en' and en_val is not None and d.strip() == en_val.strip():
                pure_symbol = not re.search(r'[\w\u4e00-\u9fff\uac00-\ud7af]', en_val.strip())
                norm = en_val.strip().lower().replace(' ', '')
                if not pure_symbol and norm not in KEEP and not re.fullmatch(r'[A-Za-z0-9._\-/ ]+', en_val.strip()):
                    problems.append(f'{sh}/{k}: 与英文基线同形「{en_val[:24]}」')
    print(f'{lang}: {len(shards)} 分片 / {total} 键 / problems={len(problems)}')
    for p in problems[:25]: print('  ',p)
    if len(problems)>25: print(f'   ... 另 {len(problems)-25} 项')
    return len(problems)

if __name__=='__main__':
    lang=sys.argv[1]
    base=sys.argv[2] if len(sys.argv)>2 else f'.translate-work/i18n/{lang}'
    sys.exit(1 if check(lang,base) else 0)
