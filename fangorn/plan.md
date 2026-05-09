# fangorn — 决策树与随机森林 Stata 插件设计方案

## 1. 项目目标与范围

### 1.1 目标
构建一个高性能的 Stata C 插件，实现：
- **决策树（Decision Tree）**：支持分类（Classification）和回归（Regression）
- **随机森林（Random Forest）**：基于决策树的 Bagging 集成方法

### 1.2 核心要求
1. **高效性**：C 语言实现 + OpenMP 并行，确保大规模数据下的运算速度
2. **一致性**：遵循 HHStataToolkit 现有架构（kdensity2 / nwreg 模式）
3. **可扩展性**：模块化设计，支持未来添加梯度提升树（GBDT / XGBoost）
4. **兼容性**：支持 target 划分（训练/测试集分离），与现有插件风格统一

### 1.3 非目标（Phase 1 不做）
- 缺失值自动处理（Stata 端通过 `if` 条件或 `complete cases` 预处理）
- 分类变量的原生支持（Stata 端通过 `egen group()` 编码为数值）
- 树的图形化可视化（仅返回结构数据，Stata 端可后处理）
- 超参数网格搜索 / 交叉验证（Stata 端通过循环实现）

---

## 2. 可行性评估与关键设计决策

### 2.1 数据类型：Double 而非 Float

**原设计想法**：统一将数据转为单精度 float。

**评估结论**：**建议保持 double**，理由如下：

| 维度 | Float (32-bit) | Double (64-bit) |
|------|----------------|-----------------|
| Stata 原生类型 | ST_double | ST_double（无 float 接口） |
| 转换开销 | 需显式 cast，增加代码复杂度 | 直接传递，零开销 |
| 精度 | 约 7 位有效数字，阈值比较可能出错 | 约 15 位有效数字，决策树阈值精确 |
| 速度（现代 CPU） | SIMD 带宽高一倍 | 64 位寄存器原生支持，通常无差别 |
| 内存占用 | 减半 | 多一倍，但 Stata 数据集通常 < 1M 行，可接受 |

**决策**：**全程使用 `double`**。用户确认速度差异不大，优先保证精度。若未来真有内存瓶颈，再考虑增加 `float` 编译选项。

### 2.2 节点编码：Heap-style Binary Tree

**原设计想法**：用二进制位运算编码节点路径（根=0，左=0，右=1，左左=00...）。

**问题**：该编码无法唯一标识节点（根=0 与左子=0 冲突），且需要可变长路径存储。

**替代方案**：采用 **堆式二叉树编码（Heap-style）**：
- 根节点 ID = 0
- 左子节点 ID = parent × 2 + 1
- 右子节点 ID = parent × 2 + 2
- 父节点 ID = (child - 1) / 2

**优势**：
- 每个节点有唯一整数 ID，可用作数组索引
- 从根到任意节点的路径可通过位运算快速推导（右移即可得祖先链）
- 与观测归属数组完美配合：`node_id[n_obs]` 直接存储每个观测当前所在的叶子节点 ID

**深度限制**：`int32` 最大支持深度 30（2^30 > 10 亿节点）。用户确认 30 层足够，因此使用 `int` 类型存储 node_id 完全可行。

### 2.3 树生长策略：Best-First vs Recursive

**原设计想法**：Best-first 策略——每轮并行计算所有叶子的最佳 split，只执行下降最大的那个，重复直到停止。

**评估**：

| 策略 | 优点 | 缺点 | 适用场景 |
|------|------|------|----------|
| **Best-first** | 相同叶子数下总 impurity 更低；易控制最大叶子数 | 实现复杂；每轮需全局同步；建树速度慢（100 叶子需 100 轮） | 单棵决策树优化；Boosting 小树 |
| **Recursive (CART)** | 实现简单；建树速度快；与文献一致 | 树的形状固定（深度优先）；不易精确控制叶子数 | 随机森林；通用决策树 |

**决策**：
- **决策树模式**：支持 best-first（用户可选）和 recursive 两种策略
- **随机森林模式**：强制使用 recursive。原因：随机森林通常每棵树有数百至数千叶子，best-first 的轮次开销过大；且随机森林不需要每棵树都是"最优"的，个体树的过拟合反而增加 ensemble 多样性。

### 2.4 分位数 vs 排序唯值（Split 阈值选择）

**原设计想法**：使用十分位数作为候选 split 阈值。

**核心问题**：每次分裂后在新节点上重新计算分位数，若每次都排序，复杂度为 O(m log m)（m 为当前节点样本数），当树较深时累计开销大。

**评估**：
- **分位数策略**：固定 N-1 个阈值，候选点少、计算快，但可能错过相邻唯值之间的最佳分割点
- **排序唯值策略**：对所有唯值中点进行评估，理论最优，但候选点多、计算量大
- **预排序优化（scikit-learn 核心策略）**：在树构建前，对每个特征全局排序一次并保存排序索引。节点分裂时，利用父节点的排序索引，通过线性扫描将索引分成左右两个已排序子数组。这样每个节点的 split 评估可在线性时间内完成，无需重新排序。

**快速分位数算法**：
当使用分位数策略时，有以下加速方法：

| 方法 | 复杂度 | 适用场景 |
|------|--------|----------|
| **全局预排序 + 直接取位置** | O(n log n) 预处理，O(1) 每次查询 | 最优，内存换时间 |
| **Quickselect (Hoare)** | 平均 O(n)，最坏 O(n²) | 单次查询，实现简单 |
| **Introselect (Medians-of-medians)** | 严格 O(n) | 需要最坏情况保证 |
| **部分排序 (nth_element)** | 平均 O(n) | C++ 标准库，C 需自行实现 |

**决策**：
- **默认策略**：排序唯值 + 预排序索引继承（精确，与 scikit-learn 一致）
- **可选策略**：分位数（通过 `ntiles(N)` 参数指定），配合预排序数组直接取位置
- **实现优先级**：
  1. **Phase 1**：预排序 + 索引继承（最高效，实现复杂度适中）
  2. **Phase 3**：增加分位数选项（对超大 n 的近似加速）

### 2.5 预排序策略的考量：scikit-learn 的演进

**重要背景**：本方案推荐的预排序+索引继承策略源自 scikit-learn 0.24 之前的 `presort` 模式。在 scikit-learn 0.24+ 中，该策略已被移除，转而使用直方图分桶（基于 LightGBM 的 `HistGradientBoosting`）和分区排序（`Partitioner` 类）替代。

**为什么本方案仍采用预排序**：

| 维度 | scikit-learn 的考量 | Stata 插件的考量 |
|------|---------------------|-----------------|
| 数据规模 | sklearn 需处理 10M+ 样本，预排序内存不可接受 | Stata 数据集通常 < 1M 行，40MB 预排序开销可接受 |
| 灵活性 | 需同时支持稀疏矩阵，预排序不适用 | Stata 数据始终为稠密矩阵，无此限制 |
| 精度 | 直方图分桶损失精度换取速度 | 学术研究需要精确结果，预排序保留全精度 |
| 实现复杂度 | 预排序代码维护成本高 | 一次性实现，C 代码无向后兼容负担 |
| 确定性 | 直方图分桶引入随机性 | 预排序给出确定性的 split 结果 |

**结论**：scikit-learn 移除 presort 是因其服务场景与我们的 Stata 插件不同。对于 Stata 用户场景（< 1M 观测，稠密矩阵，需要精确结果），预排序+索引继承仍然是最优选择。此设计决策已在 Section 2.4 中确认。

### 2.6 分类变量处理

**用户要求**：分类变量不需要在 C 代码中考虑，Stata 端会预处理为 one-hot encoding 输入。

**设计影响**：
- C 插件接收的全部是数值型特征（double），无需处理分类变量逻辑
- 分类变量的 one-hot 转换由用户在 Stata 端通过 `tabulate var, gen(dum_)` 或 `xi:` 等命令完成
- 特征重要性会分别显示每个 dummy 变量的重要性，用户可以自行聚类

---

### 2.7 并行策略层级与线程安全

**原设计想法**：每轮并行计算各个节点的最佳 split。

**问题**：如果同时存在"树级别并行"和"节点级别并行"，线程资源会竞争。另外，用户关心"只对原始数据进行读取"是否有线程安全问题。

**OpenMP 只读数据线程安全分析**：

| 问题 | 结论 |
|------|------|
| 多线程只读同一数组是否需要锁？ | **完全不需要**。C/C++ 标准和 OpenMP 规范明确：同时只读访问同一内存无 data race |
| CPU cache coherence 开销？ | **几乎为零**。MESI 协议下，只读数据在所有核心缓存为 Shared 状态，无 invalidation 流量 |
| False sharing 风险？ | **低**。False sharing 发生于多线程写入同一 cache line 的不同变量。只读场景下不存在此问题 |
| 最佳内存布局？ | **列优先（SoA）**：`X[feature][obs]` 比 `X[obs][feature]` 更适合决策树。每个特征列是连续内存，排序和扫描时 cache 友好 |

**决策**：采用**分层并行**，避免资源冲突：

```
随机森林（外层）：
  └── #pragma omp parallel for（树级别并行）
        └── 每棵树内部串行构建（单线程 recursive）
        └── 所有树共享只读特征矩阵 X（const，无锁）

单棵决策树（若 ntree=1）：
  └── #pragma omp parallel for（特征级别并行）
        └── 计算最佳 split
        └── 每个线程有独立的 local_best 和临时缓冲区
```

**理由**：
- 随机森林的核心并行度在"树之间"，100 棵树可完美并行
- 特征矩阵 X 声明为 `const`，所有线程同时只读，无需任何同步（参考 scikit-learn `_tree.pyx` 的 `const DOUBLE_t[:, ::1] X` 设计）
- 单棵树内部的并行收益有限（数据访问局部性差，cache 不友好）
- 避免 OpenMP nested parallelism 的复杂性和性能陷阱

---

## 3. 系统架构

### 3.1 模块划分

```
fangorn/
├── fangorn.c          # C 插件主逻辑
├── fangorn.ado        # Stata 命令包装器
├── fangorn.sthlp      # Stata 帮助文件
├── tree.c             # 决策树核心（可独立编译）
├── tree.h             # 决策树头文件
├── forest.c           # 随机森林核心
├── forest.h           # 随机森林头文件
├── split.c            # Split 查找与 impurity 计算
├── split.h            # Split 头文件
├── utils_rf.c         # fangorn 专用工具（随机数、采样、分位数）
├── utils_rf.h         # 工具头文件
└── plan.md            # 本文档
```

**与现有代码库的关系**：
- 复用 `src/stplugin.h/c` 和 `src/utils.h/c`（数据 I/O、内存分配）
- `fangorn.c` 作为入口，遵循 `stata_call()` 接口约定，include：
  ```c
  #include "stplugin.h"
  #include "utils.h"
  #include "tree.h"
  #include "split.h"
  #include "forest.h"
  #include "utils_rf.h"
  ```
- `fangorn.ado` 遵循现有 ado 包装器的参数解析和变量布局模式

### 3.2 数据流

```
┌─────────────────────────────────────────────────────────────────┐
│ Stata 用户输入                                                   │
│   fangorn y x1 x2 x3, type(classify) ntree(100) generate(pred)   │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ fangorn.ado                                                      │
│   - 解析语法、验证参数                                            │
│   - 创建 touse 标记变量                                           │
│   - 处理 string group vars → numeric（如有）                     │
│   - 生成输出变量（pred, leaf_id, importance）                     │
│   - 构建 plugin_vars 列表                                         │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ C Plugin (fangorn.c)                                             │
│   stata_call(argc, argv)                                         │
│   ├── 解析 argv（选项字符串）                                      │
│   ├── 读取 Stata 数据到 C 数组（X, y, target, touse）             │
│   ├── 提取训练集（target=0 或全部）                               │
│   ├── 构建随机森林 / 决策树                                       │
│   │     ├── Bootstrap 采样（仅 RF）                               │
│   │     ├── 逐棵树构建（OpenMP 并行）                             │
│   │     │     └── 递归构建决策树                                  │
│   │     │           ├── 对每个节点，找最佳 split                   │
│   │     │           │     ├── 对每特征，计算候选阈值               │
│   │     │           │     │     ├── 分位数 或 排序唯值             │
│   │     │           │     │     └── 评估每个阈值的 impurity 下降   │
│   │     │           │     └── 选择最佳（特征, 阈值）               │
│   │     │           ├── 若满足停止条件 → 标记为叶子                │
│   │     │           └── 否则 → 分裂，递归处理子节点                │
│   │     └── 聚合多棵树预测                                        │
│   ├── 对全部观测（含 target=1）做预测                              │
│   ├── 计算特征重要性（MDI）                                        │
│   └── 写回 Stata（聚合预测值 + 每棵树一列节点 ID）                 │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ Stata 后处理（用户可选）                                          │
│   - 按叶子 ID 分组分析                                            │
│   - 查看特征重要性排序                                            │
│   - 计算准确率 / MSE                                              │
└─────────────────────────────────────────────────────────────────┘
```

---

## 4. 数据结构详细设计

### 4.1 节点与树

```c
/* 树节点 */
typedef struct {
    int node_id;              /* 堆式编码唯一 ID */
    int parent_id;            /* 父节点 ID，根为 -1 */
    int depth;                /* 节点深度，根为 0 */
    
    /* Split 信息（仅非叶子节点有效） */
    int split_feature;        /* 划分特征索引（0-based） */
    double split_threshold;   /* 划分阈值 */
    double impurity_decrease; /* 该 split 带来的 impurity 下降 */
    
    /* 叶子信息（仅叶子节点有效） */
    int is_leaf;              /* 1 = 叶子，0 = 内部节点 */
    double leaf_value;        /* 预测值：回归=均值，分类=众数类别 */
    double leaf_impurity;     /* 叶子 impurity（Gini/Entropy/MSE） */
    int n_samples;            /* 到达该叶子的训练样本数 */
    
    /* 子节点索引（在 tree->nodes 数组中的下标，-1 表示无） */
    int left_child;           
    int right_child;          
} TreeNode;

/* 决策树 */
typedef struct {
    TreeNode *nodes;          /* 节点数组，动态扩展 */
    int n_nodes;              /* 当前节点数 */
    int capacity;             /* 数组容量 */
    int max_depth;            /* 最大深度限制（0=无限制） */
    int min_samples_split;    /* 最小分裂样本数 */
    int min_samples_leaf;     /* 最小叶子样本数 */
    double min_impurity_decrease; /* 最小 impurity 下降 */
    int n_classes;            /* 类别数（分类树），回归=0 */
} DecisionTree;

/* 随机森林 */
typedef struct {
    DecisionTree **trees;     /* 树指针数组 */
    int n_trees;              /* 树的数量 */
    int n_features;           /* 总特征数 */
    int mtry;                 /* 每棵树随机选择的特征数 */
    int is_classifier;        /* 1 = 分类，0 = 回归 */
    int n_classes;            /* 类别数（分类） */
    double *feature_importances; /* 特征重要性（MDI），长度 = n_features */
} RandomForest;
```

### 4.2 训练数据与采样

```c
/* 数据集（训练集视角） */
typedef struct {
    double **X;               /* 特征矩阵 [n_features][n_obs] — 列优先 */
    double *y;                /* 目标变量 [n_obs] */
    int n_obs;                /* 观测数 */
    int n_features;           /* 特征数 */
    int n_classes;            /* 类别数（分类） */
    
    /* 预排序索引：sorted_indices[f][i] = 特征 f 排序后第 i 个位置的原始观测索引 */
    int **sorted_indices;     /* [n_features][n_obs] — 可选，用于加速 split 查找 */
    int has_sorted_indices;   /* 1 = 已预排序，0 = 未预排序 */
    
    int *sample_indices;      /* 当前节点包含的样本索引（可选，避免复制） */
    int n_samples;            /* 当前节点样本数 */
} Dataset;

/* Bootstrap 采样结果 */
typedef struct {
    int *indices;             /* 采样索引数组 [n_samples]，有放回 */
    int *oob_mask;            /* OOB 标记 [n_obs]，1=未选中（out-of-bag） */
    int n_samples;            /* 样本数（等于原始训练集大小） */
} BootstrapSample;
```

### 4.3 Split 评估结果

```c
/* 单个候选 split 的评估结果 */
typedef struct {
    int feature;              /* 特征索引 */
    double threshold;         /* 阈值 */
    double impurity_decrease; /* impurity 下降量 */
    int n_left;               /* 左子节点样本数 */
    int n_right;              /* 右子节点样本数 */
    int node_idx;             /* 归属节点索引（仅 best-first 模式使用） */
} SplitResult;

/* 最佳 split 查找上下文（线程私有） */
typedef struct {
    SplitResult best;         /* 当前最佳 split */
    double *feature_values;   /* 临时特征值数组（用于排序/分位数） */
    int *sorted_indices;      /* 排序后的索引 */
} SplitContext;
```

### 4.4 预测结果与节点归属（与 Stata 交互）

**用户要求**：每棵树在 Stata 中保存一列变量，存储每个观测的节点代码。

```c
/* 预测结果 */
typedef struct {
    double *predictions;      /* 聚合预测值 [n_obs] */
    int **tree_leaf_ids;      /* 每棵树的叶子节点 ID [n_trees][n_obs] */
    double **tree_predictions; /* 每棵树的预测 [n_trees][n_obs]（OOB/特征重要性计算用） */
    int n_trees;              /* 树的数量 */
    int n_obs;                /* 观测数 */
} PredictionResult;
```

**Stata 变量生成策略**：
- `ntree=1`（决策树模式）：生成 1 列，列名 = `generate()` 指定的名称
- `ntree>1`（随机森林模式）：生成 `ntree` 列，列名前缀 = `generate()` 指定前缀 + "_t" + 树编号
  - 例如：`generate(tree_node)` + `ntree(100)` → 生成 `tree_node_t1`, `tree_node_t2`, ..., `tree_node_t100`
- 同时生成 1 列聚合预测值（分类=类别，回归=均值）

**注意**：Stata 变量名最长 32 字符，因此前缀不宜过长。ado 层需验证生成后的列名不超限。

---

## 5. 算法详细设计

### 5.1 决策树构建（Recursive CART）

```c
DecisionTree* build_tree(Dataset *data, int *sample_idx, int n_samples,
                         TreeParams *params, int is_classifier)
{
    /* 1. 创建根节点 */
    TreeNode *root = create_node(parent=-1, depth=0);
    
    /* 2. 递归构建 */
    build_node_recursive(tree, root, data, sample_idx, n_samples, params);
    
    return tree;
}

void build_node_recursive(DecisionTree *tree, TreeNode *node,
                          Dataset *data, int *sample_idx, int n_samples,
                          TreeParams *params)
{
    /* 停止条件检查 */
    if (should_stop(node, n_samples, params)) {
        make_leaf(node, data, sample_idx, n_samples);
        return;
    }
    
    /* 找最佳 split */
    SplitResult best = find_best_split(data, sample_idx, n_samples, 
                                        params, tree->n_classes);
    
    if (best.impurity_decrease <= params->min_impurity_decrease) {
        make_leaf(node, data, sample_idx, n_samples);
        return;
    }
    
    /* 执行 split */
    node->split_feature = best.feature;
    node->split_threshold = best.threshold;
    node->impurity_decrease = best.impurity_decrease;
    node->is_leaf = 0;
    
    /* 划分样本到左右子集 */
    int *left_idx = malloc(best.n_left * sizeof(int));
    int *right_idx = malloc(best.n_right * sizeof(int));
    partition_samples(data, sample_idx, n_samples, best, left_idx, right_idx);
    
    /* 创建子节点 */
    node->left_child = add_child_node(tree, node, is_left=1);
    node->right_child = add_child_node(tree, node, is_left=0);
    
    /* 递归构建子树 */
    build_node_recursive(tree, &tree->nodes[node->left_child],
                         data, left_idx, best.n_left, params);
    build_node_recursive(tree, &tree->nodes[node->right_child],
                         data, right_idx, best.n_right, params);
    
    free(left_idx);
    free(right_idx);
}
```

### 5.2 Best-First 决策树（可选模式）

```c
DecisionTree* build_tree_bestfirst(Dataset *data, TreeParams *params)
{
    /* 初始化 */
    DecisionTree *tree = create_tree(params);
    int *all_samples = range(0, data->n_obs);
    
    /* 创建根节点 */
    int root_idx = add_node(tree);
    tree->nodes[root_idx].is_leaf = 1;
    tree->nodes[root_idx].n_samples = data->n_obs;
    
    /* Leaf 队列：存储可分裂的叶子节点 */
    int *leaf_queue = malloc(params->max_leaf_nodes * sizeof(int));
    int n_leaves = 1;
    leaf_queue[0] = root_idx;
    
    /* 主循环 */
    while (n_leaves < params->max_leaf_nodes && n_leaves > 0) {
        /* 并行计算每个叶子的最佳 split */
        SplitResult *splits = malloc(n_leaves * sizeof(SplitResult));
        
        #pragma omp parallel for
        for (int i = 0; i < n_leaves; i++) {
            int node_idx = leaf_queue[i];
            TreeNode *node = &tree->nodes[node_idx];
            int *node_samples = get_node_samples(tree, node_idx); /* 动态提取 */
            
            splits[i] = find_best_split(data, node_samples, node->n_samples,
                                         params, tree->n_classes);
            splits[i].node_idx = node_idx; /* 记录归属 */
        }
        
        /* 找全局最佳 split */
        int best_idx = 0;
        for (int i = 1; i < n_leaves; i++) {
            if (splits[i].impurity_decrease > splits[best_idx].impurity_decrease)
                best_idx = i;
        }
        
        if (splits[best_idx].impurity_decrease <= params->min_impurity_decrease) {
            free(splits);
            break; /* 无有效 split */
        }
        
        /* 执行最佳 split */
        int split_node_idx = leaf_queue[best_idx];
        execute_split(tree, split_node_idx, splits[best_idx]);
        
        /* 更新 leaf 队列：移除被 split 的节点，添加两个新叶子 */
        leaf_queue[best_idx] = tree->nodes[split_node_idx].left_child;
        leaf_queue[n_leaves] = tree->nodes[split_node_idx].right_child;
        n_leaves++;
        
        free(splits);
    }
    
    free(leaf_queue);
    return tree;
}
```

**注意**：best-first 模式下，需要为每个叶子动态提取样本（通过遍历全量数据，检查 node_id 归属）。这在每轮迭代中有 O(n) 开销，当叶子数增多时成本上升。

### 5.3 最佳 Split 查找（核心计算）

**核心优化：预排序索引继承（scikit-learn 策略）**

在树构建前，对每个特征 f 全局预排序，保存 `sorted_indices[f][i]` = 特征 f 排序后第 i 位的原始观测索引。

节点分裂时，父节点的样本索引数组 `sample_idx`（已按某特征排序）可以通过线性扫描，分成左右两个子数组。这两个子数组在对应特征上仍然是排序的。

**算法（基于预排序索引）**：

```c
SplitResult find_best_split(Dataset *data, int *sample_idx, int n_samples,
                             TreeParams *params, int n_classes)
{
    SplitResult best = {.impurity_decrease = -1.0};
    
    #pragma omp parallel
    {
        SplitResult local_best = {.impurity_decrease = -1.0};
        
        /* 线程私有：当前节点样本在全局排序中的位置标记 */
        int *in_node = calloc(data->n_obs, sizeof(int));
        for (int i = 0; i < n_samples; i++) in_node[sample_idx[i]] = 1;
        
        /* 对每个特征（OpenMP 并行） */
        #pragma omp for nowait
        for (int feat = 0; feat < data->n_features; feat++) {
            /* 
             * 利用全局预排序索引，线性扫描提取当前节点的排序子序列
             * sorted_indices[feat] 是特征 feat 的全局排序索引
             * 我们只需要保留其中属于当前节点的部分
             */
            int *node_sorted = malloc(n_samples * sizeof(int));
            int n_sorted = 0;
            
            for (int i = 0; i < data->n_obs; i++) {
                int orig_idx = data->sorted_indices[feat][i];
                if (in_node[orig_idx]) {
                    node_sorted[n_sorted++] = orig_idx;
                }
            }
            
            /* 
             * 现在 node_sorted 是特征 feat 在当前节点上的排序样本索引
             * 评估所有相邻唯值之间的 split 点（线性扫描）
             * 这是 O(n_samples) 的，无需重新排序！
             */
            int n_thresholds = 0;
            for (int i = 0; i < n_sorted - 1; i++) {
                double val_i = data->X[feat][node_sorted[i]];
                double val_next = data->X[feat][node_sorted[i + 1]];
                
                if (val_i == val_next) continue; /* 跳过重复值 */
                
                double threshold = (val_i + val_next) / 2.0;
                n_thresholds++;
                
                double impurity_decrease = evaluate_split_sorted(
                    data, node_sorted, n_sorted, i + 1, /* 左子树大小 = i+1 */
                    feat, threshold, n_classes, params->criterion
                );
                
                if (impurity_decrease > local_best.impurity_decrease) {
                    local_best.feature = feat;
                    local_best.threshold = threshold;
                    local_best.impurity_decrease = impurity_decrease;
                    local_best.n_left = i + 1;
                    local_best.n_right = n_sorted - i - 1;
                }
            }
            
            free(node_sorted);
        }
        
        /* 全局归约：找所有线程中的最佳 split */
        #pragma omp critical
        {
            if (local_best.impurity_decrease > best.impurity_decrease) {
                best = local_best;
            }
        }
        
        free(in_node);
    }
    
    return best;
}
```

**复杂度对比**：

| 策略 | 每节点每特征复杂度 | 是否需要重新排序 |
|------|-------------------|-----------------|
| 朴素排序 | O(m log m) | 是 |
| Quickselect 分位数 | O(m) | 否（但只取分位点） |
| **预排序索引继承（推荐）** | **O(m)** | **否** |

其中 m = 当前节点样本数。预排序策略将每节点的 split 查找从 O(m log m) 降到 O(m)，是 scikit-learn 的核心优化。

### 5.4 Impurity 计算（函数指针）

```c
/* Impurity 函数类型 */
typedef double (*ImpurityFunc)(double *y, int *sample_idx, int n_samples, int n_classes);
typedef double (*ImpurityDecreaseFunc)(double *y, int *sample_idx, int n_samples,
                                        int split_pos, int n_classes);

/* 分类：Gini 指数 */
double gini_impurity(double *y, int *sample_idx, int n_samples, int n_classes) {
    int *class_counts = calloc(n_classes, sizeof(int));
    for (int i = 0; i < n_samples; i++) {
        int cls = (int)y[sample_idx[i]];
        class_counts[cls]++;
    }
    double gini = 1.0;
    for (int c = 0; c < n_classes; c++) {
        double p = (double)class_counts[c] / n_samples;
        gini -= p * p;
    }
    free(class_counts);
    return gini;
}

/* 分类：Entropy */
double entropy_impurity(double *y, int *sample_idx, int n_samples, int n_classes) {
    int *class_counts = calloc(n_classes, sizeof(int));
    for (int i = 0; i < n_samples; i++) {
        int cls = (int)y[sample_idx[i]];
        class_counts[cls]++;
    }
    double ent = 0.0;
    for (int c = 0; c < n_classes; c++) {
        if (class_counts[c] > 0) {
            double p = (double)class_counts[c] / n_samples;
            ent -= p * log(p);
        }
    }
    free(class_counts);
    return ent;
}

/* 回归：MSE（方差） */
double mse_impurity(double *y, int *sample_idx, int n_samples, int n_classes) {
    double mean = 0.0;
    for (int i = 0; i < n_samples; i++) mean += y[sample_idx[i]];
    mean /= n_samples;
    double mse = 0.0;
    for (int i = 0; i < n_samples; i++) {
        double diff = y[sample_idx[i]] - mean;
        mse += diff * diff;
    }
    return mse / n_samples;
}

/* Impurity 下降计算 */
double compute_impurity_decrease(double parent_impurity,
                                  double left_impurity, int n_left,
                                  double right_impurity, int n_right) {
    int n_total = n_left + n_right;
    return parent_impurity - (n_left * left_impurity + n_right * right_impurity) / n_total;
}
```

### 5.5 分位数计算与去重

**当使用分位数策略（非默认）时**，需要快速计算分位数。由于每次分裂后在新节点上重新计算，效率至关重要。

**推荐方案：基于预排序数组的直接提取**

如果全局预排序已完成，分位数可以直接从排序数组中取位置，O(1)：

```c
/* 从预排序数组中提取分位数 — O(n_tiles) */
int compute_quantiles_from_sorted(int *sorted_idx, int n, int n_tiles,
                                   double *X_feat, double **out_quantiles) {
    int n_quantiles = n_tiles - 1;
    double *quantiles = malloc(n_quantiles * sizeof(double));
    int n_unique = 0;
    
    for (int i = 1; i < n_tiles; i++) {
        int pos = (int)((double)i / n_tiles * (n - 1));
        double q = X_feat[sorted_idx[pos]];
        
        /* 去重：与上一个分位数比较 */
        if (n_unique == 0 || fabs(q - quantiles[n_unique - 1]) > 1e-12) {
            quantiles[n_unique++] = q;
        }
    }
    
    *out_quantiles = realloc(quantiles, n_unique * sizeof(double));
    return n_unique;
}
```

**备选方案：Quickselect / Introselect（无预排序时）**

```c
/* Quickselect — 平均 O(n)，最坏 O(n²) */
double quickselect(double *data, int n, int k) {
    /* Hoare's quickselect 实现 */
    int left = 0, right = n - 1;
    
    while (left < right) {
        double pivot = data[(left + right) / 2];
        int i = left, j = right;
        
        while (i <= j) {
            while (data[i] < pivot) i++;
            while (data[j] > pivot) j--;
            if (i <= j) {
                double tmp = data[i]; data[i] = data[j]; data[j] = tmp;
                i++; j--;
            }
        }
        
        if (k <= j) right = j;
        else if (k >= i) left = i;
        else break;
    }
    
    return data[k];
}

/* Introselect — 严格 O(n)，最坏情况保证 */
double introselect(double *data, int n, int k) {
    /* 结合 quickselect 和 median-of-medians */
    /* 当递归深度超过限制时，切换到 median-of-medians */
    /* 实现较复杂，但提供严格 O(n) 保证 */
    /* 注：对分位数计算，通常 quickselect 已足够 */
    return quickselect(data, n, k);
}
```

**性能对比**：

| 场景 | 方法 | 复杂度 | 实际速度 |
|------|------|--------|----------|
| 已预排序 | 直接取位置 | O(n_tiles) | 最快 |
| 未排序，单次查询 | Quickselect | 平均 O(n) | 快 |
| 未排序，多次查询 | 先排序再取 | O(n log n) | 中等 |
| 未排序，严格保证 | Introselect | O(n) | 较慢（常数大） |

### 5.6 随机森林构建

```c
/* OOB 预测聚合结构 */
typedef struct {
    double *oob_sum;          /* OOB 预测值累计 [n_obs]（回归） */
    int    *oob_count;        /* OOB 预测次数 [n_obs] */
    int    **oob_votes;       /* OOB 投票累计 [n_obs][n_classes]（分类） */
    double *oob_predictions;  /* OOB 聚合预测 [n_obs] */
    double oob_error;         /* OOB 误差（分类=1-准确率，回归=MSE） */
} OOBState;

/* 初始化 OOB 状态 */
static OOBState* init_oob_state(int n_obs, int is_classifier, int n_classes) {
    OOBState *oob = malloc(sizeof(OOBState));
    oob->oob_sum = is_classifier ? NULL : alloc_double_array(n_obs);
    oob->oob_count = calloc(n_obs, sizeof(int));
    oob->oob_votes = is_classifier ? malloc(n_obs * sizeof(int*)) : NULL;
    if (is_classifier) {
        for (int i = 0; i < n_obs; i++)
            oob->oob_votes[i] = calloc(n_classes, sizeof(int));
    }
    oob->oob_predictions = alloc_double_array(n_obs);
    oob->oob_error = 0.0;
    return oob;
}

RandomForest* build_random_forest(Dataset *data, ForestParams *params)
{
    RandomForest *rf = create_forest(params);
    
    /* 初始化 OOB 状态 */
    OOBState *oob = init_oob_state(data->n_obs, rf->is_classifier, rf->n_classes);
    
    /* 树级别并行 */
    #pragma omp parallel for schedule(static)
    for (int t = 0; t < params->n_trees; t++) {
        /* Bootstrap 采样 */
        BootstrapSample bs = bootstrap_sample(data->n_obs, params->seed + t);
        
        /* 构建单棵树（递归，串行） */
        DecisionTree *tree = build_tree(data, bs.indices, bs.n_samples,
                                         &params->tree_params, rf->is_classifier);
        
        rf->trees[t] = tree;
        
        /* OOB 预测：对该树的 OOB 样本做预测并累计 */
        #pragma omp critical(oob_accum)
        {
            for (int i = 0; i < data->n_obs; i++) {
                if (bs.oob_mask[i]) {
                    double pred = predict_single_tree(tree, data->X[i]);
                    if (rf->is_classifier) {
                        int cls = (int)pred;
                        oob->oob_votes[i][cls]++;
                    } else {
                        oob->oob_sum[i] += pred;
                    }
                    oob->oob_count[i]++;
                }
            }
        }
        
        /* 累计特征重要性（MDI） */
        accumulate_importance(rf, tree);
        
        free_bootstrap(&bs);
    }
    
    /* 计算 OOB 聚合预测和误差 */
    int n_oob_valid = 0;
    for (int i = 0; i < data->n_obs; i++) {
        if (oob->oob_count[i] > 0) {
            if (rf->is_classifier) {
                int best_class = 0;
                for (int c = 1; c < rf->n_classes; c++) {
                    if (oob->oob_votes[i][c] > oob->oob_votes[i][best_class])
                        best_class = c;
                }
                oob->oob_predictions[i] = (double)best_class;
                if ((int)data->y[i] != best_class) oob->oob_error += 1.0;
            } else {
                oob->oob_predictions[i] = oob->oob_sum[i] / oob->oob_count[i];
                double diff = data->y[i] - oob->oob_predictions[i];
                oob->oob_error += diff * diff;
            }
            n_oob_valid++;
        }
    }
    if (n_oob_valid > 0) {
        if (rf->is_classifier)
            oob->oob_error /= n_oob_valid;  /* 1 - accuracy */
        else
            oob->oob_error /= n_oob_valid;  /* MSE */
    }
    
    /* 归一化特征重要性 */
    normalize_importance(rf);
    
    /* 释放 OOB 状态（oob_predictions 保留供输出） */
    free(oob->oob_sum);
    free(oob->oob_count);
    if (oob->oob_votes) {
        for (int i = 0; i < data->n_obs; i++) free(oob->oob_votes[i]);
        free(oob->oob_votes);
    }
    free(oob);
    
    return rf;
}
```

### 5.7 预测

```c
/* 单棵树预测一个观测 */
double predict_single_tree(DecisionTree *tree, double *x)
{
    int node_idx = 0; /* 从根开始 */
    TreeNode *node = &tree->nodes[node_idx];
    
    while (!node->is_leaf) {
        if (x[node->split_feature] <= node->split_threshold) {
            node_idx = node->left_child;
        } else {
            node_idx = node->right_child;
        }
        node = &tree->nodes[node_idx];
    }
    
    return node->leaf_value;
}

/* 随机森林预测 */
void predict_forest(RandomForest *rf, double **X, int n_obs,
                    double *out_pred, int *out_leaf_ids)
{
    #pragma omp parallel for
    for (int i = 0; i < n_obs; i++) {
        if (rf->is_classifier) {
            /* 分类：多数投票 */
            double *class_votes = calloc(rf->n_classes, sizeof(double));
            for (int t = 0; t < rf->n_trees; t++) {
                int pred_class = (int)predict_single_tree(rf->trees[t], X[i]);
                class_votes[pred_class]++;
            }
            /* 找最大投票 */
            int best_class = 0;
            for (int c = 1; c < rf->n_classes; c++) {
                if (class_votes[c] > class_votes[best_class]) best_class = c;
            }
            out_pred[i] = (double)best_class;
            free(class_votes);
        } else {
            /* 回归：平均 */
            double sum = 0.0;
            for (int t = 0; t < rf->n_trees; t++) {
                sum += predict_single_tree(rf->trees[t], X[i]);
            }
            out_pred[i] = sum / rf->n_trees;
        }
    }
}
```

### 5.8 特征重要性（MDI: Mean Decrease Impurity）

```c
void accumulate_importance(RandomForest *rf, DecisionTree *tree) {
    for (int n = 0; n < tree->n_nodes; n++) {
        TreeNode *node = &tree->nodes[n];
        if (!node->is_leaf) {
            /* 该 split 带来的 impurity 下降，按样本数加权 */
            double importance = node->impurity_decrease * node->n_samples;
            #pragma omp atomic
            rf->feature_importances[node->split_feature] += importance;
        }
    }
}

void normalize_importance(RandomForest *rf) {
    double total = 0.0;
    for (int f = 0; f < rf->n_features; f++) total += rf->feature_importances[f];
    if (total > 0) {
        for (int f = 0; f < rf->n_features; f++) {
            rf->feature_importances[f] /= total;
        }
    }
}
```

---

## 6. 内存管理策略

### 6.1 分配原则

| 数据结构 | 生命周期 | 分配方式 | 释放责任 |
|----------|----------|----------|----------|
| 特征矩阵 X | 插件调用期间 | `alloc_double_matrix()` | `stata_call()` 末尾统一 free |
| 目标变量 y | 插件调用期间 | `alloc_double_array()` | `stata_call()` 末尾统一 free |
| 树节点数组 | 树构建期间 | `realloc()` 动态扩展 | `free_tree()` |
| 样本索引数组 | 递归函数局部 | `malloc()` | 递归函数内 free |
| Split 上下文 | 线程局部（OpenMP） | `malloc()` | 线程结束前 free |
| Bootstrap 索引 | 树构建期间 | `malloc()` | `free_bootstrap()` |
| OOB 状态 | `build_random_forest()` 期间 | `init_oob_state()` | `build_random_forest()` 末尾 |

### 6.2 关键内存安全点

1. **树节点动态扩展**：初始容量设为 64，每次满时翻倍（`capacity *= 2`），`realloc()` 处理
2. **递归深度限制**：`max_depth` 默认设为 20，避免栈溢出
3. **样本索引传递**：通过 `int *sample_idx` + `n_samples` 传递，避免复制特征数据
4. **OpenMP 线程私有存储**：每个线程独立的 `feat_vals` 和 `sorted_idx`，避免竞争
5. **特征矩阵内存布局**：使用列优先 `double** X [n_features][n_obs]`（SoA），排序和扫描时 cache 友好。预测时的访问模式 `X[split_feature][obs]` 也匹配此布局。如果未来需要行优先访问（如逐行预测优化），可考虑 `alloc_double_contiguous()` 辅助函数统一分配一块连续内存 + 指针数组

---

## 7. 并行策略详解

### 7.1 随机森林：树级别并行（主要）

```c
#pragma omp parallel for schedule(static)
for (int t = 0; t < n_trees; t++) {
    /* 每棵树独立构建，无共享写操作 */
    trees[t] = build_single_tree(...);
}
```

**线程安全详细说明**：
- **读共享**：全局特征矩阵 `X`（`const double **`）。多个线程同时只读同一内存完全符合 C/OpenMP 规范，无需锁、原子操作或任何同步
- **写私有**：每棵树的 `DecisionTree` 节点数组、`BootstrapSample` 索引、`SplitContext` 临时缓冲区均为线程私有（每个线程通过 `malloc` 独立分配）
- **共享写（需同步）**：特征重要性数组 `feature_importances` 需要 `#pragma omp atomic` 保护（见 5.8 节）
- **同步点**：循环结束后单线程归一化重要性

**False Sharing 避免**：
- 每棵树的 `TreeState` 结构体独立 `malloc`，天然 64B+ 对齐，不同树的数据不会落在同一 cache line
- 特征重要性数组若被多线程写入，需确保每个元素是独立 8B（double），相邻元素可能落在同一 cache line。建议重要性累计使用 `atomic`，或在每棵树内维护局部重要性副本，循环结束后串行合并

### 7.2 单棵决策树：特征级别并行（次要）

仅在 `ntree=1` 时启用：

```c
#pragma omp parallel
{
    SplitResult local_best = ...;
    double *local_buffer = malloc(...);
    
    #pragma omp for nowait
    for (int feat = 0; feat < n_features; feat++) {
        /* 查找该特征的最佳 split */
        local_best = ...;
    }
    
    #pragma omp critical
    {
        if (local_best > global_best) global_best = local_best;
    }
    
    free(local_buffer);
}
```

**注意事项**：
- 特征级别并行在大特征集（p > 50）时才有收益
- 小特征集下，并行开销可能超过收益，应自动降级为串行
- `schedule(dynamic)` 避免负载不均（不同特征的唯值数量差异大）

### 7.3 避免的并行模式

| 模式 | 原因 |
|------|------|
| 嵌套并行（树级别 + 特征级别同时） | OpenMP nested 复杂，性能不可预测 |
| `#pragma omp parallel for` 在递归函数内部 | 每节点分裂都创建线程，开销巨大 |
| 对叶子队列的并行修改（best-first） | 需要锁保护，串行化严重 |

---

## 8. Stata-C 接口设计

### 8.1 变量布局（与 kdensity2 / nwreg 一致）

**关于 terminology 的说明**：本设计中 "y" 指因变量（depvar，需要预测的目标），"target" 指 0/1 训练/测试划分变量（与 kdensity2/nwreg 中的 target 含义一致）。两者是不同的变量。

| Stata 变量索引 | 内容 |
|----------------|------|
| 1 .. n_features | 特征变量（X，indepvars） |
| n_features + 1 | 因变量（y，depvar） |
| n_features + 2 | target 变量（可选，0=训练，1=测试） |
| n_features + 3 | group 变量（可选） |
| n_features + 4 | 输出变量：聚合预测值（分类=类别，回归=均值） |
| n_features + 5 .. n_features + 4 + ntree | 输出变量：每棵树的叶子节点 ID（每棵树一列） |
| n_features + 5 + ntree | touse 标记变量（0/1） |

**布局与 nwreg 完全一致**：features → y → target(0/1) → group → result → touse。插件在 C 端通过 `extract_option_value` 接收 `nfeatures`、`ntarget`、`ngroup` 等参数来确定偏移量，不使用 `SF_nvar()`（后者返回数据集总变量数而非插件变量数）。

**每棵树一列的存储设计**：

- `ntree=1`（决策树模式）：生成 1 列叶子 ID，列名 = `generate()` 参数指定
- `ntree>1`（随机森林模式）：生成 `ntree` 列叶子 ID，列名格式 = `prefix_t#`
  - 例如：`generate(rf_node)` + `ntree(100)` → 生成 `rf_node_t1`, `rf_node_t2`, ..., `rf_node_t100`
  - 再加一列聚合预测值 `rf_node_pred`
- **Stata 变量名长度限制**：最长 32 字符。ado 层需验证：`strlen(prefix) + strlen("_t") + digits(ntree) <= 32`
- **内存估算**：`ntree × n_obs × 4 bytes`（int 类型）。100 棵树 × 100K 观测 = 40MB，可接受。

### 8.2 C 插件参数（argv 格式）

| 参数 | 格式 | 说明 |
|------|------|------|
| type | `type(classify)` / `type(regress)` | 任务类型 |
| ntree | `ntree(100)` | 树的数量 |
| mtry | `mtry(3)` | 每棵树随机特征数（默认 sqrt(p) 或 p/3） |
| maxdepth | `maxdepth(10)` | 最大深度（0=无限制） |
| minsamplessplit | `minsamplessplit(2)` | 最小分裂样本数 |
| minsamplesleaf | `minsamplesleaf(1)` | 最小叶子样本数 |
| minimpuritydecrease | `minimpuritydecrease(0.0)` | 最小 impurity 下降 |
| nfeatures | `nfeatures(5)` | 特征数 |
| ntiles | `ntiles(10)` | 分位数数量（0=使用排序唯值） |
| criterion | `criterion(gini)` / `criterion(entropy)` / `criterion(mse)` | Impurity 指标 |
| seed | `seed(42)` | 随机种子 |
| strategy | `strategy(recursive)` / `strategy(bestfirst)` | 树生长策略 |
| maxleafnodes | `maxleafnodes(100)` | 最大叶子数（仅 best-first） |
| importance | `importance(1)` | 是否计算特征重要性 |
| ntarget | `ntarget(1)` | 是否有 target 变量 |
| ngroup | `ngroup(1)` | group 变量数 |
| nclasses | `nclasses(3)` | 分类任务中的类别数（回归=0，由 ado 层从数据中提取） |

### 8.3 Stata ado 命令语法

**注意**：与 kdensity2/nwreg 一致，由于 Stata 18 的 `if` 解析 bug，此处使用 `if(string)` 和 `in(string)` 作为选项而非 Stata 内置 qualifier。

```stata
fangorn depvar indepvars, 
    [ type(classify|regress)            /* 默认自动检测（数值=regress，整数小范围=classify） */
      ntree(integer 100)                /* 树的数量 */
      mtry(integer -1)                  /* 每棵树特征数，默认 classify=sqrt(p), regress=p/3 */
      maxdepth(integer 20)              /* 最大深度 */
      minsamplessplit(integer 2)        /* 最小分裂样本 */
      minsamplesleaf(integer 1)         /* 最小叶子样本 */
      minimpuritydecrease(real 0.0)     /* 最小 impurity 下降 */
      ntiles(integer 0)                 /* 分位数阈值（0=排序唯值） */
      criterion(string)                 /* gini/entropy/mse */
      seed(integer 12345)               /* 随机种子 */
      strategy(string)                  /* recursive/bestfirst */
      maxleafnodes(integer 1000)        /* 最大叶子数 */
      nclasses(integer -1)              /* 类别数（-1=自动检测，回归=0，分类>0） */
      generate(string)                  /* 节点 ID 变量名前缀（随机森林生成多列：prefix_t1, prefix_t2...） */
      predname(string)                  /* 聚合预测值变量名（默认 prefix_pred） */
      importance(string)                /* 特征重要性变量名 */
      target(varname)                   /* 训练/测试分割变量（0=训练，1=测试） */
      group(varlist)                    /* 分组变量 */
      if(string)                        /* if 条件（字符串选项，非 Stata qualifier） */
      in(string)                        /* in 条件（同上） */
    ]
```

### 8.4 返回值（r()）

| 宏/标量 | 内容 |
|---------|------|
| r(N) | 观测数 |
| r(ntree) | 树的数量 |
| r(mtry) | 每棵树特征数 |
| r(maxdepth) | 最大深度 |
| r(nleaves_avg) | 平均叶子数 |
| r(oob_error) | OOB 误差（随机森林） |
| r(type) | "classify" 或 "regress" |

---

## 9. 实现路线图

### Phase 1：基础决策树（2-3 周）

**目标**：实现单棵决策树，支持分类和回归

1. **Week 1.1**：数据结构与工具函数
   - [ ] `tree.h/c`：TreeNode, DecisionTree 结构，create/free/expand
   - [ ] `utils_rf.h/c`：LCG 随机数，Bootstrap 采样，quickselect，排序
   - [ ] `split.h/c`：Impurity 函数（Gini, Entropy, MSE），分位数计算
   - [ ] **预排序索引**：全局特征排序函数 `precompute_sorted_indices()`

2. **Week 1.2**：核心算法
   - [ ] `find_best_split()`：基于预排序索引的 O(m) split 查找
   - [ ] `build_tree_recursive()`：递归 CART 构建（含索引继承）
   - [ ] `predict_tree()`：单观测预测

3. **Week 1.3**：Stata 集成
   - [ ] `fangorn.c`：`stata_call()` 入口，参数解析，每棵树一列的节点 ID 输出
   - [ ] `fangorn.ado`：语法解析，变量布局（含每棵树一列的列名生成），plugin 调用
   - [ ] 基础测试：iris 等经典数据集

### Phase 2：随机森林（1-2 周）

**目标**：多棵树集成 + 特征重要性

1. **Week 2.1**：森林核心
   - [ ] `forest.h/c`：RandomForest 结构，`build_random_forest()`
   - [ ] 树级别 OpenMP 并行
   - [ ] Bootstrap 采样 + OOB 误差计算

2. **Week 2.2**：预测与评估
   - [ ] `predict_forest()`：分类投票 / 回归平均
   - [ ] 特征重要性（MDI）计算
   - [ ] 返回 Stata：每棵树一列节点 ID + 聚合预测值 + 重要性

3. **Week 2.3**：测试与优化
   - [ ] 与 scikit-learn 结果对比验证
   - [ ] 性能基准测试（不同数据规模）

### Phase 3：高级功能（1-2 周）

**目标**：Best-first 策略 + 额外功能

1. **Week 3.1**：Best-first 决策树
   - [ ] `build_tree_bestfirst()` 实现
   - [ ] Leaf 队列管理
   - [ ] 节点归属数组维护

2. **Week 3.2**：增强功能
   - [ ] best-first 模式下的动态节点归属维护
   - [ ] Group 变量支持（类似 kdensity2）
   - [ ] 更完善的 Stata 帮助文件（.sthlp）

3. **Week 3.3**：性能优化
   - [ ] 可选分位数策略实现（`ntiles` 参数，不启用预排序时的回退方案）
   - [ ] SIMD 向量化（impurity 计算）
   - [ ] 内存池分配（减少 malloc/free 开销）

### Phase 4：文档与发布（1 周）

1. [ ] 编写 `fangorn/README.md`（技术文档）
2. [ ] 编写测试 do-files（`test/test_fangorn_basic.do`, `test/test_fangorn_cv.do`）
3. [ ] 更新项目根 `README.md`
4. [ ] 更新 `Makefile`（添加 `fangorn` 到 `PLUGINS`）

---

## 10. 关键问题与风险

### 10.1 已识别问题

| 问题 | 影响 | 缓解策略 |
|------|------|----------|
| **预排序内存开销** | `sorted_indices[n_features][n_obs]` 需要 `n_features × n_obs × 4` bytes 额外内存。p=100, n=100K 时约 40MB | 对超大 n 可禁用预排序，回退到每节点排序；或只预排序 `mtry` 个随机特征子集 |
| **Best-first 内存开销** | 每轮需动态提取节点样本，O(n × n_leaves) | 仅用于单棵决策树；随机森林用 recursive |
| **OpenMP 嵌套限制** | 树级别+特征级别同时并行导致性能下降 | 明确分层：外层树并行，内层串行 |
| **分类变量处理** | C 端不原生支持分类变量 | Stata 端用 `egen group()` 预处理 |
| **缺失值处理** | Stata 缺失值传入 C 后变为 0（当前 utils.c 行为） | 在 ado 层用 `if` 过滤，或在 C 端增加缺失值检查 |
| **大唯值变量的速度** | 连续变量唯值多，排序+枚举阈值慢 | 使用预排序索引继承策略，将每节点复杂度从 O(m log m) 降到 O(m) |
| **树的深度过大** | 递归深度 > 1000 时栈溢出 | `maxdepth` 默认限制为 20；大深度用迭代栈替代递归 |
| **随机数可重复性** | 不同平台 / OpenMP 调度导致结果不一致 | 固定 seed；每棵树用 `seed + t` 独立 LCG；树级别并行用 `schedule(static)` 确保每棵树始终分配到固定线程。实际由于 LCG 状态由 tree index `t` 唯一确定，`dynamic` 调度不影响数值结果，但 `static` 更规范 |
| **Stata 变量名长度** | 每棵树一列，前缀 + "_t" + 编号，总长不能超过 32 | ado 层验证；超长时自动截断前缀 |
| **Stata 最大变量数** | Stata 不同版本对变量数有限制（Stata/IC: 2048, Stata/SE: 32767, Stata/MP: 120000） | `ntree` 过大时警告用户；提供只输出聚合预测的选项 |
| **n_classes 未传递** | 分类模式下，C 插件需要知道类别数以分配 voting 数组和计算 impurity | ado 层从 depvar 提取唯一值数量，通过 `nclasses(N)` 参数传入 C 插件；回归传 0 |
| **OOB 误差未计算** | `build_random_forest()` 原代码未累计 OOB 预测 | 已修复：增加 `OOBState` 结构，在树构建时累计 OOB 预测，构建完成后计算误差 |
| **Stata 18 `if` 解析 bug** | 使用 Stata 内置 `[if]` qualifier 会导致 "option if not allowed" 错误 | ado 语法使用 `if(string)` 和 `in(string)` 选项模式，与 kdensity2/nwreg 一致 |
| **预排序线程内存开销** | `find_best_split()` 中每个 OpenMP 线程分配 `calloc(data->n_obs, sizeof(int))` 的 `in_node` 数组 | 8 线程 × 100K obs = 3.2MB，可接受。但在 n_obs > 500K 时可考虑改用 `memset(0)` 复用缓冲区 |

### 10.2 设计权衡记录

1. **Double vs Float**：**确认保留 Double**。用户要求与 Stata 原生类型一致，精度优先
2. **Best-first vs Recursive**：两者都支持，随机森林强制 Recursive（效率优先）
3. **分位数 vs 排序唯值**：**默认预排序 + 排序唯值**（精确，O(m) 每节点），可选分位数（快速近似）
4. **树级别 vs 节点级别并行**：树级别为主（简单且扩展性好）。只读数据无需同步，符合 scikit-learn 模式
5. **OOB 误差计算**：每棵树构建时同步计算（增加内存但避免二次遍历）
6. **分类变量**：C 端不处理，Stata 端 one-hot 编码后输入
7. **存储设计**：每棵树一列变量存储节点 ID（用户要求），Stata 端可后处理分析
8. **预排序内存 vs 速度**：用 `n_features × n_obs × 4B` 内存换取每节点 O(m) 而非 O(m log m) 的 split 查找
9. **预排序策略的 sklearn 演进**：scikit-learn 在 0.24+ 中移除了 presort 模式，改用直方图分桶。本方案仍采用预排序，原因见 Section 2.5（Stata 场景：小数据量、稠密矩阵、需精确结果）
10. **`schedule(static)` vs `schedule(dynamic)`**：随机森林构建使用 `schedule(static)`（结果确定性强，每棵树计算量近似均衡）；单棵树特征级别并行使用 `schedule(dynamic)`（特征间唯值数量差异大，需动态负载均衡）

---

## 11. 性能目标

### 11.1 基准预期

在 8 核 CPU、32GB 内存环境下：

| 数据规模 | 任务 | 预期时间 |
|----------|------|----------|
| n=10,000, p=10, ntree=100 | 分类 | < 5 秒 |
| n=100,000, p=50, ntree=100 | 分类 | < 2 分钟 |
| n=10,000, p=10, ntree=1 | 决策树（best-first, 100 叶子） | < 1 秒 |

### 11.2 优化方向

1. **预排序特征**：对大数据集，在树构建前对每个特征预排序，避免每节点重复排序
2. **直方图近似**：对极大数据集（n > 100K），使用分桶直方图替代精确阈值搜索
3. **SIMD**：利用 AVX2 加速 impurity 计算（需编译时检测）
4. **内存对齐**：确保特征矩阵按 cache line 对齐，提高访问效率

---

## 12. 测试计划

### 12.1 单元测试（C 层）

- [ ] Impurity 计算验证（Gini, Entropy, MSE 与手动计算对比）
- [ ] 分位数计算验证（与 Stata `pctile` 对比）
- [ ] Bootstrap 采样验证（统计特性）
- [ ] 单棵树预测验证（与 scikit-learn `DecisionTreeClassifier` 对比）

### 12.2 集成测试（Stata do-file）

- [ ] `test_fangorn_basic.do`：基本分类/回归，小数据集
- [ ] `test_fangorn_target.do`：target=0/1 划分
- [ ] `test_fangorn_group.do`：group 变量分组
- [ ] `test_fangorn_importance.do`：特征重要性验证
- [ ] `test_fangorn_bestfirst.do`：best-first vs recursive 一致性
- [ ] `test_fangorn_compare_sklearn.do`：与 Python scikit-learn 结果对比

### 12.3 性能测试

- [ ] 不同 n（1K, 10K, 100K, 1M）的耗时曲线
- [ ] 不同 ntree（10, 100, 500）的扩展性
- [ ] 不同 p（10, 50, 100, 500）的扩展性
- [ ] 单线程 vs 多线程（2, 4, 8 核）加速比

---

## 13. 附录：随机数生成器

为保证结果可重复且跨平台一致，不使用系统 `rand()`，而是实现简单的 LCG（Linear Congruential Generator）：

```c
typedef struct {
    unsigned int state;
} LCGState;

static inline LCGState lcg_init(unsigned int seed) {
    LCGState rng = {seed ? seed : 1U};
    return rng;
}

static inline unsigned int lcg_next(LCGState *rng) {
    rng->state = rng->state * 1103515245U + 12345U;
    return rng->state;
}

static inline double lcg_uniform(LCGState *rng) {
    return (double)lcg_next(rng) / (double)0xFFFFFFFF;
}

static inline int lcg_randint(LCGState *rng, int max) {
    return (int)(lcg_uniform(rng) * max);
}
```

**优点**：
- 确定性强，seed 相同则序列相同
- 无全局状态，线程安全（每个树/线程有自己的 LCGState）
- 速度快，无系统调用
- 跨平台一致（不依赖 `RAND_MAX`）

**注意**：`lcg_init(0)` 被映射为 `seed = 1`（`seed ? seed : 1U`），因此 seed=0 与 seed=1 产生相同随机序列。ado 层应确保传入的 seed > 0，或修改此行为以保持 seed=0 唯一（例如使用 `~seed` 作为初始状态）。

---

## 14. 总结

本方案设计了一个与 HHStataToolkit 现有架构高度一致的决策树 / 随机森林 Stata 插件。核心设计决策包括：

1. **Double 精度（用户确认）**：保留 double，与 Stata 原生类型一致，精度优先
2. **堆式节点编码**：唯一 ID + 数组索引，支持高效遍历，30 层深度足够
3. **分层并行（线程安全确认）**：
   - 随机森林：树级别并行，特征矩阵 `const` 只读，**无需任何同步**
   - 单棵树：特征级别并行（`ntree=1` 时），线程私有缓冲区
4. **Recursive + Best-first 双策略**：随机森林强制 Recursive（效率优先）
5. **预排序索引继承 + 分位数**：
   - **默认**：全局预排序 + 索引继承，每节点 split 查找 O(m)（scikit-learn 核心优化）
   - **可选**：分位数策略（`ntiles`），从预排序数组直接取位置
6. **函数指针 Impurity**：支持 Gini / Entropy / MSE 动态切换
7. **分类变量**：C 端不处理，Stata 端 one-hot 编码后输入
8. **每棵树一列存储**：用户要求每棵树在 Stata 中保存一列节点 ID，ado 层处理列名生成

### 关键可行性结论

| 问题 | 结论 |
|------|------|
| 只读数据线程安全？ | ✅ **完全安全**。OpenMP 多线程只读无 data race，无需锁/原子操作 |
| 30 层深度够吗？ | ✅ **足够**。int32 堆式编码支持 30 层，远超实际需求 |
| 分位数重新计算速度？ | ✅ **优化方案可行**。预排序索引继承将每节点复杂度从 O(m log m) 降到 O(m) |
| 每棵树一列会超 Stata 限制？ | ⚠️ **需验证**。Stata/IC 限 2048 变量，`ntree` 过大时警告用户 |

实现将分 4 个 Phase 推进，预计总工期 5-7 周。Phase 1 的基础决策树（含预排序优化）是核心里程碑，完成后即可验证整体设计可行性。
