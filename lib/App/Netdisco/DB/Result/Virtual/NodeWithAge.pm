use utf8;
package App::Netdisco::DB::Result::Virtual::NodeWithAge;

# 带年龄的节点虚拟结果类
# 提供带年龄信息的节点虚拟视图

use strict;
use warnings;

use base 'App::Netdisco::DB::Result::Node';

__PACKAGE__->load_components('Helper::Row::SubClass');
__PACKAGE__->subclass;

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');
__PACKAGE__->table("node_with_age");
__PACKAGE__->result_source_instance->is_virtual(1);
# 虚拟视图定义：带年龄的节点
# 计算节点最后活动时间的年龄，格式化为可读的时间差
__PACKAGE__->result_source_instance->view_definition(q{
  SELECT *,
    replace( date_trunc( 'minute', age( LOCALTIMESTAMP, time_last + interval '30 second' ) ) ::text, 'mon', 'month')
      AS time_last_age
  FROM node
});

# 添加年龄列定义
# time_last_age: 节点最后活动时间的年龄，格式化为文本
__PACKAGE__->add_columns(
  "time_last_age",
  { data_type => "text", is_nullable => 1 },
);

1;
