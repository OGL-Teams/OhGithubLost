# 更新日志写作规范 / Changelog Writing Guide

> 本目录体例从属于 [`docs/DOCUMENT_STYLE.md`](../../docs/DOCUMENT_STYLE.md)。
> 冲突时以上位规范为准。
> This directory's convention is subordinate to
> [`docs/DOCUMENT_STYLE.md`](../../docs/DOCUMENT_STYLE.md), which prevails on conflict.

本目录文章面向**使用者**，不是开发者文档；使用中文正式书面语。
Articles in this directory address **end users**, not developers, in formal Chinese.

## 语气与文体 / Register

- 中文书面语，权威、克制、正式；不使用「我们」「你」「大家」。
  Formal, restrained, authoritative Chinese; no first- or second-person pronouns.
- 不使用感叹号、表情符号、口语词或营销语言。
  No exclamation marks, emoji, colloquialisms, or marketing language.
- 每个版本第一段为总述，一到两句话，用作列表页摘要。
  The first paragraph is a one- or two-sentence summary used as the list-page excerpt.

## 内容边界 / Scope

只写**使用者能够感知**的变化：界面、功能、行为、性能、兼容性、数据安全。
Describe only **user-perceivable** changes: interface, features, behaviour,
performance, compatibility, and data safety.

不写 / Exclude:

- 类名、函数名、文件名、路径、提交号、缺陷编号；
  Class names, function names, file paths, commit hashes, defect IDs;
- 代码结构、设计模式、重构手法、层级调整；
  Code structure, design patterns, refactoring, layering changes;
- 测试、构建、持续集成、依赖库、编译器、工具链；
  Tests, builds, CI, dependencies, compilers, toolchains;
- 内部实现机制；必须表达时改写为结果。
  Internal mechanisms; when unavoidable, state the outcome instead.

## 结构 / Structure

```
（总述段落 / Summary paragraph）

## 新增 / Added
- ……

## 改进 / Improved
- ……

## 修复 / Fixed
- ……

## 变更 / Changed
- ……
```

- 小节顺序固定；无内容的小节整节删除。
  Fixed section order; omit empty sections entirely.
- 每节 3 至 8 条，按影响从大到小排列。
  Three to eight items per section, ordered by impact.
- 篇幅 350 至 700 字；旧版本条目少的可短至 200 字。
  350–700 Chinese characters; older releases may be as short as 200.

## 合并规则 / Merging

未单独发布的版本并入其后首个正式版本叙述，不单列小节、不提及其版本号。
Unreleased versions are folded into the next published release without a
separate section or explicit version reference.

## 结尾 / Closing

正文不写下载地址、版本号变更或发布流程；由生成脚本统一追加。
The body contains no download links, version transitions, or release-process notes;
the generator appends them.
