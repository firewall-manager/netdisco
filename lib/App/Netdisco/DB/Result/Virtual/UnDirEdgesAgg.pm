package App::Netdisco::DB::Result::Virtual::UnDirEdgesAgg;

# 无向边聚合虚拟结果类
# 提供设备间无向连接边的聚合虚拟视图

use strict;
use warnings;

use base 'DBIx::Class::Core';

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');

__PACKAGE__->table('undir_edges_agg');
__PACKAGE__->result_source_instance->is_virtual(1);
# 虚拟视图定义：无向边聚合
# 聚合设备间的双向连接，创建无向图结构
__PACKAGE__->result_source_instance->view_definition(<<'ENDSQL');
   SELECT left_ip,
          array_agg(right_ip) AS links
   FROM
     ( SELECT dp.ip AS left_ip,
              di.ip AS right_ip
      FROM
        (SELECT device_port.ip,
                device_port.remote_ip
         FROM device_port
         WHERE device_port.remote_port IS NOT NULL
         GROUP BY device_port.ip,
                  device_port.remote_ip) dp
      LEFT JOIN device_ip di ON dp.remote_ip = di.alias
      WHERE di.ip IS NOT NULL
      UNION SELECT di.ip AS left_ip,
                   dp.ip AS right_ip
      FROM
        (SELECT device_port.ip,
                device_port.remote_ip
         FROM device_port
         WHERE device_port.remote_port IS NOT NULL
         GROUP BY device_port.ip,
                  device_port.remote_ip) dp
      LEFT JOIN device_ip di ON dp.remote_ip = di.alias
      WHERE di.ip IS NOT NULL ) AS foo
   GROUP BY left_ip
   ORDER BY left_ip
ENDSQL

# 定义虚拟视图的列
# 包含设备IP和连接的设备IP数组
__PACKAGE__->add_columns(
  'left_ip' => {
    data_type => 'inet',
  },
  'links' => {
    data_type => 'inet[]',
  }
);

# 定义关联关系：设备
# 通过IP地址关联到设备表
__PACKAGE__->belongs_to('device', 'App::Netdisco::DB::Result::Device',
  { 'foreign.ip' => 'self.left_ip' });

1;
