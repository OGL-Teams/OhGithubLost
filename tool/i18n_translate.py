#!/usr/bin/env python3
import argparse, concurrent.futures, json, os, re, sys, threading, time
import urllib.request, urllib.error, collections
# ★ 用**当前工作目录**（CI 的 checkout 根），不硬编码本地沙箱路径。
ROOT=os.path.abspath(os.environ.get('OGL_ROOT') or os.getcwd())
ENDPOINT='https://index-translate.bilibili.com/v1/chat/completions'
LANGS=[('ja','Japanese'),('ko','Korean'),('es','Spanish'),('pt','Portuguese'),('it','Italian'),('nl','Dutch'),('pl','Polish'),('tr','Turkish'),('ar','Arabic'),('hi','Hindi'),('th','Thai'),('vi','Vietnamese'),('id','Indonesian'),('ms','Malay'),('uk','Ukrainian'),('cs','Czech'),('sv','Swedish'),('da','Danish'),('fi','Finnish'),('no','Norwegian'),('hu','Hungarian'),('ro','Romanian'),('he','Hebrew'),('el','Greek')]
EXISTING={'zh','zh_Hant','en','de','fr','ru'}
SHARDS=sorted(x[:-5] for x in os.listdir(ROOT+'/assets/i18n/zh') if x.endswith('.json'))
PH=re.compile(r'%\d*\$?[@a-zA-Z]|\{\w+\}|\$\d+|\\n|\\t')
def phset(s): return collections.Counter(PH.findall(s))
def build_prompt(texts, lang):
    payload=json.dumps(texts,ensure_ascii=False,separators=(',',':'))
    return ('Translate the following Chinese mobile-app UI strings into %s, following every constraint.\n'
            '[SOURCE]\n%s\n[CONSTRAINTS]\n'
            '1. [HARD] Input is a JSON object. Output ONLY a JSON object with the EXACT SAME keys and the same number of values; every value must be a string. Keep every placeholder token (%%@, {name}, $1, %%1$s) and every JSON escape (\\n, \\t) byte-for-byte inside the translated value. Do not add, remove or rename keys.\n'
            '2. [SOFT] Mobile software UI copy: formal, concise, restrained. Express the meaning idiomatically in the target language rather than word-for-word; keep the same tone and level of politeness. Do not explain.\n'
            'Output only the JSON object, no markdown, no prose.')%(lang,payload)

def call(body, model, timeout):
    rate_gate()
    req=urllib.request.Request(ENDPOINT,data=json.dumps(body).encode('utf-8'),headers={'Content-Type':'application/json','Authorization':'Bearer index','User-Agent':'Mozilla/5.0'})
    with urllib.request.urlopen(req,timeout=timeout) as r: return json.loads(r.read())

def clean(s):
    if '</think>' in s: s=s.split('</think>',1)[1]
    s=s.strip()
    if s.startswith('```'):
        s=re.sub(r'^```[a-zA-Z]*\s*','',s); s=re.sub(r'\s*```$','',s)
    return s.strip()

def request_shard(texts, lang, force_model=None):
    model=force_model or ('Index-Translate-9B' if len(json.dumps(texts,ensure_ascii=False))>3500 else 'Index-Translate-35B-A3B')
    body={'model':model,'temperature':0,'chat_template_kwargs':{'enable_thinking':False},'messages':[{'role':'user','content':build_prompt(texts,lang)}]}
    last=None
    for attempt in range(3):
        try:
            r=call(body,model,60)
            out=clean(r['choices'][0]['message']['content'] or '')
            m=re.search(r'\{.*\}',out,re.S)
            parsed=json.loads(m.group(0) if m else out)
            if not isinstance(parsed,dict): raise ValueError('not object')
            if set(parsed)!=set(texts): raise ValueError('key mismatch')
            bad=[k for k,v in parsed.items() if not isinstance(v,str) or phset(v)!=phset(texts[k])]
            if bad: raise ValueError('placeholder/type mismatch: '+','.join(bad[:4]))
            return parsed,None
        except urllib.error.HTTPError as e:
            last='HTTP %d'%e.code
            if e.code not in (429,500,502,503,504): return None,last
        except Exception as e:
            last='%s: %s'%(type(e).__name__,str(e)[:80])
        # ★ 退避阶梯（用户指定）：第 1 次失败等 5s，第 2 次等 15s；
        #   仍失败则**跳过该块并记录**（不阻断整批，可续跑补齐）。
        time.sleep(5.0 if attempt == 0 else 15.0)
        # ★ 504 连发说明 RPM 撞顶：把全局间隔翻倍（上限 8s），后续请求整体放慢。
        if last == 'HTTP 504':
            with _RATE:
                globals()['MIN_INTERVAL'] = min(MIN_INTERVAL * 2, 8.0)
    return None,last
LOCK=threading.Lock(); DONE=[0]; FAIL=[]; START=[0.0]
# ★ RPM 限速闸：免费公网接口按 IP 限速，连续请求会 504（实测：间隔够就成功）。
#   用一个全局闸保证任意两次请求的最小间隔，2 并发也受它约束。
MIN_INTERVAL=float(os.environ.get('I18N_MIN_INTERVAL','1.0'))
_LAST=[0.0]
_RATE=threading.Lock()
def rate_gate():
    with _RATE:
        wait=_LAST[0]+MIN_INTERVAL-time.time()
        if wait>0: time.sleep(wait)
        _LAST[0]=time.time()
def bar(total):
    d=DONE[0]; w=32; n=int(w*d/total) if total else w
    el=time.time()-START[0]; eta=(el/d*(total-d)) if d else 0
    def fmt(s): return '%02d:%02d'%(int(s)//60,int(s)%60)
    sys.stdout.write('\r[%-32s] %d/%d  ok=%d fail=%d  elapsed=%s eta=%s'%('#'*n+'.'*(w-n),d,total,d-len(FAIL),len(FAIL),fmt(el),fmt(eta)))
    sys.stdout.flush()

CHUNK_CHARS=0  # 0 = 单键一块（最保守，CI 默认）

def chunk_by_chars(src, limit):
    # limit<=0 → 单键一块（最保守：每次只翻一条，避开 RPM 限速与长输入超时）
    if limit and limit <= 0:
        return [{k: v} for k, v in src.items()]
    out=[]; cur={}; n=0
    for k,v in src.items():
        L=len(str(v))
        if cur and n+L>limit:
            out.append(cur); cur={}; n=0
        cur[k]=v; n+=L
    if cur: out.append(cur)
    return out

def job(lang,name,shard):
    src=json.load(open(ROOT+'/assets/i18n/zh/'+shard+'.json',encoding='utf-8'))
    dst=ROOT+'/assets/i18n/%s/%s.json'%(lang,shard)
    prev=None
    if os.path.exists(dst):
        try: prev=json.load(open(dst,encoding='utf-8'))
        except Exception: prev=None
    if prev and set(prev)==set(src) and all(isinstance(v,str) for v in prev.values()):
        with LOCK: DONE[0]+=1; bar(TOTAL)
        return
    # ★ 按**字符数**切块（约 500 字符/块）：固定条数会让长文本块过大 → 504。
    #   每块独立校验，失败只影响该块（可续跑）。
    result={}
    for part in chunk_by_chars(src, CHUNK_CHARS):
        out,err=request_shard(part,name)
        if out is None:
            # ★ 质量优先的降级：35B 超时/504 → 改用 9B 再试一次（仍保质量档）
            out,err=request_shard(part,name,force_model='Index-Translate-9B')
        if out is None:
            with LOCK: FAIL.append('%s/%s: %s'%(lang,shard,err)); DONE[0]+=1; bar(TOTAL)
            return
        result.update(out)
    with open(dst,'w',encoding='utf-8') as f:
        json.dump(result,f,ensure_ascii=False,indent=2); f.write('\n')
    with LOCK: DONE[0]+=1; bar(TOTAL)

def wire(langs):
    import io
    p=ROOT+'/lib/surface/i18n/og_l_i18n.dart'; s=io.open(p,encoding='utf-8').read()
    # 追加 locales（保持已有 6 项不动）
    add=''.join("    OgLLocale('%s', '%s'),\n"%(code,name) for code,name in langs if code not in EXISTING)
    s=s.replace("    OgLLocale('ru', 'Русский'),\n","    OgLLocale('ru', 'Русский'),\n"+add,1)
    io.open(p,'w',encoding='utf-8').write(s)
    p=ROOT+'/lib/surface/settings.dart'; s=io.open(p,encoding='utf-8').read()
    add=''.join("    '%s',\n"%code for code,name in langs if code not in EXISTING)
    s=s.replace("    'ru',\n","    'ru',\n"+add,1)
    io.open(p,'w',encoding='utf-8').write(s)
    p=ROOT+'/pubspec.yaml'; s=io.open(p,encoding='utf-8').read()
    add=''.join("    - assets/i18n/%s/\n"%code for code,name in langs if code not in EXISTING)
    s=s.replace("    - assets/i18n/ru/\n","    - assets/i18n/ru/\n"+add,1)
    io.open(p,'w',encoding='utf-8').write(s)
TOTAL=0
def run_one(code, name, shards, concurrency=1, interval=None, chunk=None):
    global TOTAL
    if interval is not None: globals()['MIN_INTERVAL']=interval
    if chunk is not None: globals()['CHUNK_CHARS']=chunk
    TOTAL=len(shards)
    print('batch language=%s (%s) shards=%d jobs=%d'%(code,name,len(shards),TOTAL))
    os.makedirs(ROOT+'/assets/i18n/'+code,exist_ok=True)
    START[0]=time.time(); FAIL.clear(); DONE[0]=0; bar(TOTAL)
    with concurrent.futures.ThreadPoolExecutor(max_workers=concurrency) as ex:
        fs=[ex.submit(job,code,name,x) for x in shards]
        for f in concurrent.futures.as_completed(fs):
            try: f.result()
            except Exception as e: FAIL.append('job: %s'%e)
    bar(TOTAL); print()
    if FAIL:
        print('FAILURES %d:'%len(FAIL))
        for x in FAIL[:20]: print(' ',x)
        return 1
    print('OK %s'%code)
    return 0

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--lang',default='',help='single language code; one batch = one language')
    ap.add_argument('--batch',type=int,default=0,help='batch number 1-24 (one language per batch)')
    ap.add_argument('--list',action='store_true')
    ap.add_argument('--dry-run',action='store_true')
    ap.add_argument('--shards',default='')
    ap.add_argument('--wire',action='store_true',help='register all 30 languages in code/pubspec (run once)')
    ap.add_argument('--concurrency',type=int,default=3)
    ap.add_argument('--chunk',type=int,default=0,help='chars per chunk; 0 = one key per chunk (safest)')
    ap.add_argument('--interval',type=float,default=0.0,help='min seconds between requests (default 2.5)')
    a=ap.parse_args()
    if a.list:
        for i,(c,n) in enumerate(LANGS,1): print('%2d %-8s %s%s'%(i,c,n,' (existing)' if c in EXISTING else ''))
        return
    shards=[x for x in SHARDS if not a.shards or x in a.shards.split(',')]
    if a.wire:
        wire(LANGS); print('wired'); return
    if a.lang:
        sel=[x for x in LANGS if x[0]==a.lang]
        if not sel: print('unknown language'); return 2
    elif 1 <= a.batch <= 24:
        sel=[LANGS[a.batch-1]]
    else:
        print('ERROR: use --lang CODE or --batch N (1-24); one invocation handles exactly one language'); return 2
    if a.dry_run:
        print('dry-run: %s / %d shards / concurrency=%d / interval=%.1fs'%(sel[0][0],len(shards),a.concurrency,MIN_INTERVAL)); return 0
    return run_one(sel[0][0],sel[0][1],shards,a.concurrency,a.interval, a.chunk if a.chunk else 0)
if __name__=='__main__':
    sys.exit(main())
