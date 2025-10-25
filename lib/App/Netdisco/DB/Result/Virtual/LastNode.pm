package App::Netdisco::DB::Result::Virtual::LastNode;

# 最后节点虚拟结果类
# 提供每个交换机端口上最后发现的节点信息虚拟视图

use strict;
use warnings;

use base 'DBIx::Class::Core';

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');

__PACKAGE__->table('last_node');
__PACKAGE__->result_source_instance->is_virtual(1);

# 虚拟视图定义：最后节点
# 获取每个交换机端口上最后发现的节点，按时间排序
__PACKAGE__->result_source_instance->view_definition(
  <<ENDSQL
  SELECT DISTINCT ON (switch, port) * FROM node
    ORDER BY switch, port, time_last desc
ENDSQL
);

# 定义虚拟视图的列
# 包含节点的完整信息，继承自node表的所有字段
__PACKAGE__->add_columns(
  "mac",
  {data_type => "macaddr", is_nullable => 0},
  "switch",
  {data_type => "inet", is_nullable => 0},
  "port",
  {data_type => "text", is_nullable => 0},
  "active",
  {data_type => "boolean", is_nullable => 1},
  "oui",
  {data_type => "varchar", is_nullable => 1, size => 9},
  "time_first", {
    data_type     => "timestamp",
    default_value => \"LOCALTIMESTAMP",
    is_nullable   => 1,
    original      => {default_value => \"LOCALTIMESTAMP"},
  },
  "time_recent", {
    data_type     => "timestamp",
    default_value => \"LOCALTIMESTAMP",
    is_nullable   => 1,
    original      => {default_value => \"LOCALTIMESTAMP"},
  },
  "time_last", {
    data_type     => "timestamp",
    default_value => \"LOCALTIMESTAMP",
    is_nullable   => 1,
    original      => {default_value => \"LOCALTIMESTAMP"},
  },
  "vlan",
  {data_type => "text", is_nullable => 0, default_value => '0'},
);

1;
