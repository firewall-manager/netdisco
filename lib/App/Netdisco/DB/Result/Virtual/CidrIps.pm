package App::Netdisco::DB::Result::Virtual::CidrIps;

# CIDR IP地址虚拟结果类
# 提供CIDR网络范围内所有IP地址的虚拟视图

use strict;
use warnings;

use utf8;
use base 'DBIx::Class::Core';

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');

__PACKAGE__->table('cidr_ips');
__PACKAGE__->result_source_instance->is_virtual(1);

# 虚拟视图定义：CIDR IP地址生成
# 根据CIDR前缀生成网络范围内的所有IP地址，模拟节点结构
__PACKAGE__->result_source_instance->view_definition(<<'ENDSQL');
SELECT host(network (prefix) + sub.int)::inet AS ip,
       NULL::macaddr AS mac,
       NULL::timestamp AS time_first,
       NULL::timestamp AS time_last,
       NULL::text AS dns,
       false::boolean AS active,
       false::boolean AS node,
       replace( date_trunc( 'minute', age( LOCALTIMESTAMP, NULL::timestamp ) ) ::text, 'mon', 'month') AS age,
       NULL::text AS vendor,
       NULL::text AS nbname
  FROM (
    SELECT prefix,
           generate_series(1, (broadcast(prefix) - network(prefix) - 1)) AS int
      FROM (
        SELECT ?::inet AS prefix
      ) AS addr
  ) AS sub
ENDSQL

# 定义虚拟视图的列，模拟节点表结构
# 所有字段都设为NULL或false，因为这是生成的虚拟IP地址
__PACKAGE__->add_columns(
  "ip",         {data_type => "inet",      is_nullable => 0},
  "mac",        {data_type => "macaddr",   is_nullable => 1},
  "time_first", {data_type => "timestamp", is_nullable => 1,},
  "time_last",  {data_type => "timestamp", is_nullable => 1,},
  "dns",        {data_type => "text",      is_nullable => 1},
  "active",     {data_type => "boolean",   is_nullable => 1},
  "node",       {data_type => "boolean",   is_nullable => 1},
  "age",        {data_type => "text",      is_nullable => 1},
  "vendor",     {data_type => "text",      is_nullable => 1},
  "nbname",     {data_type => "text",      is_nullable => 1},
);

1;
