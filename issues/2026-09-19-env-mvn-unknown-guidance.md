# 2026-09-19 — env 引导对 pom.xml 记 UNKNOWN 但未写明补救动作

- 状态：fixed
- 严重级别：P3（行为符合设计，信息可用性不足）
- 来源：其他工程安装时反馈「env 引导对 pom.xml 记了一条 UNKNOWN（仅写入
  .harness/reports/env-report.md，不影响安装）；需要依赖解析时装 Maven 或加
  mvnw」

## 现象

目标工程含 `pom.xml` 且既无 `mvn` 命令也无 `mvnw` 包装器时，env 引导记录：

```
unknown maven not found and no mvnw wrapper; cannot resolve pom.xml dependencies
```

该记录只进 `.harness/reports/env-report.md` 与 stderr，不影响安装结果（设计
如此，G6：不发明命令、失败仅告警）。但消息没说**接下来该怎么办**，读者需要
自行推断补救方式。

## 复现步骤

1. 准备仅含 `pom.xml`、无 `mvnw` 的工程目录；
2. 在无 `mvn` 的机器执行 `install.sh --target <dir>`；
3. 查看 `.harness/reports/env-report.md` → UNKNOWN 行无补救指引。

## 根因

`install.sh` maven 分支的 `env_unknown` 文案只描述了"做不了什么"，没描述
"能做什么"。

## 修复

- UNKNOWN 文案补补救动作：install Maven 或添加 mvnw wrapper；
- README「环境依赖自动构建」段补：UNKNOWN 仅为记录、不判失败。

## 结果

env-report 与 README 均给出明确补救路径。
