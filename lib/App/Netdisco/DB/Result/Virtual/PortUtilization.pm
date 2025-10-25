package App::Netdisco::DB::Result::Virtual::PortUtilization;

# 端口利用率虚拟结果类
# 提供端口利用率统计信息的虚拟视图

use strict;
use warnings;

use base 'DBIx::Class::Core';

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');

# 注意：此查询在`git grep 'THREE PLACES'`中有三个地方使用
__PACKAGE__->table('port_utilization');
__PACKAGE__->result_source_instance->is_virtual(1);

# 虚拟视图定义：端口利用率统计
# 统计设备的端口总数、使用中、关闭和空闲端口数量
__PACKAGE__->result_source_instance->view_definition(
  <<ENDSQL
 SELECT d.dns AS dns, d.ip as ip,
     sum(CASE WHEN (dp.type IS NULL OR dp.type !~* '^(53|ieee8023adLag|propVirtual|l2vlan|l3ipvlan|135|136|137)\$') THEN 1
              ELSE 0 END) as port_count,
     sum(CASE WHEN ((dp.type IS NULL OR dp.type !~* '^(53|ieee8023adLag|propVirtual|l2vlan|l3ipvlan|135|136|137)\$')
                    AND dp.up_admin = 'up' AND dp.up = 'up') THEN 1
              ELSE 0 END) as ports_in_use,
     sum(CASE WHEN ((dp.type IS NULL OR dp.type !~* '^(53|ieee8023adLag|propVirtual|l2vlan|l3ipvlan|135|136|137)\$')
                    AND dp.up_admin != 'up') THEN 1
              ELSE 0 END) as ports_shutdown,
     sum(CASE
      WHEN ( (dp.type IS NULL OR dp.type !~* '^(53|ieee8023adLag|propVirtual|l2vlan|l3ipvlan|135|136|137)\$')
             AND dp.up_admin = 'up' AND dp.up != 'up'
             AND (age(LOCALTIMESTAMP, to_timestamp(extract(epoch from d.last_discover) - (d.uptime/100))::timestamp) < ?::interval)
             AND (last_node.time_last IS NULL OR (age(LOCALTIMESTAMP, last_node.time_last)) > ?::interval) )
        THEN 1
      WHEN ( (dp.type IS NULL OR dp.type !~* '^(53|ieee8023adLag|propVirtual|l2vlan|l3ipvlan|135|136|137)\$')
             AND dp.up_admin = 'up' AND dp.up != 'up'
             AND (age(LOCALTIMESTAMP, to_timestamp(extract(epoch from d.last_discover) - (d.uptime - dp.lastchange)/100)::timestamp) > ?::interval) )
        THEN 1
      ELSE 0
     END) as ports_free
   FROM device d
   LEFT JOIN device_port dp
     ON d.ip = dp.ip
   LEFT JOIN
     ( SELECT DISTINCT ON (switch, port) * FROM node
         ORDER BY switch, port, time_last desc ) AS last_node
     ON dp.port = last_node.port AND dp.ip = last_node.switch
   GROUP BY d.dns, d.ip
   ORDER BY d.dns, d.ip
ENDSQL
);

# 定义虚拟视图的列
# 包含设备信息和端口利用率统计
__PACKAGE__->add_columns(
  'dns'            => {data_type => 'text',},
  'ip'             => {data_type => 'inet',},
  'port_count'     => {data_type => 'integer',},
  'ports_in_use'   => {data_type => 'integer',},
  'ports_shutdown' => {data_type => 'integer',},
  'ports_free'     => {data_type => 'integer',},
);

1;
