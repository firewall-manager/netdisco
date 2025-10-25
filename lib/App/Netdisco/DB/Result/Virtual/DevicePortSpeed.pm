package App::Netdisco::DB::Result::Virtual::DevicePortSpeed;

# 设备端口速度虚拟结果类
# 提供设备端口总速度统计信息的虚拟视图

use strict;
use warnings;

use base 'DBIx::Class::Core';

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');

__PACKAGE__->table('device_port_speed');
__PACKAGE__->result_source_instance->is_virtual(1);

# 虚拟视图定义：设备端口速度统计
# 计算每个设备的总端口速度，排除VLAN和虚拟端口
__PACKAGE__->result_source_instance->view_definition(
  <<ENDSQL
  SELECT ip,
         GREATEST(1, sum( COALESCE(dpp.raw_speed,1) )) as total
  FROM device_port
  LEFT OUTER JOIN device_port_properties dpp USING (ip, port)
  WHERE port !~* 'vlan'
    AND (descr IS NULL OR descr !~* 'vlan')
    AND (type IS NULL OR type !~* '^(53|ieee8023adLag|propVirtual|l2vlan|l3ipvlan|135|136|137)\$')
    AND (is_master = 'false' OR slave_of IS NOT NULL)
  GROUP BY ip
  ORDER BY total DESC, ip ASC
ENDSQL
);

# 定义虚拟视图的列
# total: 设备端口总速度
__PACKAGE__->add_columns('total' => {data_type => 'integer',},);

# 定义关联关系：设备
# 通过IP地址关联到设备表
__PACKAGE__->belongs_to('device', 'App::Netdisco::DB::Result::Device', {'foreign.ip' => 'self.ip'});

1;
