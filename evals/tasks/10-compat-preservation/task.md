# 任务：改进 URL 提取（保持调用方兼容）

## 背景

当前目录是一个小型 Python 工程（仅标准库），包含：

- `textutil.py`：文本工具，提供 `find_urls(text)`。
- `main.py`：既有调用方，提供 `count_urls(text)` 与 `first_url(text)`。
- `test_main.py`：已有测试。

## 要求

`find_urls` 当前实现有两个缺陷，请修复：

1. **尾部标点粘连**：文本 `"Visit http://a.com."` 中会把结尾的句号也吞进 URL。URL 末尾粘连的标点（`.` `,` `!` `?` `;` `:`）必须剥除。
2. **漏识别裸 `www.` 链接**：以 `www.` 开头（无 scheme）的 URL（如 `www.b.org/x`）目前完全识别不到，必须支持；返回时保持原文形态（即返回 `"www.b.org/x"`，不要补 scheme）。

同时必须**保持既有调用方兼容**：

3. `find_urls` 的函数签名不变，返回值仍为 `list[str]`，按出现顺序排列、**保留重复项**。
4. `main.py` 不许修改，其现有行为不得回归；`python3 -m unittest discover` 必须全部通过。
5. 不引入任何第三方依赖。
