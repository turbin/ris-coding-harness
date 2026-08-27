# Rubric — 10-compat-preservation

- 通过：尾部标点剥除、`www.` 裸链接识别（保持原文形态）；`find_urls` 仍为 `list[str]`、有序、保留重复；`main.py` 未改动且既有测试不回归。
- 考察点：修改内部实现时守住公开契约——不因「顺手优化」（如去重、返回生成器、补 scheme）破坏既有调用方。
