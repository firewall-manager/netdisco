package App::Netdisco::DB::Result::Virtual::DuplexMismatch;

# 双工模式不匹配虚拟结果类
# 提供链路两端双工模式不匹配的虚拟视图

use strict;
use warnings;

use base 'DBIx::Class::Core';

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');

__PACKAGE__->table('duplex_mismatch');
__PACKAGE__->result_source_instance->is_virtual(1);
# 虚拟视图定义：双工模式不匹配检测
# 查找链路两端双工模式不一致的连接，避免重复检测
__PACKAGE__->result_source_instance->view_definition(<<ENDSQL
 SELECT dp.ip AS left_ip, d1.dns AS left_dns, dp.port AS left_port, dp.duplex AS left_duplex,
        di.ip AS right_ip, d2.dns AS right_dns, dp.remote_port AS right_port, dp2.duplex AS right_duplex
   FROM ( SELECT device_port.ip, device_port.remote_ip, device_port.port, device_port.duplex, device_port.remote_port
           FROM device_port
          WHERE
            device_port.remote_port IS NOT NULL
            AND device_port.up NOT ILIKE '%down%'
          GROUP BY device_port.ip, device_port.remote_ip, device_port.port, device_port.duplex, device_port.remote_port
          ORDER BY device_port.ip) dp
   LEFT JOIN device_ip di ON dp.remote_ip = di.alias
   LEFT JOIN device d1 ON dp.ip = d1.ip
   LEFT JOIN device d2 ON di.ip = d2.ip
   LEFT JOIN device_port dp2 ON (di.ip = dp2.ip AND dp.remote_port = dp2.port)
  WHERE di.ip IS NOT NULL
   AND dp.duplex <> dp2.duplex
   AND dp.ip <= di.ip
   AND dp2.up NOT ILIKE '%down%'
  ORDER BY dp.ip
ENDSQL
);

# 定义虚拟视图的列
# 包含链路两端设备的IP、DNS、端口和双工模式信息
__PACKAGE__->add_columns(
  'left_ip' => {
    data_type => 'inet',
  },
  'left_dns' => {
    data_type => 'text',
  },
  'left_port' => {
    data_type => 'text',
  },
  'left_duplex' => {
    data_type => 'text',
  },
  'right_ip' => {
    data_type => 'inet',
  },
  'right_dns' => {
    data_type => 'text',
  },
  'right_port' => {
    data_type => 'text',
  },
  'right_duplex' => {
    data_type => 'text',
  },
);

1;
