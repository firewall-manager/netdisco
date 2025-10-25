use utf8;
package App::Netdisco::DB::Result::Virtual::ActiveNode;

# 活跃节点虚拟结果类
# 提供活跃节点的虚拟视图

use strict;
use warnings;

use base 'App::Netdisco::DB::Result::Node';

__PACKAGE__->load_components('Helper::Row::SubClass');
__PACKAGE__->subclass;

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');
__PACKAGE__->table("active_node");
__PACKAGE__->result_source_instance->is_virtual(1);
# 虚拟视图定义：活跃节点
# 只选择活跃状态的节点记录
__PACKAGE__->result_source_instance->view_definition(q{
  SELECT * FROM node WHERE active
});

1;
