use utf8;
package App::Netdisco::DB::Result::Virtual::NodeIp6;

# IPv6节点IP虚拟结果类
# 提供IPv6节点IP地址的虚拟视图

use strict;
use warnings;

use base 'App::Netdisco::DB::Result::NodeIp';

__PACKAGE__->load_components('Helper::Row::SubClass');
__PACKAGE__->subclass;

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');
__PACKAGE__->table("node_ip6");
__PACKAGE__->result_source_instance->is_virtual(1);
# 虚拟视图定义：IPv6节点IP
# 只选择IPv6地址的节点IP记录
__PACKAGE__->result_source_instance->view_definition(q{
  SELECT * FROM node_ip WHERE family(ip) = 6
});

1;
