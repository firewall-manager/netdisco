# Netdisco bin/ 目录脚本说明

本目录包含 Netdisco 网络发现和管理系统的所有可执行脚本。这些脚本提供了完整的网络设备发现、数据收集、数据库管理和 Web 服务功能。

## 脚本分类

### 1. 数据库管理脚本

#### `nd-dbic-versions`
- **用途**：创建和管理 Netdisco 数据库架构版本
- **功能**：
  - 生成 SQL DDL 文件用于数据库初始化
  - 创建数据库架构升级脚本
  - 支持从指定版本到当前版本的升级
- **代码逻辑**：
  - 使用 `FindBin` 定位脚本目录
  - 通过 `App::Netdisco::DB` 获取架构版本信息
  - 使用 `Getopt::Long` 解析命令行参数
  - 调用 `create_ddl_dir` 生成 PostgreSQL 架构文件

#### `netdisco-db-deploy`
- **用途**：部署和升级 Netdisco 数据库架构
- **功能**：
  - 检查 PostgreSQL 版本兼容性（最低 9.6）
  - 支持强制重新部署（`--redeploy-all`）
  - 逐步升级数据库架构
  - 事务回滚保护（测试环境）
- **代码逻辑**：
  - 环境初始化和 localenv 查找
  - PostgreSQL 版本检查
  - 数据库版本管理和升级
  - 异常处理和错误恢复

### 2. 部署和配置脚本

#### `netdisco-deploy`
- **用途**：完整的 Netdisco 部署向导
- **功能**：
  - 交互式部署流程
  - 数据库架构部署
  - OUI 数据更新
  - MIB 文件管理
  - 初始管理员用户创建
- **代码逻辑**：
  - 用户交互和确认流程
  - 数据库部署和统计信息更新
  - 网络数据下载和处理
  - 密码安全设置检查

#### `nd-import-topology`
- **用途**：导入 Netdisco 1.x 格式的拓扑文件
- **功能**：
  - 解析拓扑文件格式
  - 创建设备发现作业
  - 保存链接信息到数据库
- **代码逻辑**：
  - 文件解析和注释处理
  - 设备地址验证
  - 数据库事务处理
  - 作业队列管理

### 3. 后端服务脚本

#### `netdisco-backend`
- **用途**：Netdisco 后端守护进程控制器
- **功能**：
  - 守护进程管理
  - 配置文件监控
  - 日志轮转
  - 自动重启
- **代码逻辑**：
  - 使用 `Daemon::Control` 进行进程管理
  - 文件系统监控（`Filesys::Notify::Simple`）
  - 信号处理和进程通信
  - 日志轮转算法

#### `netdisco-backend-fg`
- **用途**：Netdisco 后端前台进程
- **功能**：
  - 多进程作业处理
  - 调度器、管理器、轮询器角色
  - MCE 多核处理
- **代码逻辑**：
  - MCE 多进程配置
  - 工作进程角色分配
  - 共享队列管理
  - 进程生命周期管理

### 4. Web 服务脚本

#### `netdisco-web`
- **用途**：Netdisco Web 服务器守护进程
- **功能**：
  - Web 服务器进程管理
  - 配置文件监控
  - 日志轮转
  - 会话管理
- **代码逻辑**：
  - 守护进程控制
  - 文件权限管理
  - 进程监控和重启
  - 日志轮转处理

#### `netdisco-web-fg`
- **用途**：Netdisco Web 应用前端
- **功能**：
  - Plack 中间件栈配置
  - 安全头设置
  - 静态资源处理
  - 调试支持
- **代码逻辑**：
  - 中间件配置和顺序
  - 安全策略设置
  - 静态文件路由
  - 调试面板配置

### 5. 命令行工具脚本

#### `netdisco-do`
- **用途**：Netdisco 命令行工具
- **功能**：
  - 执行各种网络发现任务
  - 设备管理操作
  - 数据收集和处理
  - 系统管理功能
- **代码逻辑**：
  - 命令行参数解析
  - 设备地址验证和解析
  - 作业创建和执行
  - 错误处理和状态跟踪

### 6. 数据收集脚本

#### `netdisco-sshcollector`（已弃用）
- **用途**：通过 SSH 收集 ARP 数据
- **功能**：
  - 多进程 SSH 连接
  - 平台特定数据处理
  - ARP 条目验证和存储
- **代码逻辑**：
  - MCE 多进程处理
  - SSH 连接管理
  - 平台类动态加载
  - 数据验证和存储

### 7. 导出和集成脚本

#### `netdisco-rancid-export`（已弃用）
- **用途**：导出 RANCID 配置
- **功能**：
  - 设备分组和分类
  - 厂商映射
  - 配置文件生成
- **代码逻辑**：
  - 设备查询和分组
  - 权限匹配
  - 文件生成和写入

### 8. 辅助脚本

#### `netdisco-daemon`
- **用途**：守护进程启动脚本（兼容性）
- **功能**：
  - PID 文件重命名
  - 调用新的后端脚本
- **代码逻辑**：
  - 路径解析
  - 文件操作
  - 进程执行

#### `netdisco-daemon-fg`
- **用途**：前台守护进程启动脚本
- **功能**：
  - 调用前台后端脚本
- **代码逻辑**：
  - 路径解析
  - 进程执行

#### `netdisco-env`
- **用途**：环境设置脚本
- **功能**：
  - 设置 Netdisco 环境
  - 执行传入的命令
- **代码逻辑**：
  - 环境变量设置
  - 库路径配置
  - 命令执行

## 通用代码模式

### 1. 环境初始化
所有脚本都遵循相同的环境初始化模式：
```perl
BEGIN {
  use FindBin;
  FindBin::again();
  # 设置主目录
  $home = ($ENV{NETDISCO_HOME} || $ENV{HOME});
  # 查找 localenv 脚本
  # 配置库路径
}
```

### 2. 模块导入
标准模块导入模式：
```perl
use App::Netdisco;
use Dancer ':script';
use Dancer::Plugin::DBIC 'schema';
```

### 3. 错误处理
使用 `Try::Tiny` 进行异常处理：
```perl
try {
  # 执行操作
} catch {
  # 错误处理
};
```

### 4. 配置管理
通过 `setting()` 函数获取配置：
```perl
my $config = setting('config_key');
```

## 脚本依赖关系

```
netdisco-deploy
├── netdisco-db-deploy
├── netdisco-do (loadmibs)
└── 网络下载 (OUI, MIBs)

netdisco-backend
└── netdisco-backend-fg

netdisco-web
└── netdisco-web-fg

netdisco-daemon
└── netdisco-backend

netdisco-daemon-fg
└── netdisco-backend-fg
```

## 使用建议

1. **首次部署**：使用 `netdisco-deploy` 进行完整部署
2. **日常管理**：使用 `netdisco-do` 执行各种操作
3. **服务管理**：使用 `netdisco-backend` 和 `netdisco-web` 管理服务
4. **数据迁移**：使用 `nd-import-topology` 导入拓扑数据
5. **数据库管理**：使用 `nd-dbic-versions` 和 `netdisco-db-deploy` 管理数据库

## 注意事项

1. 某些脚本（如 `netdisco-sshcollector`、`netdisco-rancid-export`）已弃用
2. 所有脚本都需要正确的环境配置
3. 数据库操作需要适当的权限
4. 网络操作需要相应的网络访问权限
5. 建议在生产环境中使用守护进程版本（非 `-fg` 版本）
