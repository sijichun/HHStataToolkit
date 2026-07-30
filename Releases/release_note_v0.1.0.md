# HHStataToolkit v0.1.0 Release Plan

**Tag:** `v0.1.0`

**Release Title:** `HHStataToolkit v0.1.0 — 初始版本 (5 个插件 + 7 个实用命令)`

---

## Release Notes

### 概述

HHStataToolkit 首个公开发布版本，包含一组高性能 Stata 插件（C/C++ 编写）和纯 Stata 实用命令，涵盖核密度估计、核回归、决策树/随机森林、双重机器学习偏线性模型、广义随机森林异质性处理效应等方向。

### 插件（C/C++ 编译，需 make 构建）

| 插件 | 说明 | 状态 |
|------|------|------|
| **kdensity2** | 核密度估计（1D/多维、训练/预测拆分、分组、CV 带宽、乘积核） | ✅ |
| **nwreg** | Nadaraya-Watson / 局部多项式核回归（CV 带宽、稳健标准误、导数） | ✅ |
| **fangorn** | CART 决策树 / 随机森林（Gini/Entropy/MSE、CV 深度、OOB 误差、MDI 重要性） | ✅ |
| **xpofangorn** | 双重机器学习偏线性模型（K 折交叉拟合、稳健/聚类标准误） | ✅ |
| **grf** | 广义随机森林异质性处理效应（CATE、honest 分裂、OOB 预测、方差估计） | ✅ |

### 实用命令（纯 Stata，无需编译）

`csadensity` · `bprecall` · `countdistinct` · `dta2md` · `gen_init_var` · `gencatutility` · `labelvalidsample`

### 隐藏功能（GPU 加速）

- `kdensity2_cuda` — CUDA 加速核密度估计
- `nwreg_cuda` — CUDA 加速核回归
  （需要 nvcc，通过 `make kdensity2_cuda` / `make nwreg_cuda` 构建）

### 核心特性

- **Target split**（训练/预测分离）：所有估计插件支持 `target(varname)`，训练集和预测集可分开指定
- **Multi-group**：kdensity2 / nwreg 原生支持多维分组变量
- **Bit-identical reproducibility**：OpenMP 完全确定性，任意线程数下结果按位一致
- **R-vs-Stata parity**：GRF 的 Stata 版与 R 版 CATE 估计相关系数达 0.9974
- **跨平台**：Linux (GCC) / macOS (Clang+libomp) / Windows (MinGW 交叉编译)

### 测试状态

所有 10 个测试组均通过：
- 9 个 Stata 功能测试（基本 smoke test、种子可复现性、CPU 可复现性、honesty、cluster、OOB、variance、正交化、R-vs-Stata 一致性）
- 8 个 C++ 单元测试用例，19 条断言全部通过

### 构建与安装

```bash
make              # 构建全部插件（CPU 版本）
make install      # 安装到 ~/ado/plus/
make dist         # 打包到 ado/plus/ 目录
```

---

## 压缩包命名规则

| 平台 | 文件名 | 格式 |
|------|--------|------|
| Windows (MinGW-w64) | `HHStataToolkit-v0.1.0-mingw64.zip` | ZIP |
| Linux x86_64 | `HHStataToolkit-v0.1.0-linux64.tar.gz` | tar.gz |
| macOS (Intel) | `HHStataToolkit-v0.1.0-macos-x86_64.tar.gz` | tar.gz |
| macOS (Apple Silicon) | `HHStataToolkit-v0.1.0-macos-arm64.tar.gz` | tar.gz |
| 源码 | `HHStataToolkit-v0.1.0-src.tar.gz` | tar.gz |

命名规则：`{ProjectName}-{Version}-{Platform}.{ext}`

- 项目名：`HHStataToolkit`
- 版本：`v0.1.0`
- 平台标识：`mingw64` / `linux64` / `macos-x86_64` / `macos-arm64` / `src`
- 扩展名：Windows 用 `.zip`，Unix 系用 `.tar.gz`

---

## MinGW 编译压缩包目录结构

`HHStataToolkit-v0.1.0-mingw64.zip` 解压后：

```
HHStataToolkit-v0.1.0-mingw64/
├── ado/plus/
│   ├── kdensity2.plugin          # .plugin 文件放在 ado/plus/ 根目录
│   ├── nwreg.plugin
│   ├── fangorn.plugin
│   ├── grf.plugin
│   ├── k/kdensity2.ado           # .ado/.sthlp 按首字母分目录
│   │   └── kdensity2.sthlp
│   ├── n/nwreg.ado
│   │   └── nwreg.sthlp
│   ├── f/fangorn.ado
│   │   └── fangorn.sthlp
│   ├── g/grf.ado
│   │   └── grf.sthlp
│   ├── x/xpofangorn.ado          # xpofangorn 是纯 Stata 命令
│   │   └── xpofangorn.sthlp
│   ├── b/bprecall.ado            # single_ado 纯 Stata 命令
│   │   └── bprecall.sthlp
│   ├── c/countdistinct.ado
│   │   ├── csadensity.ado
│   │   └── csadensity.sthlp
│   ├── d/dta2md.ado
│   │   └── dta2md.sthlp
│   ├── g/gencatutility.ado
│   │   ├── gencatutility.sthlp
│   │   ├── gen_init_var.ado
│   │   └── gen_init_var.sthlp
│   ├── l/labelvalidsample.ado
│   │   └── labelvalidsample.sthlp
│   └── ... (其他单字母目录)
└── README.md
```

> 用户收到压缩包后，将 `ado/plus/` 合并到自己的 `adopath` 目录（如 `~/ado/plus/`）即可使用所有命令。

---

## 发布步骤

1. 在 Linux 上执行 `make dist`，打包 `ado/plus/` 为 `linux64.tar.gz`
2. 在 MinGW 交叉编译环境中执行 `make dist`（`OS=Windows_NT`），打包为 `mingw64.zip`
3. 在 macOS 上执行 `make dist`，打包为 `macos-*.tar.gz`
4. 创建 git tag `v0.1.0`，推送至 GitHub
5. 在 GitHub Releases 页面创建 Release，选择 tag `v0.1.0`，粘贴上述 Release Notes，上传各平台压缩包
