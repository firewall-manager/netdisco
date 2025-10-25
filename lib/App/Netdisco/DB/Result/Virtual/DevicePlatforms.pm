package App::Netdisco::DB::Result::Virtual::DevicePlatforms;

# 设备平台虚拟结果类
# 提供设备平台统计信息的虚拟视图，包括厂商和型号统计

use strict;
use warnings;

use base 'DBIx::Class::Core';

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');

__PACKAGE__->table('device_platforms');
__PACKAGE__->result_source_instance->is_virtual(1);

# 虚拟视图定义：设备平台统计
# 按厂商和型号统计设备数量，优先使用机箱序列号，否则使用IP地址
__PACKAGE__->result_source_instance->view_definition(
  <<ENDSQL
  SELECT device.vendor, device.model,
    CASE WHEN count(distinct( module.serial )) = 0
      THEN count(distinct( device.ip ))
      ELSE count(distinct( module.serial )) END
      AS count
  FROM device
    LEFT JOIN device_module module
      ON (device.ip = module.ip and module.class = 'chassis'
        AND module.serial IS NOT NULL
        AND module.serial != '')
  GROUP BY device.vendor, device.model
ENDSQL
);

# 定义虚拟视图的列
# 包含厂商、型号和统计数量
__PACKAGE__->add_columns(
  'vendor' => {data_type => 'text',},
  'model'  => {data_type => 'text',},
  'count'  => {data_type => 'integer',},
);

1;
