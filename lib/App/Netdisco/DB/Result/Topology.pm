use utf8;
package App::Netdisco::DB::Result::Topology;

# 拓扑结果类
# 提供网络拓扑连接信息的管理模型

use strict;
use warnings;

use base 'App::Netdisco::DB::Result';

__PACKAGE__->table("topology");

# 定义表列
# 包含两个设备及其端口的连接信息
__PACKAGE__->add_columns(
  "dev1",
  { data_type => "inet", is_nullable => 0 },
  "port1",
  { data_type => "text", is_nullable => 0 },
  "dev2",
  { data_type => "inet", is_nullable => 0 },
  "port2",
  { data_type => "text", is_nullable => 0 },
);

# 添加唯一约束
# 确保每个设备端口组合的唯一性
__PACKAGE__->add_unique_constraint(['dev1','port1']);
__PACKAGE__->add_unique_constraint(['dev2','port2']);

# 定义关联关系：设备1
# 返回连接中的第一个设备信息
__PACKAGE__->belongs_to(
  device1 => 'App::Netdisco::DB::Result::Device',
  {'foreign.ip' => 'self.dev1'}
);

# 定义关联关系：设备2
# 返回连接中的第二个设备信息
__PACKAGE__->belongs_to(
  device2 => 'App::Netdisco::DB::Result::Device',
  {'foreign.ip' => 'self.dev2'}
);

1;
